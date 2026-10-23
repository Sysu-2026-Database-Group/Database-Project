"""Windows 本机统一入口的编排层。SQL/Python 业务逻辑仍保留在原模块。"""
from __future__ import annotations

import argparse
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone
import hashlib
import importlib.util
from importlib.metadata import version
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
ROLES = ('auth', 'cashier', 'inventory', 'manager')
DEFAULTS = dict(server='localhost', driver='', database='ShiguangBookstoreWeek7EntryYourRun',
                login_prefix='bookstore_w7_yourrun', port=5000, settings_directory='app')


def workspace_path(value):
    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT) or path == ROOT:
        raise RuntimeError('配置和结果文件必须位于项目目录内。')
    return path


def load_configuration(args):
    path = workspace_path(args.config)
    config = dict(DEFAULTS)
    if path.exists():
        values = json.loads(path.read_text(encoding='utf-8-sig'))
        if not isinstance(values, dict) or set(values) - set(DEFAULTS):
            raise RuntimeError('配置必须是对象，且只能包含 run.example.json 中的字段。')
        config.update(values)
    for key in ('server', 'driver', 'database', 'login_prefix', 'port'):
        value = getattr(args, key)
        if value is not None:
            config[key] = value
    if not isinstance(config['server'], str) or not re.fullmatch(r'[A-Za-z0-9_.\\-]+', config['server']):
        raise RuntimeError('此入口仅支持本机实例，例如 localhost 或 localhost\\SQLEXPRESS。')
    # 备份路径由本机 SQL 服务访问；不把远程部署误当本机准备。
    host = config['server'].split('\\')[0].lower()
    if host not in {'localhost', '.', os.environ.get('COMPUTERNAME', '').lower()}:
        raise RuntimeError('此入口仅支持本机 SQL Server；请使用 localhost 或本机实例名。')
    if not isinstance(config['database'], str) or not re.fullmatch(r'ShiguangBookstoreWeek7[A-Za-z0-9_]{1,85}', config['database']):
        raise RuntimeError('运行库必须是 ShiguangBookstoreWeek7 开头的专用库名。')
    if not isinstance(config['login_prefix'], str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,90}', config['login_prefix']):
        raise RuntimeError('服务登录前缀只能包含 ASCII 字母、数字和下划线，且以字母开头。')
    if type(config['port']) is not int or not 1 <= config['port'] <= 65535:
        raise RuntimeError('端口必须在 1 到 65535 之间。')
    if not isinstance(config['driver'], str):
        raise RuntimeError('driver 必须是 ODBC 驱动名称。')
    workspace_path(config['settings_directory'])
    if not config['driver'] and importlib.util.find_spec('pyodbc'):
        import pyodbc
        config['driver'] = next((driver for driver in ('ODBC Driver 18 for SQL Server', 'ODBC Driver 17 for SQL Server')
                                 if driver in pyodbc.drivers()), '')
    return config, path


def safe_error(error):
    # pyodbc 原始错误可能含 SQL 文本或连接参数；只打印 SQLSTATE/原生错误号。
    if type(error).__module__ == 'pyodbc':
        state = str(error.args[0]) if error.args and re.fullmatch(r'[A-Z0-9]{5}', str(error.args[0])) else 'unknown'
        numbers = sorted(set(re.findall(r'\((-?\d+)\)', ' '.join(map(str, error.args)))))
        return f'SQL 连接/操作失败：SQLSTATE={state}, native={",".join(numbers)}。检查实例、Windows 管理权限、驱动及认证方式。'
    if isinstance(error, RuntimeError):
        return str(error)
    return f'{type(error).__name__}：请检查配置格式、文件权限和本步日志；不回显连接秘密。'


