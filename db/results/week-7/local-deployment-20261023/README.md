# 本机运行账号与 HTTP 登录验收

执行日期：2026-10-23（客户端时区 UTC+8）。用户要求完成运行配置，并明确同意“允许，现在切换并重启”。本次由 AI 执行配置及验证，不记为人工浏览器操作。

同日后续已接入门店销售，运行副本新增请求技术表后为22表/52外码；见[销售验收记录](../sale-entry-20261023/README.md)。本页保留账号配置完成时的原始验收状态。

## 实际变更

- 目标副本：`ShiguangBookstoreWeek7EntryYourRun`。
- 创建4个 SQL 登录及同名数据库用户：`bookstore_w7_yourrun_auth`、`bookstore_w7_yourrun_cashier`、`bookstore_w7_yourrun_inventory`、`bookstore_w7_yourrun_manager`，各自仅加入一个对应的 `bookstore_app_*` 角色；没有加入 sysadmin 或 db_owner。
- 为副本中4名既有员工初始化随机练习口令，数据库仅存口令哈希；当前启用、会话版本均为1。
- 生成 `app/settings.local.ps1`（签名密钥及服务连接）和 `app/demo-credentials.local.json`（员工练习口令）。两者被 Git 忽略，本机 ACL 限定为当前 Windows 用户与 SYSTEM；不把秘密复制到结果目录。
- 经用户确认，执行 [认证模式脚本](../../../enable-local-sql-auth.sql)，将默认实例改为混合身份验证，并重启 MSSQLSERVER。普通进程首次重启因 Windows 服务控制权限不足失败；随后通过 Windows UAC 管理员授权执行 [重启脚本](../../../restart-local-sql.ps1)，成功，当前 `IsIntegratedSecurityOnly=0`。Windows 登录保留，没有启用 sa、变更网络协议或开放端口。
- 启动只监听 `127.0.0.1:5000` 的 Flask 本地开发服务；重启电脑后需重新运行启动脚本。

一次性准备及验证工具为 [app/provision_local.py](../../../../app/provision_local.py)，仅面向此固定练习副本；如果已有配置、登录或员工凭据，会拒绝重新初始化。启动方式见 [app/README.md](../../../../app/README.md)。

## 验收结果

| 证据 | 结果 |
|---|---|
| [01-independent-logins.txt](01-independent-logins.txt) | 四个真实 SQL 登录独立连接，ORIGINAL_LOGIN/USER_NAME/DB_NAME 匹配预期；直接读凭据、读销售和改库存均返回229。通过真实 DAO 的 Flask 测试客户端验证四名员工登录、身份、工作台和退出。 |
| [02-http-login.txt](02-http-login.txt) | 经实际运行中的 HTTP 服务，四名员工分别完成匿名401、获取CSRF、登录、工作台及身份核对、退出、退出后401。采用CookieJar和真实表单POST，无连接模拟。 |
| [03-state.txt](03-state.txt) | 混合身份验证生效；四个服务登录启用且均非sysadmin；数据库角色绑定正确；四份员工凭据启用；目标21表/50外码，来源20表/49外码。查询源码：[state.sql](state.sql)。 |
| [04-source-snapshot.txt](04-source-snapshot.txt)、[05-target-snapshot.txt](05-target-snapshot.txt) | 来源及运行副本的19张业务表旧列指纹。 |
| [06-snapshot-comparison.json](06-snapshot-comparison.json) | 与前一步保存的来源快照逐项比较，19项来源前后及来源与运行副本全部一致。旧列快照不含 supplier 的两列 Week6 新增留痕。 |

本次验证补足此前未完成的“独立 SQL 登录连接”和“实际 HTTP 服务”验收。原有25项可回滚测试在最初的空凭据副本上通过；本次没有将其写成已在配置员工口令后的运行副本重跑。Week6 历史交付审计仍通过。

## 使用与复验

访问 `http://127.0.0.1:5000/auth/login`，在本地 `app/demo-credentials.local.json` 中查看对应员工的练习口令。新终端启动服务：

```powershell
. ./app/start-local.ps1
```

如果已有服务占用5000端口，直接使用现有服务。只读复验：

```powershell
. ./app/settings.local.ps1
.\.venv\Scripts\python.exe -m app.provision_local verify
.\.venv\Scripts\python.exe -m app.provision_local verify-http
```

`verify-http` 要求5000端口服务已运行。密码重置通过 `app.manage set-password` 交互执行，重置后本地练习口令文件不会自动同步，应使用新口令登录；此时基于旧练习口令文件的复验会失败。

当前工作台仅显示员工身份并提供退出；销售、预订等业务写入仍在后续实现范围。
