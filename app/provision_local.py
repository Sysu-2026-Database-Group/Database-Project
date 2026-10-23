"""为本机 Week7 练习副本一次性配置服务账号、员工口令和本地设置。"""
import argparse
import json
import secrets
from pathlib import Path

import pyodbc
from werkzeug.security import generate_password_hash

from .manage import update_credential
from .local_config import connection_string, restrict_local_file


DATABASE = 'ShiguangBookstoreWeek7EntryYourRun'
ROLES = ('auth', 'cashier', 'inventory', 'manager')
LOGINS = {role: 'bookstore_w7_yourrun_' + role for role in ROLES}
DIRECTORY = Path(__file__).resolve().parent
SETTINGS = DIRECTORY / 'settings.local.ps1'
CREDENTIALS = DIRECTORY / 'demo-credentials.local.json'
ADMIN_CONNECTION = (
    'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;'
    f'DATABASE={DATABASE};Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;'
)


def preflight(cursor, *, database=DATABASE, logins=None, directory=DIRECTORY):
    logins = logins or LOGINS
    if (directory / SETTINGS.name).exists() or (directory / CREDENTIALS.name).exists():
        raise RuntimeError('本地配置已存在；拒绝覆盖，请使用现有配置。')
    if cursor.execute('SELECT DB_NAME()').fetchval() != database:
        raise RuntimeError('连接未指向指定练习副本。')
    if cursor.execute('SELECT COUNT(*) FROM auth.employee_credential').fetchval():
        raise RuntimeError('员工凭据已存在；拒绝覆盖。')
    for role, login in logins.items():
        if cursor.execute('SELECT SUSER_ID(?)', (login,)).fetchval() is not None:
            raise RuntimeError('预定服务登录已存在；拒绝重设口令。')
        if cursor.execute('SELECT DATABASE_PRINCIPAL_ID(?)', (login,)).fetchval() is not None:
            raise RuntimeError('预定服务用户已存在；拒绝覆盖。')
        if cursor.execute('SELECT DATABASE_PRINCIPAL_ID(?)', ('bookstore_app_' + role,)).fetchval() is None:
            raise RuntimeError('入口基础尚未部署。')
    return [tuple(row) for row in cursor.execute('SELECT phone,name,role FROM dbo.employee ORDER BY phone').fetchall()]


