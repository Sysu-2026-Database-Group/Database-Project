class AppError(Exception):
    def __init__(self, code, message, status):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


class DatabaseUnavailable(AppError):
    def __init__(self):
        super().__init__('database_unavailable', '系统暂时无法完成操作，请稍后重试。', 503)
