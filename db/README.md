# 数据库脚本执行与复现说明

本目录保存拾光书店数据库项目的 Week 3、Week 4 和 Week 6 SQL 脚本。

**验证环境（数据库引擎与客户端工具的版本、以及实例名，一律以本地为准）**：

- 数据库引擎：SQL Server Express 版即可。**本文不写死版本号** —— 不同机器上可能是 2022 / 2025 等不同版本，
  本文档也不记录某台机器的具体环境；脚本只使用通用 T-SQL，请按**你本地的实际版本**运行；
- **实例名以本地为准**：默认实例写 `localhost`，命名实例形如 `localhost\SQLEXPRESS`
  —— 本文示例统一写 `localhost\SQLEXPRESS`，**请替换为你自己的实例名**；
- 身份验证：Windows 身份验证（`sqlcmd -E`）—— 若你用 SQL 登录，权限测试的结果不可与本文直接比较；
- 命令行工具：`sqlcmd` + ODBC Driver 18 —— **ODBC 18 默认要求加密连接**，故命令一律带 `-C`（信任服务器证书）；
  `-C` 只用于本机练习实例，**正式环境不要使用**；
- 样例业务截面：**2026-09-20 收盘** —— 全部样例（"有效预订""可售量""积分余额""现金余额"等）都按**这个历史时点**解释：
  - 数据里**没有"到期自动过期"的作业**，所以**预订单不会因为运行当天已过有效期就被改成过期** —— 它的状态就是样例里写的那个；
  - `query.sql` 里的有效预订/可售量判断用**固定的时点**（`@AsOf = 2026-09-20T12:00`）过滤，不取当前时间；
  - 因此**查询与视图的预期结果与"今天几号"无关**（判据见 §5）。

Week 3 建库脚本创建 19 张表、47 个外键并装载 77 行样例数据。Week 4 在此基础上增加多表查询、统计视图、完整性验证和最小权限角色测试。

## 1. 文件说明

| 文件 | 作用 |
|---|---|
| `schema.sql` | 创建数据库、19 张表、主键、唯一约束、外键、默认值和基础 CHECK 约束 |
| `sample-data.sql` | 按外键依赖装载 77 行可复现样例数据 |
| `checks/verify.sql` | 检查结构、样例行数、库存、积分、资金和基础约束反例 |
| `tests/crud.sql` | 演示商品、库存和销售单的 CRUD；演示事务结束时回滚 |
| `query.sql` | 多表连接、`LEFT JOIN`、聚合、`GROUP BY`、`HAVING` 和子查询 |
| `view.sql` | 创建并查询销售明细、商品销售汇总、库存状态三个视图 |
| `constraint.sql` | 验证合法数据和非法数据；补充会员卡档位的跨行约束测试 |
| `role.sql` | 创建店长、收银员、库存管理员角色，授予最小权限并测试越权 |
| `results/` | 执行结果与记录：`week-3/week-3.md` / `week-4/week-4.md` 两份记录 + 各脚本的原始输出（`.txt`） |

## 2. 从空数据库完整执行

复现请**每次换一个新的、一次性的数据库名**（例：`ShiguangBookstoreVerify2`）；
**不要**沿用别人的库名 —— 若目标库已存在且里面有表，`schema.sql` 会按设计**报 `51000` 并停止**
（这是防呆保护，不是错误：它保证不会覆盖已有数据）；换一个库名重跑即可。
也不要对已有业务数据的库重新执行 `schema.sql`。
**重复执行建表脚本（`CREATE TABLE`）之前，必须二选一**：**换一个新的库名**，或**先 `DROP DATABASE` 删掉上一次的练习库**
（删库前确认它只是练习库，并关闭正在连接它的查询窗口）；其余脚本（`sample-data.sql` 起）都可以在同一个库上重复执行。

其中 **`sample-data.sql` 是幂等的**：

- 库里数据与样例基线**完全一致** → **跳过不插**（输出 `sample-data.sql PASS: baseline loaded or unchanged (77 rows).`）；
- **不一致** → **报 `51001` 并回滚本次装载**，**不覆盖**库里已有的数据（防呆：样例数据不许把真实/已有数据冲掉）；
- 标识列靠 `IDENTITY_INSERT` 保留样例里的 id，所以装出来的行的 id 与数据字典一致。

