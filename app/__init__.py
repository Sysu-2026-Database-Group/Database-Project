import logging
import os
import secrets
from datetime import timedelta

from flask import Flask, session

from .dao import EmployeeDAO
from .services import EmployeeService
from .sales import SalesService, SaleDraftStore
from .web import install_web_contracts
from .operations import OperationsService


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
                        for key in ('auth', 'cashier', 'inventory', 'manager', 'guest', 'task')},
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

    app.extensions['employees'] = service
    app.extensions['shop_dao'] = service.dao
    app.extensions['sales'] = sales
    app.extensions['operations'] = OperationsService(service.dao, app.config['SECRET_KEY'])
    from .reservations import ReservationService
    app.extensions['reservations'] = ReservationService(service.dao, app.config['SECRET_KEY'])
    from .members import MemberService
    app.extensions['members'] = MemberService(service.dao, app.config['SECRET_KEY'])
    from .returns import ReturnService
    app.extensions['returns'] = ReturnService(service.dao, app.config['SECRET_KEY'])
    app.extensions['sale_drafts'] = SaleDraftStore()
    request_logger = logging.getLogger('bookstore.requests')
    request_logger.setLevel(logging.INFO)
    if not request_logger.handlers:
        request_logger.addHandler(logging.StreamHandler())
    install_web_contracts(app)
    from .routes.auth import bp as auth
    from .routes.sales import bp as sales_routes
    from .routes.workspace import bp as workspace
    from .routes.operations import bp as operations
    from .shop import bp as shop
    from .reservations import bp as reservations
    from .management import bp as management
    from .members import bp as members
    from .returns import bp as returns
    for blueprint in (auth, sales_routes, workspace, operations, shop, reservations, management, members, returns):
        app.register_blueprint(blueprint)
    return app