class Report:
    def __init__(self, command, config):
        self.run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + secrets.token_hex(3)
        self.directory = ROOT / '.runner' / (command + '-' + self.run_id)
        self.directory.mkdir(parents=True)
        self.data = dict(command=command, run_id=self.run_id, status='RUNNING',
                         config=config, resources=[], steps=[])
        self.save()

    def save(self):
        (self.directory / 'summary.json').write_text(json.dumps(self.data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    def resource(self, kind, name):
        self.data['resources'].append(dict(kind=kind, name=name))
        self.save()

    def action(self, name, function):
        filename = f'{len(self.data["steps"]):02d}-{name}.log'
        print(f'[{name}] ...', flush=True)
        step = dict(name=name, log=filename, status='RUNNING')
        self.data['steps'].append(step)
        self.save()
        try:
            with (self.directory / filename).open('w', encoding='utf-8') as output:
                with redirect_stdout(output), redirect_stderr(output):
                    value = function()
            step['status'] = 'PASS'
            return value
        except BaseException as error:
            step.update(status='FAIL', error=safe_error(error))
            raise
        finally:
            self.save()
            print(f'[{name}] {step["status"]}', flush=True)

    def process(self, name, arguments, *, env=None):
        def execute():
            result = subprocess.run(arguments, cwd=ROOT, env=env, stdout=sys.stdout, stderr=sys.stderr)
            self.data['steps'][-1]['exit_code'] = result.returncode
            if result.returncode:
                raise RuntimeError(f'{name} 失败（退出码 {result.returncode}）；查看本步日志。')
        self.action(name, execute)

    def finish(self, status, error=None):
        self.data['status'] = status
        if error:
            self.data['error'] = safe_error(error)
        self.save()
        sources = sorted(set([ROOT / 'run.ps1', ROOT / 'scripts/project_runner.py', ROOT / 'requirements.txt']
                             + list((ROOT / 'app').glob('*.py')) + list((ROOT / 'tests').glob('test_*.py'))
                             + list((ROOT / 'db').glob('*.sql'))))
        manifest = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
        (self.directory / 'source-hashes.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        print(f'{status}: {self.directory / "summary.json"}', flush=True)


def require_dependencies(config, *, sql=True):
    if sys.version_info < (3, 10):
        raise RuntimeError('需要 Python 3.10 或更新版本；已实测 Python 3.12。')
    missing = [name for name in ('flask', 'pyodbc') if importlib.util.find_spec(name) is None]
    if missing:
        raise RuntimeError('缺少 Python 依赖：' + ', '.join(missing) + '；执行 .\\run.ps1 setup。')
    print(f'Python {sys.version.split()[0]}; Flask {version("Flask")}; pyodbc {version("pyodbc")}')
    if sql:
        import pyodbc
        if config['driver'] not in pyodbc.drivers():
            raise RuntimeError('未找到配置的 ODBC 驱动；安装 Microsoft ODBC Driver 17/18 或通过 -Driver 指定。')
        if not shutil.which('sqlcmd'):
            raise RuntimeError('找不到 sqlcmd；安装 SQL Server 命令行工具并加入 PATH。')


def admin_connection(config, database='master'):
    import pyodbc
    from app.local_config import connection_string
    return pyodbc.connect(connection_string(config['server'], database, config['driver']), autocommit=True, timeout=5)


def check_instance(config):
    connection = admin_connection(config)
    try:
        cursor = connection.cursor()
        try:
            row = cursor.execute("SELECT CONVERT(int,SERVERPROPERTY('IsIntegratedSecurityOnly')),CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')),CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion'))").fetchone()
            print(f'实例：{row[1]}；SQL Server：{row[2]}；驱动：{config["driver"]}')
            if row[0] != 0:
                raise RuntimeError('实例尚未启用 Windows + SQL Server 混合身份验证。请由管理员单独配置并重启；runner 不修改实例认证或重启服务。')
        finally:
            cursor.close()
    finally:
        connection.close()


def sql_script(report, config, name, script, database, **variables):
    arguments = [shutil.which('sqlcmd'), '-S', config['server'], '-E', '-C', '-b', '-f', '65001',
                 '-l', '10', '-t', '180', '-i', str(ROOT / 'db' / script), '-v', 'DatabaseName=' + database]
    arguments += [key + '=' + value for key, value in variables.items()]
    report.process(name, arguments)


def prepare_source(report, config):
    source = 'ShiguangBookstoreWeek6Runner' + report.run_id.replace('T', '').replace('Z', '')
    connection = admin_connection(config)
    try:
        if connection.cursor().execute('SELECT DB_ID(?)', source).fetchval() is not None:
            raise RuntimeError('本次基线库名发生冲突，拒绝复用。')
    finally:
        connection.close()
    report.resource('baseline_database', source)
    scripts = [('schema', 'schema.sql'), ('seed', 'sample-data.sql'), ('baseline-check', 'checks/verify.sql'),
               ('migration', 'migration.sql'), ('migration-check', 'checks/migration-check.sql'),
               ('expanded-seed', 'sample-data-week-6.sql'), ('regression', 'regression.sql')]
    for name, script in scripts:
        sql_script(report, config, name, script, source)
    return source


def prepare_target(report, config, source, target, label):
    report.resource(label + '_database', target)
    sql_script(report, config, label + '-copy', 'prepare-entry-copy.sql', target, SourceDatabaseName=source)
    sql_script(report, config, label + '-auth-schema', 'entry-foundation.sql', target)
    sql_script(report, config, label + '-sales-schema', 'sale-entry.sql', target)


def settings_directory(config):
    return workspace_path(config['settings_directory'])


def business_fingerprints(config, database):
    connection = admin_connection(config, database)
    try:
        cursor = connection.cursor()
        try:
            tables = [row[0] for row in cursor.execute("SELECT name FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo') AND name<>'schema_migration' ORDER BY name").fetchall()]
            if len(tables) != 19:
                raise RuntimeError('业务表数量不符，无法确认测试后的数据恢复。')
            result = {}
            quote = lambda value: '[' + value.replace(']', ']]') + ']'
            for table in tables:
                keys = [row[0] for row in cursor.execute('''SELECT c.name FROM sys.indexes i
                    JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
                    JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
                    WHERE i.is_primary_key=1 AND i.object_id=OBJECT_ID(?) ORDER BY ic.key_ordinal''', 'dbo.' + table).fetchall()]
                if not keys:
                    raise RuntimeError('业务表缺少主键，无法生成稳定数据指纹。')
                raw = ''.join(row[0] for row in cursor.execute('SELECT * FROM dbo.' + quote(table)
                    + ' ORDER BY ' + ','.join(map(quote, keys)) + ' FOR JSON PATH,INCLUDE_NULL_VALUES').fetchall())
                result[table] = hashlib.sha256(raw.encode('utf-8')).hexdigest()
            return result
        finally:
            cursor.close()
    finally:
        connection.close()


def validate_runtime(config):
    from app.dao import EmployeeDAO
    from app import create_app
    connections = {role: os.environ.get('BOOKSTORE_DB_' + role.upper(), '') for role in ROLES}
    if not all(connections.values()):
        raise RuntimeError('缺少四条服务连接；先完成 setup，或检查 settings.local.ps1。')
    dao = EmployeeDAO(connections, expected_database=config['database'])
    actual_server = None
    for role in ROLES:
        with dao.connection(role) as connection:
            cursor = connection.cursor()
            try:
                row = cursor.execute("SELECT ORIGINAL_LOGIN(),USER_NAME(),CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))").fetchone()
                expected_login = config['login_prefix'] + '_' + role
                if row[0] != expected_login or row[1] != expected_login or (actual_server is not None and row[2] != actual_server):
                    raise RuntimeError('服务连接登录或实例不一致；请检查配置，禁止使用管理连接启动应用。')
                actual_server = row[2]
                required = {'auth': ('usp_employee_login_lookup', 'usp_employee_session_lookup'),
                            'cashier': ('usp_employee_context', 'usp_sale_catalog', 'usp_sale_quote', 'usp_sale_create', 'usp_sale_get'),
                            'inventory': ('usp_employee_context',), 'manager': ('usp_employee_context',)}[role]
                for procedure in required:
                    if cursor.execute("SELECT OBJECT_ID(?, 'P')", 'api.' + procedure).fetchval() is None:
                        raise RuntimeError('缺少运行过程或执行授权，请检查入口基础与销售部署。')
            finally:
                cursor.close()
    os.environ['BOOKSTORE_DATABASE'] = config['database']
    create_app()  # 同时验证签名密钥等应用配置，不启动监听。
    print(f'四条实际服务连接及应用配置 PASS；实例={actual_server}，库={config["database"]}')


def setup(report, config, config_path):
    from app.provision_local import provision
    directory = settings_directory(config)
    if any((directory / filename).exists() for filename in ('settings.local.ps1', 'demo-credentials.local.json')):
        raise RuntimeError('本地配置或员工口令已存在，拒绝覆盖。已有环境请执行 doctor/start/verify；新建另一环境请使用独立配置和 settings_directory。')
    connection = admin_connection(config)
    try:
        cursor = connection.cursor()
        try:
            if cursor.execute('SELECT DB_ID(?)', config['database']).fetchval() is not None:
                raise RuntimeError('目标运行库已存在，拒绝覆盖。检查既有环境或指定新的 -DatabaseName。')
            for role in ROLES:
                if cursor.execute('SELECT SUSER_ID(?)', config['login_prefix'] + '_' + role).fetchval() is not None:
                    raise RuntimeError('服务登录前缀已占用，拒绝修改既有口令；请指定新的 -LoginPrefix。')
        finally:
            cursor.close()
    finally:
        connection.close()
    source = prepare_source(report, config)
    prepare_target(report, config, source, config['database'], 'runtime')
    report.resource('service_login_prefix', config['login_prefix'])
    report.action('provision', lambda: provision(database=config['database'], server=config['server'],
                  driver=config['driver'], login_prefix=config['login_prefix'], directory=directory))
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('首次准备完成。配置、基线库和备份均保留；员工口令见本机 demo-credentials.local.json。')


def clean_test_environment():
    return {key: value for key, value in os.environ.items() if not key.startswith('BOOKSTORE_')}


def test_suite(report, *, unit=False, environment=None):
    """独立进程发现测试，防止父进程已导入测试模块时环境变量被冻结。"""
    env = clean_test_environment()
    if not unit:
        if environment is None:
            raise RuntimeError('完整验收必须提供本次隔离环境，不能继承运行连接。')
        env = environment
    result_path = report.directory / 'unittest-results.json'
    args = [sys.executable, str(Path(__file__).resolve()), 'suite', '--results', str(result_path)]
    if unit:
        args.append('--unit')
    try:
        report.process('unit-tests' if unit else 'full-tests', args, env=env)
    finally:
        if result_path.exists():
            report.data['tests'] = json.loads(result_path.read_text(encoding='utf-8'))
            report.save()
    result = report.data['tests']
    print(f'测试：{result["run"]}；失败：{result["failures"]}；错误：{result["errors"]}；跳过：{result["skipped"]}')


def full_test(report, config):
    from app.local_config import connection_string
    source = prepare_source(report, config)
    suffix = report.run_id.replace('T', '').replace('Z', '')
    auth_database = 'ShiguangBookstoreWeek7AuthTests' + suffix
    sale_database = 'ShiguangBookstoreWeek7SaleTests' + suffix
    prepare_target(report, config, source, auth_database, 'auth-test')
    prepare_target(report, config, source, sale_database, 'sale-test')
    baseline = report.action('business-baseline', lambda: business_fingerprints(config, source))
    env = clean_test_environment()
    env.update(BOOKSTORE_TEST_ADMIN_CONNECTION=connection_string(config['server'], auth_database, config['driver']),
               BOOKSTORE_SALE_TEST_ADMIN_CONNECTION=connection_string(config['server'], sale_database, config['driver']),
               BOOKSTORE_SALE_TEST_DATABASE=sale_database)
    prefix = 'bookstore_test_' + secrets.token_hex(8)
    env['BOOKSTORE_SALE_TEST_LOGIN_PREFIX'] = prefix
    logins = []
    connection = admin_connection(config)
    try:
        cursor = connection.cursor()
        try:
            for role in ROLES:
                login, password = prefix + '_' + role, 'W7!' + secrets.token_urlsafe(32)
                # 标识符和密码均由固定安全字母表生成，不接收外部 SQL 输入。
                cursor.execute(f"CREATE LOGIN [{login}] WITH PASSWORD=N'{password}', DEFAULT_DATABASE=[master], CHECK_POLICY=ON, CHECK_EXPIRATION=OFF")
                logins.append(login)
                report.resource('temporary_login', login)
                env['BOOKSTORE_SALE_TEST_DB_' + role.upper()] = connection_string(
                    config['server'], sale_database, config['driver'], login=login, password=password)
        finally:
            cursor.close()
        test_suite(report, environment=env)
        def verify_restored():
            fingerprints = {source: baseline}
            for database in (auth_database, sale_database):
                fingerprints[database] = business_fingerprints(config, database)
                if fingerprints[database] != baseline:
                    raise RuntimeError('测试后业务数据指纹不一致，必须检查测试库；不报告验收通过。')
                check_connection = admin_connection(config, database)
                try:
                    check = check_connection.cursor()
                    try:
                        row = check.execute('''SELECT (SELECT COUNT(*) FROM auth.employee_credential),
                            (SELECT COUNT(*) FROM api.sale_request),
                            (SELECT COUNT(*) FROM sys.database_principals WHERE name LIKE 'bookstore[_]test[_]%'),
                            OBJECT_ID('dbo.sale_test_fail_fund','TR')''').fetchone()
                        if tuple(row) != (0, 0, 0, None):
                            raise RuntimeError('测试凭据、服务用户、请求或故障触发器未清理。')
                    finally:
                        check.close()
                finally:
                    check_connection.close()
            (report.directory / 'business-fingerprints.json').write_text(json.dumps(fingerprints, indent=2) + '\n', encoding='utf-8')
            print('两个测试库的19张业务表与基线逐表一致；测试技术数据和用户已清理。')
        report.action('test-state-restored', verify_restored)
    finally:
        try:
            def cleanup():
                cursor = connection.cursor()
                try:
                    for login in reversed(logins):
                        cursor.execute(f'DROP LOGIN [{login}]')
                    print(f'已清理 {len(logins)} 个本次临时登录；测试库与备份保留供复查。')
                finally:
                    cursor.close()
            report.action('cleanup-test-logins', cleanup)
        finally:
            connection.close()


def iter_tests(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from iter_tests(item)
        else:
            yield item


def run_suite(args):
    tests = list(iter_tests(unittest.defaultTestLoader.discover(str(ROOT / 'tests'))))
    required = {'EntryDatabaseTests', 'SaleDatabaseTests'}
    if args.unit:
        tests = [test for test in tests if type(test).__name__ not in required]
    elif not required <= {type(test).__name__ for test in tests}:
        raise RuntimeError('完整验收未发现必需的数据库测试套件。')
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(tests))
    data = dict(run=result.testsRun, failures=len(result.failures), errors=len(result.errors), skipped=len(result.skipped),
                mode='unit' if args.unit else 'full', successful=result.wasSuccessful() and not result.skipped)
    workspace_path(args.results).write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    return 0 if data['successful'] and data['run'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('help', 'doctor', 'setup', 'start', 'test', 'verify', 'suite'))
    parser.add_argument('--config', default=str(ROOT / 'run.local.json'))
    parser.add_argument('--server')
    parser.add_argument('--driver')
    parser.add_argument('--database')
    parser.add_argument('--login-prefix')
    parser.add_argument('--port', type=int)
    parser.add_argument('--unit', action='store_true')
    parser.add_argument('--http', action='store_true')
    parser.add_argument('--results')
    args = parser.parse_args()
    if args.command == 'help':
        print('Usage: .\\run.ps1 doctor | setup | start | test [-Unit] | verify [-Http]')
        print('Options: -Server localhost\\SQLEXPRESS -Driver "ODBC Driver 18 for SQL Server"')
        print('         -DatabaseName ShiguangBookstoreWeek7Team -LoginPrefix bookstore_team -Port 5000')
        print('         -ConfigFile run.local.json -Python python')
        print('First machine: install Python 3.10+, SQL Server (mixed auth), ODBC 17/18 and sqlcmd.')
        print('Then: setup -> doctor -> test -> start. In another terminal: verify -Http.')
        return 0
    if args.command == 'suite':
        return run_suite(args)
    report = None
    try:
        if args.unit and args.command != 'test' or args.http and args.command != 'verify':
            raise RuntimeError('-Unit 只适用于 test；-Http 只适用于 verify。')
        config, config_path = load_configuration(args)
        report = Report(args.command, config)
        report.action('dependencies', lambda: require_dependencies(config, sql=not args.unit and args.command in ('doctor', 'setup', 'test')))
        if args.command in ('doctor', 'setup') or args.command == 'test' and not args.unit:
            report.action('instance', lambda: check_instance(config))
        if args.command == 'setup':
            setup(report, config, config_path)
        elif args.command == 'doctor':
            report.action('runtime', lambda: validate_runtime(config))
        elif args.command == 'start':
            report.action('runtime', lambda: validate_runtime(config))
            env = clean_test_environment()
            env.update({key: value for key, value in os.environ.items()
                        if key in {'BOOKSTORE_SECRET_KEY', 'BOOKSTORE_COOKIE_SECURE', 'BOOKSTORE_DATABASE'}
                        or key in {'BOOKSTORE_DB_' + role.upper() for role in ROLES}})
            print(f'启动 http://127.0.0.1:{config["port"]}；Ctrl+C 停止。', flush=True)
            code = subprocess.call([sys.executable, '-m', 'flask', '--app', 'app', 'run', '--host', '127.0.0.1',
                                    '--port', str(config['port']), '--no-reload'], cwd=ROOT, env=env)
            if code:
                raise RuntimeError(f'Flask 退出码为 {code}，检查端口是否占用。')
        elif args.command == 'verify':
            from app.provision_local import verify, verify_http
            report.action('runtime', lambda: validate_runtime(config))
            report.action('verify', lambda: verify(database=config['database'], login_prefix=config['login_prefix'], directory=settings_directory(config)))
            if args.http:
                report.action('verify-http', lambda: verify_http(port=config['port'], directory=settings_directory(config)))
        elif args.unit:
            test_suite(report, unit=True)
        else:
            full_test(report, config)
            report.process('week6-artifact-audit', [sys.executable, str(ROOT / 'db/checks/audit-week-6-artifacts.py')])
        report.finish('PASS')
        return 0
    except KeyboardInterrupt:
        if report:
            report.finish('STOPPED')
        return 130
    except Exception as error:
        if report:
            report.finish('FAIL', error)
        print(safe_error(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
