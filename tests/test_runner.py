"""统一入口的隔离及失败判定；不连接真实数据库。"""
import argparse
from contextlib import redirect_stderr
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from app.dao import EmployeeDAO
from app.errors import DatabaseUnavailable
from app.local_config import connection_string
from scripts import project_runner as runner


class RunnerSafetyTests(unittest.TestCase):
    def test_odbc_values_escape_delimiters_and_closing_braces(self):
        value = connection_string('localhost\\SQLEXPRESS', 'a;b', 'ODBC Driver 18 for SQL Server',
                                  login='service', password="p;}x'$")
        self.assertIn('DATABASE={a;b};', value)
        self.assertIn("PWD={p;}}x'$};", value)
        self.assertNotIn('Trusted_Connection', value)

    def test_runtime_database_mismatch_rejected_before_business_call(self):
        connection = MagicMock()
        connection.cursor.return_value.execute.return_value.fetchone.return_value = (
            'service', 0, 0, 0, 1, 0, 0, 'runtime_database')
        with patch('app.dao.pyodbc.connect', return_value=connection):
            with self.assertRaises(DatabaseUnavailable):
                with EmployeeDAO({'cashier': 'connection'}, expected_database='test_database').connection('cashier'):
                    self.fail('不应允许在错误数据库执行业务')
        connection.close.assert_called_once()

    def test_test_environment_discards_inherited_runtime_and_admin_connections(self):
        with patch.dict(os.environ, {'BOOKSTORE_DB_CASHIER': 'secret', 'BOOKSTORE_DB_ADMIN': 'admin',
                                    'BOOKSTORE_SALE_TEST_ADMIN_CONNECTION': 'old'}, clear=False):
            self.assertFalse(any(key.startswith('BOOKSTORE_') for key in runner.clean_test_environment()))

    def test_sale_fixture_cannot_fall_back_to_runtime_connection(self):
        from test_sales import SaleDatabaseTests
        with patch.dict(os.environ, {'BOOKSTORE_SALE_TEST_LOGIN_PREFIX': 'test_service',
                                     'BOOKSTORE_DB_AUTH': 'runtime'}, clear=True):
            with patch('test_sales.pyodbc.connect') as connect:
                with self.assertRaises(KeyError):
                    SaleDatabaseTests.setUpClass()
                connect.assert_not_called()

    def test_paths_cannot_escape_workspace(self):
        with self.assertRaises(RuntimeError):
            runner.workspace_path('../outside.json')

    def test_sql_error_diagnostics_do_not_disclose_password_or_sql(self):
        import pyodbc
        message = runner.safe_error(pyodbc.Error('28000', 'password=private; SQL CREATE LOGIN private (18456)'))
        self.assertIn('18456', message)
        self.assertNotIn('private', message)
        self.assertNotIn('CREATE LOGIN', message)

    def test_full_acceptance_with_skipped_required_suites_returns_failure(self):
        missing = lambda case: case.skipTest('missing database configuration')
        suite = unittest.TestSuite([type(name, (unittest.TestCase,), {'runTest': missing})()
                                   for name in ('EntryDatabaseTests', 'SaleDatabaseTests')])
        directory = runner.ROOT / '.runner'
        directory.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=directory) as temporary:
            result_path = Path(temporary) / 'results.json'
            with patch.object(unittest.defaultTestLoader, 'discover', return_value=suite), redirect_stderr(io.StringIO()):
                self.assertEqual(runner.run_suite(argparse.Namespace(unit=False, results=str(result_path))), 1)
            result = json.loads(result_path.read_text(encoding='utf-8'))
            self.assertEqual(result['skipped'], 2)
            self.assertFalse(result['successful'])

    def test_full_acceptance_requires_both_database_suites(self):
        with patch.object(unittest.defaultTestLoader, 'discover', return_value=unittest.TestSuite()):
            with self.assertRaises(RuntimeError):
                runner.run_suite(argparse.Namespace(unit=False, results='unused.json'))

    def test_full_suite_refuses_implicit_environment(self):
        with self.assertRaises(RuntimeError):
            runner.test_suite(MagicMock())

    def test_provision_file_permission_failure_rolls_back_credentials_and_files(self):
        from app.provision_local import provision
        connection = MagicMock()
        directory = runner.ROOT / '.runner'
        directory.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=directory) as temporary:
            with patch('app.provision_local.pyodbc.connect', return_value=connection), \
                 patch('app.provision_local.preflight', return_value=[('13800000001', '练习员工', '店长')]), \
                 patch('app.provision_local.update_credential'), \
                 patch('app.provision_local.restrict_local_file', side_effect=PermissionError('denied')):
                with self.assertRaises(PermissionError):
                    provision(directory=Path(temporary))
            self.assertFalse((Path(temporary) / 'settings.local.ps1').exists())
            self.assertFalse((Path(temporary) / 'demo-credentials.local.json').exists())
        connection.rollback.assert_called_once()
        connection.commit.assert_not_called()
        connection.close.assert_called_once()
