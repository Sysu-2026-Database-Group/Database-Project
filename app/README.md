# 拾光书店 Web 应用

2026-11-02当前版本已实现全角色核心业务入口，119项完整测试、52页真实Edge及11个真实表单节点通过。当前状态以[Web台账](../docs/tasks/task-web-development.md)为准；[操作手册](../docs/design/web-operation-manual.md)、[阶段报告](../docs/reports/report-web-v1.0.md)及[增量21实体模型](../docs/design/web-model-extension.md)已补齐。下文旧部署记录保留历史范围，其中“尚未实现”不代表当前结论。原经营副本未升级，人工、跨机及合并ER等差距见台账。

2026-11-02实时状态见 [Web实施台账](../docs/tasks/task-web-development.md)。P0/P1修复后76项完整验收已核实，P2主要闭环及采购竞争补充后93项完整验收通过；P3公开商品查询正在增量实现，不能用93项旧结果替代P3完整验收。下文历史部署状态不代表当前机器已配置。

P3新增公开商品 `/shop`、详情及公开API，使用专用顾客身份，只显示公开资料、售价及有货状态。新增部署为P2之后安装 `shop-entry.sql`；新库setup自动创建guest登录。已有环境须按 [P3设计及增量升级说明](../docs/design/p3-public-catalog.md) 添加独立配置，不能重新setup覆盖员工口令。预订、取货及自动到期尚未实现。

新增部署顺序：在明确指定的Week7副本先执行 `db/application-baseline.sql`，再执行原 `entry-foundation.sql`、`sale-entry.sql` 和新增 `workspace-entry.sql`，最后执行 `checks/application-baseline-check.sql` 与 `checks/application-permissions-check.sql`。SQLCMD均带 `-f 65001 -b`。这些安装不重新装载样例、不重置口令；应先通过新建隔离库的 `run.ps1 test` 后再安排已有运行副本升级。doctor/start/verify现在检查基线版本、触发器、视图、索引和精确授权，缺项会明确失败。

新增页面：`/workspace` 为员工工作台；`/sales` 为本人销售列表，支持 `page` 和 `page_size`（默认20、最大100），其他岗位不能访问。`/sales/new` 支持保存清单、改数量、数量置0移除及清空；内容留在服务端临时内存，重启后丢弃，确认前不占库存。提交后303跳转到凭证；结果不确定时保留原确认凭据重试。该实现用于当前单进程本机演示，多进程部署须先改为共享服务端清单存储。

统一错误响应补充顶层 `request_id`，响应头含 `X-Request-ID`；请求日志使用 `bookstore.requests` logger记录时间、动作、脱敏主体、岗位、错误码、结果和耗时，避免记录原始URL、查询参数、请求体及凭据。

当前实现员工登录、退出、本人身份查询，门店销售及本人单据，以及P2商品/供应商/报价、店长定价上下架、采购草稿至收货、注资资金查询和报损库存查询。预订、会员办理、退货及完整经营管理仍待后续开发。技术方案及信任边界见 [入口与权限方案](../docs/design/entry-permissions.md)，P2见[增量入口设计](../docs/design/p2-operations.md)和[90项完整验收](../db/results/week-7/p2-operations-20261102/README.md)。已有运行副本尚未升级，新库由runner自动部署。

P2新增部署顺序：在`workspace-entry.sql`之后执行 `operations-entry.sql`，再执行基线和精确授权检查。沿用 `sqlcmd -S localhost -E -C -b -f 65001 -i db/operations-entry.sql -v DatabaseName=明确指定的Week7副本`；不要重新setup覆盖原配置或口令。完整验收使用 `.\run.ps1 test`；本机直接执行脚本若被执行策略拒绝，可使用项目Python等效入口 `.venv\Scripts\python.exe scripts/project_runner.py test`。受限环境无法连接SQL时须正常审批，不修改实例设置。

## 推荐入口

统一使用仓库根目录 `run.ps1`。本机已有配置，可直接执行 doctor、test、start，无需重新生成账号或口令。队友首次换电脑使用 setup，完整说明见[统一入口与跨电脑复现](../docs/design/unified-entry.md)。

```powershell
.\run.ps1 doctor
.\run.ps1 test -Unit
.\run.ps1 test
.\run.ps1 start
# 保持start运行，在另一终端：
.\run.ps1 verify -Http
```

若系统禁止脚本执行，可用 `powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 doctor`，其他命令同理。完整测试自行准备独立库及临时登录，不需要手动加载运行配置或设置测试连接。

下面第1—6节保留底层部署说明供排查；日常操作以上述入口为准，不必再逐条执行。

## 1 准备依赖

在仓库根目录执行（Python 3.12已实测）：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

测试使用 Python 自带 unittest，不依赖 pytest。数据库客户端依赖本机已安装的 SQL Server ODBC 驱动。

## 2 建立第七周练习副本并部署

