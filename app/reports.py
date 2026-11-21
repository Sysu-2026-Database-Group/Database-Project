from datetime import date, timedelta

from flask import Blueprint, current_app, render_template, request, session

from .dao import ROLE_KEYS
from .errors import AppError

bp = Blueprint('reports', __name__, url_prefix='/reports')

METRICS = {'quantity', 'revenue', 'orders'}


def _current_actor():
    stored = session.get('actor')
    if not stored:
        return None
    try:
        return current_app.extensions['employees'].current_actor(stored)
    except AppError:
        return None


@bp.get('/moving-average')
def moving_average():
    actor = _current_actor()
    if not actor or actor['role'] != '店长':
        raise AppError('forbidden', '仅店长可以查看移动平均。', 403)

    today = date.today()
    raw_date = request.args.get('as_of_date')
    try:
        as_of_date = date.fromisoformat(raw_date) if raw_date else today
    except ValueError:
        raise AppError('invalid_date', '日期应为 YYYY-MM-DD。', 400) from None
    if as_of_date > today:
        raise AppError('invalid_date', '指定日期不能晚于今天。', 400)
    if as_of_date < date(1, 1, 3):
        raise AppError('invalid_date', '指定日期超出可计算范围。', 400)

    rows = current_app.extensions['shop_dao'].moving_average_sales(as_of_date)
    summary = rows[-1] if len(rows) == 3 else None
    has_sales = any(
        float(row['daily_net_quantity'] or 0) != 0 or float(row['daily_net_revenue'] or 0) != 0
        for row in rows)
    return render_template(
        'moving_average.html', actor=actor, rows=rows, summary=summary,
        as_of_date=as_of_date.isoformat(),
        window_start=(as_of_date - timedelta(days=2)).isoformat(),
        window_end=as_of_date.isoformat(), has_sales=has_sales, today=today.isoformat())


@bp.get('/cumulative-sales')
def cumulative_sales():
    actor = _current_actor()
    if not actor or actor['role'] != '店长':
        raise AppError('forbidden', '仅店长可以查看累计销售。', 403)

    mode = (request.args.get('mode') or 'date').strip().lower()
    if mode not in {'date', 'product'}:
        raise AppError('invalid_mode', '模式应为 date 或 product。', 400)

    today = date.today()
    try:
        from_date = date.fromisoformat(request.args.get('from_date') or '') if request.args.get('from_date') else today - timedelta(days=29)
        to_date = date.fromisoformat(request.args.get('to_date') or '') if request.args.get('to_date') else today
    except ValueError:
        raise AppError('invalid_date', '日期应为 YYYY-MM-DD。', 400) from None
    if from_date > to_date:
        raise AppError('invalid_date', '起始日期不能晚于结束日期。', 400)

    if mode == 'date':
        rows = current_app.extensions['shop_dao'].cumulative_sales_by_date(from_date, to_date)
    else:
        rows = current_app.extensions['shop_dao'].cumulative_sales_by_product(from_date, to_date)
    return render_template(
        'cumulative_sales.html', actor=actor, rows=rows, mode=mode,
        from_date=from_date.isoformat(), to_date=to_date.isoformat())


@bp.get('/product-ranking')
def product_ranking():
    actor = _current_actor()
    is_manager = bool(actor and actor['role'] == '店长')

    requested_metric = (request.args.get('metric') or 'quantity').strip().lower()
    downgraded = False
    if requested_metric not in METRICS:
        requested_metric = 'quantity'
        downgraded = True
    if not is_manager and requested_metric in {'revenue', 'orders'}:
        requested_metric = 'quantity'
        downgraded = True

    today = date.today()
    try:
        from_date = date.fromisoformat(request.args.get('from_date') or '') if request.args.get('from_date') else today - timedelta(days=29)
        to_date = date.fromisoformat(request.args.get('to_date') or '') if request.args.get('to_date') else today
    except ValueError:
        raise AppError('invalid_date', '日期应为 YYYY-MM-DD。', 400) from None
    if from_date > to_date:
        raise AppError('invalid_date', '起始日期不能晚于结束日期。', 400)

    connection = 'guest' if actor is None else ROLE_KEYS[actor['role']]
    rows = current_app.extensions['shop_dao'].product_sales_rank(
        connection, from_date, to_date, requested_metric)
    return render_template(
        'product_ranking.html',
        actor=actor,
        rows=rows,
        metric=requested_metric,
        from_date=from_date.isoformat(),
        to_date=to_date.isoformat(),
        is_manager=is_manager,
        downgraded=downgraded,
    )
