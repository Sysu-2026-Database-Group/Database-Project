"""销售单元测试；真实事务测试需显式设置 BOOKSTORE_SALE_TEST_ADMIN_CONNECTION。

真实测试仅在固定专用副本运行，使用独立SQL服务连接；每例清理自建销售并恢复样例。
"""
import json
import os
import secrets
import re
import threading
import unittest
from decimal import Decimal
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import pyodbc
from werkzeug.security import generate_password_hash

from app import create_app
from app.dao import EmployeeDAO
from app.errors import AppError
from app.sales import SalesService


class QuoteDAO:
    def __init__(self):
        self.created = []

    def sale_quote(self, actor, payload):
        return json.dumps(dict(paid_amount=19, items=payload['items']))

    def sale_create(self, *arguments):
        self.created.append(arguments)
        return dict(no='unit-test-sale')


class SaleValidationTests(unittest.TestCase):
    def setUp(self):
        self.dao = QuoteDAO()
        self.service = SalesService(self.dao, 'sales-unit-test-secret-' * 3)
        self.actor = dict(phone='13800000003', role='收银员', session_version=1)
        self.payload = dict(request_key=str(uuid4()), items=[dict(goods_id=3, quantity=1)], used_points=0)

    def test_reject_invalid_lines_numbers_and_duplicate_items(self):
        for items in ([], [dict(goods_id=3, quantity=0)], [dict(goods_id=True, quantity=1)],
                      [dict(goods_id=3, quantity=1.5)], [dict(goods_id=3, quantity=1001)],
                      [dict(goods_id=3, quantity=1, unit_price=0.01)],
                      [dict(goods_id=3, quantity=1), dict(goods_id=3, quantity=2)]):
            with self.subTest(items=items), self.assertRaises(AppError):
                self.service.preview(self.actor, dict(self.payload, items=items))

    def test_reject_invalid_points_phone_and_request_key(self):
        for change in (dict(used_points=True), dict(used_points=-1), dict(used_points=1.5),
                       dict(member_phone='1390000000０'), dict(request_key='invalid')):
            with self.subTest(change=change), self.assertRaises(AppError):
                self.service.preview(self.actor, dict(self.payload, **change))

    def test_foreign_actor_and_tampered_confirmation_rejected(self):
        result = self.service.preview(self.actor, self.payload)
        for actor, token in ((dict(self.actor, phone='13800000004'), result['quote_token']),
                             (dict(self.actor, session_version=2), result['quote_token']),
                             (self.actor, result['quote_token']+'tampered')):
            with self.subTest(actor=actor), self.assertRaises(AppError):
                self.service.create(actor, token)
        self.assertEqual(self.dao.created, [])

    def test_payload_cannot_override_employee_or_prices(self):
        result = self.service.preview(self.actor, dict(self.payload, cashier_by='13800000001', paid_amount=0))
        self.service.create(self.actor, result['quote_token'])
        actor, key, request, quote = self.dao.created[0]
        self.assertEqual(actor['phone'], '13800000003')
        self.assertNotIn('paid_amount', request)
        self.assertNotIn('cashier_by', request)

    def test_non_cashier_cannot_preview_or_confirm(self):
        for role in ('店长', '库管'):
            with self.subTest(role=role), self.assertRaises(AppError) as error:
                self.service.preview(dict(self.actor, role=role), self.payload)
            self.assertEqual(error.exception.status, 403)


TEST_DATABASE = os.environ.get('BOOKSTORE_SALE_TEST_DATABASE', 'ShiguangBookstoreWeek7SaleTests20261023')