本机来源 `ShiguangBookstoreWeek6Work` 已完成第六周迁移。以下操作要求项目组的数据库管理身份；脚本拒绝覆盖目标库或文件。每次准备副本应更换数据库名，备份及副本会保留。

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -i db/prepare-entry-test.sql -v DatabaseName=ShiguangBookstoreWeek7EntryYourRun
sqlcmd -S localhost -E -C -b -f 65001 -i db/entry-foundation.sql -v DatabaseName=ShiguangBookstoreWeek7EntryYourRun
sqlcmd -S localhost -E -C -b -f 65001 -i db/sale-entry.sql -v DatabaseName=ShiguangBookstoreWeek7EntryYourRun
```

这些 SQL 文件使用 UTF-8 编码，`-f 65001` 必须保留。本机 `sqlcmd` 的默认代码页不能正确读取这些文件中的中文注释，可能漏执行后续语句，表现为准备副本仅显示切换到 `master`，部署时再报 `api` 架构不存在。准备副本成功时应看到备份、校验、恢复消息及目标库名称；后两步应分别看到 `entry-foundation.sql PASS`、`sale-entry.sql PASS`。当前本机副本已完成全部部署，不必重建。

后两条部署脚本可以在该副本上重复执行，不重新装载样例或重置凭据。登录基础新增1张技术表，销售再新增1张请求技术表；全部部署后为22表/52外码。不要对第七周副本执行第六周固定截面验收并期待其表数仍为20。

## 3 配置运行身份

2026-10-23，本机 `ShiguangBookstoreWeek7EntryYourRun` 已完成以下配置：四个独立受限 SQL 服务登录、四名员工的随机练习口令，以及 `app/settings.local.ps1`。经用户确认，默认实例已切换为 Windows + SQL Server 混合身份验证并重启；Windows 登录继续保留。四条真实服务连接及实际 HTTP 登录均已验证，详见[本机部署记录](../db/results/week-7/local-deployment-20261023/README.md)。

**使用当前机器时可直接跳到第5节启动。不要重复执行一次性配置，也不要覆盖现有本地设置。**

下述说明用于理解配置或准备其他环境。

需要四个独立的低权限数据库用户，分别只加入 `bookstore_app_auth`、`bookstore_app_cashier`、`bookstore_app_inventory`、`bookstore_app_manager`。不要加入历史 `bookstore_*` 角色或数据库管理员角色。

对于已经存在的低权限登录，管理员在第七周副本中创建用户并绑定角色，例如：

```sql
-- 仅示意：先确认 bookstore_cashier_login 已由部署人员建立，且无服务器管理权限。
CREATE USER bookstore_cashier_service FOR LOGIN bookstore_cashier_login;
ALTER ROLE bookstore_app_cashier ADD MEMBER bookstore_cashier_service;
```

其余三个用户同理，分别绑定各自角色。采用 SQL 登录时还需要实例支持该认证方式；采用 Windows 服务身份时需配置相应服务进程身份。配置四条连接时不能都指向当前 dbo/管理员连接。

本机一次性配置脚本为 `python -m app.provision_local provision`，仅面向固定练习副本；它生成四个随机服务口令、初始化已有员工，并写入两份忽略文件。遇到已有配置、登录或员工凭据即拒绝执行，不负责重置。`db/enable-local-sql-auth.sql` 和 `db/restart-local-sql.ps1` 是此次实例操作的留档，影响整个本机实例，只有在明确同意切换及重启时才使用。

复制 `app/settings.example.ps1` 为被 Git 忽略的 `app/settings.local.ps1`，填写本机连接与随机签名密钥，然后手动点源。示例中的 SQL 登录名称和密码占位符不是已经创建的账号。当前代码不自动加载 `.env`。

各条连接的 `DATABASE` 必须与第2步创建的副本名一致。当前配置示例使用 `ShiguangBookstoreWeek7EntryYourRun`；若使用其他副本名，请相应替换，包括初始化员工口令时使用的管理连接。

```powershell
. ./app/settings.local.ps1
```

`BOOKSTORE_COOKIE_SECURE=0` 仅用于本机 HTTP；HTTPS 部署设置为1。

## 4 初始化员工口令

当前四名员工已初始化。打开本地 [demo-credentials.local.json](demo-credentials.local.json) 查看手机号、姓名、岗位及各自练习口令。该文件与 `settings.local.ps1` 均被 Git 忽略，且已将本机访问权限限制为当前用户和 SYSTEM。下面的命令用于后续主动重置或停用。

在单独的管理终端配置管理连接，使用交互工具输入口令；不要将口令写进命令参数或提交仓库。

```powershell
$env:BOOKSTORE_DB_ADMIN='DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=ShiguangBookstoreWeek7EntryYourRun;Trusted_Connection=yes;TrustServerCertificate=yes;'
.\.venv\Scripts\python.exe -m app.manage set-password 13800000003
```

该手机号必须已存在于 `dbo.employee`。相同命令可重置口令并恢复启用；旧会话因版本改变而失效。停用命令：

```powershell
.\.venv\Scripts\python.exe -m app.manage disable 13800000003
```

该工具是部署工具，尚未实现店长通过 Web 页面维护员工账号。运行 Flask 的环境不需要配置 `BOOKSTORE_DB_ADMIN`。

## 5 启动与检查

当前服务已启动在 `http://127.0.0.1:5000`。如果访问正常，直接使用；停止服务或重启电脑后，在仓库根目录执行：

