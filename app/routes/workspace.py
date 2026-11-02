from flask import Blueprint, current_app, redirect, render_template, session, url_for

bp = Blueprint('workspace', __name__)


@bp.get('/')
def home():
    if 'actor' not in session:
        return redirect(url_for('shop.index'))
    return workspace()


@bp.get('/workspace')
def workspace():
    service = current_app.extensions['employees']
    actor = service.current_actor(session.get('actor'))
    return render_template('home.html', actor=service.dao.employee_context(actor))