def provision(*, database=DATABASE, server='localhost', driver='ODBC Driver 17 for SQL Server',
              login_prefix='bookstore_w7_yourrun', directory=DIRECTORY):
    import re
    if not re.fullmatch(r'ShiguangBookstoreWeek7[A-Za-z0-9_]{1,85}', database):
        raise RuntimeError('无效的 Week7 运行库名。')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,90}', login_prefix):
        raise RuntimeError('无效的服务登录前缀。')
    logins = {role: login_prefix + '_' + role for role in ROLES}
    directory = Path(directory)
    settings, credentials = directory / SETTINGS.name, directory / CREDENTIALS.name
    directory.mkdir(parents=True, exist_ok=True)
    connection = pyodbc.connect(connection_string(server, database, driver), autocommit=False, timeout=5)
    created_files = []
    try:
        cursor = connection.cursor()
        employees = preflight(cursor, database=database, logins=logins, directory=directory)
        if not employees:
            raise RuntimeError('练习副本中没有员工。')
        configuration = {
            'BOOKSTORE_SECRET_KEY': secrets.token_hex(32),
            'BOOKSTORE_COOKIE_SECURE': '0',
            'BOOKSTORE_DATABASE': database,
            'BOOKSTORE_SERVER': server,
            'BOOKSTORE_LOGIN_PREFIX': login_prefix,
        }
        for role, login in logins.items():
            # 标识符来自上方固定映射；口令为程序生成的安全字母表，不接收外部SQL片段。
            password = 'W7!' + secrets.token_urlsafe(32)
            cursor.execute(
                f"CREATE LOGIN [{login}] WITH PASSWORD=N'{password}', "
                f"DEFAULT_DATABASE=[{database}], CHECK_POLICY=ON, CHECK_EXPIRATION=OFF;"
            )
            cursor.execute(f'CREATE USER [{login}] FOR LOGIN [{login}];')
            cursor.execute(f'ALTER ROLE [bookstore_app_{role}] ADD MEMBER [{login}];')
            configuration['BOOKSTORE_DB_' + role.upper()] = connection_string(
                server, database, driver, login=login, password=password)
        demo_employees = []
        for phone, name, role in employees:
            password = 'Demo!' + secrets.token_urlsafe(18)
            update_credential(cursor, phone, generate_password_hash(password))
            demo_employees.append(dict(phone=phone, name=name, role=role, password=password))
        # x 模式禁止覆盖，UTF-8 BOM 让 Windows PowerShell 5 正确读取中文注释。
        with settings.open('x', encoding='utf-8-sig') as output:
            created_files.append(settings)
            output.write('# 本机练习配置，含服务凭据；不要提交。手动点源加载。\n')
            for key, value in configuration.items():
                escaped = value.replace("'", "''")
                output.write(f"$env:{key} = '{escaped}'\n")
        with credentials.open('x', encoding='utf-8') as output:
            created_files.append(credentials)
            json.dump(dict(database=database, purpose='本机练习口令，可用 app.manage 重置', employees=demo_employees),
                      output, ensure_ascii=False, indent=2)
            output.write('\n')
        for path in created_files:
            restrict_local_file(path)
        cursor.close()
        connection.commit()
    except BaseException:
        connection.rollback()
        for path in created_files:
            path.unlink()
        raise
    finally:
        connection.close()
    print('已配置4个受限服务登录及员工练习凭据。')
    print(f'本地设置：{settings}；员工口令：{credentials}（均不输出口令）。')


def verify(*, database=DATABASE, login_prefix='bookstore_w7_yourrun', directory=DIRECTORY):
    """真正通过四个独立SQL登录连接，不使用管理连接或模拟身份。"""
    import os
    from . import create_app
    from .dao import EmployeeDAO

    configuration = {role: os.environ['BOOKSTORE_DB_' + role.upper()] for role in ROLES}
    logins = {role: login_prefix + '_' + role for role in ROLES}
    dao = EmployeeDAO(configuration, expected_database=database)
    for role in ROLES:
        with dao.connection(role) as connection:
            cursor = connection.cursor()
            try:
                identity = cursor.execute('SELECT ORIGINAL_LOGIN(),USER_NAME(),DB_NAME()').fetchone()
                if identity[0] != logins[role] or identity[1] != logins[role] or identity[2] != database:
                    raise RuntimeError('服务连接身份与目标不符。')
                for sql in ('SELECT password_hash FROM auth.employee_credential',
                            'SELECT * FROM dbo.sale'):
                    try:
                        cursor.execute(sql)
                    except pyodbc.Error as error:
                        if '(229)' not in str(error):
                            raise
                    else:
                        raise RuntimeError('服务账号意外拥有底表权限。')
            finally:
                cursor.close()
        print(f'{logins[role]}: independent login and direct-table read denial PASS')
    application = create_app({'TESTING': True}, dao=dao)
    employees = json.loads((Path(directory) / CREDENTIALS.name).read_text(encoding='utf-8'))['employees']
    for employee in employees:
        client = application.test_client()
        if client.get('/api/me').status_code != 401:
            raise RuntimeError('匿名身份查询未被拒绝。')
        client.get('/auth/login')
        with client.session_transaction() as stored:
            token = stored['csrf_token']
        response = client.post('/auth/login', data=dict(phone=employee['phone'], password=employee['password'], csrf_token=token))
        if response.status_code != 302:
            raise RuntimeError('员工实际连接登录失败。')
        response = client.get('/api/me')
        if response.status_code != 200 or response.json['data']['phone'] != employee['phone'] or response.json['data']['role'] != employee['role']:
            raise RuntimeError('员工身份查询不符。')
        if client.get('/').status_code != 200:
            raise RuntimeError('工作台读取失败。')
        expected_sales = 200 if employee['role'] == '收银员' else 403
        if client.get('/sales/new').status_code != expected_sales:
            raise RuntimeError('销售页面岗位边界不符。')
        with client.session_transaction() as stored:
            token = stored['csrf_token']
        if client.post('/auth/logout', data={'csrf_token': token}).status_code != 302 or client.get('/api/me').status_code != 401:
            raise RuntimeError('退出登录验证失败。')
        print(f"employee {employee['phone']}: login, identity, home and logout PASS")


