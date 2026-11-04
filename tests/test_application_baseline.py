"""Deployment mutation tests on the runner's dedicated authentication copy."""
import os
from pathlib import Path
import re
import subprocess
import unittest

import pyodbc

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get('BOOKSTORE_TEST_ADMIN_CONNECTION'), '未配置独立基线验收库')
class ApplicationBaselineDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.connection = pyodbc.connect(os.environ['BOOKSTORE_TEST_ADMIN_CONNECTION'], autocommit=True)
        cls.addClassCleanup(cls.connection.close)
        cls.cursor = cls.connection.cursor()
        cls.addClassCleanup(cls.cursor.close)
        cls.database, cls.server = cls.cursor.execute(
            "SELECT DB_NAME(),CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))").fetchone()
        if not re.fullmatch(r'ShiguangBookstoreWeek7AuthTests[A-Za-z0-9_]+', cls.database):
            raise RuntimeError('Baseline mutation tests require an isolated AuthTests copy.')

    def check(self, script='application-baseline-check.sql', expected=0):
        result = subprocess.run(['sqlcmd', '-S', self.server, '-E', '-C', '-b', '-f', '65001',
                                 '-l', '10', '-t', '30', '-i', str(ROOT/'db/checks'/script),
                                 '-v', 'DatabaseName='+self.database], capture_output=True)
        if expected == 0:
            self.assertEqual(result.returncode, 0, result.stdout.decode('utf-8', errors='replace'))
        else:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(str(expected).encode(), result.stdout+result.stderr)

    def test_missing_view_is_rejected_and_restored(self):
        for view in ('v_sale_detail', 'v_goods_sales_summary', 'v_inventory_status'):
            definition = self.cursor.execute('SELECT OBJECT_DEFINITION(OBJECT_ID(?))', 'dbo.'+view).fetchval()
            try:
                self.cursor.execute('DROP VIEW dbo.'+view)
                self.check(expected=52201)
            finally:
                self.cursor.execute(definition)
            self.check()

    def test_disabled_trigger_is_rejected(self):
        try:
            self.cursor.execute('DISABLE TRIGGER dbo.tr_card_type_cross_row ON dbo.card_type')
            self.check(expected=52201)
        finally:
            self.cursor.execute('ENABLE TRIGGER dbo.tr_card_type_cross_row ON dbo.card_type')
        self.check()

    def test_missing_or_broad_procedure_permission_is_rejected(self):
        script = 'application-permissions-check.sql'
        try:
            self.cursor.execute('REVOKE EXECUTE ON OBJECT::api.usp_sale_get FROM bookstore_app_cashier')
            self.check(script, expected=52205)
        finally:
            self.cursor.execute('GRANT EXECUTE ON OBJECT::api.usp_sale_get TO bookstore_app_cashier')
        try:
            self.cursor.execute('GRANT EXECUTE ON SCHEMA::api TO bookstore_app_cashier')
            self.check(script, expected=52205)
        finally:
            self.cursor.execute('REVOKE EXECUTE ON SCHEMA::api FROM bookstore_app_cashier')
        self.check(script)

    def test_list_is_restricted_to_own_sales(self):
        try:
            self.cursor.execute("BEGIN TRANSACTION; INSERT auth.employee_credential(employee_phone,password_hash) "
                                "SELECT phone,REPLICATE('x',64) FROM dbo.employee; "
                                "CREATE USER baseline_cashier WITHOUT LOGIN; "
                                "ALTER ROLE bookstore_app_cashier ADD MEMBER baseline_cashier;")
            for phone in ('13800000003', '13800000004'):
                import json
                rows = self.cursor.execute('SELECT no FROM dbo.sale WHERE cashier_by=?', phone).fetchall()
                expected = {row[0] for row in rows}
                self.cursor.execute("EXECUTE AS USER='baseline_cashier'")
                try:
                    raw = self.cursor.execute('EXEC api.usp_sale_list ?,1,1,100', phone).fetchval()
                finally:
                    self.cursor.execute('REVERT')
                result = json.loads(raw)
                self.assertIn('records', result, result)
                self.assertIsInstance(result['records'], list)
                self.assertEqual({row['no'] for row in result['records']}, expected)
                self.assertEqual(result['total'], len(expected))
        finally:
            self.cursor.execute('IF @@TRANCOUNT>0 ROLLBACK')

    def test_empty_page_always_contains_records_array(self):
        try:
            self.cursor.execute("BEGIN TRANSACTION; INSERT auth.employee_credential(employee_phone,password_hash) "
                                "SELECT phone,REPLICATE('x',64) FROM dbo.employee; "
                                "CREATE USER baseline_empty_cashier WITHOUT LOGIN; "
                                "ALTER ROLE bookstore_app_cashier ADD MEMBER baseline_empty_cashier;")
            self.cursor.execute("EXECUTE AS USER='baseline_empty_cashier'")
            try:
                import json
                result = json.loads(self.cursor.execute(
                    "EXEC api.usp_sale_list '13800000003',1,1000000,100").fetchval())
            finally:
                self.cursor.execute('REVERT')
            self.assertIn('records', result, result)
            self.assertEqual(result['records'], [])
            self.assertEqual(result['page'], 1000000)
        finally:
            self.cursor.execute('IF @@TRANCOUNT>0 ROLLBACK')
