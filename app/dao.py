"""唯一连接 SQL Server 的应用模块。运行连接只能执行明确授予的过程。"""
import logging
import json
from contextlib import contextmanager

import pyodbc

from .errors import AppError, DatabaseUnavailable

ROLE_KEYS = {'收银员': 'cashier', '库管': 'inventory', '店长': 'manager'}
ROLE_NAMES = {key: 'bookstore_app_' + key for key in ('auth', 'cashier', 'inventory', 'manager')}
logger = logging.getLogger(__name__)


class EmployeeDAO:
    def __init__(self, connections, *, expected_database=None):
        self.connections = connections
        self.expected_database = expected_database

    @contextmanager
    def connection(self, key):
        connection = None
        try:
            connection = pyodbc.connect(self.connections[key], autocommit=True, timeout=5)
            connection.timeout = 15
            # 配置失误不能把 dbo/系统管理员连接当成受限应用账号运行。
            cursor = connection.cursor()
            try:
                row = cursor.execute("""
                    SELECT USER_NAME(), IS_SRVROLEMEMBER('sysadmin'), IS_MEMBER('db_owner'),
                        IS_MEMBER('bookstore_app_auth'), IS_MEMBER('bookstore_app_cashier'),
                        IS_MEMBER('bookstore_app_inventory'), IS_MEMBER('bookstore_app_manager'), DB_NAME()
                """).fetchone()
            finally:
                cursor.close()
            memberships = dict(zip(ROLE_NAMES, row[3:7]))
            if (row[0] == 'dbo' or row[1] == 1 or row[2] == 1
                    or memberships[key] != 1
                    or sum(value == 1 for value in memberships.values()) != 1):
                raise RuntimeError('Runtime connection must use exactly its designated restricted role')
            if self.expected_database is not None and row[7] != self.expected_database:
                raise RuntimeError('Runtime connection points to an unexpected database')
            yield connection
        except pyodbc.Error as exc:
            # 错误号只从 SQL Server 原生消息括号中提取，不把客户端参数作为错误码。
            import re
            message = ' '.join(str(part) for part in exc.args)
            if re.search(r'\(52001\)', message):
                raise AppError('session_expired', '登录已失效，请重新登录。', 401) from exc
            if re.search(r'\(52003\)|\(229\)', message):
                raise AppError('forbidden', '当前账号无权执行该操作。', 403) from exc
            sales_errors = {
                52101: ('invalid_sale', '商品、数量、手机号或积分格式不正确，或金额超出支持范围。', 400),
                52102: ('member_not_found', '会员不存在；非会员请留空会员手机号。', 400),
                52103: ('goods_unavailable', '商品不存在、未上架或未定价。', 409),
                52104: ('insufficient_stock', '可售量不足，请调整数量后重新预览。', 409),
                52105: ('points_limit', '积分抵扣超过本次上限，请减少使用积分。', 400),
                52106: ('request_conflict', '同一请求标识不能用于不同的销售内容。', 409),
                52107: ('quote_changed', '价格或会员结算条件已变化，请重新预览并确认收款。', 409),
                52108: ('sale_not_found', '销售单不存在或不属于当前收银员。', 404),
            }
            for number, details in sales_errors.items():
                if f'({number})' in message:
                    raise AppError(*details) from exc
            if re.search(r'\(1205\)|\(1222\)', message):
                raise AppError('sale_busy', '当前结算繁忙，请保留原确认页面重试。', 409) from exc
            logger.exception('Database operation failed')
            raise DatabaseUnavailable() from exc
        except (KeyError, RuntimeError) as exc:
            logger.error('Runtime database configuration is invalid: %s', type(exc).__name__)
            raise DatabaseUnavailable() from exc
        finally:
            if connection is not None:
                connection.close()

    def _one(self, key, sql, parameters):
        with self.connection(key) as connection:
            cursor = connection.cursor()
            try:
                cursor.execute(sql, parameters)
                row = cursor.fetchone()
                return dict(zip((column[0] for column in cursor.description), row)) if row else None
            finally:
                cursor.close()

    def credentials(self, phone):
        return self._one('auth', 'EXEC api.usp_employee_login_lookup @employee_phone=?', (phone,))

    def session_identity(self, phone, version):
        return self._one('auth', 'EXEC api.usp_employee_session_lookup @employee_phone=?, @session_version=?', (phone, version))

    def employee_context(self, actor):
        return self._one(ROLE_KEYS[actor['role']],
                         'EXEC api.usp_employee_context @employee_phone=?, @session_version=?',
                         (actor['phone'], actor['session_version']))

    def sale_catalog(self, actor):
        with self.connection('cashier') as connection:
            cursor = connection.cursor()
            try:
                cursor.execute('EXEC api.usp_sale_catalog ?,?', (actor['phone'], actor['session_version']))
                columns = [column[0] for column in cursor.description]
                return [dict(zip(columns, row)) for row in cursor.fetchall()]
            finally:
                cursor.close()

    def sale_quote(self, actor, payload):
        return self._one('cashier', 'EXEC api.usp_sale_quote ?,?,?,?,?',
                         (actor['phone'], actor['session_version'], json.dumps(payload['items']),
                          payload['member_phone'], payload['used_points']))['quote_json']

    def sale_create(self, actor, request_key, payload, expected_quote):
        row = self._one('cashier', 'EXEC api.usp_sale_create ?,?,?,?,?,?,?',
                        (actor['phone'], actor['session_version'], request_key, json.dumps(payload['items']),
                         payload['member_phone'], payload['used_points'], expected_quote))
        return json.loads(row['result_json'])

    def sale_get(self, actor, sale_no):
        row = self._one('cashier', 'EXEC api.usp_sale_get ?,?,?', (actor['phone'], actor['session_version'], sale_no))
        return json.loads(row['result_json'])