def verify_http(*, port=5000, directory=DIRECTORY):
    """通过本机运行中的HTTP服务验证；口令只放在POST正文，不写入日志。"""
    import re
    from http.cookiejar import CookieJar
    from urllib.error import HTTPError
    from urllib.parse import urlencode
    from urllib.request import HTTPCookieProcessor, build_opener

    base = f'http://127.0.0.1:{port}'
    employees = json.loads((Path(directory) / CREDENTIALS.name).read_text(encoding='utf-8'))['employees']
    for employee in employees:
        client = build_opener(HTTPCookieProcessor(CookieJar()))
        try:
            client.open(base + '/api/me', timeout=10)
        except HTTPError as error:
            if error.code != 401:
                raise
            error.close()
        else:
            raise RuntimeError('匿名HTTP身份查询未被拒绝。')
        with client.open(base + '/auth/login', timeout=10) as response:
            page = response.read().decode('utf-8')
        token = re.search(r'name="csrf_token" value="([A-Za-z0-9_-]+)"', page).group(1)
        body = urlencode(dict(phone=employee['phone'], password=employee['password'], csrf_token=token)).encode('utf-8')
        with client.open(base + '/auth/login', data=body, timeout=10) as response:
            page = response.read().decode('utf-8')
            if response.status != 200 or employee['name'] not in page or employee['role'] not in page:
                raise RuntimeError('HTTP登录后的工作台不符。')
        with client.open(base + '/api/me', timeout=10) as response:
            actor = json.load(response)['data']
        if actor['phone'] != employee['phone'] or actor['role'] != employee['role']:
            raise RuntimeError('HTTP员工身份不符。')
        try:
            with client.open(base + '/sales/new', timeout=10) as response:
                if employee['role'] != '收银员' or response.status != 200:
                    raise RuntimeError('HTTP销售页面岗位边界不符。')
        except HTTPError as error:
            if employee['role'] == '收银员' or error.code != 403:
                raise
            error.close()
        token = re.search(r'name="csrf_token" value="([A-Za-z0-9_-]+)"', page).group(1)
        with client.open(base + '/auth/logout', data=urlencode(dict(csrf_token=token)).encode('utf-8'), timeout=10) as response:
            if not response.geturl().endswith('/auth/login'):
                raise RuntimeError('HTTP退出后未返回登录页。')
        try:
            client.open(base + '/api/me', timeout=10)
        except HTTPError as error:
            if error.code != 401:
                raise
            error.close()
        else:
            raise RuntimeError('HTTP退出后身份仍可用。')
        print(f"employee {employee['phone']}: HTTP login, home, identity and logout PASS")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('check', 'provision', 'verify', 'verify-http'))
    operation = parser.parse_args().operation
    try:
        if operation == 'provision':
            provision()
        elif operation == 'verify':
            verify()
        elif operation == 'verify-http':
            verify_http()
        else:
            with pyodbc.connect(ADMIN_CONNECTION, autocommit=True, timeout=5) as connection:
                cursor = connection.cursor()
                employees = preflight(cursor)
                cursor.close()
            print(f'preflight PASS: target={DATABASE}, employees={len(employees)}, no existing credentials/configuration')
    except Exception as error:
        # 不回显pyodbc异常中的SQL文本或配置，避免意外打印服务口令。
        print(f'操作未完成：{type(error).__name__}。请检查目标库、配置文件及账号状态；不输出连接秘密。')
        raise SystemExit(1) from None


if __name__ == '__main__':
    main()
