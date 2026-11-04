import json
import os
import unittest
from decimal import Decimal
from uuid import uuid4
from unittest.mock import Mock, patch

from app.errors import AppError
from app.operations import OperationsService, normalize
import test_entry_database as entry_fixture


class OperationsServiceTests(unittest.TestCase):
    def test_reject_overrides_and_lossy_money(self):
        for value in ({'amount': '1.001'}, {'amount': '-1'}, {'amount': 1.5}, {'amount': 'NaN'},
                      {'amount': '50', 'recorded_by': '13800000001'}, {'amount': '1', 'balance': '100'}):
            with self.subTest(value=value), self.assertRaises(AppError):
                normalize('inject', value)

    def test_draft_duplicate_items_and_invalid_quantities_rejected(self):
        line = dict(goods_id=1, quantity=3, unit_cost='10.00')
        for items in ([line, line], [dict(line, quantity=True)], [dict(line, unit_cost='1.234')]):
            with self.assertRaises(AppError):
                normalize('draft', dict(supplier_id=1, items=items))

    def test_money_confirmation_bound_to_actor_and_action(self):
        dao = Mock()
        dao.operation_quote.return_value = json.dumps(dict(action='inject', amount='50.00', expires_at='2099-01-01'))
        service = OperationsService(dao, 'test-secret' * 5)
        actor = dict(phone='13800000001', role='店长', session_version=1)
        envelope = dict(request_key=str(uuid4()), payload={'amount': '50'})
        preview = service.preview(actor, 'inject', envelope)
        dao.operation_write.assert_not_called()
        with self.assertRaises(AppError):
            service.confirm(dict(actor, session_version=2), preview['quote_token'])
        with self.assertRaises(AppError):
            service.preview(dict(actor, role='库管'), 'inject', envelope)
        with self.assertRaises(AppError):
            service.write(actor, 'inject', envelope)
        service.confirm(actor, preview['quote_token'])
        self.assertEqual(dao.operation_write.call_args.args[1:4], ('inject', envelope['request_key'], '{"amount":"50.00"}'))


