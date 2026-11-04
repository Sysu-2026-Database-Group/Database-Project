import base64
import hashlib
import hmac
import re
from uuid import UUID, uuid4

from flask import Blueprint, current_app, jsonify, redirect, render_template, request, session, url_for
from itsdangerous import BadData, URLSafeSerializer

from .errors import AppError
from .sales import SalesService, require_cashier
from .web import json_object

bp = Blueprint('reservations', __name__)


def credential(data):
    phone, code = data.get('phone'), data.get('code')
    if not isinstance(phone,str) or not re.fullmatch('[0-9]{11}',phone) or not isinstance(code,str) or not re.fullmatch('[A-Z2-7]{20}',code):
        raise AppError('invalid_credential','请填写11位手机号和20位预定码。',400)
    return phone,code


def cancellation_key(data):
    try:
        return str(UUID(data.get('request_key','')))
    except (TypeError,ValueError,AttributeError):
        raise AppError('invalid_reservation','取消请求标识不正确。',400) from None


class ReservationService:
    def __init__(self, dao, secret):
        self.dao=dao
        self.secret=secret.encode()
        self.signer=URLSafeSerializer(secret,salt='pickup-v1')

    def create(self, data):
        # Reuse strict goods/quantity validation without accepting sale amounts.
        if not isinstance(data,dict) or set(data)!={'request_key','phone','items'}:
            raise AppError('invalid_reservation','请填写手机号及预订商品。',400)
        key,payload=SalesService.validate(dict(request_key=data['request_key'],items=data['items']))
        phone=data['phone']
        if not isinstance(phone,str) or not re.fullmatch('[0-9]{11}',phone):
            raise AppError('invalid_reservation','手机号应为11位数字。',400)
        # Stable unguessable code for a request, including unknown-result retries.
        code=base64.b32encode(hmac.new(self.secret,('reservation:'+key).encode(),hashlib.sha256).digest()).decode()[:20]
        return self.dao.reservation_create(key,phone,code,payload['items'])

    def preview(self, actor, data):
        require_cashier(actor)
        phone,code=credential(data)
        key,payload=SalesService.validate(dict(request_key=data.get('request_key'),items=[dict(goods_id=1,quantity=1)],
                                              member_phone=data.get('member_phone'),used_points=data.get('used_points',0)))
        payload.pop('items')
        quote=self.dao.pickup_quote(actor,phone,code,payload)
        token=self.signer.dumps(dict(actor=[actor['phone'],actor['session_version']],phone=phone,code=code,key=key,payload=payload,quote=quote))
        import json
        return dict(quote=json.loads(quote),quote_token=token,request_key=key)

    def confirm(self, actor, token):
        require_cashier(actor)
        try:
            if not isinstance(token,str) or len(token)>16000:
                raise BadData('invalid')
            value=self.signer.loads(token)
            if not isinstance(value,dict) or set(value)!={'actor','phone','code','key','payload','quote'}:
                raise BadData('invalid')
            if value['actor']!=[actor['phone'],actor['session_version']]:
                raise BadData('actor')
            credential(value)
            UUID(value['key'])
        except (BadData,ValueError,TypeError,AttributeError):
            raise AppError('invalid_confirmation','取货确认无效，请重新预览。',400) from None
        return self.dao.pickup_create(actor,value['key'],value['phone'],value['code'],value['payload'],value['quote'])


def service():
    return current_app.extensions['reservations']


def cashier():
    actor=current_app.extensions['employees'].current_actor(session.get('actor'))
    require_cashier(actor)
    return actor


@bp.get('/shop/reservations/new')
def form():
    return render_template('reservation_form.html',request_key=str(uuid4()),goods=current_app.extensions['shop_dao'].shop_catalog(page_size=100)['records'])


@bp.post('/shop/reservations')
def create():
    from .sales import form_payload
    payload=form_payload(request.form)
    result=service().create(dict(request_key=payload['request_key'],phone=request.form.get('phone'),items=payload['items']))
    session['reservation_credential']=dict(phone=result['phone'],code=result['code'])
    return redirect(url_for('reservations.receipt'),code=303)


@bp.get('/shop/reservations/lookup')
def lookup_form():
    return render_template('reservation_lookup.html')


@bp.post('/shop/reservations/lookup')
def lookup():
    phone,code=credential(request.form)
    service().dao.reservation_lookup(phone,code)
    session['reservation_credential']=dict(phone=phone,code=code)
    return redirect(url_for('reservations.receipt'),code=303)


@bp.get('/shop/reservations/receipt')
def receipt():
    phone,code=credential(session.get('reservation_credential') or {})
    return render_template('reservation_receipt.html',reservation=service().dao.reservation_lookup(phone,code),request_key=str(uuid4()))


@bp.post('/shop/reservations/cancel')
def cancel():
    phone,code=credential(session.get('reservation_credential') or {})
    service().dao.reservation_cancel(phone,code,request_key=cancellation_key(request.form))
    return redirect(url_for('reservations.receipt'),code=303)


@bp.get('/pickups')
def pickup_form():
    actor=cashier()
    return render_template('pickup_form.html',actor=actor,request_key=str(uuid4()))


@bp.post('/pickups/preview')
def pickup_preview():
    actor=cashier()
    try:
        points=int(request.form.get('used_points','0'))
    except ValueError:
        raise AppError('invalid_sale','积分应为整数。',400) from None
    data=dict(request.form); data['used_points']=points
    return render_template('pickup_preview.html',actor=actor,**service().preview(actor,data))


@bp.post('/pickups')
def pickup_confirm():
    result=service().confirm(cashier(),request.form.get('quote_token'))
    return redirect(url_for('sales.sale_receipt',sale_no=result['no']),code=303)


@bp.post('/pickups/cancel')
def cashier_cancel():
    actor=cashier(); phone,code=credential(request.form)
    result=service().dao.reservation_cancel(phone,code,actor,request_key=cancellation_key(request.form))
    return render_template('reservation_receipt.html',actor=actor,reservation=result)


@bp.post('/api/shop/reservations')
def create_api():
    return jsonify(data=service().create(json_object()))


@bp.post('/api/shop/reservations/lookup')
def lookup_api():
    return jsonify(data=service().dao.reservation_lookup(*credential(json_object())))


@bp.post('/api/shop/reservations/cancel')
def cancel_api():
    data=json_object()
    return jsonify(data=service().dao.reservation_cancel(*credential(data),request_key=cancellation_key(data)))


@bp.post('/api/pickups/preview')
def pickup_preview_api():
    return jsonify(data=service().preview(cashier(),json_object()))


@bp.post('/api/pickups')
def pickup_confirm_api():
    return jsonify(data=service().confirm(cashier(),json_object().get('quote_token')))
