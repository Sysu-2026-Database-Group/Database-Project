import json
import re
from uuid import UUID, uuid4

from itsdangerous import BadData, URLSafeSerializer

from .errors import AppError


def require_cashier(actor):
    if actor['role'] != '收银员':
        raise AppError('forbidden', '只有收银员可以办理门店销售。', 403)


class SalesService:
    def __init__(self, dao, secret_key):
        self.dao = dao
        self.signer = URLSafeSerializer(secret_key, salt='bookstore-sale-confirmation-v1')

    @staticmethod
    def validate(payload):
        if not isinstance(payload, dict):
            raise AppError('invalid_sale', '请填写销售内容。', 400)
        items = payload.get('items')
        if not isinstance(items, list) or not 1 <= len(items) <= 50:
            raise AppError('invalid_sale', '请选择1至50种商品。', 400)
        seen = set()
        for item in items:
            if (not isinstance(item, dict) or set(item) != {'goods_id', 'quantity'}
                    or type(item['goods_id']) is not int or not 1 <= item['goods_id'] <= 9223372036854775807
                    or type(item['quantity']) is not int or not 1 <= item['quantity'] <= 1000
                    or item['goods_id'] in seen):
                raise AppError('invalid_sale', '商品不能重复，数量必须是1至1000的整数。', 400)
            seen.add(item['goods_id'])
        phone = payload.get('member_phone')
        if phone == '':
            phone = None
        if phone is not None and (not isinstance(phone, str) or not re.fullmatch(r'[0-9]{11}', phone)):
            raise AppError('invalid_sale', '会员手机号应为11位数字，非会员请留空。', 400)
        points = payload.get('used_points', 0)
        if type(points) is not int or not 0 <= points <= 2147483647:
            raise AppError('invalid_sale', '使用积分必须是非负整数。', 400)
        try:
            key = str(UUID(payload.get('request_key', '')))
        except (ValueError, TypeError, AttributeError):
            raise AppError('invalid_sale', '请求标识不正确，请重新打开销售页面。', 400) from None
        return key, {'items': sorted(items, key=lambda item: item['goods_id']), 'member_phone': phone, 'used_points': points}

    def preview(self, actor, payload):
        require_cashier(actor)
        key, request = self.validate(payload)
        raw_quote = self.dao.sale_quote(actor, request)
        token = self.signer.dumps(dict(phone=actor['phone'], version=actor['session_version'],
                                      request_key=key, payload=request, quote=raw_quote))
        return dict(quote=json.loads(raw_quote), quote_token=token, request_key=key)

    def create(self, actor, token):
        require_cashier(actor)
        if not isinstance(token, str) or not token or len(token)>16000:
            raise AppError('invalid_confirmation', '结算确认无效，请重新预览。', 400)
        try:
            confirmation = self.signer.loads(token)
        except BadData:
            raise AppError('invalid_confirmation', '结算确认无效，请重新预览。', 400) from None
        if confirmation['phone'] != actor['phone'] or confirmation['version'] != actor['session_version']:
            raise AppError('invalid_confirmation', '这份结算确认不属于当前登录，请重新预览。', 403)
        return self.dao.sale_create(actor, confirmation['request_key'], confirmation['payload'], confirmation['quote'])


def form_payload(form):
    """页面只提交数量，数据库决定成交价；拒绝非整数及重复字段。"""
    items = []
    try:
        for key in form:
            if key.startswith('quantity_'):
                values = form.getlist(key)
                if len(values) != 1 or not re.fullmatch(r'[0-9]+', values[0]):
                    raise ValueError()
                quantity = int(values[0])
                if quantity:
                    items.append(dict(goods_id=int(key.removeprefix('quantity_')), quantity=quantity))
        raw_points = form.get('used_points', '0')
        if not re.fullmatch(r'[0-9]+', raw_points):
            raise ValueError()
        return dict(items=items, member_phone=form.get('member_phone', '').strip(),
                    used_points=int(raw_points), request_key=form.get('request_key'))
    except ValueError:
        raise AppError('invalid_sale', '数量和积分必须是非负整数。', 400) from None


def new_request_key():
    return str(uuid4())
