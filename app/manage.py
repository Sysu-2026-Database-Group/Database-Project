"""本机部署工具：由项目组配置凭据，运行服务账号没有此权限。"""
import argparse
import getpass
import os
import re

import pyodbc
from werkzeug.security import generate_password_hash


def update_credential(cursor, phone, password_hash=None):
    """只执行凭据变更；事务由部署工具或测试调用者提交/回滚。"""
    if password_hash:
        cursor.execute('''
            SET NOCOUNT ON;
            IF NOT EXISTS(SELECT 1 FROM dbo.employee WHERE phone=?)
                THROW 52004,N'员工不存在，请先完成员工建档。',1;
            UPDATE auth.employee_credential WITH(UPDLOCK,SERIALIZABLE)
            SET password_hash=?, enabled=1, session_version=session_version+1, updated_at=SYSDATETIME()
            WHERE employee_phone=?;
            IF @@ROWCOUNT=0
                INSERT auth.employee_credential(employee_phone,password_hash) VALUES(?,?);
        ''', (phone, password_hash, phone, phone, password_hash))
    else:
        cursor.execute('''
            SET NOCOUNT ON;
            UPDATE auth.employee_credential
            SET enabled=0,session_version=session_version+1,updated_at=SYSDATETIME()
            WHERE employee_phone=?;
            IF @@ROWCOUNT=0 THROW 52004,N'员工尚未配置登录凭据。',1;
        ''', (phone,))
    while cursor.nextset():
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('set-password', 'disable'))
    parser.add_argument('phone')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]{11}', args.phone):
        parser.error('员工账号必须为11位数字')
    connection_string = os.environ.get('BOOKSTORE_DB_ADMIN')
    if not connection_string:
        parser.error('请设置仅供本机部署使用的 BOOKSTORE_DB_ADMIN')
    password_hash = None
    if args.operation == 'set-password':
        password = getpass.getpass('新密码（12—256个字符）：')
        if not 12 <= len(password) <= 256 or password != getpass.getpass('再次输入：'):
            parser.error('密码长度不符或两次输入不一致')
        password_hash = generate_password_hash(password)
    connection = pyodbc.connect(connection_string, autocommit=False, timeout=5)
    try:
        cursor = connection.cursor()
        database = cursor.execute('SELECT DB_NAME()').fetchval()
        if not database.startswith('ShiguangBookstoreWeek7'):
            raise RuntimeError('本阶段凭据配置只允许在 ShiguangBookstoreWeek7 副本执行')
        update_credential(cursor, args.phone, password_hash)
        cursor.close()
        connection.commit()
        print('员工登录凭据已更新；原有会话已失效。')
    except BaseException:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == '__main__':
    main()
