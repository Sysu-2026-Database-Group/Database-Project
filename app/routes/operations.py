from uuid import uuid4
from datetime import date

from flask import Blueprint, current_app, jsonify, redirect, render_template, request, session, url_for

from ..operations import LABELS, require_operation, invalid
from ..web import json_object, pagination

bp = Blueprint('operations', __name__)
READS = {'goods', 'suppliers', 'quotes', 'purchases', 'purchase', 'stock', 'finance'}
PAGES = {'/goods': 'goods', '/management/goods': 'goods', '/suppliers': 'suppliers',
         '/supplier-quotes': 'quotes', '/purchases': 'purchases', '/inventory': 'stock', '/management/finance': 'finance'}
TITLES = {'goods': '商品资料与库存', 'suppliers': '供应商资料', 'quotes': '供应商报价',
          'purchases': '采购申请', 'stock': '库存变动', 'finance': '门店资金', 'purchase': '采购详情'}


def actor_for(action):
    actor = current_app.extensions['employees'].current_actor(session.get('actor'))
    require_operation(actor, action)
    return actor


def dao():
    return current_app.extensions['employees'].dao


def service():
    return current_app.extensions['operations']


def stock_filters():
    result={}
    reason=request.args.get('reason','')
    if reason and reason not in {'购入','卖出','退货','损坏'}: invalid()
    result['reason']=reason or None
    for name in ('from_date','to_date'):
        value=request.args.get(name,'')
        try: result[name]=date.fromisoformat(value).isoformat() if value else None
        except ValueError: invalid()
    if result['from_date'] and result['to_date'] and result['from_date']>result['to_date']: invalid()
    return result


@bp.get('/goods')
@bp.get('/management/goods')
@bp.get('/suppliers')
@bp.get('/supplier-quotes')
@bp.get('/purchases')
@bp.get('/inventory')
@bp.get('/management/finance')
def page():
    action = PAGES[request.path]
    actor = actor_for(action)
    identifier = request.args.get('goods_id') if action == 'stock' else None
    if identifier is not None:
        identifier = form_integer(identifier)
    listing = dao().operation_read(actor, action, id=identifier, **pagination(), **(stock_filters() if action=='stock' else {}))
    edit = None
    if request.args.get('edit'):
        edit_id = form_integer(request.args['edit'])
        edit = next((row for row in listing['records'] if row.get('id') == edit_id), None)
        if edit is None:
            invalid()
    return render_template('operations.html', actor=actor, kind=action, title=TITLES[action], listing=listing,
                           edit=edit or {}, request_key=str(uuid4()), labels=LABELS)


@bp.get('/purchases/<int:purchase_id>')
def purchase(purchase_id):
    actor = actor_for('purchase')
    value = dao().operation_read(actor, 'purchase', id=purchase_id)
    return render_template('purchase.html', actor=actor, purchase=value, request_key=str(uuid4()), labels=LABELS)


def form_integer(value, optional=False):
    if optional and not value:
        return None
    if not isinstance(value, str) or not value.isascii() or not value.isdecimal() or len(value) > 19:
        invalid()
    return int(value)


def form_envelope(action):
    data = {key: value for key, value in request.form.items() if key not in {'csrf_token', 'request_key'}}
    if any(len(request.form.getlist(key)) != 1 for key in request.form):
        invalid()
    if action == 'draft':
        items = []
        for index in range(50):
            goods = data.pop(f'goods_id_{index}', '')
            quantity = data.pop(f'quantity_{index}', '')
            cost = data.pop(f'unit_cost_{index}', '')
            if goods and quantity != '0':
                items.append(dict(goods_id=form_integer(goods), quantity=form_integer(quantity), unit_cost=cost))
            elif not goods and (quantity or cost):
                invalid()
        data['items'] = items
    for key in ('id', 'supplier_id', 'goods_id', 'page_count', 'quantity'):
        if key in data:
            data[key] = form_integer(data[key], optional=key in {'id', 'page_count'})
    if action == 'price':
        if data.get('on_shelf') not in {'0', '1'}:
            invalid()
        data['on_shelf'] = data['on_shelf'] == '1'
    return dict(request_key=request.form.get('request_key'), payload=data)


def destination(result):
    action = result['action']
    if action in {'draft', 'submit', 'cancel', 'approve', 'pay', 'receive'}:
        return url_for('operations.purchase', purchase_id=result['id'])
    return {'inject': '/management/finance', 'withdraw': '/management/finance', 'price': '/management/goods', 'goods_save': '/goods',
            'goods_delete': '/goods', 'supplier_save': '/suppliers', 'quote_save': '/supplier-quotes', 'damage': '/inventory'}[action]


@bp.post('/operations/<action>/preview')
def preview(action):
    actor = actor_for(action)
    value = service().preview(actor, action, form_envelope(action))
    return render_template('operation_preview.html', actor=actor, label=LABELS[action], **value)


@bp.post('/operations/confirm')
def confirm():
    actor = current_app.extensions['employees'].current_actor(session.get('actor'))
    result = service().confirm(actor, request.form.get('quote_token'))
    return redirect(destination(result), code=303)


@bp.post('/operations/<action>')
def write(action):
    actor = actor_for(action)
    result = service().write(actor, action, form_envelope(action))
    return redirect(destination(result), code=303)


@bp.get('/api/operations/<action>')
def read_api(action):
    if action not in READS:
        invalid()
    actor = actor_for(action)
    identifier = form_integer(request.args['id']) if 'id' in request.args else None
    return jsonify(data=dao().operation_read(actor, action, id=identifier, **pagination(), **(stock_filters() if action=='stock' else {})))


@bp.post('/api/operations/<action>/preview')
def preview_api(action):
    actor = actor_for(action)
    return jsonify(data=service().preview(actor, action, json_object()))


@bp.post('/api/operations/confirm')
def confirm_api():
    actor = current_app.extensions['employees'].current_actor(session.get('actor'))
    return jsonify(data=service().confirm(actor, json_object().get('quote_token')))


@bp.post('/api/operations/<action>')
def write_api(action):
    actor = actor_for(action)
    return jsonify(data=service().write(actor, action, json_object()))
