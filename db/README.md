# 数据库脚本执行与复现说明

本目录保存拾光书店数据库项目的 Week 3 和 Week 4 SQL 脚本。

当前验证环境：

- SQL Server 2022 Enterprise Evaluation，版本 `16.0.1000.6`
- SQL Server 实例：`localhost`
- 身份验证：Windows 身份验证
- 命令行工具：`sqlcmd`
- 样例业务截面：2026-09-20 收盘

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

## 2. 从空数据库完整执行

完整复现必须使用一个新的数据库名，例如 `ShiguangBookstoreWeek4Replay`。不要在已有业务数据上重新执行 `schema.sql`。

在仓库根目录打开 PowerShell，依次执行：

```powershell
sqlcmd -S localhost -E -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/schema.sql `
  -o db/results/week-4-replay-schema.txt

sqlcmd -S localhost -E -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/sample-data.sql `
  -o db/results/week-4-replay-sample-data.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/verify.sql `
  -o db/results/week-4-replay-verify-before.txt

sqlcmd -S localhost -E -b -f 65001 `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/crud.sql `
  -o db/results/week-4-replay-crud.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/verify.sql `
  -o db/results/week-4-replay-verify-after.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/query.sql `
  -o db/results/week-4-replay-query.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/view.sql `
  -o db/results/week-4-replay-view.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4Replay `
  -i db/constraint.sql `
  -o db/results/week-4-replay-constraint.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
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
sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/query.sql `
  -o db/results/week-4-query.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/view.sql `
  -o db/results/week-4-view.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
  -v DatabaseName=ShiguangBookstoreWeek4 `
  -i db/constraint.sql `
  -o db/results/week-4-constraint.txt

sqlcmd -S localhost -E -b -f 65001 -W -s "|" `
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

## 5. Week 3 基线

空库复现和 Week 4 测试完成后，应继续核对以下基线：

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

`db/week4-testing/` 保存过程中的原始测试输出和结构检查材料；`db/results/` 保存提交用的正式结果文件。正式结果必须能由仓库中的 SQL 脚本重新生成，截图不能替代脚本和文本输出。

Week 4 的最终验收还需要由非脚本作者的组员从新的空数据库执行完整流程，记录实际环境、命令、退出码、结果和问题，并现场解释查询的业务含义、`LEFT JOIN` 的选择、非法数据拒绝和越权失败。相关 AI 候选 SQL、人工修改和验证过程记录在 `docs/ai-usage-log.md` 的 Week 4 条目中。

基础约束和本周测试不代表 26 条业务规则全部自动化实现。积分上限、累计退货、完整状态迁移、自动过期、并发库存控制和重复请求幂等仍需要后续事务、存储过程或应用业务逻辑补充。