> 下面这段是 **PowerShell 写法**（行尾反引号续行、`$LASTEXITCODE` 取退出码）。
> **cmd.exe 需要微调**：去掉行尾反引号、每条命令写成一行，退出码用 `echo %ERRORLEVEL%`。

在仓库根目录打开 PowerShell，依次执行：

```powershell
sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/schema.sql `
  -o db/results/week-4/week-4-replay-schema.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/sample-data.sql `
  -o db/results/week-4/week-4-replay-sample-data.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/checks/verify.sql `
  -o db/results/week-4/week-4-replay-verify-before.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/tests/crud.sql `
  -o db/results/week-4/week-4-replay-crud.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/checks/verify.sql `
  -o db/results/week-4/week-4-replay-verify-after.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/query.sql `
  -o db/results/week-4/week-4-replay-query.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/view.sql `
  -o db/results/week-4/week-4-replay-view.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/constraint.sql `
  -o db/results/week-4/week-4-replay-constraint.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/role.sql `
  -o db/results/week-4/week-4-replay-role.txt
```

每条命令执行后检查退出码：

```powershell
$LASTEXITCODE
```

退出码为 `0` 才能继续下一步。`-b` 使 SQL 错误返回非零退出码，`-f 65001` 用于 UTF-8 输入输出，`-W -s "|"` 便于保存和复核表格结果。

## 3. 当前测试库的 Week 4 执行

当前已使用 `ShiguangBookstoreWeek4` 完成 Week 3 建库和样例装载。Week 4 四个脚本的正式输出为：

```text
results/week-4/week-4-query.txt
results/week-4/week-4-view.txt
results/week-4/week-4-constraint.txt
results/week-4/week-4-role.txt
```

如果该数据库已经完成 Week 3 初始化，只执行下面四个 Week 4 脚本：

```powershell
sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/query.sql `
  -o db/results/week-4/week-4-query.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/view.sql `
  -o db/results/week-4/week-4-view.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/constraint.sql `
  -o db/results/week-4/week-4-constraint.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/role.sql `
  -o db/results/week-4/week-4-role.txt
