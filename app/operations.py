"""P2 input contracts and monetary confirmations; SQL owns state and ledgers."""
import json
import re
from decimal import Decimal, InvalidOperation
from uuid import UUID

from itsdangerous import BadData, URLSafeSerializer

from .errors import AppError

MANAGER = {'inject', 'withdraw', 'price', 'approve', 'pay', 'finance'}
INVENTORY = {'goods_save', 'supplier_save', 'quote_save', 'draft', 'submit', 'receive', 'damage', 'goods_delete'}
SHARED = {'goods', 'suppliers', 'quotes', 'purchases', 'purchase', 'stock', 'cancel'}
WRITES = MANAGER | INVENTORY | {'cancel'}
LABELS = {'withdraw': '店长提现', 'inject': '店长注资', 'price': '定价与上下架', 'approve': '审批采购', 'pay': '采购付款',
          'goods_save': '保存商品资料', 'supplier_save': '保存供应商', 'quote_save': '保存报价',
          'draft': '保存采购草稿', 'submit': '提交采购', 'receive': '整单收货', 'damage': '登记报损',
          'goods_delete': '删除商品档案', 'cancel': '取消采购'}


def require_operation(actor, action):
    allowed = {'店长'} if action in MANAGER else {'库管'} if action in INVENTORY else {'店长', '库管'} if action in SHARED else set()
    if actor['role'] not in allowed:
        raise AppError('forbidden', '当前岗位不能执行此操作。', 403)


def invalid():
    raise AppError('invalid_operation', '请检查必填字段、编号、数量和金额格式。', 400)


def integer(value, *, optional=False, maximum=9223372036854775807):
    if optional and value in (None, ''):
        return None
    if type(value) is not int or not 1 <= value <= maximum:
        invalid()
    return value


def money(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]{1,8}(\.[0-9]{1,2})?', value):
        invalid()
    try:
        amount = Decimal(value)
        if amount <= 0:
            invalid()
        return format(amount, '.2f')
    except InvalidOperation:
        invalid()


def text(value, maximum=100):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        invalid()
    return value.strip()


def normalize(action, data):
    if not isinstance(data, dict):
        invalid()
    # Unknown fields (especially actor, price or inventory overrides) are refused.
    fields = {
        'inject': {'amount'}, 'withdraw': {'amount'}, 'price': {'id', 'amount', 'on_shelf'},
        'goods_save': {'id', 'name', 'category', 'code', 'author', 'publisher', 'page_count', 'spec'},
        'supplier_save': {'id', 'name'}, 'quote_save': {'supplier_id', 'goods_id', 'amount'},
        'draft': {'id', 'supplier_id', 'items'}, 'damage': {'id', 'quantity', 'note'},
        'goods_delete': {'id'},
        'submit': {'id'}, 'cancel': {'id'}, 'approve': {'id'}, 'pay': {'id'}, 'receive': {'id'},
    }
    if action not in fields or set(data) - fields[action]:
        invalid()
    result = dict(data)
    if 'id' in fields[action]:
        result['id'] = integer(data.get('id'), optional=action in {'goods_save', 'supplier_save', 'draft'})
    for key in ('supplier_id', 'goods_id'):
        if key in fields[action]:
            result[key] = integer(data.get(key))
    if 'amount' in fields[action]:
        result['amount'] = money(data.get('amount'))
    if action == 'price':
        if type(data.get('on_shelf')) is not bool:
            invalid()
        # SQL JSON_VALUE returns true/false for JSON booleans; use a numeric bit.
        result['on_shelf'] = int(data['on_shelf'])
    if action in {'goods_save', 'supplier_save'}:
        result['name'] = text(data.get('name'))
    if action == 'goods_save':
        category = data.get('category')
        if category not in {'图书', '文创'}:
            invalid()
        result['code'] = text(data.get('code'), 17 if category == '图书' else 20)
        if not result['code'].isascii() or len(result['code']) < (10 if category == '图书' else 1):
            invalid()
        if category == '图书':
            result.update(author=text(data.get('author')), publisher=text(data.get('publisher')),
                          page_count=integer(data.get('page_count'), maximum=2147483647))
            result.pop('spec', None)
        else:
            result['spec'] = text(data.get('spec'))
            for key in ('author', 'publisher', 'page_count'):
                result.pop(key, None)
    if action == 'damage':
        result.update(quantity=integer(data.get('quantity'), maximum=1000), note=text(data.get('note'), 200))
    if action == 'draft':
        items = data.get('items')
        if not isinstance(items, list) or len(items) > 50:
            invalid()
        lines, seen = [], set()
        for item in items:
            if not isinstance(item, dict) or set(item) != {'goods_id', 'quantity', 'unit_cost'}:
                invalid()
            goods = integer(item['goods_id'])
            if goods in seen:
                invalid()
            seen.add(goods)
            lines.append(dict(goods_id=goods, quantity=integer(item['quantity'], maximum=1000), unit_cost=money(item['unit_cost'])))
        result['items'] = sorted(lines, key=lambda line: line['goods_id'])
    return result


class OperationsService:
    def __init__(self, dao, secret):
        self.dao = dao
        self.signer = URLSafeSerializer(secret, salt='bookstore-operation-v1')

    def prepare(self, actor, action, envelope):
        require_operation(actor, action)
        if not isinstance(envelope, dict) or set(envelope) != {'request_key', 'payload'}:
            invalid()
        try:
            key = str(UUID(envelope['request_key']))
        except (ValueError, TypeError, AttributeError):
            invalid()
        payload = normalize(action, envelope['payload'])
        raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
        return key, raw

    def preview(self, actor, action, envelope):
        key, raw = self.prepare(actor, action, envelope)
        if action not in {'inject', 'withdraw', 'pay'}:
            invalid()
        quote = self.dao.operation_quote(actor, action, raw)
        token = self.signer.dumps(dict(phone=actor['phone'], version=actor['session_version'], action=action,
                                      request_key=key, payload=raw, quote=quote))
        return dict(quote=json.loads(quote), quote_token=token, request_key=key)

    def confirm(self, actor, token):
        if not isinstance(token, str) or len(token) > 16000:
            invalid()
        try:
            value = self.signer.loads(token)
        except BadData:
            raise AppError('invalid_confirmation', '确认凭据无效，请重新预览。', 400) from None
        if (not isinstance(value, dict) or set(value) != {'phone', 'version', 'action', 'request_key', 'payload', 'quote'}
                or value.get('action') not in {'inject', 'withdraw', 'pay'} or not isinstance(value.get('quote'), str)
                or not isinstance(value.get('payload'), str)):
            invalid()
        require_operation(actor, value['action'])
        if (value['phone'], value['version']) != (actor['phone'], actor['session_version']):
            raise AppError('invalid_confirmation', '此确认不属于当前登录。', 403)
        # SQL finds successful requests before checking quote expiry and business state.
        return self.dao.operation_write(actor, value['action'], value['request_key'], value['payload'], value['quote'])

    def write(self, actor, action, envelope):
        key, raw = self.prepare(actor, action, envelope)
        if action in {'inject', 'withdraw', 'pay'}:
            raise AppError('preview_required', '请先预览并确认金额。', 400)
        return self.dao.operation_write(actor, action, key, raw)
