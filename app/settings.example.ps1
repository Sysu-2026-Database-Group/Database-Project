# 复制为 settings.local.ps1 后填写，手动点源：. ./app/settings.local.ps1
# 此文件不会自动读取；本机实际驱动为17，安装18的机器请替换驱动名称。
# 用 python -c "import secrets; print(secrets.token_hex(32))" 生成自己的签名密钥。
$env:BOOKSTORE_SECRET_KEY = ''
$env:BOOKSTORE_COOKIE_SECURE = '0'
$env:BOOKSTORE_DATABASE = 'ShiguangBookstoreWeek7EntryYourRun'
$env:BOOKSTORE_SERVER = 'localhost'
$env:BOOKSTORE_LOGIN_PREFIX = 'bookstore_w7_yourrun'
# 以下UID是将来配置的四个不同低权限服务登录，不是四名员工的手机号。
# SQL登录需要实例支持SQL身份验证。2026-10-23本机已配置混合身份验证和以下登录。
# 本文件只是无秘密示例；已有 settings.local.ps1 时直接加载它，不要覆盖随机口令。
$env:BOOKSTORE_DB_AUTH = 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=ShiguangBookstoreWeek7EntryYourRun;UID=bookstore_w7_yourrun_auth;PWD=REPLACE_LOCALLY;Encrypt=yes;TrustServerCertificate=yes;'
$env:BOOKSTORE_DB_CASHIER = 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=ShiguangBookstoreWeek7EntryYourRun;UID=bookstore_w7_yourrun_cashier;PWD=REPLACE_LOCALLY;Encrypt=yes;TrustServerCertificate=yes;'
$env:BOOKSTORE_DB_INVENTORY = 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=ShiguangBookstoreWeek7EntryYourRun;UID=bookstore_w7_yourrun_inventory;PWD=REPLACE_LOCALLY;Encrypt=yes;TrustServerCertificate=yes;'
$env:BOOKSTORE_DB_MANAGER = 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=ShiguangBookstoreWeek7EntryYourRun;UID=bookstore_w7_yourrun_manager;PWD=REPLACE_LOCALLY;Encrypt=yes;TrustServerCertificate=yes;'
