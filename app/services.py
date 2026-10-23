import re

from werkzeug.security import check_password_hash, generate_password_hash

from .dao import ROLE_KEYS
from .errors import AppError


class EmployeeService:
    def __init__(self, dao):
        self.dao = dao
        # 不存在的账号也走一次哈希验证，不对外区分账号不存在/密码错/已停用。
        self.dummy_hash = generate_password_hash('not-an-employee-password')

    def login(self, phone, password):
        if (not isinstance(phone, str) or not re.fullmatch(r'[0-9]{11}', phone)
                or not isinstance(password, str) or not 1 <= len(password) <= 256):
            raise AppError('invalid_login', '账号或密码不正确。', 401)
        employee = self.dao.credentials(phone)
        try:
            valid = check_password_hash(employee['password_hash'] if employee else self.dummy_hash, password)
        except (ValueError, TypeError):
            valid = False
        if not valid or not employee or not employee['enabled'] or employee['role'] not in ROLE_KEYS:
            raise AppError('invalid_login', '账号或密码不正确。', 401)
        return {key: employee[key] for key in ('phone', 'name', 'role', 'session_version')}

    def current_actor(self, stored):
        if not isinstance(stored, dict):
            raise AppError('login_required', '请先登录。', 401)
        phone, version = stored.get('phone'), stored.get('session_version')
        if (not isinstance(phone, str) or not re.fullmatch(r'[0-9]{11}', phone)
                or type(version) is not int or not 1 <= version <= 2147483647):
            raise AppError('login_required', '请先登录。', 401)
        actor = self.dao.session_identity(phone, version)
        if not actor or actor['role'] not in ROLE_KEYS or actor['role'] != stored.get('role'):
            raise AppError('session_expired', '登录已失效，请重新登录。', 401)
        return actor
