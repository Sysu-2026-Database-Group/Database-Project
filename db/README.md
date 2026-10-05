# 数据库脚本执行与复现说明

本目录保存拾光书店数据库项目的 Week 3 和 Week 4 SQL 脚本。

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
| `verify.sql` | 检查结构、样例行数、库存、积分、资金和基础约束反例 |
| `crud.sql` | 演示商品、库存和销售单的 CRUD；演示事务结束时回滚 |
| `query.sql` | 多表连接、`LEFT JOIN`、聚合、`GROUP BY`、`HAVING` 和子查询 |
| `view.sql` | 创建并查询销售明细、商品销售汇总、库存状态三个视图 |
| `constraint.sql` | 验证合法数据和非法数据；补充会员卡档位的跨行约束测试 |
| `role.sql` | 创建店长、收银员、库存管理员角色，授予最小权限并测试越权 |
| `results/` | 执行结果与记录：`week-3.md` / `week-4.md` 两份记录 + 各脚本的原始输出（`.txt`） |

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
  -o db/results/week-4-replay-schema.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/sample-data.sql `
  -o db/results/week-4-replay-sample-data.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/verify.sql `
  -o db/results/week-4-replay-verify-before.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/crud.sql `
  -o db/results/week-4-replay-crud.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/verify.sql `
  -o db/results/week-4-replay-verify-after.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/query.sql `
  -o db/results/week-4-replay-query.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/view.sql `
  -o db/results/week-4-replay-view.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/constraint.sql `
  -o db/results/week-4-replay-constraint.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/role.sql `
  -o db/results/week-4-replay-role.txt
```

每条命令执行后检查退出码：

```powershell
$LASTEXITCODE
```

退出码为 `0` 才能继续下一步。`-b` 使 SQL 错误返回非零退出码，`-f 65001` 用于 UTF-8 输入输出，`-W -s "|"` 便于保存和复核表格结果。

## 3. 当前测试库的 Week 4 执行

当前已使用 `ShiguangBookstoreWeek4` 完成 Week 3 建库和样例装载。Week 4 四个脚本的正式输出为：

```text
results/week-4-query.txt
results/week-4-view.txt
results/week-4-constraint.txt
results/week-4-role.txt
```

如果该数据库已经完成 Week 3 初始化，只执行下面四个 Week 4 脚本：

```powershell
sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/query.sql `
  -o db/results/week-4-query.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/view.sql `
  -o db/results/week-4-view.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/constraint.sql `
  -o db/results/week-4-constraint.txt

sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/role.sql `
  -o db/results/week-4-role.txt
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
某次实际执行的环境、命令、退出码与输出见 `db/results/week-4.md` 与 `db/results/*.txt`
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
- 复现记录写进 `db/results/week-4.md`（或同目录下新建一份），**按四样写**：**环境 · 命令 · 退出码与输出 · 遇到的问题**；
- 非作者组员已在本机独立复现：**SQLCMD 复现**（九步、退出码全 0）+ **SSMS 人工核对**
  （对象：表 19 · 外键 47 · 主键 19 · 唯一 9 · `CHECK` 95 · 视图 3 · 触发器 1 · 列注释 135（= 字段数，全覆盖）· 3 角色 + 3 测试用户；
  数据：**合计 77 行**、在架 = 变动累加（6 / 0 / 10 / 19）、积分 −26 = 流水之和、末笔现金 1430.30）；
  记录见 `db/results/week-4.md`，截图见 `db/results/week-4-verify2-ssms-*.png`；
  **现场讲解**（查询的业务含义、`LEFT JOIN` 的选择、非法数据拒绝、越权失败）仍待完成 —— 见 `docs/task-week-4.md` 第 12、13 条；
- 相关 AI 候选 SQL、人工修改和验证过程记录在 `docs/ai-usage-log.md` 的 Week 4 条目中。

基础约束和本周测试不代表 26 条业务规则全部自动化实现。积分上限、累计退货、完整状态迁移、自动过期、并发库存控制和重复请求幂等仍需要后续事务、存储过程或应用业务逻辑补充。

## 7. SSMS 复查证据（2026-10-05）

下面几张截图是**复查（核对）证据**：在 SQLCMD **复现**出来的库 `ShiguangBookstoreVerify2` 上，
用 SSMS 逐项检查"建出来的东西对不对"。

> **它们不是复现证据** —— 复现证据是 §2 那九步的**可重跑输出**（`db/results/week-4-verify2-*.txt`）。
> 一句话区分：**复现 = 从空库跑出来（可重跑、有退出码）；复查 = 对已建好的库逐项核对（这里就是截图）。**
> 详细结论与核对方式见 `db/results/week-4.md`。

| 截图（都在 `db/results/`） | 看的是 | 结论 |
|---|---|---|
| `week-4-verify2-ssms-结构核对.png` | 对象计数 + 角色与测试用户 | 表 19 · 外键 47 · 主键 19 · 唯一 9 · `CHECK` 95 · 视图 3 · 触发器 1 · 列注释 135（= 字段数，全覆盖）· 3 角色 + 3 测试用户 |
| `week-4-verify2-ssms-对账-行数.png` | 19 张表逐表行数 | 合计 **77** 行，每张 ≥ 2 行 |
| `week-4-verify2-ssms-对账-三本账.png` | 总行数 / 在架 vs 变动累加 / 积分 vs 流水 / 资金末笔 | 77 ✓ · 6 / 0 / 10 / 19 ✓ · −26 ✓ · 1430.30（13 笔）✓<br>**该图最后一段（已订量）是修正前的查询结果，见下一张** |
| `week-4-verify2-ssms-对账-已订量-修正.png` | 有效已订量（修正后的查询） | 商品 1 → 6 / 6，其余 → 0 / 0 ✓ |

> "应当看到什么"（判据）见 §5；以上是某次实际核对的结果。