```

## 4. Week 4 验收内容

`query.sql` 覆盖销售单、销售明细、商品、会员、预订单、采购和退货，并包含说明过用途的 `LEFT JOIN`。统计查询覆盖销量、销售额、库存和会员消费，使用了聚合函数、`GROUP BY`、`HAVING` 和子查询。

`view.sql` 创建并查询以下三个视图：

- `v_sale_detail`：销售单与销售明细；
- `v_goods_sales_summary`：商品销售数量和销售金额，保留没有销售记录的商品；
- `v_inventory_status`：在架数量、已订数量、可售数量和可售标志。

`constraint.sql` 不重复创建 Week 3 已有的主键、外键、唯一、默认值和单行 CHECK 约束。它验证库存数量、销售明细数量、外键、销售单号和资金余额等非法数据被拒绝并回滚，并通过触发器验证银卡、金卡之间的费用和折扣关系。

`role.sql` 创建三个店内数据库角色：

- `bookstore_manager`：店长；
- `bookstore_cashier`：收银员；
- `bookstore_inventory`：库存管理员。

脚本授予表级或列级最小权限，并在对应用户身份下测试正常操作和越权失败。脚本不授予 `db_owner`、`CONTROL` 或 `ALTER`。顾客属于业务层主体，不创建员工式数据库角色；顾客查询自己的预订和单据时使用手机号与预订码等业务凭证，由应用层或业务 SQL 验证归属。

## 5. Week 3 基线（判据）

本节写的是**跑完应当看到什么**（判据），**不是某次实测结果** ——
某次实际执行的环境、命令、退出码与输出见 `db/results/week-4/week-4.md` 与 `db/results/*.txt`
（同一批数字只在一处记"实测"，避免两处说法打架）。

空库复现和 Week 4 测试完成后，应核对：

- 用户表数量：19；
- 外键数量：47；
- 样例数据总行数：77；
- 商品库存依次为：6、0、10、19；
- 商品 1 的有效已订数量：6；
- 会员 `13900000001` 的积分余额：-26；
- 现金余额：1430.30；
- 经营盈亏：-69.70。

演示和非法测试都应使用事务回滚。自增列出现间隙是允许的，验收比较行内容、关联关系和对账结果，不要求下一次运行生成相同的自增 ID。

## 6. 输出与人工验收

`db/results/` 保存正式的结果文件与执行记录（`week-3.md` / `week-4.md` + 各脚本的原始输出）。
正式结果必须能由仓库中的 SQL 脚本重新生成，截图不能替代脚本和文本输出。

**跑完之后的收尾约定**：

- 复现用的库**先保留**（便于用 SSMS 逐项核对结构、角色、视图与数据），核对完可自行 `DROP DATABASE`；
- 复现记录写进 `db/results/week-4/week-4.md`（或同目录下新建一份），**按四样写**：**环境 · 命令 · 退出码与输出 · 遇到的问题**；
- 非作者组员已在本机独立复现：**SQLCMD 复现**（九步、退出码全 0）+ **SSMS 人工核对**
  （对象：表 19 · 外键 47 · 主键 19 · 唯一 9 · `CHECK` 95 · 视图 3 · 触发器 1 · 列注释 135（= 字段数，全覆盖）· 3 角色 + 3 测试用户；
  数据：**合计 77 行**、在架 = 变动累加（6 / 0 / 10 / 19）、积分 −26 = 流水之和、末笔现金 1430.30）；
  记录见 `db/results/week-4/week-4.md`，截图见 `db/results/week-4/week-4-verify2-ssms-*.png`；
- 相关 AI 候选 SQL、人工修改和验证过程记录在 `docs/ai-usage-log.md` 的 Week 4 条目中。

基础约束和本周测试不代表 26 条业务规则全部自动化实现。积分上限、累计退货、完整状态迁移、自动过期、并发库存控制和重复请求幂等仍需要后续事务、存储过程或应用业务逻辑补充。

## 7. SSMS 复查证据（2026-10-05）

下面几张截图是**复查（核对）证据**：在 SQLCMD **复现**出来的库 `ShiguangBookstoreVerify2` 上，
用 SSMS 逐项检查"建出来的东西对不对"。

> **它们不是复现证据** —— 复现证据是 §2 那九步的**可重跑输出**（`db/results/week-4/week-4-verify2-*.txt`）。
> 一句话区分：**复现 = 从空库跑出来（可重跑、有退出码）；复查 = 对已建好的库逐项核对（这里就是截图）。**
> 详细结论与核对方式见 `db/results/week-4/week-4.md`。

| 截图（都在 `db/results/`） | 看的是 | 结论 |
|---|---|---|
| `week-4-verify2-ssms-结构核对.png` | 对象计数 + 角色与测试用户 | 表 19 · 外键 47 · 主键 19 · 唯一 9 · `CHECK` 95 · 视图 3 · 触发器 1 · 列注释 135（= 字段数，全覆盖）· 3 角色 + 3 测试用户 |
| `week-4-verify2-ssms-对账-行数.png` | 19 张表逐表行数 | 合计 **77** 行，每张 ≥ 2 行 |
| `week-4-verify2-ssms-对账-三本账.png` | 总行数 / 在架 vs 变动累加 / 积分 vs 流水 / 资金末笔 | 77 ✓ · 6 / 0 / 10 / 19 ✓ · −26 ✓ · 1430.30（13 笔）✓<br>**该图最后一段（已订量）是修正前的查询结果，见下一张** |
| `week-4-verify2-ssms-对账-已订量-修正.png` | 有效已订量（修正后的查询） | 商品 1 → 6 / 6，其余 → 0 / 0 ✓ |

> **八类验收截图**（2026-10-06 补拍，共 **13 张**）：正常用例 · 非法数据 · 越权访问 · 关键查询 1–4 · CRUD ·
> 统计视图 1–3 · 角色权限 1–2（成功建库沿用上表第一张）—— 文件名、对应语句与预期值见
> `docs/reports/evidence-v0.1.md`（八类对照表 + §3）。

> "应当看到什么"（判据）见 §5；以上是某次实际核对的结果。

## 8. Week 6 迁移、样例扩充与回归

第六周脚本在从 `ShiguangBookstoreWeek3` 备份还原出的工作副本
`ShiguangBookstoreWeek6Work` 上执行。原始库只用于保留 v0.1 基线，不能作为迁移或样例装载目标。
2026-10-21 起，第六周 SQL 统一用 `$(DatabaseName)` 选择目标，调用者须显式指定以 `ShiguangBookstoreWeek6` 开头的专用副本名；脚本不再用内置 `:setvar` 覆盖命令行 `-v`。所有本周脚本须在 SQLCMD 模式执行，`:On Error exit` 保证目标选择失败后停止；筛选索引要求的 SET 选项已在脚本中明确设置。

推荐用 PowerShell 7 执行完整验收（**每次换新库名和新结果目录**）：

```powershell
./db/accept-week-6.ps1 -Server localhost `
  -DatabaseName ShiguangBookstoreWeek6AcceptanceNew `
  -EvidenceDirectory db/results/week-6/acceptance-new
```

入口只支持本机默认实例及 Windows 身份验证。从现有 Week3 库 COPY_ONLY 备份并还原两个新副本，逐项保存 SQLCMD 原始输出、退出码和哈希；不存在删库、覆盖还原、自动清理或全局配置变更。SQL Server 服务账号须能访问默认数据 / 备份目录。备份校验使用 BACKUP CHECKSUM 和 RESTORE VERIFYONLY CHECKSUM；不要求终端账号能读取备份文件做文件哈希。

仅手动执行一项时：

```powershell
sqlcmd -S localhost -E -C -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek6AcceptanceNew -i db/regression.sql
```

SSMS 中需启用“查询 → SQLCMD 模式”，在调用脚本之前单独定义 `:setvar DatabaseName 专用副本名`；不要把固定值写回正式脚本。缺少变量或选到错误目标时应停止。

### 8.1 执行顺序

按下面顺序执行，每一步确认结果符合预期后再继续：

1. 在原始库完成备份，并将备份还原为 `ShiguangBookstoreWeek6Work`；确认数据库状态为 `ONLINE`。
2. 在工作副本执行 `checks/verify.sql` 或迁移前只读基线检查，确认 19 张表、47 个外码、77 行旧样例、现金 `1430.30` 和经营盈亏 `-69.70`。
3. 执行 `migration.sql`，完成 `schema_migration`、供应商留痕字段、唯一索引、来源约束和迁移标记；失败时按脚本事务回滚，必要时使用备份恢复。
4. 执行 `checks/migration-check.sql`，确认目标结构和旧业务快照仍可追溯。
5. 执行 `sample-data-week-6.sql`，装载 W6-S01—W6-S11 的新增对象、单据、明细和流水。该脚本只允许在已完成迁移的工作副本上运行。
6. 执行 `regression.sql`，核对旧场景、新场景、库存 / 预订、积分、销售、退货和资金对账。
7. 依次执行 `tests/regression-negative.sql`、`role.sql` 和 `tests/transaction-week-6.sql`，分别检查结构反例、角色越权和中途失败回滚。反例和事务测试必须在事务中回滚，不得污染扩充后的合法截面。
8. 最后再次执行 `regression.sql`，确认测试没有改变样例数量、四类账目或旧场景快照。
9. 单独执行 `tests/duplicate-cancel-boundary-check.sql` 和 `tests/auto-expiry-boundary-check.sql`，如实记录当前是否具备重复请求幂等和自动过期入口；这两个脚本的 `PASS` 只表示边界检查完成，不表示相应业务功能已经实现。

### 8.2 第六周脚本入口

| 文件 | 用途 |
|---|---|
| `accept-week-6.ps1` | 自动备份 / 还原新副本并运行完整验收、故障注入和原始证据归档 |
| `checks/legacy-snapshot.sql` | 按主键排序，核对 19 张旧业务表完整旧列的行数与 SHA-256 |
| `migration.sql` | 从 v0.1 副本迁移到第六周目标结构 |
| `checks/migration-check.sql` | 迁移后元数据、旧场景和约束只读核对 |
| `sample-data-week-6.sql` | 装载 W6-S01—W6-S11 新增样例 |
| `sample-data-week-6-plan.md` | 新场景编号、业务键、时点和预期值 |
| `regression.sql` | 扩充后只读回归和四类账目对账 |
| `tests/regression-negative.sql` | 22 个已实现结构约束反例；每项应拒绝并回滚 |
| `role.sql` | 店长、收银员和库存管理员的授权 / 越权检查 |
| `tests/transaction-week-6.sql` | 中途约束失败时整笔事务回滚 |
| `tests/price-snapshot-week-6.sql` | W6-S08：临时调价 / 修改卡参数，验证历史成交快照不变并回滚 |
| `tests/supplier-audit-week-6.sql` | I-09：合法改名、成对留痕及员工外码专项测试，逐项回滚 |
| `tests/unique-index-week-6.sql` | I-07 / I-18：补测重复文创引用及重复积分抵扣，核对索引名并回滚 |
| `tests/sales-statistics-week-6.sql` | 只读输出旧 / 新订单明细、逐商品销量、逐日实付退款及范围汇总，核对显式预期 |
| `tests/inventory-query-week-6.sql` | 只读输出逐商品库存、预订占用及来源对账；另列已到期但未释放的占用 |
| `tests/supplier-cost-week-6.sql` | W6-S11：只读比较当前报价与历史采购批次成本，按供应商对账入库和付款 |
| `tests/member-validity-week-6.sql` | W6-S05：只读核对到期日 / 次日边界及第六周成交卡档快照 |
| `tests/duplicate-cancel-boundary-check.sql` | 重复取消请求的当前实现边界 |
| `tests/auto-expiry-boundary-check.sql` | 到期但仍有效预订的当前实现边界 |
| `results/week-6/records/week-6-*.md` | 第六周执行反馈、预期 / 实际、差异和未实现项 |

### 8.3 第六周预期截面

扩充后工作副本应满足以下关键值；旧截面仍按历史时点单独核对：

- 用户表 20 张，外码 49 个，迁移记录 1 条；
- `goods=10`、`member=6`、`purchase_request=10`、`reservation=8`；
- `sale=9`、`goods_return=5`、`stock_movement=31`、`point_movement=13`、`fund_flow=29`；
- 扩充后现金余额 `555.30`，经营盈亏 `-944.70`；
- 旧商品、旧会员、旧单据和旧流水仍可按迁移前快照复核。

这些数字是脚本定义的第六周截面，不要求扩充后全库仍保持 77 行。临时反例、权限和事务测试不计入合法样例基线。

### 8.4 已知实现边界

当前数据库已经验证了结构约束、权限边界和一个中途失败事务的回滚，但以下能力仍需业务入口或后续应用阶段实现：

- 重复取消、重复取货、重复退款等请求的幂等保护；
- 预订到期后的自动状态更新和已订量释放；
- 并发销售 / 预订下的库存锁定；
- 覆盖全部采购、取货、退货和资金流程的统一受控入口。

静态终态样例只能证明数据覆盖，不能替代这些流程功能的实现。第六周允许 AI 自检；当前技术结果和唯一 ER 人工填写入口见 [正式验收](../docs/reviews/review-week-6.md)，当前 ER 见 [v1.4](../ER/review-v1.4.md)。


### 8.5 当前验收结果

当前正式结论只维护在 [`docs/reviews/review-week-6.md`](../docs/reviews/review-week-6.md)。本轮允许AI自检，由Codex主代理在新隔离库完成45步及日期变异检查，最新原始输出见 [`results/week-6/acceptance/final-check/`](results/week-6/acceptance/final-check)。原子代理输出保留历史执行归属；ER图最终人工结果已于2026-10-22由梁宇聪确认通过。

19 表完整旧列哈希验证还原、迁移和测试恢复后数据一致；哈希不覆盖 IDENTITY 内部计数，回滚产生的自增间隙允许存在。供应商新增审计列和技术表另由专项与迁移核对覆盖。会员专项核对11个独立固定输入日期规则示例（含重买起算、闰日）及成交快照；实际办理/收费、权益恢复和积分保持的业务入口未实现，按后续阶段边界登记。

`db/results/` 按验收对象周次组织：第 3、4 周保留对应文本结果和截图；第 6 周 `records/` 保存逐项执行反馈，`acceptance/` 保存唯一最新审核及其原始输出。较早三轮审核目录已清理；本次文件整理没有删除数据库或备份。新运行默认输出到 `results/week-6/<DatabaseName>/`，仍拒绝覆盖已有目录；若要替换当前审核，先确认新结果再整理，不能直接覆盖旧结果。

### 目录职责

根目录保留课程指定交付入口；`checks/` 保存结构 / 数据快照辅助核对，`tests/` 保存 CRUD 演示、反例和专项测试。这些测试属于复现与验收材料，保留。早期三个 I-04 一次性探测脚本已删除，结论及证据限制保留在[规范化说明](../docs/design/design-normalization-v1.0.md) §23；正式 45 步所用脚本均保留。样例规划移入[设计文档](../docs/design/sample-data-week-6-plan.md)。

本轮审核收口：完整45步输出位于 `results/week-6/acceptance/final-check/`。`regression.sql` 为第六周固定装载快照，不用于第7—9周任意写入后的数据库。会员专项验证固定日期规则示例，不代表办理入口已实现。
