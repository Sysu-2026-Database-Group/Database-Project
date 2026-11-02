# 拾光书店项目队友交接单

交接日期：2026-11-02（北京时间）。仓库：[Sysu-2026-Database-Group/Database-Project](https://github.com/Sysu-2026-Database-Group/Database-Project)，日常分支为 `main`。本文件用于队友接手、换电脑运行、演示与最后交付检查；实时开发状态仍以[任务台账](tasks/task-web-development.md)为准。

## 1. 这次交付了什么

当前为可运行、已有真实 SQL Server 与浏览器证据的 Web 阶段版本，保留第5—6周材料；尚未取得本轮组员人工签收和另一台电脑复现结果。

| 使用人 | 已有入口与能力 |
|---|---|
| 顾客 | `/shop` 商品列表/详情；预订、凭手机号和预定码查询/取消；`/shop/member` 凭独立凭证查询本人权益、销售/退款明细与积分 |
| 收银员 | `/sales/new` 销售清单、预览及结算；`/sales` 本人单据；`/pickups` 预订整单取货/代取消；`/members` 开卡续费升级与联系维护；`/returns/new` 凭原单受理退款 |
| 库管 | 商品、供应商、报价；采购草稿与明细、提交/取消、付款后收货；库存流水及报损；`/return-recovery` 独立退货回收 |
| 店长 | 定价上下架；采购审批/一次付款；注资提现；卡参数；员工启停/改岗/重置；经营收支与全店销售、预订、退货单据 |
| 到期任务 | 独立受限身份，默认每60秒最多处理100笔到期预订；有日志及与 Web 共同启停入口 |

技术栈：Python、Flask/Jinja、pyodbc、SQL Server；运行时依赖见根目录 `requirements.txt`。路由与服务不直连数据库，运行 SQL 统一在 DAO 中，重要写入由存储过程完成。当前有21个经营实体，运行连接分为 auth/cashier/inventory/manager/guest/task 六类。

## 2. 队友拿到仓库后怎么运行

先安装 Python（已实测3.12）、SQL Server、Microsoft ODBC Driver17/18、`sqlcmd` 和 Windows PowerShell5.1及以上。实例需支持项目采用的 SQL 登录；Windows 管理身份需有创建练习库、备份恢复和配置服务登录的权限。入口只检查实例，不自动改变实例设置。没有配置权限时由本机数据库负责人处理。

首次在自己的电脑准备，从新目录开始：

```powershell
git clone https://github.com/Sysu-2026-Database-Group/Database-Project.git
cd Database-Project

# 将 Teammate 改成自己电脑上未占用的名字；不要复用已有经营库。
.\run.ps1 setup -Server localhost -DatabaseName ShiguangBookstoreWeek7Teammate -LoginPrefix bookstore_teammate
.\run.ps1 doctor
.\run.ps1 test
.\run.ps1 start
```

保持 start 终端运行，在项目另一终端执行：

```powershell
.\run.ps1 verify -Http
.\run.ps1 status
# 演示结束：
.\run.ps1 stop
```

脚本执行策略阻止时，可使用 `powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 doctor`，其他命令同理；不需要修改整机策略。命名实例把 `localhost` 改为实际值，例如 `localhost\SQLEXPRESS`。`setup` 自动创建虚拟环境并安装运行依赖，默认HTTP端口5000，只监听本机。

`setup` 从仓库脚本建立新基线和练习副本，无需拿原开发者的数据库备份或密码；已有库、登录前缀或本地凭据重名会拒绝覆盖。失败时先查看 `.runner` 对应报告，不要删除已有库后盲目重试。重复尝试应选择新的库名、登录前缀和独立配置目录。详细参数见[统一入口说明](design/unified-entry.md)。

已有本地环境先执行 `doctor`。旧版本可能缺少新过程及 guest/task 连接，**不要重新 setup 覆盖原环境**；按[全角色手册](design/web-operation-manual.md)安装增量和补充独立身份。本轮没有升级原开发者经营副本，只新建了隔离测试和演示副本。

## 3. 账号、配置和数据如何交接

| 文件或资源 | 用途与交接方式 |
|---|---|
| `run.example.json` | 无秘密示例；setup成功后生成本机 `run.local.json`，保存实例、库名、前缀、端口和配置目录 |
| `app/settings.local.ps1` | 默认配置目录的服务连接和应用密钥；各电脑由setup自行生成，不复制他人连接，不提交Git |
| `app/demo-credentials.local.json` | 本机练习员工账号及随机口令；在本机打开查看，用于员工登录；不发到仓库或截图报告 |
| `settings.guest.local.ps1` / `settings.task.local.ps1` | 旧环境增量补身份时生成；新setup已在主配置内生成六种连接 |
| `.runner/` | 本地运行报告、备份相关清单及演示配置；默认不提交。需交付的脱敏证据已经归档到 `db/results/week-7/` |
| SQL Server 数据库和备份 | 不随Git传输；各电脑从脚本复现。测试库和备份保留会占磁盘，由数据库负责人按报告核对后管理 |

员工入口 `/auth/login`，根据本机凭据文件选择店长、库管或收银员。顾客不需要员工账号。会员自助凭证由收银员现场核验后发放/重置，不能仅凭手机号申领。预订凭证是手机号加预定码。

当前开发机独立演示库为 `ShiguangBookstoreWeek7WebDemo20261102A`，配置在 `.runner/web-demo/`，端口5091。它保留演示交易，且目前已停止；队友无需复制此环境，在自己的电脑重新setup即可。原经营副本、账号及实例设置没有被本轮验收修改。

## 4. 最新测试怎么看

最新完整报告为 `.runner/test-20261102T154529Zf4a747`，脱敏原件已提交到[交付证据目录](../db/results/week-7/web-delivery-20261102/README.md)：

- **full 119项，失败0、错误0、跳过0，41步骤全部PASS**。
- 92个应用、SQL、测试和入口源码SHA-256匹配；两个隔离副本21张经营表恢复一致，请求/凭据/测试用户及6个临时登录清理通过。
- 真实Edge在360px及1440px共52个页面检查通过，11个真实表单流程节点通过。
- 本机独立副本 setup、doctor、verify-Http 和 start/status/stop 实测通过；第六周历史材料指纹审计通过。

`tests/results.txt` 是本机旧失败输出，不能当最新报告。早期76/90/93/98项报告只证明当时版本。队友修改源码后须重新验收，新报告不能直接沿用本轮指纹。

完整测试自行创建隔离副本，不使用经营库，也不要求加载运行账号。仅运行非数据库检查可用 `.\run.ps1 test -Unit`，该结果不能代替完整SQL验收。日志中预期越权/故障注入错误以最终断言和报告为准。

可选浏览器脚本位于 `scripts/browser_acceptance.py`、`scripts/browser_workflows.py`，依赖额外安装Playwright及本机Edge，不是启动应用的必需依赖。写流程脚本只允许明确的独立WebDemo副本，**会产生演示交易**；不要改成经营库后运行。

## 5. 建议课堂演示顺序

1. 店长注资；库管建商品/供应商/报价；店长定价上架。
2. 库管采购草稿增改删行并提交，店长审批付款，库管整单收货，核对钱和货分别变化。
3. 顾客预订并保存凭证，收银员核验、预览并取货成交；另演示一次整单取消及释放已订量。
4. 收银员办理会员、预览销售与积分抵扣，展示本人单据；会员凭证查本人记录。
5. 凭原销售单部分退款，确认库存尚未增加；库管回收后再核对库存及流水。
6. 店长查看经营与现金余额、全店单据，演示注资/提现不计经营盈亏；结束后status/stop。

只在新演示副本操作。成交前清单可改数量、移除及清空；成交后保留原单，通过退款冲销。预订到期为创建时刻加三天，下架保留预订但不能取货；退款只退原实付比例、原使用积分不返还；采购一次付款和一次收货。详细规则及操作截图见手册与证据目录。

## 6. 还需要队友接手的事情

| 待办 | 需要保留的实际结果 |
|---|---|
| 另一台电脑从零复现 | 执行人、日期、软件版本、setup/doctor/test/start/verify-Http结果及新报告；本机新副本不算跨机实测 |
| 人工页面及业务签收 | 顾客/收银/库管/店长全流程操作，360px/桌面可读性、金额和来源对账，记录审阅人及具体问题 |
| 当前ER与课程材料核对 | [21实体drawio](../ER/er-diagram-web-v1.0.drawio)及[PNG](../ER/er-diagram-web-v1.0.png)人工核对；原第六周图和指纹保护材料保留 |
| 第二阶段真实分工 | 根据各成员实际工作补录，不能把第一阶段负责人复制成本阶段实现者；本轮AI实现/运行范围已在AI记录说明 |
| 剩余技术边界复核 | 超大会员历史分页、更广的退款/回收独立连接并发；临时销售清单目前是单进程内存，重启丢弃，多进程前需共享存储 |
| 正式交付打包 | 对照 `homework/` 原始要求核对应用、说明、阶段报告、分工、第5—6周成果；处理差距后再标记最终完成 |

人员分工由小组按实际安排确认，本文件不虚构新的负责人或签收记录。当前为核心实现及上述技术验收通过的阶段交付，不能据此直接声明所有课程要求已经签收。

## 7. 文件入口与协作约定

优先阅读：[本交接单](team-handoff.md) → [全角色手册](design/web-operation-manual.md) → [实时台账](tasks/task-web-development.md) → [阶段报告](reports/report-web-v1.0.md)。模型见[Web增量说明](design/web-model-extension.md)，业务规则以 `docs/specs/` 为准。

源码主要在 `app/`，安装和业务过程在 `db/`，统一入口在 `run.ps1` / `scripts/project_runner.py`，测试在 `tests/`。不要修改历史证据的manifest来消除审计失败；新扩展写独立文档和迁移。不要提交 `.venv`、本机配置、口令、数据库文件或 `.runner`。

开始工作前先 `git pull --ff-only`（有未提交改动时先妥善保存）；建议新建功能分支，说明变更和验证再合入main，避免强制推送覆盖队友。排障反馈提供对应报告目录、失败步骤、错误码和复现操作，隐去连接串、口令、Cookie与凭证。
