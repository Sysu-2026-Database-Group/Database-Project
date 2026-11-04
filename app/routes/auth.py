import secrets

from flask import Blueprint, current_app, jsonify, redirect, render_template, request, session, url_for

bp = Blueprint('auth', __name__)


@bp.get('/auth/login')
def login_form():
    return render_template('login.html', error=None)


@bp.post('/auth/login')
def login():
    actor = current_app.extensions['employees'].login(request.form.get('phone'), request.form.get('password'))
    current_app.extensions['sale_drafts'].discard(session.get('sale_draft'))
    session.clear()
    session.permanent = True
    session['actor'] = {key: actor[key] for key in ('phone', 'role', 'session_version')}
    session['csrf_token'] = secrets.token_urlsafe(32)
    return redirect(url_for('workspace.home'))


@bp.post('/auth/logout')
def logout():
    current_app.extensions['sale_drafts'].discard(session.get('sale_draft'))
    session.clear()
    return redirect(url_for('auth.login_form'))


@bp.get('/api/me')
def me():
    service = current_app.extensions['employees']
    actor = service.current_actor(session.get('actor'))
    return jsonify(data=service.dao.employee_context(actor))
