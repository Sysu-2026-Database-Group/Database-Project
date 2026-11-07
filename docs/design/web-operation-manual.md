# Web 全角色操作与验收手册

实现状态和真实证据以[台账](../tasks/task-web-development.md)为准；新增模型及事务口径见[增量模型](web-model-extension.md)。所有示例从仓库根目录执行，不覆盖已有配置或口令。

## 环境与启动

在 Windows 上准备本机 SQL Server、sqlcmd、ODBC Driver 17 或 18、Python 和 PowerShell。实例须支持项目使用的 SQL 登录。首次运行时，从示例复制本地配置，选择未占用的 Week7 库名、登录前缀和端口，以及独立设置目录。配置字段见[统一入口](unified-entry.md)。

~~~powershell
if (Test-Path -LiteralPath 'run.stage.local.json') { throw '请使用新的配置文件名' }
Copy-Item -LiteralPath run.example.json -Destination run.stage.local.json
~~~

编辑并保存 `run.stage.local.json`，将 `database`、`login_prefix`、`port` 和 `settings_directory` 改为本次环境的值，再执行以下命令。

~~~powershell
$config = 'run.stage.local.json'
.\run.ps1 setup -ConfigFile $config
.\run.ps1 doctor -ConfigFile $config
.\run.ps1 test -ConfigFile $config
.\run.ps1 start -Detach -ConfigFile $config
.\run.ps1 verify -Http -ConfigFile $config
# 使用配置端口打开本地 Web。演示完毕后停止并检查。
.\run.ps1 stop -ConfigFile $config
.\run.ps1 status -ConfigFile $config
~~~

已有环境从 doctor 开始。test 自建两个隔离测试库并在结束时清理临时身份，测试库及备份保留供排查。首次准备命令会生成本地演示凭据。

