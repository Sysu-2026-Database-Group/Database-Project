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
                        IS_MEMBER('bookstore_app_inventory'), IS_MEMBER('bookstore_app_manager'), DB_NAME(),
                        IS_MEMBER('bookstore_app_guest')
                        ,IS_MEMBER('bookstore_app_task')
                """).fetchone()
            finally:
                cursor.close()
            memberships = dict(zip(ROLE_NAMES, row[3:7]))
            if len(row) > 8:
                memberships['guest'] = row[8]
            if len(row) > 9:
                memberships['task'] = row[9]
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
            operation_errors = {
                52301: ('invalid_operation', '请检查商品、供应商、数量、金额及必填资料。', 400),
                52302: ('operation_conflict', '当前状态不允许此操作，或可售量不足。请刷新单据核对。', 409),
                52303: ('request_conflict', '该请求标识已用于其他内容。', 409),
                52304: ('record_not_found', '指定记录不存在。', 404),
                52305: ('quote_changed', '预览已过期或金额发生变化，请重新预览。', 409),
                52306: ('insufficient_funds', '门店资金不足，请由店长注资后重试。', 409),
                52307: ('goods_has_stock', '该商品有库存，不能删除。', 409),
                52308: ('goods_on_shelf', '请先下架再删除。', 409),
                52309: ('goods_referenced', '该商品已被单据引用，不能删除。', 409),
            }
            for number, details in operation_errors.items():
                if f'({number})' in message:
                    raise AppError(*details) from exc
            if re.search(r'\(1205\)|\(1222\)', message):
                raise AppError('sale_busy', '当前结算繁忙，请保留原确认页面重试。', 409) from exc
            if re.search(r'\(2601\)|\(2627\)', message):
                raise AppError('duplicate_record', '记录已存在，或请求与已有记录冲突。', 409) from exc
            if re.search(r'\(547\)|\(515\)|\(51025\)', message):
                raise AppError('constraint_conflict', '操作不符合数据规则，请检查关联记录和输入。', 409) from exc
            if re.search(r'\(52204\)', message):
                raise AppError('invalid_pagination', '页码或每页数量超出范围。', 400) from exc
            if '(52404)' in message:
                raise AppError('goods_not_found', '商品不存在或尚未上架。', 404) from exc
            if '(52401)' in message:
                raise AppError('invalid_filter', '搜索或分类条件格式不正确。', 400) from exc
            reservation_errors = {
                52501: ('invalid_reservation', '预订信息格式不正确。', 400),
                52502: ('reservation_conflict', '预订已结束或到期，当前不能执行此操作。', 409),
                52503: ('request_conflict', '此预订请求已用于其他内容。', 409),
                52504: ('invalid_credential', '手机号或预定码不正确。', 404),
            }
            for number, details in reservation_errors.items():
                if f'({number})' in message:
                    raise AppError(*details) from exc
            if '(52601)' in message:
                raise AppError('invalid_management','员工或会员卡参数不符合规则。',400) from exc
            if '(52602)' in message:
                raise AppError('management_conflict','不能停用或改岗最后一位可用店长，或当前管理操作繁忙。',409) from exc
            if '(52701)' in message:
                raise AppError('invalid_member','会员不存在、联系方式冲突或所选办理不符合升级及续期规则。',400) from exc
            if '(52704)' in message:
                raise AppError('invalid_credential','会员联系方式或自助凭证不正确。',404) from exc
            if '(52801)' in message:
                raise AppError('invalid_return','退货明细格式不正确。',400) from exc
            if '(52802)' in message:
                raise AppError('return_conflict','退货数量超限、已回收或记录状态发生变化。',409) from exc
            if '(52804)' in message:
                raise AppError('sale_not_found','原销售单不存在。',404) from exc
            state = str(exc.args[0]) if exc.args and re.fullmatch(r'[A-Z0-9]{5}', str(exc.args[0])) else 'unknown'
            numbers = sorted(set(re.findall(r'\((-?\d+)\)', message)))
            logger.error('Database operation failed: SQLSTATE=%s native=%s', state, ','.join(numbers))
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

    def sale_list(self, actor, page=1, page_size=20):
        row = self._one('cashier', 'EXEC api.usp_sale_list ?,?,?,?',
                        (actor['phone'], actor['session_version'], page, page_size))
        return json.loads(row['result_json'])

    def operation_read(self, actor, action, id=None, page=1, page_size=20, reason=None, from_date=None, to_date=None):
        row = self._one(ROLE_KEYS[actor['role']], 'EXEC api.usp_operation_read ?,?,?,?,?,?,?,?,?',
                        (actor['phone'], actor['session_version'], action, id, page, page_size, reason, from_date, to_date))
        return json.loads(row['result_json'])

    def operation_quote(self, actor, action, payload):
        return self._one(ROLE_KEYS[actor['role']], 'EXEC api.usp_operation_quote ?,?,?,?',
                         (actor['phone'], actor['session_version'], action, payload))['result_json']

    def operation_write(self, actor, action, key, payload, quote=None):
        row = self._one(ROLE_KEYS[actor['role']], 'EXEC api.usp_operation_write ?,?,?,?,?,?',
                        (actor['phone'], actor['session_version'], action, key, payload, quote))
        return json.loads(row['result_json'])

    def shop_catalog(self, id=None, search='', category=None, page=1, page_size=20):
        row = self._one('guest', 'EXEC api.usp_shop_catalog ?,?,?,?,?', (id, search, category, page, page_size))
        return json.loads(row['result_json'])

    def reservation_create(self, key, phone, code, items):
        row = self._one('guest', 'EXEC api.usp_reservation_create ?,?,?,?', (key, phone, code, json.dumps(items)))
        return json.loads(row['result_json'])

    def reservation_lookup(self, phone, code):
        return json.loads(self._one('guest', 'EXEC api.usp_reservation_lookup ?,?', (phone,code))['result_json'])

    def reservation_cancel(self, phone, code, actor=None, *, request_key):
        row = self._one('cashier' if actor else 'guest', 'EXEC api.usp_reservation_cancel ?,?,?,?,?',
                        (phone, code, actor['phone'] if actor else None, actor['session_version'] if actor else None, request_key))
        return json.loads(row['result_json'])

    def reservations_expire(self, batch_size=100):
        return self._one('task', 'EXEC api.usp_reservations_expire ?', (batch_size,))['expired_count']

    def pickup_quote(self, actor, phone, code, payload):
        return self._one('cashier', 'EXEC api.usp_pickup_quote ?,?,?,?,?,?',
                         (actor['phone'],actor['session_version'],phone,code,payload['member_phone'],payload['used_points']))['quote_json']

    def pickup_create(self, actor, key, phone, code, payload, quote):
        row = self._one('cashier', 'EXEC api.usp_pickup_create ?,?,?,?,?,?,?,?',
                        (actor['phone'],actor['session_version'],key,phone,code,payload['member_phone'],payload['used_points'],quote))
        return json.loads(row['result_json'])

    def management_read(self, actor, action, page=1, page_size=20, from_date=None, to_date=None):
        return json.loads(self._one('manager','EXEC api.usp_management_read ?,?,?,?,?,?,?',
                         (actor['phone'],actor['session_version'],action,page,page_size,from_date,to_date))['result_json'])

    def management_write(self, actor, key, action, payload):
        return json.loads(self._one('manager','EXEC api.usp_management_write ?,?,?,?,?',
                                   (actor['phone'],actor['session_version'],key,action,payload))['result_json'])

    def member_read(self, actor, phone):
        row=self._one('cashier','EXEC api.usp_member_read ?,?,?',(actor['phone'],actor['session_version'],phone))
        return json.loads(row['result_json']) if row and row['result_json'] else None

    def member_quote(self, actor, phone, level, operation):
        return self._one('cashier','EXEC api.usp_member_quote ?,?,?,?,?',(actor['phone'],actor['session_version'],phone,level,operation))['result_json']

    def member_create(self, actor, key, phone, level, operation, quote, token_hash):
        return json.loads(self._one('cashier','EXEC api.usp_member_create ?,?,?,?,?,?,?,?',
                         (actor['phone'],actor['session_version'],key,phone,level,operation,quote,token_hash))['result_json'])

    def member_contact(self, actor, key, phone, contact, token_hash):
        return json.loads(self._one('cashier','EXEC api.usp_member_contact ?,?,?,?,?,?',
                         (actor['phone'],actor['session_version'],key,phone,contact,token_hash))['result_json'])

    def member_self(self, contact, token_hash):
        return json.loads(self._one('guest','EXEC api.usp_member_self ?,?',(contact,token_hash))['result_json'])

    def return_source(self, actor, no):
        return json.loads(self._one('cashier','EXEC api.usp_return_source ?,?,?',(actor['phone'],actor['session_version'],no))['result_json'])

    def return_quote(self, actor, no, items):
        return self._one('cashier','EXEC api.usp_return_quote ?,?,?,?',(actor['phone'],actor['session_version'],no,items))['result_json']

    def return_create(self, actor, key, no, items, quote):
        return json.loads(self._one('cashier','EXEC api.usp_return_create ?,?,?,?,?,?',(actor['phone'],actor['session_version'],key,no,items,quote))['result_json'])

    def return_pending(self, actor, page=1, page_size=20):
        return json.loads(self._one('inventory','EXEC api.usp_return_pending ?,?,?,?',(actor['phone'],actor['session_version'],page,page_size))['result_json'])

    def return_recover(self, actor, key, item):
        return json.loads(self._one('inventory','EXEC api.usp_return_recover ?,?,?,?',(actor['phone'],actor['session_version'],key,item))['result_json'])
