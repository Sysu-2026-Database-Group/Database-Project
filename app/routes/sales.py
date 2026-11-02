from flask import Blueprint, current_app, jsonify, redirect, render_template, request, session, url_for

from ..errors import AppError
from ..sales import form_payload, require_cashier
from ..web import json_object, pagination

bp = Blueprint('sales', __name__)


def cashier():
    actor = current_app.extensions['employees'].current_actor(session.get('actor'))
    require_cashier(actor)
    return actor


def services():
    return current_app.extensions['employees'].dao, current_app.extensions['sales']


def draft():
    handle, value = current_app.extensions['sale_drafts'].get(session.get('sale_draft'), session['actor'])
    session['sale_draft'] = handle
    return value


def save_draft():
    payload = form_payload(request.form)
    payload['request_key'] = draft()['request_key']
    key, normalized = services()[1].validate(payload, allow_empty=True)
    normalized['request_key'] = key
    current_app.extensions['sale_drafts'].save(session['sale_draft'], session['actor'], normalized)
    return normalized


@bp.get('/sales/new')
def sale_form():
    actor = cashier()
    value = draft()
    return render_template('sale_form.html', actor=actor, goods=services()[0].sale_catalog(actor),
                           draft=value, quantities={item['goods_id']: item['quantity'] for item in value['items']},
                           request_key=value['request_key'])


@bp.post('/sales/cart')
def sale_cart():
    cashier()
    action = request.form.get('action')
    if action == 'clear':
        current_app.extensions['sale_drafts'].discard(session.get('sale_draft'))
        session.pop('sale_draft', None)
    elif action == 'update':
        save_draft()
    else:
        raise AppError('invalid_sale', '请选择保存或清空清单。', 400)
    return redirect(url_for('sales.sale_form'), code=303)


@bp.post('/sales/preview')
def sale_preview():
    actor = cashier()
    return render_template('sale_preview.html', actor=actor, **services()[1].preview(actor, save_draft()))


@bp.post('/sales')
def sale_create():
    result = services()[1].create(cashier(), request.form.get('quote_token'))
    current_app.extensions['sale_drafts'].discard(session.pop('sale_draft', None))
    return redirect(url_for('sales.sale_receipt', sale_no=result['no']), code=303)


@bp.get('/sales/<sale_no>')
def sale_receipt(sale_no):
    actor = cashier()
    return render_template('sale_receipt.html', actor=actor, sale=services()[0].sale_get(actor, sale_no))


@bp.get('/sales')
def sale_list():
    actor = cashier()
    return render_template('sale_list.html', actor=actor, listing=services()[0].sale_list(actor, **pagination()))


@bp.get('/api/sale-goods')
def sale_goods_api():
    return jsonify(data=services()[0].sale_catalog(cashier()))


@bp.get('/api/sales')
def sale_list_api():
    return jsonify(data=services()[0].sale_list(cashier(), **pagination()))


@bp.post('/api/sales/preview')
def sale_preview_api():
    actor = cashier()
    return jsonify(data=services()[1].preview(actor, json_object()))


@bp.post('/api/sales')
def sale_create_api():
    actor = cashier()
    return jsonify(data=services()[1].create(actor, json_object().get('quote_token')))


@bp.get('/api/sales/<sale_no>')
def sale_get_api(sale_no):
    return jsonify(data=services()[0].sale_get(cashier(), sale_no))
