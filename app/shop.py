"""Public catalogue contract. Internal stock, cost and employee data stay private."""
from flask import Blueprint, current_app, jsonify, render_template, request

from .errors import AppError
from .web import pagination

bp = Blueprint('shop', __name__)


def catalog(goods_id=None):
    filters = {}
    for name, maximum in (('search', 100), ('category', 10)):
        values = request.args.getlist(name)
        if len(values) > 1 or (values and len(values[0]) > maximum):
            raise AppError('invalid_filter', '搜索或分类条件格式不正确。', 400)
        filters[name] = (values[0].strip() if values else '')
    if filters['category'] not in {'', '图书', '文创'}:
        raise AppError('invalid_filter', '请选择图书或文创分类。', 400)
    filters['category'] = filters['category'] or None
    if goods_id is not None and not 1 <= goods_id <= 9223372036854775807:
        raise AppError('goods_not_found', '商品不存在或尚未上架。', 404)
    if goods_id is not None:
        # Detail visibility depends on its id, independently of list filters.
        filters = dict(search='', category=None)
    pages = pagination()
    if goods_id is not None:
        pages = dict(page=1, page_size=1)
    return current_app.extensions['shop_dao'].shop_catalog(id=goods_id, **filters, **pages)


@bp.get('/shop')
def index():
    return render_template('shop.html', listing=catalog())


@bp.get('/shop/goods/<int:goods_id>')
def detail(goods_id):
    listing = catalog(goods_id)
    if not listing['records']:
        raise AppError('goods_not_found', '商品不存在或尚未上架。', 404)
    return render_template('shop_detail.html', goods=listing['records'][0])


@bp.get('/api/shop/goods')
def catalog_api():
    return jsonify(data=catalog())


@bp.get('/api/shop/goods/<int:goods_id>')
def detail_api(goods_id):
    listing = catalog(goods_id)
    if not listing['records']:
        raise AppError('goods_not_found', '商品不存在或尚未上架。', 404)
    return jsonify(data=listing['records'][0])