@unittest.skipUnless(os.environ.get('BOOKSTORE_TEST_ADMIN_CONNECTION'), '未配置隔离数据库测试连接')
class OperationsDatabaseTests(unittest.TestCase):
    """Each case owns one rollback transaction on the runner's fresh auth copy.

    SQL runs under actual restricted database users. A failed XACT_ABORT write
    can roll back the whole fixture; subsequent assertions only inspect baseline.
    """
    connect_as = entry_fixture.EntryDatabaseTests.connect_as
    login = entry_fixture.EntryDatabaseTests.login
    assert_sql_denied = entry_fixture.EntryDatabaseTests.assert_sql_denied

    def setUp(self):
        entry_fixture.EntryDatabaseTests.setUpClass.__func__(type(self))
        self.addCleanup(self.connection.close)
        self.addCleanup(self.connection.rollback)
        self.patch = patch('app.dao.pyodbc.connect', side_effect=self.connect_as)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.service = OperationsService(self.dao, 'operations-test-secret' * 3)
        self.manager = dict(phone='13800000001', role='店长', session_version=1)
        self.inventory = dict(phone='13800000002', role='库管', session_version=1)
        self.client = self.app.test_client()

    def write(self, action, data, actor=None, key=None):
        actor = actor or self.inventory
        return self.service.write(actor, action, dict(request_key=key or str(uuid4()), payload=data))

    def scalar(self, sql, *args):
        return self.connection.cursor().execute(sql, args).fetchval()

    def monetary(self, action, data):
        preview = self.service.preview(self.manager, action, dict(request_key=str(uuid4()), payload=data))
        return self.service.confirm(self.manager, preview['quote_token']), preview

    def setup_purchase(self):
        goods = self.write('goods_save', dict(name='P2测试文创', category='文创', code='P2-TEST', spec='测试规格'))['id']
        supplier = self.write('supplier_save', dict(name='P2测试供应商'))['id']
        self.write('quote_save', dict(supplier_id=supplier, goods_id=goods, amount='10.00'))
        purchase = self.write('draft', dict(supplier_id=supplier, items=[dict(goods_id=goods, quantity=3, unit_cost='10.00')]))['id']
        return goods, supplier, purchase

    def test_zero_funds_to_injection_purchase_payment_and_receipt(self):
        # Clear only this transaction's isolated fixture cash; teardown rolls back.
        self.connection.cursor().execute('DELETE dbo.fund_flow')
        goods, supplier, purchase = self.setup_purchase()
        row = self.connection.cursor().execute('SELECT price,on_shelf,stock_total,reserved_qty FROM dbo.goods WHERE id=?', goods).fetchone()
        self.assertEqual(tuple(row), (None, False, 0, 0))
        self.write('price', dict(id=goods, amount='19.00', on_shelf=True), self.manager)
        self.write('submit', dict(id=purchase))
        self.write('approve', dict(id=purchase), self.manager)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM dbo.fund_flow'), 0)
        result, preview = self.monetary('inject', dict(amount='50.00'))
        self.assertEqual(self.service.confirm(self.manager, preview['quote_token']), result)
        self.assertEqual(self.scalar('SELECT TOP(1) fund_after FROM dbo.fund_flow ORDER BY id DESC'), Decimal('50'))
        paid, payment = self.monetary('pay', dict(id=purchase))
        # Expired confirmations still return a previously successful result.
        value = self.service.signer.loads(payment['quote_token'])
        quote = json.loads(value['quote']); quote['expires_at'] = '2000-01-01'
        value['quote'] = json.dumps(quote)
        self.assertEqual(self.service.confirm(self.manager, self.service.signer.dumps(value)), paid)
        self.assertEqual(self.scalar('SELECT TOP(1) fund_after FROM dbo.fund_flow ORDER BY id DESC'), Decimal('20'))
        key = str(uuid4())
        received = self.write('receive', dict(id=purchase), key=key)
        self.assertEqual(self.write('receive', dict(id=purchase), key=key), received)
        self.assertEqual(self.scalar('SELECT stock_total FROM dbo.goods WHERE id=?', goods), 3)
        self.assertEqual(self.scalar('SELECT SUM(quantity) FROM dbo.stock_movement WHERE request_id=?', purchase), 3)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM dbo.fund_flow WHERE request_id=?', purchase), 1)
        self.assertEqual(self.scalar('SELECT status FROM dbo.purchase_request WHERE id=?', purchase), '已收货')
        self.assertEqual(self.scalar("SELECT SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END) FROM dbo.fund_flow WHERE reason_type NOT IN (N'注资',N'提现')"), Decimal('-30'))

    def test_draft_edit_remove_and_cancellation_preserve_document(self):
        goods, supplier, purchase = self.setup_purchase()
        self.write('draft', dict(id=purchase, supplier_id=supplier, items=[]))
        self.assertEqual(self.dao.operation_read(self.inventory, 'purchase', id=purchase)['items'], [])
        self.write('draft', dict(id=purchase, supplier_id=supplier, items=[dict(goods_id=goods, quantity=2, unit_cost='11.25')]))
        self.write('cancel', dict(id=purchase), self.manager)
        self.assertEqual(self.scalar('SELECT status FROM dbo.purchase_request WHERE id=?', purchase), '已取消')
        self.assertEqual(self.scalar('SELECT request_qty FROM dbo.purchase_request_item WHERE request_id=?', purchase), 2)

    def test_receive_without_payment_rolls_back_and_does_not_add_stock(self):
        goods, supplier, purchase = self.setup_purchase()
        self.write('submit', dict(id=purchase))
        self.write('approve', dict(id=purchase), self.manager)
        with self.assertRaises(AppError) as caught:
            self.write('receive', dict(id=purchase))
        self.assertEqual(caught.exception.code, 'operation_conflict')
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM dbo.goods WHERE toy_code='P2-TEST'"), 0)

    def test_insufficient_funds_has_no_partial_payment(self):
        self.connection.cursor().execute('DELETE dbo.fund_flow')
        goods, supplier, purchase = self.setup_purchase()
        self.write('submit', dict(id=purchase))
        self.write('approve', dict(id=purchase), self.manager)
        preview = self.service.preview(self.manager, 'pay', dict(request_key=str(uuid4()), payload=dict(id=purchase)))
        with self.assertRaises(AppError) as caught:
            self.service.confirm(self.manager, preview['quote_token'])
        self.assertEqual(caught.exception.code, 'insufficient_funds')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM api.operation_request'), 0)

    def test_sql_role_checks_and_table_denials(self):
        self.assert_sql_denied('cashier', "EXEC api.usp_operation_read '13800000003',1,'goods'")
        self.assert_sql_denied('inventory', "EXEC api.usp_operation_read '13800000002',1,'finance'", expected=52003)
        self.assert_sql_denied('inventory', 'SELECT * FROM api.operation_request')
        # Actor check precedes any domain writes; this rejection rolls back fixture DDL.
        self.assert_sql_denied('manager', "EXEC api.usp_operation_write '13800000001',1,'receive','00000000-0000-0000-0000-000000000001',N'{}'", expected=52003)

    def test_pages_forms_and_csrf_under_restricted_sql_identity(self):
        self.login('13800000002')
        for path in ('/goods', '/suppliers', '/supplier-quotes', '/purchases', '/inventory'):
            self.assertEqual(self.client.get(path).status_code, 200, path)
        self.assertEqual(self.client.post('/operations/supplier_save', data={'name': 'no csrf'}).status_code, 403)
        self.login('13800000001')
        self.assertEqual(self.client.get('/management/finance').status_code, 200)
        self.assertEqual(self.client.get('/management/goods').status_code, 200)

    def test_real_form_workflow_previews_confirms_and_renders_purchase(self):
        def post(action, data, suffix=''):
            with self.client.session_transaction() as stored:
                token = stored['csrf_token']
            return self.client.post('/operations/' + action + suffix, data=dict(
                csrf_token=token, request_key=str(uuid4()), **data))

        self.login('13800000002')
        self.assertEqual(post('supplier_save', dict(name='P2表单供应商')).status_code, 303)
        supplier = self.scalar("SELECT id FROM dbo.supplier WHERE name=N'P2表单供应商'")
        self.assertEqual(post('goods_save', dict(name='P2表单商品', category='文创', code='P2-FORM', spec='礼盒',
                                              author='', publisher='', page_count='')).status_code, 303)
        goods = self.scalar("SELECT id FROM dbo.goods WHERE toy_code='P2-FORM'")
        self.assertEqual(post('quote_save', dict(supplier_id=str(supplier), goods_id=str(goods), amount='10')).status_code, 303)
        created = post('draft', dict(supplier_id=str(supplier)))
        self.assertEqual(created.status_code, 303)
        path = created.headers['Location']
        purchase = int(path.rsplit('/', 1)[1])
        self.assertEqual(self.client.get(path).status_code, 200)
        self.assertEqual(post('draft', dict(id=str(purchase), supplier_id=str(supplier), goods_id_0=str(goods),
                                           quantity_0='3', unit_cost_0='10')).status_code, 303)
        self.assertEqual(post('submit', dict(id=str(purchase))).status_code, 303)
        self.login('13800000001')
        self.assertEqual(post('approve', dict(id=str(purchase))).status_code, 303)
        preview = post('pay', dict(id=str(purchase)), '/preview')
        self.assertEqual(preview.status_code, 200)
        import re
        from html import unescape
        quote_token = unescape(re.search(r'name="quote_token" value="([^"]+)"', preview.text).group(1))
        with self.client.session_transaction() as stored:
            csrf = stored['csrf_token']
        confirmation = dict(csrf_token=csrf, quote_token=quote_token)
        self.assertEqual(self.client.post('/operations/confirm', data=confirmation).status_code, 303)
        self.assertEqual(self.client.post('/operations/confirm', data=confirmation).status_code, 303)
        self.login('13800000002')
        self.assertEqual(post('receive', dict(id=str(purchase))).status_code, 303)
        self.assertIn('已收货', self.client.get(path).text)

    def test_damage_keeps_reserved_stock_and_requires_reason(self):
        before = self.connection.cursor().execute('SELECT stock_total,reserved_qty FROM dbo.goods WHERE id=3').fetchone()
        self.write('damage', dict(id=3, quantity=1, note='包装破损'))
        after = self.connection.cursor().execute('SELECT stock_total,reserved_qty FROM dbo.goods WHERE id=3').fetchone()
        self.assertEqual(tuple(after), (before[0]-1, before[1]))
        self.assertEqual(self.scalar("SELECT quantity FROM dbo.stock_movement WHERE goods_id=3 AND note=N'包装破损'"), -1)
        self.connection.cursor().execute('UPDATE dbo.goods SET reserved_qty=stock_total WHERE id=3')
        with self.assertRaises(AppError) as caught:
            self.write('damage', dict(id=3, quantity=1, note='不可损坏预订商品'))
        self.assertEqual(caught.exception.code, 'operation_conflict')

    def test_expired_preview_before_success_is_rejected(self):
        preview = self.service.preview(self.manager, 'inject', dict(request_key=str(uuid4()), payload=dict(amount='50')))
        value = self.service.signer.loads(preview['quote_token'])
        quote = json.loads(value['quote']); quote['expires_at'] = '2000-01-01'
        value['quote'] = json.dumps(quote)
        with self.assertRaises(AppError) as caught:
            self.service.confirm(self.manager, self.service.signer.dumps(value))
        self.assertEqual(caught.exception.code, 'quote_changed')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM api.operation_request'), 0)

    def test_failure_after_inventory_change_rolls_back_all_receipt_writes(self):
        goods, supplier, purchase = self.setup_purchase()
        self.write('submit', dict(id=purchase))
        self.write('approve', dict(id=purchase), self.manager)
        self.monetary('pay', dict(id=purchase))
        self.connection.cursor().execute("""CREATE TRIGGER dbo.p2_test_fail_stock ON dbo.stock_movement AFTER INSERT AS
            THROW 52302,N'Injected stock failure',1;""")
        with self.assertRaises(AppError):
            self.write('receive', dict(id=purchase))
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM dbo.goods WHERE toy_code='P2-TEST'"), 0)
        self.assertEqual(self.scalar("SELECT OBJECT_ID('dbo.p2_test_fail_stock','TR')"), None)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM api.operation_request'), 0)
