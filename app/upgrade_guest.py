"""Add only the public SQL login to an existing Week7 deployment.

Writes a separate restricted configuration file; never rewrites employee
credentials or settings.local.ps1. Run after installing shop-entry.sql.
"""
import argparse
from pathlib import Path
import re
import secrets

import pyodbc

from .local_config import connection_string, restrict_local_file


def upgrade(*, database, login_prefix, directory, server='localhost', driver='ODBC Driver 17 for SQL Server', identity='guest'):
    if identity not in {'guest','task'}:
        raise ValueError('Invalid service identity')
    if not re.fullmatch(r'ShiguangBookstoreWeek7[A-Za-z0-9_]{1,85}', database):
        raise ValueError('Invalid Week7 database')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,90}', login_prefix):
        raise ValueError('Invalid login prefix')
    directory = Path(directory).resolve()
    workspace = Path(__file__).resolve().parents[1]
    if not directory.is_relative_to(workspace) or not (directory/'settings.local.ps1').is_file():
        raise ValueError('Use the existing workspace settings directory')
    output = directory/('settings.'+identity+'.local.ps1')
    if output.exists():
        raise RuntimeError('Guest settings already exist; refusing to overwrite')
    login = login_prefix + '_' + identity
    connection = pyodbc.connect(connection_string(server, database, driver), autocommit=False, timeout=5)
    created_file = False
    try:
        cursor = connection.cursor()
        if cursor.execute('SELECT DB_NAME()').fetchval() != database:
            raise RuntimeError('Unexpected database')
        procedure='api.usp_shop_catalog' if identity=='guest' else 'api.usp_reservations_expire'
        if not cursor.execute("SELECT OBJECT_ID(?,'P')",procedure).fetchval():
            raise RuntimeError('Install shop-entry.sql first')
        if cursor.execute('SELECT SUSER_ID(?)', login).fetchval() is not None or cursor.execute('SELECT DATABASE_PRINCIPAL_ID(?)', login).fetchval() is not None:
            raise RuntimeError('Guest identity already exists; refusing to change its password')
        password = 'W7!' + secrets.token_urlsafe(32)
        cursor.execute(f"CREATE LOGIN [{login}] WITH PASSWORD=N'{password}', DEFAULT_DATABASE=[{database}], CHECK_POLICY=ON, CHECK_EXPIRATION=OFF")
        cursor.execute(f'CREATE USER [{login}] FOR LOGIN [{login}]; ALTER ROLE [bookstore_app_{identity}] ADD MEMBER [{login}];')
        value = connection_string(server, database, driver, login=login, password=password).replace("'", "''")
        with output.open('x', encoding='utf-8-sig') as target:
            created_file = True
            target.write("# Dedicated service secret. Do not commit.\n$env:BOOKSTORE_DB_"+identity.upper()+" = '" + value + "'\n")
        restrict_local_file(output)
        cursor.close()
        connection.commit()
    except BaseException:
        connection.rollback()
        if created_file:
            output.unlink(missing_ok=True)
        raise
    finally:
        connection.close()
    print(f'{identity} login and separate settings.{identity}.local.ps1 created. Employee credentials unchanged.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--login-prefix', required=True)
    parser.add_argument('--directory', default='app')
    parser.add_argument('--server', default='localhost')
    parser.add_argument('--driver', default='ODBC Driver 17 for SQL Server')
    parser.add_argument('--identity',choices=('guest','task'),default='guest')
    try:
        upgrade(**vars(parser.parse_args()))
    except Exception as error:
        print('Guest upgrade failed: ' + type(error).__name__ + '. No connection secrets are printed.')
        raise SystemExit(1) from None


if __name__ == '__main__':
    main()