```powershell
. ./app/start-local.ps1
```

启动脚本会加载本地设置并在前台运行，按 `Ctrl+C` 停止。若提示端口已占用，先访问现有服务。此次后台进程信息位于 `app/server.local.json`，日志位于 `app/server.stdout.local.log` 和 `app/server.stderr.local.log`，均被 Git 忽略。

访问 `http://127.0.0.1:5000/auth/login`。成功后工作台显示姓名、岗位并提供退出按钮。`GET /api/me` 返回当前员工身份；未登录时返回401。写请求需使用页面隐藏字段或 `X-CSRF-Token` 传递令牌。

前端提交 `role=店长` 或另一个手机号不会改变当前员工身份。浏览器不得获得数据库连接或员工口令哈希。

## 6 验证

仅应用测试（真实数据库测试会明确标为 skipped）：

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

真实数据库集成测试，需要一个已部署入口基础、尚未配置员工凭据的第七周副本：

```powershell
$env:BOOKSTORE_TEST_ADMIN_CONNECTION='DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=ShiguangBookstoreWeek7Entry20261022;Trusted_Connection=yes;TrustServerCertificate=yes;'
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

测试通过管理连接事务创建临时数据库用户和随机口令的哈希，使用 `EXECUTE AS USER` 执行真实SQL，并通过 Flask 测试客户端走登录和身份查询。测试结束后整笔回滚；遇到已经配置员工凭据的副本会拒绝运行，避免覆盖。本项不替代四个真实服务账号的独立连接部署验收，也不涉及浏览器手动演示。

本机 `YourRun` 副本现在已有持久练习凭据，上述可回滚集成测试应使用仍为空凭据的 `ShiguangBookstoreWeek7Entry20261022`，或另外建立全新副本。对已配置的运行副本，用以下命令只读验证真实连接和通过运行服务的 HTTP 流程：

```powershell
. ./app/settings.local.ps1
.\.venv\Scripts\python.exe -m app.provision_local verify
# 先确保 http://127.0.0.1:5000 正在运行
.\.venv\Scripts\python.exe -m app.provision_local verify-http
```

## 7 办理门店销售

1. 用收银员 `13800000003` 或 `13800000004` 登录；口令在 `app/demo-credentials.local.json`。
2. 在工作台点击“办理门店销售”，选择数量；会员填写已有会员手机号，非会员留空，使用积分默认0。
3. 点击“预览结算”，核对商品、折扣、积分及应收金额；此时不写销售、不扣库存，也不预留商品。
4. 实际收款后点击“确认已收款并生成销售单”，进入销售凭证页，把单号交给顾客。同一确认重复提交返回原销售，不重复扣库存或记款。

门店销售是现场收款确认，没有接入外部支付网关。当前会员样例 `13900000003` 为银卡，`13900000004` 为金卡；会员权益由成交时的到期日判断。新开表单只读取当前数据，真实确认会重新校验价格、会员条件和可售量；价格等结算条件变化需要重新预览。

例如初始样例“拾光帆布袋”售价19元：非会员买1件实收19元；银卡会员使用100积分时，折后18.05元，抵扣1元，实收17.05元、获得17积分。只有确认后才产生这笔交易。库存不足、未上架、超积分上限或写入中途失败均不会留下部分销售。

店长、库管不能办理销售；收银员只能访问自己经手的销售凭证。当前没有销售列表，可通过成交后的凭证页或 `/sales/<单号>` 返回查看。商品名称取当前展示名称，单价、数量、折扣和金额取成交快照。

接口与 CSRF：

| 接口 | 用途 |
|---|---|
| `GET /api/sale-goods` | 收银员读取结算用商品与库存 |
| `POST /api/sales/preview` | 传 `request_key`（UUID）、`items`（商品编号及数量）、可选 `member_phone` 和 `used_points`；返回签名确认令牌 |
| `POST /api/sales` | 传 `quote_token`，返回销售结果；重复调用返回同一结果 |
| `GET /api/sales/<单号>` | 当前收银员的销售凭证 |

API写请求须带当前会话的 `X-CSRF-Token`。价格、折扣、金额、操作人及时间不接受前端指定。支持每单1至50种商品、每种1至1000件，单笔原价小计不超过 `99,999,999.99` 元。提交结果不确定时保留原确认令牌重试；不要为同一笔交易另开请求。

## 8 销售验收复现

统一入口为每次验收建立新的认证与销售专用库，并生成四个临时 SQL 服务登录；不依赖固定日期库名或既有运行登录。写入前逐条核对实际目标库、实例和登录。结束后清理测试用户、凭据和销售，恢复数据，核对19张业务表指纹并删除临时登录。数据库和备份保留供复查。

```powershell
.\run.ps1 test
```

历史销售阶段48项通过记录继续保留。统一入口增加隔离及失败判定测试，最新结果以本次 `.runner/` 内报告为准。覆盖真正的HTTP表单确认、重复提交、并发库存/积分竞争、资金余额链及中途故障回滚。自增值和单号序列允许有空号，不代表残留业务数据。
