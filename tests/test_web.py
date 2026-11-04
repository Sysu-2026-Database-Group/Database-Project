"""Shared HTTP, privacy and editable sale draft contracts."""
import copy
import json
import unittest
from unittest.mock import patch

import pyodbc

from app import create_app
from app.dao import EmployeeDAO
from app.errors import AppError
from test_auth import MemoryEmployees


class WorkspaceDAO(MemoryEmployees):
    def __init__(self):
        super().__init__()
        self.list_calls = []

    def sale_catalog(self, actor):
        return [dict(id=3, name='测试商品', price='19.00', stock_total=5,
                     reserved_qty=0, available_qty=5, on_shelf=True)]

    def sale_list(self, actor, page, page_size):
        self.list_calls.append((copy.copy(actor), page, page_size))
        return dict(records=[], total=0, page=page, page_size=page_size)


class WebContractsTests(unittest.TestCase):
    def setUp(self):
        self.dao = WorkspaceDAO()
        self.app = create_app(dict(TESTING=True, SECRET_KEY='web-contract-secret-'*3), dao=self.dao)
        self.client = self.app.test_client()

    def login(self, role='收银员'):
        self.dao.row['role'] = role
        self.client.get('/auth/login')
        with self.client.session_transaction() as stored:
            token = stored['csrf_token']
        self.client.post('/auth/login', data=dict(phone=self.dao.row['phone'],
                         password='test-password-123', csrf_token=token))
        with self.client.session_transaction() as stored:
            return stored['csrf_token']

    def test_framework_errors_have_same_json_contract_and_request_id(self):
        for method, path, status in [('GET', '/api/missing', 404), ('POST', '/api/me', 405),
                                     ('POST', '/api/missing', 404)]:
            response = self.client.open(path, method=method)
            self.assertEqual(response.status_code, status)
            self.assertEqual(set(response.json), {'error', 'request_id'})
            self.assertEqual(response.json['request_id'], response.headers['X-Request-ID'])
            self.assertEqual(response.headers['Cache-Control'], 'no-store')
        self.assertIn('GET', self.client.post('/api/me').headers['Allow'])

    def test_bad_json_wrong_content_type_and_large_request(self):
        token = self.login()
        headers = {'X-CSRF-Token': token}
        for data, content_type, expected in [('{', 'application/json', 400),
                                              ('[]', 'application/json', 400),
                                              ('{}', 'text/plain', 415),
                                              ('x'*20000, 'application/json', 413)]:
            response = self.client.post('/api/sales/preview', data=data,
                                        content_type=content_type, headers=headers)
            self.assertEqual(response.status_code, expected)
            self.assertEqual(response.json['request_id'], response.headers['X-Request-ID'])

    def test_invalid_pagination_never_reaches_dao(self):
        self.login()
        for query in ('page=0', 'page=1&page=2', 'page_size=101', 'page=-1', 'page=1.0', 'page=abc'):
            self.assertEqual(self.client.get('/api/sales?'+query).status_code, 400)
        self.assertEqual(self.dao.list_calls, [])
        self.assertEqual(self.client.get('/api/sales?page=2&page_size=30').status_code, 200)
        self.assertEqual(self.dao.list_calls[-1][1:], (2, 30))

    def test_other_roles_cannot_access_sales_lists(self):
        for role in ('库管', '店长'):
            self.login(role)
            self.assertEqual(self.client.get('/api/sales').status_code, 403)
            self.assertEqual(self.client.get('/sales').status_code, 403)
        self.assertEqual(self.dao.list_calls, [])

    def test_draft_add_update_remove_clear_and_csrf(self):
        token = self.login()
        self.assertEqual(self.client.get('/sales/new').status_code, 200)
        with self.client.session_transaction() as stored:
            handle = stored['sale_draft']
            _, value = self.app.extensions['sale_drafts'].get(handle, stored['actor'])
            key = value['request_key']
        for quantity, expected in [('2', [dict(goods_id=3, quantity=2)]),
                                   ('1', [dict(goods_id=3, quantity=1)]), ('0', [])]:
            response = self.client.post('/sales/cart', data=dict(action='update', quantity_3=quantity,
                                        csrf_token=token, request_key='forged'))
            self.assertEqual(response.status_code, 303)
            with self.client.session_transaction() as stored:
                self.assertIsInstance(stored['sale_draft'], str)
                _, value = self.app.extensions['sale_drafts'].get(stored['sale_draft'], stored['actor'])
                self.assertEqual(value['items'], expected)
                self.assertEqual(value['request_key'], key)
        self.assertEqual(self.client.post('/sales/cart', data={'action':'clear'}).status_code, 403)
        self.client.post('/sales/cart', data=dict(action='clear', csrf_token=token))
        with self.client.session_transaction() as stored:
            self.assertNotIn('sale_draft', stored)

    def test_request_logs_exclude_paths_values_and_credentials(self):
        token = self.login()
        with self.assertLogs('bookstore.requests', level='INFO') as captured:
            response = self.client.get('/api/missing/private-reservation-code?password=very-secret')
        record = json.loads(captured.records[-1].getMessage())
        self.assertEqual(record['request_id'], response.headers['X-Request-ID'])
        self.assertEqual(record['role'], '收银员')
        self.assertEqual(record['error_code'], 'not_found')
        for private in ('private-reservation-code', 'very-secret', self.dao.row['phone'], token):
            self.assertNotIn(private, '\n'.join(captured.output))
        for key in ('time', 'duration_ms', 'result', 'subject', 'subject_type', 'action'):
            self.assertIn(key, record)

    def test_unexpected_errors_hide_exception_values_but_log_stack_locations(self):
        self.login()
        with patch.object(self.dao, 'employee_context', side_effect=RuntimeError('password=private')):
            with self.assertLogs('bookstore.requests', level='ERROR') as captured:
                response = self.client.get('/api/me')
        self.assertEqual(response.status_code, 500)
        self.assertNotIn('private', response.get_data(as_text=True))
        self.assertNotIn('password=private', '\n'.join(captured.output))
        self.assertTrue(json.loads(captured.records[0].getMessage())['stack'])

    def test_every_template_compiles(self):
        for name in self.app.jinja_env.list_templates():
            self.app.jinja_env.get_template(name)

    def test_server_side_draft_cannot_be_read_by_another_actor(self):
        store = self.app.extensions['sale_drafts']
        first = dict(phone='13800000003', role='收银员', session_version=1)
        second = dict(first, phone='13800000004')
        handle, value = store.get(None, first)
        value['items'] = [dict(goods_id=3, quantity=2)]
        store.save(handle, first, value)
        other_handle, other_value = store.get(handle, second)
        self.assertNotEqual(other_handle, handle)
        self.assertEqual(other_value['items'], [])
        with self.assertRaises(AppError):
            store.save(handle, second, value)

    def test_expired_draft_cannot_be_saved_without_reading_it_first(self):
        store = self.app.extensions['sale_drafts']
        actor = dict(phone='13800000003', role='收银员', session_version=1)
        with patch('app.sales.time.monotonic', return_value=10):
            handle, value = store.get(None, actor)
        with patch('app.sales.time.monotonic', return_value=10+store.lifetime):
            with self.assertRaises(AppError) as error:
                store.save(handle, actor, value)
        self.assertEqual(error.exception.code, 'draft_expired')

    def test_logout_logs_retain_masked_subject(self):
        token = self.login()
        with self.assertLogs('bookstore.requests', level='INFO') as captured:
            self.client.post('/auth/logout', data=dict(csrf_token=token))
        record = json.loads(captured.records[-1].getMessage())
        self.assertEqual(record['role'], '收银员')
        self.assertIsNotNone(record['subject'])
        self.assertNotIn(self.dao.row['phone'], record['subject'])


class DatabaseErrorMappingTests(unittest.TestCase):
    def test_constraint_conflicts_are_not_connection_failures(self):
        for native in (2601, 2627, 547, 515, 51025):
            with self.subTest(native=native), patch('app.dao.pyodbc.connect',
                    side_effect=pyodbc.Error('23000', f'private SQL values ({native})')):
                with self.assertRaises(AppError) as caught:
                    with EmployeeDAO({'cashier': 'test'}).connection('cashier'):
                        self.fail('database connection should fail')
                self.assertEqual(caught.exception.status, 409)
                self.assertNotIn('private', caught.exception.message)
