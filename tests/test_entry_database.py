"""真实 SQL Server 权限/Flask集成测试；默认跳过，显式设置测试连接后执行。

仅用于 Week7 新练习副本。测试用户和凭据都在一个管理连接事务内，结束后回滚。
Flask DAO 的 connect 被替换为该连接上的 EXECUTE AS USER；SQL仍在真实受限用户下执行。
这不替代未来四个独立运行账号的真实登录部署验收。
"""
import os
import secrets
import unittest
from unittest.mock import patch

import pyodbc
from werkzeug.security import generate_password_hash

from app import create_app
from app.dao import EmployeeDAO
from app.errors import DatabaseUnavailable
from app.manage import update_credential


@unittest.skipUnless(os.environ.get('BOOKSTORE_TEST_ADMIN_CONNECTION'), '未配置隔离数据库测试连接')
class EntryDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.connection = pyodbc.connect(os.environ['BOOKSTORE_TEST_ADMIN_CONNECTION'], autocommit=False, timeout=5)
        try:
            cursor = cls.connection.cursor()
            database = cursor.execute('SELECT DB_NAME()').fetchval()
            if not database.startswith('ShiguangBookstoreWeek7'):
                raise RuntimeError('集成测试只能在 Week7 练习副本运行')
            if cursor.execute('SELECT COUNT(*) FROM auth.employee_credential').fetchval():
                raise RuntimeError('请使用未配置员工凭据的新副本，测试不会覆盖现有凭据')
            cls.users = {}
            for role in ('auth', 'cashier', 'inventory', 'manager'):
                # 所有标识符由固定前缀与随机十六进制构成，不使用外部SQL输入。
                user = 'entry_test_' + role + '_' + secrets.token_hex(4)
                cls.users[role] = user
                cursor.execute(f'CREATE USER [{user}] WITHOUT LOGIN; ALTER ROLE [bookstore_app_{role}] ADD MEMBER [{user}];')
            cls.password = secrets.token_urlsafe(24)
            password_hash = generate_password_hash(cls.password)
            cursor.execute('''INSERT auth.employee_credential(employee_phone,password_hash)
                              SELECT phone,? FROM dbo.employee;''', (password_hash,))
            cls.dao = EmployeeDAO({key: key for key in cls.users})
            cls.app = create_app({'TESTING': True, 'SECRET_KEY': secrets.token_hex(32)}, dao=cls.dao)
            cursor.close()
        except BaseException:
            cls.connection.rollback()
            cls.connection.close()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.connection.rollback()
        cls.connection.close()

    def setUp(self):
        self.client = self.app.test_client()

    def connect_as(self, key, **kwargs):
        connection = self.connection
        user = self.users[key]
        cursor = connection.cursor()
        cursor.execute(f'EXECUTE AS USER=N\'{user}\';')
        cursor.close()

        class BorrowedConnection:
            timeout = 15

            def cursor(self):
                return connection.cursor()

            def close(self):
                cursor = connection.cursor()
                cursor.execute('REVERT;')
                cursor.close()

        return BorrowedConnection()

    def assert_sql_denied(self, key, sql, parameters=(), expected=229):
        borrowed = self.connect_as(key)
        cursor = borrowed.cursor()
        try:
            with self.assertRaises(pyodbc.Error) as caught:
                cursor.execute(sql, parameters).fetchall()
            self.assertIn(f'({expected})', str(caught.exception))
        finally:
            cursor.close()
            borrowed.close()

    def login(self, phone):
        self.client.get('/auth/login')
        with self.client.session_transaction() as stored:
            token = stored['csrf_token']
        return self.client.post('/auth/login', data=dict(phone=phone, password=self.password, csrf_token=token))

    def test_all_roles_can_login_and_read_own_context_through_procedures(self):
        for phone, role in (('13800000001', '店长'), ('13800000002', '库管'), ('13800000003', '收银员'), ('13800000004', '收银员')):
            with self.subTest(role=role, phone=phone), patch('app.dao.pyodbc.connect', side_effect=self.connect_as):
                self.client = self.app.test_client()
                self.assertEqual(self.login(phone).status_code, 302)
                result = self.client.get('/api/me')
                self.assertEqual(result.status_code, 200)
                self.assertEqual(result.json['data']['phone'], phone)
                self.assertEqual(result.json['data']['role'], role)

    def test_all_runtime_roles_cannot_directly_read_credentials(self):
        for key in self.users:
            with self.subTest(role=key):
                self.assert_sql_denied(key, 'SELECT password_hash FROM auth.employee_credential')

    def test_runtime_roles_cannot_write_business_tables(self):
        for key in self.users:
            with self.subTest(role=key):
                self.assert_sql_denied(key, 'UPDATE dbo.goods SET stock_total=stock_total WHERE id=1')
                self.assert_sql_denied(key, "INSERT dbo.sale(no,cashier_by,subtotal_amount,paid_amount) VALUES('ENTRY-UNAUTHORIZED','13800000003',0,0)")

    def test_cashier_cannot_read_other_cashiers_sales_directly(self):
        self.assert_sql_denied('cashier', 'SELECT * FROM dbo.sale')

    def test_runtime_role_cannot_fetch_password_hash_via_auth_procedure(self):
        self.assert_sql_denied('cashier', "EXEC api.usp_employee_login_lookup '13800000003'")

    def test_auth_role_cannot_call_business_context(self):
        self.assert_sql_denied('auth', "EXEC api.usp_employee_context '13800000003',1")

    def test_helper_cannot_be_called_directly(self):
        self.assert_sql_denied('cashier', "EXEC api.usp_require_employee '13800000003',1,N'收银员'")

    def test_wrong_employee_role_rejected_inside_database(self):
        self.assert_sql_denied('cashier', "EXEC api.usp_employee_context '13800000001',1", expected=52001)

    def test_stale_session_rejected_inside_database(self):
        self.assert_sql_denied('cashier', "EXEC api.usp_employee_context '13800000003',2", expected=52001)

    def test_disabled_employee_rejected_inside_database(self):
        self.connection.cursor().execute("UPDATE auth.employee_credential SET enabled=0 WHERE employee_phone='13800000003'")
        try:
            self.assert_sql_denied('cashier', "EXEC api.usp_employee_context '13800000003',1", expected=52001)
        finally:
            self.connection.cursor().execute("UPDATE auth.employee_credential SET enabled=1 WHERE employee_phone='13800000003'")

    def test_database_owner_cannot_be_used_as_runtime_connection(self):
        class BorrowedOwner:
            timeout = 15

            def cursor(inner):
                return self.connection.cursor()

            def close(inner):
                pass

        with patch('app.dao.pyodbc.connect', return_value=BorrowedOwner()):
            with self.assertRaises(DatabaseUnavailable):
                self.dao.credentials('13800000003')

    def test_multiple_application_roles_are_rejected(self):
        user = self.users['cashier']
        self.connection.cursor().execute(f'ALTER ROLE bookstore_app_manager ADD MEMBER [{user}]')
        try:
            self.assert_sql_denied('cashier', "EXEC api.usp_employee_context '13800000003',1", expected=52003)
        finally:
            self.connection.cursor().execute(f'ALTER ROLE bookstore_app_manager DROP MEMBER [{user}]')

    def test_management_reset_and_disable_invalidate_old_session(self):
        cursor = self.connection.cursor()
        cursor.execute('SAVE TRANSACTION credential_management_test;')
        try:
            update_credential(cursor, '13800000003', generate_password_hash('replacement-password'))
            self.assert_sql_denied('cashier', "EXEC api.usp_employee_context '13800000003',1", expected=52001)
            with patch('app.dao.pyodbc.connect', side_effect=self.connect_as):
                self.assertIsNone(self.dao.session_identity('13800000003', 1))
                self.assertEqual(self.dao.session_identity('13800000003', 2)['role'], '收银员')
            update_credential(cursor, '13800000003')
            with patch('app.dao.pyodbc.connect', side_effect=self.connect_as):
                self.assertIsNone(self.dao.session_identity('13800000003', 2))
        finally:
            cursor.execute('ROLLBACK TRANSACTION credential_management_test;')
            cursor.close()

    def test_management_can_initialize_missing_credential_without_changing_employee(self):
        cursor = self.connection.cursor()
        cursor.execute('SAVE TRANSACTION credential_create_test;')
        try:
            cursor.execute("DELETE auth.employee_credential WHERE employee_phone='13800000004'")
            update_credential(cursor, '13800000004', generate_password_hash('initial-password'))
            row = cursor.execute("SELECT session_version,enabled FROM auth.employee_credential WHERE employee_phone='13800000004'").fetchone()
            self.assertEqual(tuple(row), (1, True))
            cursor.fetchall()
        finally:
            cursor.execute('ROLLBACK TRANSACTION credential_create_test;')
            cursor.close()


if __name__ == '__main__':
    unittest.main()
