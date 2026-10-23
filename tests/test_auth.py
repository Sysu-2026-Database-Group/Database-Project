import copy
import unittest

from werkzeug.security import generate_password_hash

from app import create_app
from app.errors import DatabaseUnavailable


class MemoryEmployees:
    def __init__(self):
        self.row = dict(phone='13800000003', name='测试收银员', role='收银员',
                        password_hash=generate_password_hash('test-password-123'), enabled=True, session_version=1)
        self.context_calls = []

    def credentials(self, phone):
        return copy.copy(self.row) if phone == self.row['phone'] else None

    def session_identity(self, phone, version):
        if phone == self.row['phone'] and version == self.row['session_version'] and self.row['enabled']:
            return {k: self.row[k] for k in ('phone', 'name', 'role', 'session_version')}

    def employee_context(self, actor):
        self.context_calls.append(copy.copy(actor))
        return {k: actor[k] for k in ('phone', 'name', 'role')}


class AuthenticationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dao = MemoryEmployees()
        cls.original = copy.copy(cls.dao.row)
        cls.app = create_app({'TESTING': True, 'SECRET_KEY': 'test-secret-' * 4}, dao=cls.dao)

    def setUp(self):
        self.dao.row = copy.copy(self.original)
        self.dao.context_calls.clear()
        self.client = self.app.test_client()

    def token(self):
        self.client.get('/auth/login')
        with self.client.session_transaction() as stored:
            return stored['csrf_token']

    def login(self, **extra):
        data = dict(phone='13800000003', password='test-password-123', csrf_token=self.token())
        data.update(extra)
        return self.client.post('/auth/login', data=data)

    def test_anonymous_cannot_read_identity(self):
        self.assertEqual(self.client.get('/api/me').status_code, 401)
        self.assertEqual(self.dao.context_calls, [])

    def test_login_uses_server_role_and_rotates_csrf(self):
        old = self.token()
        self.assertEqual(self.login(role='店长', employee_phone='13800000001').status_code, 302)
        result = self.client.get('/api/me')
        self.assertEqual(result.json['data']['role'], '收银员')
        with self.client.session_transaction() as stored:
            self.assertNotIn('password', stored)
            self.assertNotIn('password_hash', stored)
            self.assertNotEqual(stored['csrf_token'], old)

    def test_wrong_password_unknown_account_and_disabled_have_same_response(self):
        first = self.login(password='wrong').data
        second = self.login(phone='13999999999').data
        self.dao.row['enabled'] = False
        third = self.login().data
        # CSRF token stays constant on these failures, so exact response equality is meaningful.
        self.assertEqual(first, second)
        self.assertEqual(second, third)
        self.assertEqual(self.client.get('/api/me').status_code, 401)

    def test_forged_cookie_rejected(self):
        self.client.set_cookie('session', 'forged-phone-and-manager-role')
        self.assertEqual(self.client.get('/api/me').status_code, 401)

    def test_injected_phone_is_not_used_for_current_identity(self):
        self.login()
        result = self.client.get('/api/me?phone=13800000001&role=店长')
        self.assertEqual(result.json['data']['phone'], '13800000003')

    def test_password_reset_invalidates_old_session(self):
        self.login()
        self.dao.row['session_version'] += 1
        self.assertEqual(self.client.get('/api/me').status_code, 401)
        self.assertEqual(self.dao.context_calls, [])

    def test_disabling_employee_invalidates_old_session(self):
        self.login()
        self.dao.row['enabled'] = False
        self.assertEqual(self.client.get('/api/me').status_code, 401)

    def test_changed_role_requires_login_again(self):
        self.login()
        self.dao.row['role'] = '店长'
        self.assertEqual(self.client.get('/api/me').status_code, 401)

    def test_login_and_logout_require_csrf(self):
        self.assertEqual(self.client.post('/auth/login', data={'phone': '13800000003'}).status_code, 403)
        self.login()
        self.assertEqual(self.client.post('/auth/logout').status_code, 403)
        self.assertEqual(self.client.get('/api/me').status_code, 200)
        with self.client.session_transaction() as stored:
            token = stored['csrf_token']
        self.assertEqual(self.client.post('/auth/logout', data={'csrf_token': token}).status_code, 302)
        self.assertEqual(self.client.get('/api/me').status_code, 401)

    def test_database_failure_does_not_expose_internal_details(self):
        from unittest.mock import patch
        self.login()
        with patch.object(self.dao, 'employee_context', side_effect=DatabaseUnavailable()):
            response = self.client.get('/api/me')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(set(response.json['error']), {'code', 'message'})
        self.assertNotIn('SQL', response.get_data(as_text=True))

    def test_secret_required(self):
        with self.assertRaises(ValueError):
            create_app({'SECRET_KEY': 'short'}, dao=self.dao)


if __name__ == '__main__':
    unittest.main()
