import logging
import os
import secrets
from datetime import timedelta

from flask import Flask, jsonify, redirect, render_template, request, session, url_for

from .dao import EmployeeDAO
from .errors import AppError
from .services import EmployeeService
from .sales import SalesService, form_payload, new_request_key, require_cashier


def create_app(config=None, *, dao=None):
    app = Flask(__name__)
    app.config.from_mapping(
        SECRET_KEY=os.environ.get('BOOKSTORE_SECRET_KEY', ''),
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE='Lax',
        SESSION_COOKIE_SECURE=os.environ.get('BOOKSTORE_COOKIE_SECURE') == '1',
        PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
        MAX_CONTENT_LENGTH=16384,
        DB_CONNECTIONS={key: os.environ.get('BOOKSTORE_DB_' + key.upper(), '')
                        for key in ('auth', 'cashier', 'inventory', 'manager')},
        DB_DATABASE=os.environ.get('BOOKSTORE_DATABASE'),
    )
    if config:
        app.config.update(config)
    if len(app.config['SECRET_KEY']) < 32:
        raise ValueError('BOOKSTORE_SECRET_KEY must contain at least 32 characters')
    service = EmployeeService(dao if dao is not None else EmployeeDAO(
        app.config['DB_CONNECTIONS'], expected_database=app.config['DB_DATABASE']))
    sales = SalesService(service.dao, app.config['SECRET_KEY'])

    def csrf_token():
        if 'csrf_token' not in session:
            session['csrf_token'] = secrets.token_urlsafe(32)
        return session['csrf_token']

    app.jinja_env.globals['csrf_token'] = csrf_token

    @app.before_request
    def protect_writes():
        if request.method in ('POST', 'PUT', 'PATCH', 'DELETE'):
            expected = session.get('csrf_token', '')
            received = request.headers.get('X-CSRF-Token') or request.form.get('csrf_token', '')
            if not expected or not secrets.compare_digest(expected.encode('utf-8'), received.encode('utf-8')):
                raise AppError('invalid_csrf', '页面已过期，请刷新后重试。', 403)

    @app.after_request
    def prevent_caching(response):
        response.headers['Cache-Control'] = 'no-store'
        return response

    @app.errorhandler(AppError)
    def application_error(error):
        if error.status == 401:
            session.pop('actor', None)
        if request.path.startswith('/api/'):
            return jsonify(error={'code': error.code, 'message': error.message}), error.status
        if request.path.startswith('/sales') and error.status != 401:
            return render_template('sale_error.html', error=error.message,
                                   retry_token=request.form.get('quote_token') if error.status==503 or error.code=='sale_busy' else None), error.status
        return render_template('login.html', error=error.message), error.status

    @app.errorhandler(500)
    def unexpected_error(error):
        logging.getLogger(__name__).error('Unhandled application error: %s', type(error).__name__)
        if request.path.startswith('/api/'):
            return jsonify(error={'code': 'internal_error', 'message': '系统暂时无法完成操作，请稍后重试。'}), 500
        return render_template('login.html', error='系统暂时无法完成操作，请稍后重试。'), 500

    @app.get('/auth/login')
    def login_form():
        return render_template('login.html', error=None)

    @app.post('/auth/login')
    def login():
        actor = service.login(request.form.get('phone'), request.form.get('password'))
        session.clear()
        session.permanent = True
        session['actor'] = {key: actor[key] for key in ('phone', 'role', 'session_version')}
        csrf_token()
        return redirect(url_for('home'))

    @app.post('/auth/logout')
    def logout():
        session.clear()
        return redirect(url_for('login_form'))

    @app.get('/')
    def home():
        if 'actor' not in session:
            return redirect(url_for('login_form'))
        actor = service.current_actor(session['actor'])
        context = service.dao.employee_context(actor)
        return render_template('home.html', actor=context)

    @app.get('/api/me')
    def me():
        actor = service.current_actor(session.get('actor'))
        return jsonify(data=service.dao.employee_context(actor))

    def cashier():
        actor = service.current_actor(session.get('actor'))
        require_cashier(actor)
        return actor

    @app.get('/sales/new')
    def sale_form():
        actor = cashier()
        return render_template('sale_form.html', actor=actor, goods=service.dao.sale_catalog(actor), request_key=new_request_key())

    @app.post('/sales/preview')
    def sale_preview():
        return render_template('sale_preview.html', **sales.preview(cashier(), form_payload(request.form)))

    @app.post('/sales')
    def sale_create():
        result = sales.create(cashier(), request.form.get('quote_token'))
        return redirect(url_for('sale_receipt', sale_no=result['no']), code=303)

    @app.get('/sales/<sale_no>')
    def sale_receipt(sale_no):
        return render_template('sale_receipt.html', sale=service.dao.sale_get(cashier(), sale_no))

    @app.get('/api/sale-goods')
    def sale_goods_api():
        return jsonify(data=service.dao.sale_catalog(cashier()))

    @app.post('/api/sales/preview')
    def sale_preview_api():
        actor = cashier()
        return jsonify(data=sales.preview(actor, request.get_json(silent=True)))

    @app.post('/api/sales')
    def sale_create_api():
        actor = cashier()
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            raise AppError('invalid_sale', '请提交有效的结算确认。', 400)
        return jsonify(data=sales.create(actor, payload.get('quote_token')))

    @app.get('/api/sales/<sale_no>')
    def sale_get_api(sale_no):
        return jsonify(data=service.dao.sale_get(cashier(), sale_no))

    return app