若 PowerShell 执行策略拦截脚本，使用 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 test -ConfigFile run.stage.local.json`，其他命令同理。配置和演示账号口令留在本机。

增量安装顺序：application-baseline、entry-foundation、sale-entry、workspace-entry、operations-entry、shop-entry、reservation-entry、management-entry、member-entry、return-entry，最后两个 application 检查脚本。每个脚本用 `sqlcmd -S localhost -E -C -b -f 65001 -i db/脚本.sql -v DatabaseName=明确指定的Week7库`。完整隔离验收先通过再升级运行副本；不向已有库重装样例。新增缺失的 guest/task 身份使用 `python -m app.upgrade_guest --identity guest或task --database 明确库名 --login-prefix 原前缀 --directory 原配置目录`，仅新增独立配置，已有身份拒绝覆盖。

`start` 管理 Web 和过期任务，Ctrl+C 停止两者。本次 `.runner/start-*/summary.json` 的 processes 记录 PID 和生命周期状态，`expiry.log` 记录每轮时间、成功/失败及数量。单独排查可加载 task 配置后执行 `python -m app.expiry --once`，或 `--interval 60 --batch-size 100` 循环。任务只能连明确的 Week7 库；失败记录代码，不打印连接秘密。

## 演示顺序

1. 店长登录，进入资金页预览并确认注资，保存凭证。设置银/金卡费和折扣；金卡费必须更高、折扣率不得更高。
2. 库管新增供应商、商品、报价。新商品库存为零且未定价；店长设置售价并上架。历史销售价格快照不随调价变化。
3. 库管新建单供应商采购草稿，维护明细后提交。店长审批并预览一次付款；库管一次收货。检查资金减少与库存增加分别发生，重新提交不产生第二笔。
4. 顾客打开 `/shop`，只能见已上架商品、公开属性及有货标记。选择商品登记手机号预订，保存预定码；凭手机号和码查询。取消确认会释放整单，不能恢复。
5. 收银登录 `/pickups`，核验手机号及码，填写会员和抵扣积分，预览后确认整单取货。检查预订已取、生成销售凭证、在架量及本单已订量同时减少。过期或下架不能取货。
6. 收银在 `/sales/new` 维护临时清单：新增、改数量、置零移除和清空，再预览成交。成交前清单只在服务器内存，重启丢弃；成交后用退货冲销，不能编辑既成事实。
7. 收银在 `/members` 开卡、同档续费或升级；确认费用及前后到期日。现场核验后维护联系号码/发放自助凭证。顾客 `/shop/member` 凭当前号码和凭证查询本人销售、退款、积分；重置后旧凭证失效。
8. 收银 `/returns/new` 输入精确原单号（可跨收银），填写部分或全部退货数量，预览并确认退款。检查只退实付比例、只回滚原获得积分且库存不变。库管 `/return-recovery` 再确认各退货行回收入库。
9. 库管登记报损及文字原因；已订商品不得报损。店长/库管查库存流水，店长查资金及经营报表，核对来源单据、数量、收付及前后余额。
10. 店长管理员工：新增、启停、改岗、重置口令。原会话应失效；最后启用店长不能被停用或改岗。测试这些操作只使用隔离演示副本。

## 结果解释

写入未知结果时保留原请求与确认凭据重试，不换新键重新收款。已成交请求返回原凭证；过期预览首次提交应重新预览。资金不足、可售量不足、过量退货、权限拒绝和会话失效均应有可读错误及请求编号。GET 不写库，缺 CSRF 的 POST 应拒绝。

验收需同时保留完整 SQL 报告、源码 SHA-256、恢复/清理结果、360px/1440px 页面证据和新环境 setup/doctor/start/verify 证据。截图与自动化操作不能记为人工审阅；本机新副本复现不能冒充另一台电脑实测。阶段报告中如实记录未验收差距。

## 分角色入口

| 角色 | 入口 | 主要页面 |
|---|---|---|
| 顾客（免登录） | `/shop` | 商品目录与详情、`/shop/reservations/new`、凭证查询、`/shop/member` |
| 收银员 | `/auth/login` → `/workspace` | `/sales/new`、`/sales`、`/pickups`、`/returns/new`、`/members` |
| 库管 | 同上 | `/goods`、`/suppliers`、`/supplier-quotes`、`/purchases`、`/inventory`、`/return-recovery` |
| 店长 | 同上 | `/management/goods`、`/management/finance`、`/management/employees`、`/management/cards`、`/management/reports`、全店单据 |

## 常见问题

| 现象 | 原因与处理 |
|---|---|
| `start` 后终端没有输出、也不返回 | `start` 默认前台常驻，Ctrl+C 停止；自动化场景使用 `.\run.ps1 start -Detach`，日志在 `.runner/start-<id>/web.log` 与 `expiry.log` |
| SQL Server 报 911，找不到默认运行库 | 核对是否缺少默认配置 run.local.json，或使用了错误的库名。传入已完成 setup 的同一 -ConfigFile |
| 端口已被占用 | 先 `.\run.ps1 stop`（会结束本配置记录的 Web 与任务），再重新 `start` |
| `doctor` 报"缺少筛选唯一索引 X" | 目标库未装齐运行时对象；用新库名重新 `setup`，或按增量顺序补脚本 |
| 403 | 岗位不足或 CSRF 失效；刷新页面后重试，不要跨角色直接访问管理页 |
| 409 | 预览过期、状态变化或规则冲突；刷新并重新预览 |
| 503 | 数据库连接不可用；检查实例与服务后重试，页面上的请求编号可用于定位 |
| 开卡后没有拿到自助凭证 | 凭证只在结果页展示一次；丢失时由收银现场核验后"改联系方式/重发凭证" |
| 删除商品失败 | 提示会区分"有库存 / 请先下架 / 已被单据引用"，按提示先处理依赖 |
| 提交后页面报"请求标识冲突" | 同一请求键被用于不同内容；刷新重新提交，不要手改请求键 |
