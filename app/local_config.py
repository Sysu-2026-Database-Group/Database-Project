"""本机配置工具；连接字符串按 ODBC 规则转义，不通过替换运行配置生成测试配置。"""
import csv
import os
import subprocess


def connection_string(server, database, driver, *, login=None, password=None):
    values = {'DRIVER': driver, 'SERVER': server, 'DATABASE': database,
              'Encrypt': 'yes', 'TrustServerCertificate': 'yes'}
    if login is None:
        values['Trusted_Connection'] = 'yes'
    else:
        values.update(UID=login, PWD=password)
    return ''.join(key + '={' + str(value).replace('}', '}}') + '};' for key, value in values.items())


def restrict_local_file(path):
    """包含秘密的文件仅允许当前 Windows 用户和 SYSTEM 访问。失败则停止配置。"""
    if os.name != 'nt':
        path.chmod(0o600)
        return
    result = subprocess.run(['whoami', '/user', '/fo', 'csv', '/nh'], capture_output=True, text=True, check=True)
    sid = next(csv.reader(result.stdout.strip().splitlines()))[1]
    subprocess.run(['icacls', str(path), '/inheritance:r', '/grant:r',
                    f'*{sid}:(F)', '*S-1-5-18:(F)'], capture_output=True, check=True)
