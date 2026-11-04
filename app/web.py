"""Shared HTTP contracts and privacy-preserving request diagnostics."""
from datetime import datetime, timezone
import hashlib
import hmac
import json
import logging
import secrets
import time
import traceback

from flask import g, jsonify, render_template, request, session
from werkzeug.exceptions import HTTPException

from .errors import AppError

logger = logging.getLogger('bookstore.requests')


def json_object():
    if not request.is_json:
        raise AppError('unsupported_media_type', '请使用 JSON 格式提交。', 415)
    value = request.get_json()
    if not isinstance(value, dict):
        raise AppError('invalid_json', '请提交 JSON 对象。', 400)
    return value


def pagination():
    result = {}
    for key, default, maximum in (('page', 1, 1000000), ('page_size', 20, 100)):
        values = request.args.getlist(key)
        value = values[0] if values else str(default)
        if len(values) > 1 or not value.isascii() or not value.isdecimal() or len(value) > 7:
            raise AppError('invalid_pagination', '页码或每页数量格式不正确。', 400)
        number = int(value)
        if not 1 <= number <= maximum:
            raise AppError('invalid_pagination', '页码或每页数量超出范围。', 400)
        result[key] = number
    return result


def install_web_contracts(app):
    @app.before_request
    def begin_request():
        g.request_id = secrets.token_hex(16)
        g.request_started = time.perf_counter()
        g.error_code = None
        g.request_actor = dict(session.get('actor') or {})

    @app.before_request
    def protect_writes():
        if request.url_rule is None or request.method not in ('POST', 'PUT', 'PATCH', 'DELETE'):
            return
        expected = session.get('csrf_token', '')
        received = request.headers.get('X-CSRF-Token') or request.form.get('csrf_token', '')
        if not expected or not secrets.compare_digest(expected.encode('utf-8'), received.encode('utf-8')):
            raise AppError('invalid_csrf', '页面已过期，请刷新后重试。', 403)

    def error_response(error):
        g.error_code = error.code
        if error.status == 401:
            app.extensions['sale_drafts'].discard(session.get('sale_draft'))
            session.pop('actor', None)
            session.pop('sale_draft', None)
        if request.path == '/api' or request.path.startswith('/api/'):
            return jsonify(error=dict(code=error.code, message=error.message), request_id=g.request_id), error.status
        if request.endpoint in ('auth.login', 'auth.login_form'):
            return render_template('login.html', error=error.message), error.status
        retry_token = None
        if request.endpoint == 'sales.sale_create' and (error.status == 503 or error.code == 'sale_busy'):
            retry_token = request.form.get('quote_token')
        operation_retry = (request.endpoint in ('operations.write', 'operations.confirm','reservations.create',
                            'reservations.pickup_confirm','members.confirm','members.contact','returns.confirm','returns.recover')
                           and (error.status == 503 or error.code == 'sale_busy'))
        return render_template('error.html', error=error.message, retry_token=retry_token, status=error.status,
                               operation_retry=operation_retry), error.status

    app.register_error_handler(AppError, error_response)

    @app.errorhandler(HTTPException)
    def http_error(error):
        details = {
            400: ('invalid_request', '请求格式不正确，请检查后重试。'),
            404: ('not_found', '记录不存在或不可访问。'),
            405: ('method_not_allowed', '此操作不支持当前请求方式。'),
            413: ('request_too_large', '提交内容过大，请减少明细后重试。'),
            415: ('unsupported_media_type', '请使用支持的内容格式提交。'),
        }
        code, message = details.get(error.code, ('http_error', '暂时无法处理此请求。'))
        response = app.make_response(error_response(AppError(code, message, error.code or 500)))
        if error.code == 405:
            response.headers['Allow'] = ', '.join(error.valid_methods or [])
        return response

    @app.errorhandler(Exception)
    def unexpected_error(error):
        frames = [dict(file=frame.filename, line=frame.lineno, function=frame.name)
                  for frame in traceback.extract_tb(error.__traceback__)]
        logger.error(json.dumps(dict(event='exception', request_id=g.request_id,
                                     exception_type=type(error).__name__, stack=frames), ensure_ascii=False))
        return error_response(AppError('internal_error', '系统暂时无法完成操作，请稍后重试。', 500))

    @app.after_request
    def complete_request(response):
        response.headers['X-Request-ID'] = g.request_id
        response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        actor = session.get('actor') or g.request_actor
        phone = actor.get('phone', '')
        subject = hmac.new(app.secret_key.encode(), str(phone).encode(), hashlib.sha256).hexdigest()[:16] if phone else None
        role = actor.get('role') if actor.get('role') in ('收银员', '库管', '店长') else None
        record = dict(event='request', request_id=g.request_id,
                      time=datetime.now(timezone.utc).isoformat(), method=request.method,
                      action=request.endpoint or 'unmatched', subject_type='employee' if phone else 'anonymous',
                      role=role, subject=subject, error_code=g.error_code,
                      result='success' if response.status_code < 400 else 'failure', status=response.status_code,
                      duration_ms=round((time.perf_counter()-g.request_started)*1000, 2))
        logger.info(json.dumps(record, ensure_ascii=False))
        return response