@unittest.skipUnless(os.environ.get('BOOKSTORE_SALE_TEST_ADMIN_CONNECTION'), '未配置专用销售数据库测试连接')
class SaleDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not re.fullmatch(r'ShiguangBookstoreWeek7SaleTests[A-Za-z0-9_]+', TEST_DATABASE):
            raise RuntimeError('销售测试必须使用独立 SaleTests 专用库。')
        cls.login_prefix = os.environ['BOOKSTORE_SALE_TEST_LOGIN_PREFIX']
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,90}', cls.login_prefix):
            raise RuntimeError('无效的测试登录前缀。')
        # 专用配置必须显式提供；绝不从运行连接进行字符串替换或回退。
        cls.connections = {role: os.environ['BOOKSTORE_SALE_TEST_DB_' + role.upper()]
                           for role in ('auth', 'cashier', 'inventory', 'manager')}
        cls.admin = pyodbc.connect(os.environ['BOOKSTORE_SALE_TEST_ADMIN_CONNECTION'], autocommit=True, timeout=5)
        cls.addClassCleanup(cls.admin.close)
        cursor = cls.admin.cursor()
        cls.addClassCleanup(cursor.close)
        cursor.execute('SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET CONCAT_NULL_YIELDS_NULL ON; SET ARITHABORT ON; SET NUMERIC_ROUNDABORT OFF;')
        if cursor.execute('SELECT DB_NAME()').fetchval() != TEST_DATABASE:
            raise RuntimeError('销售集成测试只允许在固定专用副本运行。')
        if cursor.execute('SELECT COUNT(*) FROM auth.employee_credential').fetchval() or cursor.execute("SELECT COUNT(*) FROM dbo.sale WHERE no LIKE 'W7S%'").fetchval():
            raise RuntimeError('测试副本已存在凭据或销售测试数据；拒绝覆盖。')
        cls.created_users = []
        cls.inserted_credentials = False
        cls.original_expiries = []
        cls.addClassCleanup(cls.cleanup_class)
        for role in ('auth','cashier','inventory','manager'):
            login = cls.login_prefix + '_' + role
            if cursor.execute('SELECT DATABASE_PRINCIPAL_ID(?)', (login,)).fetchval() is not None:
                raise RuntimeError('测试数据库中服务用户已存在，请核对前次清理。')
            cursor.execute(f'CREATE USER [{login}] FOR LOGIN [{login}];')
            cls.created_users.append(login)
            cursor.execute(f'ALTER ROLE [bookstore_app_{role}] ADD MEMBER [{login}];')
        expected_server = cursor.execute("SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))").fetchval()
        cls.dao = EmployeeDAO(cls.connections, expected_database=TEST_DATABASE)
        # 在写入凭据或业务数据前逐条实连，核对目标库、实例、真实登录和受限角色。
        for role in cls.connections:
            with cls.dao.connection(role) as connection:
                check = connection.cursor()
                try:
                    identity = check.execute("SELECT DB_NAME(),CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')),ORIGINAL_LOGIN()").fetchone()
                    if tuple(identity) != (TEST_DATABASE, expected_server, cls.login_prefix + '_' + role):
                        raise RuntimeError('测试服务连接指向了错误的数据库、实例或登录。')
                finally:
                    check.close()
        cls.password = secrets.token_urlsafe(24)
        cursor.execute('INSERT auth.employee_credential(employee_phone,password_hash) SELECT phone,? FROM dbo.employee', (generate_password_hash(cls.password),))
        cls.inserted_credentials = True
        cls.original_expiries = [tuple(row) for row in cursor.execute('SELECT phone,expires_at FROM dbo.member')]
        cursor.execute("UPDATE dbo.member SET expires_at=DATEADD(year,1,CONVERT(date,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time'))")
        cls.goods = [tuple(row) for row in cursor.execute('SELECT id,price,stock_total,reserved_qty,on_shelf FROM dbo.goods').fetchall()]
        cls.members = [tuple(row) for row in cursor.execute('SELECT phone,expires_at,points_balance FROM dbo.member').fetchall()]
        cls.cards = [tuple(row) for row in cursor.execute('SELECT level,discount_rate FROM dbo.card_type').fetchall()]
        cls.service = SalesService(cls.dao, 'real-sales-test-secret-' * 3)
        cls.actor = dict(phone='13800000003', role='收银员', session_version=1)
        cls.app = create_app({'TESTING':True, 'SECRET_KEY':'real-sales-test-secret-' * 3}, dao=cls.dao)
        cls.baseline = cls.snapshot()

    @classmethod
    def cleanup_class(cls):
        cursor = cls.admin.cursor()
        try:
            if cls.inserted_credentials:
                cursor.execute('DELETE auth.employee_credential')
            for phone, expires in cls.original_expiries:
                cursor.execute('UPDATE dbo.member SET expires_at=? WHERE phone=?', (expires, phone))
            for login in reversed(cls.created_users):
                cursor.execute(f'DROP USER [{login}]')
        finally:
            cursor.close()

    @classmethod
    def snapshot(cls):
        cursor = cls.admin.cursor()
        result = []
        try:
            for table, key in (('dbo.goods','id'),('dbo.member','phone'),('dbo.card_type','level'),('dbo.sale','id'),('dbo.sale_item','id'),
                               ('dbo.stock_movement','id'),('dbo.point_movement','id'),('dbo.fund_flow','id'),('api.sale_request','employee_phone,request_key')):
                result.append(''.join(row[0] for row in cursor.execute(f'SELECT * FROM {table} ORDER BY {key} FOR JSON PATH,INCLUDE_NULL_VALUES').fetchall()))
            return result
        finally:
            cursor.close()

    def tearDown(self):
        cursor = self.admin.cursor()
        try:
            cursor.execute("IF OBJECT_ID('dbo.sale_test_fail_fund','TR') IS NOT NULL DROP TRIGGER dbo.sale_test_fail_fund")
            cursor.execute('''
                DELETE r FROM api.sale_request r JOIN dbo.sale s ON s.id=r.sale_id WHERE s.no LIKE 'W7S%';
                DELETE f FROM dbo.fund_flow f JOIN dbo.sale s ON s.id=f.sale_id WHERE s.no LIKE 'W7S%';
                DELETE p FROM dbo.point_movement p JOIN dbo.sale s ON s.id=p.sale_id WHERE s.no LIKE 'W7S%';
                DELETE m FROM dbo.stock_movement m JOIN dbo.sale s ON s.id=m.sale_id WHERE s.no LIKE 'W7S%';
                DELETE i FROM dbo.sale_item i JOIN dbo.sale s ON s.id=i.sale_id WHERE s.no LIKE 'W7S%';
                DELETE dbo.sale WHERE no LIKE 'W7S%';
            ''')
            for goods, price, stock, reserved, on_shelf in self.goods:
                cursor.execute('UPDATE dbo.goods SET price=?,stock_total=?,reserved_qty=?,on_shelf=? WHERE id=?', (price,stock,reserved,on_shelf,goods))
            for phone, expires, points in self.members:
                cursor.execute('UPDATE dbo.member SET expires_at=?,points_balance=? WHERE phone=?', (expires,points,phone))
            for level, rate in self.cards:
                cursor.execute('UPDATE dbo.card_type SET discount_rate=? WHERE level=?',(rate,level))
        finally:
            cursor.close()
        self.assertEqual(self.snapshot(), self.baseline, '测试后业务数据未恢复为基线')

    def sql(self, sql, parameters=()):
        cursor = self.admin.cursor()
        try:
            cursor.execute(sql, parameters)
            return [tuple(row) for row in cursor.fetchall()] if cursor.description else None
        finally:
            cursor.close()

    def payload(self, goods=3, quantity=1, member=None, points=0, key=None):
        return dict(items=[dict(goods_id=goods,quantity=quantity)],member_phone=member,used_points=points,request_key=key or str(uuid4()))

    def create_sale(self, payload=None, actor=None):
        actor = actor or self.actor
        preview = self.service.preview(actor, payload or self.payload())
        return self.service.create(actor, preview['quote_token'])

    def test_quote_does_not_write_and_nonmember_sale_reconciles(self):
        preview = self.service.preview(self.actor, self.payload())
        self.assertEqual(self.snapshot(), self.baseline)
        result = self.service.create(self.actor, preview['quote_token'])
        self.assertEqual(result['paid_amount'], 19)
        self.assertEqual(result['cashier_by'], self.actor['phone'])
        self.assertIsNone(result['card_level'])
        self.assertEqual(self.sql('SELECT stock_total,reserved_qty FROM dbo.goods WHERE id=3'), [(9,0)])
        self.assertEqual(self.sql('SELECT quantity,changed_by FROM dbo.stock_movement WHERE sale_id=?',(result['id'],)),[(-1,self.actor['phone'])])
        self.assertEqual(self.sql('SELECT fund_before,fund_after,amount,recorded_by FROM dbo.fund_flow WHERE sale_id=?',(result['id'],)),[(Decimal('555.30'),Decimal('574.30'),19,self.actor['phone'])])
        self.assertEqual(self.sql('SELECT COUNT(*) FROM dbo.point_movement WHERE sale_id=?',(result['id'],)),[(0,)])

    def test_member_discount_points_and_three_ledgers_reconcile(self):
        result = self.create_sale(self.payload(member='13900000003',points=100))
        self.assertEqual((result['paid_amount'],result['point_deduction_amount'],result['earned_points']), (17.05,1,17))
        self.assertEqual(self.sql("SELECT points_balance FROM dbo.member WHERE phone='13900000003'"),[(39,)])
        self.assertEqual(self.sql('SELECT points FROM dbo.point_movement WHERE sale_id=? ORDER BY points',(result['id'],)),[(-100,),(17,)])
        self.assertEqual(self.sql('SELECT g.id FROM dbo.goods g LEFT JOIN dbo.stock_movement m ON m.goods_id=g.id GROUP BY g.id,g.stock_total HAVING g.stock_total<>ISNULL(SUM(m.quantity),0)'),[])
        self.assertEqual(self.sql('SELECT m.phone FROM dbo.member m LEFT JOIN dbo.point_movement p ON p.member_phone=m.phone GROUP BY m.phone,m.points_balance HAVING m.points_balance<>ISNULL(SUM(p.points),0)'),[])

    def test_round_to_zero_creates_sale_without_zero_amount_ledgers(self):
        self.sql('UPDATE dbo.goods SET price=0.01 WHERE id=3')
        self.sql('UPDATE dbo.card_type SET discount_rate=0.01')
        result=self.create_sale(self.payload(member='13900000003'))
        self.assertEqual((result['paid_amount'],result['earned_points']),(0,0))
        self.assertEqual(self.sql('SELECT COUNT(*) FROM dbo.fund_flow WHERE sale_id=?',(result['id'],)),[(0,)])
        self.assertEqual(self.sql('SELECT COUNT(*) FROM dbo.point_movement WHERE sale_id=?',(result['id'],)),[(0,)])
        self.assertEqual(self.sql('SELECT stock_total FROM dbo.goods WHERE id=3'),[(9,)])

    def test_negative_balance_can_earn_but_cannot_redeem(self):
        with self.assertRaises(AppError) as error:
            self.service.preview(self.actor,self.payload(member='13900000001',points=1))
        self.assertEqual(error.exception.code,'points_limit')
        result = self.create_sale(self.payload(member='13900000001'))
        self.assertEqual(result['earned_points'],17)
        self.assertEqual(self.sql("SELECT points_balance FROM dbo.member WHERE phone='13900000001'"),[(-9,)])

    def test_expired_member_full_price_no_points_balance_preserved(self):
        self.sql("UPDATE dbo.member SET expires_at=DATEADD(day,-1,CONVERT(date,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time')) WHERE phone='13900000003'")
        result = self.create_sale(self.payload(member='13900000003'))
        self.assertEqual((result['paid_amount'],result['earned_points'],result['card_level']),(19,0,None))
        self.assertEqual(self.sql("SELECT points_balance FROM dbo.member WHERE phone='13900000003'"),[(122,)])

    def test_expiry_day_inclusive_and_rounding_points_cap(self):
        self.sql("UPDATE dbo.member SET expires_at=CONVERT(date,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time') WHERE phone='13900000003'")
        self.sql('UPDATE dbo.goods SET price=0.07 WHERE id=3')
        preview = self.service.preview(self.actor,self.payload(member='13900000003',points=1))
        self.assertEqual((preview['quote']['discounted_amount'],preview['quote']['paid_amount'],preview['quote']['earned_points']),(0.07,0.06,0))
        with self.assertRaises(AppError) as error:
            self.service.preview(self.actor,self.payload(member='13900000003',points=2))
        self.assertEqual(error.exception.code,'points_limit')
        result = self.service.create(self.actor,preview['quote_token'])
        self.assertEqual(result['earned_points'],0)
        self.assertEqual(self.sql('SELECT points FROM dbo.point_movement WHERE sale_id=?',(result['id'],)),[(-1,)])

    def test_reserved_unshelved_and_missing_goods_rejected_without_writes(self):
        reserved_book = self.sql("SELECT id FROM dbo.goods WHERE book_isbn='9787111000002'")[0][0]
        unshelved_book = self.sql("SELECT id FROM dbo.goods WHERE book_isbn='9787300000001'")[0][0]
        for goods,quantity,code in ((1,1,'insufficient_stock'),(reserved_book,8,'insufficient_stock'),(unshelved_book,1,'goods_unavailable'),(999999,1,'goods_unavailable')):
            with self.subTest(goods=goods),self.assertRaises(AppError) as error:
                self.service.preview(self.actor,self.payload(goods=goods,quantity=quantity))
            self.assertEqual(error.exception.code,code)
        self.assertEqual(self.snapshot(),self.baseline)

    def test_price_change_rejects_old_quote_and_keeps_all_writes_rolled_back(self):
        preview = self.service.preview(self.actor,self.payload())
        self.sql('UPDATE dbo.goods SET price=20 WHERE id=3')
        before = self.snapshot()
        with self.assertRaises(AppError) as error:
            self.service.create(self.actor,preview['quote_token'])
        self.assertEqual(error.exception.code,'quote_changed')
        self.assertEqual(self.snapshot(),before)

    def test_replay_returns_original_after_price_and_balance_changed(self):
        payload = self.payload(member='13900000003',points=100)
        preview = self.service.preview(self.actor,payload)
        first = self.service.create(self.actor,preview['quote_token'])
        self.sql('UPDATE dbo.goods SET price=20 WHERE id=3')
        before = self.snapshot()
        self.assertEqual(self.service.create(self.actor,preview['quote_token']),first)
        self.assertEqual(self.snapshot(),before)
        changed = self.service.preview(self.actor,dict(payload,items=[dict(goods_id=3,quantity=2)],used_points=0))
        with self.assertRaises(AppError) as error:
            self.service.create(self.actor,changed['quote_token'])
        self.assertEqual(error.exception.code,'request_conflict')

    def test_failure_after_stock_and_points_updates_rolls_back_everything(self):
        preview = self.service.preview(self.actor,self.payload(member='13900000003',points=100))
        self.sql("CREATE TRIGGER dbo.sale_test_fail_fund ON dbo.fund_flow AFTER INSERT AS THROW 52999,'injected fund failure',1;")
        with self.assertRaises(AppError) as error:
            self.service.create(self.actor,preview['quote_token'])
        self.assertEqual(error.exception.status,503)
        self.assertEqual(self.snapshot(),self.baseline)
        self.sql('DROP TRIGGER dbo.sale_test_fail_fund')
        self.create_sale(self.payload(member='13900000003',points=100))

    def concurrent_create(self, previews):
        barrier = threading.Barrier(len(previews))
        def execute(preview):
            barrier.wait(timeout=10)
            try:
                return ('ok',self.service.create(self.actor,preview['quote_token']))
            except AppError as error:
                return ('error',error.code)
        with ThreadPoolExecutor(max_workers=len(previews)) as pool:
            return list(pool.map(execute,previews))

    def test_concurrent_same_request_creates_one_sale(self):
        preview = self.service.preview(self.actor,self.payload())
        results = self.concurrent_create([preview,preview])
        self.assertEqual([result[0] for result in results],['ok','ok'])
        self.assertEqual(results[0][1],results[1][1])
        self.assertEqual(self.sql("SELECT COUNT(*) FROM dbo.sale WHERE no LIKE 'W7S%'"),[(1,)])
        self.assertEqual(self.sql('SELECT stock_total FROM dbo.goods WHERE id=3'),[(9,)])

    def test_concurrent_last_available_unit_only_one_sale(self):
        self.sql('UPDATE dbo.goods SET stock_total=1 WHERE id=3')
        previews = [self.service.preview(self.actor,self.payload()) for _ in range(2)]
        results = self.concurrent_create(previews)
        self.assertEqual(sum(result[0]=='ok' for result in results),1)
        self.assertIn(('error','insufficient_stock'),results)
        self.assertEqual(self.sql('SELECT stock_total FROM dbo.goods WHERE id=3'),[(0,)])

    def test_concurrent_member_points_cannot_be_spent_twice(self):
        self.sql("UPDATE dbo.member SET points_balance=100 WHERE phone='13900000003'")
        previews = [self.service.preview(self.actor,self.payload(member='13900000003',points=100)) for _ in range(2)]
        results = self.concurrent_create(previews)
        self.assertEqual(sum(result[0]=='ok' for result in results),1)
        self.assertIn(('error','points_limit'),results)
        self.assertEqual(self.sql("SELECT points_balance FROM dbo.member WHERE phone='13900000003'"),[(17,)])

    def test_concurrent_different_goods_append_consistent_fund_chain(self):
        previews = [self.service.preview(self.actor,self.payload(goods=goods)) for goods in (3,4)]
        results = self.concurrent_create(previews)
        self.assertTrue(all(result[0]=='ok' for result in results),results)
        flows=self.sql("SELECT fund_before,fund_after,amount FROM dbo.fund_flow WHERE sale_id IN(SELECT id FROM dbo.sale WHERE no LIKE 'W7S%') ORDER BY id")
        self.assertEqual(flows[0][0],Decimal('555.30'))
        self.assertEqual(flows[0][1],flows[1][0])
        self.assertEqual(flows[1][1],Decimal('580.30'))

    def test_receipt_is_scoped_to_own_cashier_and_other_roles_denied(self):
        result=self.create_sale()
        self.assertEqual(self.dao.sale_get(self.actor,result['no'])['no'],result['no'])
        with self.assertRaises(AppError) as error:
            self.dao.sale_get(dict(self.actor,phone='13800000004'),result['no'])
        self.assertEqual(error.exception.status,404)
        for role in ('auth','inventory','manager'):
            connection=pyodbc.connect(self.connections[role],autocommit=True,timeout=5)
            try:
                cursor=connection.cursor()
                with self.assertRaises(pyodbc.Error) as error:
                    cursor.execute("EXEC api.usp_sale_catalog '13800000003',1")
                self.assertIn('(229)',str(error.exception))
                cursor.close()
            finally:
                connection.close()

    def test_database_rejects_malformed_lines_and_internal_access(self):
        connection=pyodbc.connect(self.connections['cashier'],autocommit=True,timeout=5)
        cursor=connection.cursor()
        try:
            for raw in ('{}','[]','[1]','[{"goods_id":3,"quantity":0}]',
                        '[{"goods_id":3,"quantity":1.5}]','[{"goods_id":3,"quantity":1},{"goods_id":3,"quantity":1}]',
                        '[{"goods_id":3,"quantity":1,"unit_price":0.01}]'):
                with self.subTest(raw=raw),self.assertRaises(pyodbc.Error) as error:
                    cursor.execute('EXEC api.usp_sale_quote ?,?,?,?,?',(self.actor['phone'],1,raw,None,0)).fetchall()
                self.assertIn('(52101)',str(error.exception))
            for sql in ('SELECT * FROM api.sale_request','SELECT NEXT VALUE FOR api.sale_number',
                        'DECLARE @q nvarchar(max); EXEC api.usp_sale_calculate N\'[]\',NULL,0,@q OUTPUT'):
                with self.subTest(sql=sql),self.assertRaises(pyodbc.Error) as error:
                    cursor.execute(sql).fetchall()
                self.assertIn('(229)',str(error.exception))
        finally:
            cursor.close()
            connection.close()
        self.assertEqual(self.snapshot(),self.baseline)

    def test_flask_sales_flow_csrf_session_actor_and_receipt(self):
        client=self.app.test_client()
        client.get('/auth/login')
        with client.session_transaction() as stored:
            csrf=stored['csrf_token']
        self.assertEqual(client.post('/auth/login',data=dict(phone=self.actor['phone'],password=self.password,csrf_token=csrf)).status_code,302)
        self.assertEqual(client.get('/sales/new').status_code,200)
        self.assertEqual(client.post('/api/sales/preview',json=self.payload()).status_code,403)
        with client.session_transaction() as stored:
            csrf=stored['csrf_token']
        preview=client.post('/api/sales/preview',json=dict(self.payload(),cashier_by='13800000001'),headers={'X-CSRF-Token':csrf})
        self.assertEqual(preview.status_code,200,preview.json)
        token=preview.json['data']['quote_token']
        result=client.post('/api/sales',json=dict(quote_token=token,cashier_by='13800000001'),headers={'X-CSRF-Token':csrf})
        self.assertEqual(result.status_code,200,result.json)
        self.assertEqual(result.json['data']['cashier_by'],self.actor['phone'])
        self.assertEqual(client.get('/sales/'+result.json['data']['no']).status_code,200)
        self.assertEqual(client.post('/api/sales',json={'quote_token':token},headers={'X-CSRF-Token':csrf}).json,result.json)
        for role,phone in (('店长','13800000001'),('库管','13800000002')):
            with client.session_transaction() as stored:
                stored['actor']=dict(phone=phone,role=role,session_version=1)
            self.assertEqual(client.get('/sales/new').status_code,403)

    def test_real_http_form_preview_confirm_receipt_and_repeat(self):
        import re
        from http.cookiejar import CookieJar
        from urllib.parse import urlencode
        from urllib.request import HTTPCookieProcessor, build_opener
        from werkzeug.serving import WSGIRequestHandler, make_server

        class QuietHandler(WSGIRequestHandler):
            def log_request(self, *arguments):
                pass

        server=make_server('127.0.0.1',0,self.app,request_handler=QuietHandler)
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        client=build_opener(HTTPCookieProcessor(CookieJar()))
        base=f'http://127.0.0.1:{server.server_port}'

        def read(path, data=None):
            body=urlencode(data).encode('utf-8') if data is not None else None
            with client.open(base+path,data=body,timeout=10) as response:
                return response.geturl(),response.read().decode('utf-8')

        def hidden(page, name):
            return re.search(r'name="'+name+r'" value="([^"]+)"',page).group(1)

        try:
            _,page=read('/auth/login')
            read('/auth/login',dict(phone=self.actor['phone'],password=self.password,csrf_token=hidden(page,'csrf_token')))
            _,page=read('/sales/new')
            _,preview=read('/sales/preview',dict(quantity_3=1,used_points=0,member_phone='',request_key=hidden(page,'request_key'),csrf_token=hidden(page,'csrf_token')))
            self.assertIn('应收：19.00',preview)
            confirmation=dict(quote_token=hidden(preview,'quote_token'),csrf_token=hidden(preview,'csrf_token'))
            url,receipt=read('/sales',confirmation)
            self.assertIn('销售完成',receipt)
            self.assertIn(self.actor['phone'],receipt)
            retry_url,retry_receipt=read('/sales',confirmation)
            self.assertEqual(retry_url,url)
            self.assertEqual(retry_receipt,receipt)
            self.assertEqual(self.sql("SELECT COUNT(*) FROM dbo.sale WHERE no LIKE 'W7S%'"),[(1,)])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__=='__main__':
    unittest.main()
