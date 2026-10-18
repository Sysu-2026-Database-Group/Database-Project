# 第六周非作者独立复核记录

> **用途**：由未编写本周主要脚本的组员独立复核第六周交付物。本文是执行清单，不预填“通过”；复核人必须填写实际日期、环境、命令、结果和差异。

## 1. 复核人和环境

| 项目 | 实际填写 |
|---|---|
| 复核人 | 待填写 |
| 复核日期 | 待填写 |
| Windows 用户 | 待填写 |
| SQL Server 实例 | 待填写 |
| SQL Server 版本 | 待填写 |
| SSMS 版本 | 待填写 |
| 身份验证方式 | 待填写 |
| 使用的备份文件 | 待填写完整路径、文件大小和时间 |
| 独立复核数据库名 | 待填写 |

原始数据库 `ShiguangBookstoreWeek3` 和当前工作副本 `ShiguangBookstoreWeek6Work` 不作为独立复核的写入目标。复核应使用从 `.bak` 还原出的临时副本；复核前先确认数据库名称和文件路径，避免覆盖现有数据库。

> **脚本目标名说明**：本轮迁移、样例和回归脚本的 `USE` 目标固定为 `ShiguangBookstoreWeek6Work`。独立复核不能直接把临时副本命名成另一个名称后照跑这些脚本；应在不接触现有工作副本的前提下，先准备名称为 `ShiguangBookstoreWeek6Work` 的一次性复核副本，或制作仅替换目标库名的临时脚本副本并在记录中注明替换范围。不得修改仓库中的正式脚本来掩盖目标库差异，也不得覆盖已有工作副本。

## 2. 当前交付物清单

| 交付物 | 路径 | 复核状态 |
|---|---|---|
| 规范化设计 | [`docs/design-normalization-v1.0.md`](design-normalization-v1.0.md) | 待复核 |
| 迁移脚本 | [`db/migration.sql`](../db/migration.sql) | 待复核 |
| 迁移后核对 | [`db/migration-check.sql`](../db/migration-check.sql) | 待复核 |
| 新增样例脚本 | [`db/sample-data-week-6.sql`](../db/sample-data-week-6.sql) | 待复核 |
| 新增样例清单 | [`db/sample-data-week-6-plan.md`](../db/sample-data-week-6-plan.md) | 待复核 |
| 只读回归 | [`db/regression.sql`](../db/regression.sql) | 待复核 |
| 结构反例 | [`db/regression-negative.sql`](../db/regression-negative.sql) | 待复核 |
| 权限回归 | [`db/role.sql`](../db/role.sql) | 待复核 |
| 事务失败回归 | [`db/transaction-week-6.sql`](../db/transaction-week-6.sql) | 待复核 |
| 调价与成交快照动作 | [`db/price-snapshot-week-6.sql`](../db/price-snapshot-week-6.sql) | 用户反馈通过；非作者待复核 |
| 供应商修改留痕专项 | [`db/supplier-audit-week-6.sql`](../db/supplier-audit-week-6.sql) | 用户反馈四项符合预期；非作者待复核 |
| 唯一索引专项补测 | [`db/unique-index-week-6.sql`](../db/unique-index-week-6.sql) | 用户反馈两项符合预期；非作者待复核 |
| 订单明细与销售统计 | [`db/sales-statistics-week-6.sql`](../db/sales-statistics-week-6.sql) | 用户反馈符合预期；非作者待复核 |
| 库存查询与来源核对 | [`db/inventory-query-week-6.sql`](../db/inventory-query-week-6.sql) | 用户反馈符合预期；非作者待复核 |
| 供应商报价与批次成本 | [`db/supplier-cost-week-6.sql`](../db/supplier-cost-week-6.sql) | 用户反馈符合预期；非作者待复核 |
| 会员有效期与成交卡档 | [`db/member-validity-week-6.sql`](../db/member-validity-week-6.sql) | 修订版用户反馈符合预期；非作者待复核 |
| 重复取消边界 | [`db/duplicate-cancel-boundary-check.sql`](../db/duplicate-cancel-boundary-check.sql) | 待复核 |
| 自动过期边界 | [`db/auto-expiry-boundary-check.sql`](../db/auto-expiry-boundary-check.sql) | 待复核 |
| ER 审查与映射 | `ER/review-v1.0.md`、`docs/er-mapping-v1.0.md` | 待复核 |

## 3. 独立复核顺序

### 3.1 迁移前基线

- [ ] 从指定 `.bak` 还原临时数据库。
- [ ] 在迁移前运行旧版 `db/verify.sql`，确认 19 张表、47 条外码、77 行旧业务数据、现金 `1430.30`、经营盈亏 `-69.70`。
- [ ] 保存完整 SSMS 输出或 SQLCMD 文本，不只保存最后一行 PASS。

实际结果：待填写。证据路径：待填写。

### 3.2 迁移和迁移后旧场景核对

- [ ] 在迁移副本执行 `db/migration.sql`。
- [ ] 执行 `db/migration-check.sql`。
- [ ] 核对 20 张用户表、49 条外码、1 条 `schema_migration` 记录。
- [ ] 核对旧业务仍为 77 行，现金 `1430.30`，经营盈亏 `-69.70`。
- [ ] 检查迁移失败时是否回滚；不要在原始库上试跑失败恢复。

实际结果：待填写。证据路径：待填写。

### 3.3 新样例装载

- [ ] 在已通过迁移核对的副本执行 `db/sample-data-week-6.sql`。
- [ ] 核对目标数据库、迁移标记、旧基线快照和业务键冲突检查。
- [ ] 保存样例脚本的完整输出。
- [ ] 核对扩充后主要截面：`goods = 10`、`member = 6`、`sale = 9`、`goods_return = 5`、`fund_flow = 29`、现金 `555.30`、经营盈亏 `-944.70`。

实际结果：待填写。证据路径：待填写。

### 3.4 只读回归和结构反例

- [ ] 执行 `db/regression.sql`，确认旧场景、新场景和四类对账均通过。
- [ ] 执行 `db/regression-negative.sql`，确认 22 个反例全部为 `PASS`，且末尾出现完整 PASS 消息。
- [ ] 核对反例执行后行数、现金和经营盈亏没有变化。

实际结果：待填写。证据路径：待填写。

### 3.5 权限和事务

- [ ] 在 SQLCMD 模式下设置 `DatabaseName`，执行 `db/role.sql`。
- [ ] 核对收银员、店长、库存管理员的合法操作和越权失败。
- [ ] 执行 `db/transaction-week-6.sql`，确认数量为 0 的明细触发 `547`，销售单和明细整笔回滚。
- [ ] 执行 `db/price-snapshot-week-6.sql`，核对售价 / 卡参数实际变化、历史成交不变及四张表恢复；结果参考 `db/results/week-6-price-snapshot.md`。
- [ ] 执行 `db/supplier-audit-week-6.sql`，核对合法改名及三个拒绝用例、约束名与逐项恢复；结果参考 `db/results/week-6-supplier-audit.md`。
- [ ] 执行 `db/unique-index-week-6.sql`，核对重复文创引用、重复积分抵扣均由目标唯一索引拒绝，商品和积分流水逐项恢复；结果参考 `db/results/week-6-unique-index.md`。
- [ ] 再执行 `db/regression.sql`，确认权限 / 事务测试没有污染合法截面。

实际结果：待填写。证据路径：待填写。

### 3.6 未实现边界

- [ ] 执行 `db/duplicate-cancel-boundary-check.sql`，记录重复取消直接 DML 是否被接受；不要把“脚本 PASS”写成业务幂等已实现。
- [ ] 执行 `db/auto-expiry-boundary-check.sql`，记录固定时刻下到期但仍为“有效”的预订单数量；不要把静态“已过期”样例写成自动过期已通过。
- [ ] 在复核结论中明确：状态机、重复请求幂等、自动过期、并发库存控制和完整业务入口仍属于实现边界或后续工作。

实际结果：待填写。证据路径：待填写。

## 4. 复核结论

| 验收项 | 结论 | 证据 |
|---|---|---|
| 迁移六要件 | 待填写 | 待填写 |
| 旧场景保留 | 待填写 | 待填写 |
| W6-S01—W6-S11 覆盖 | 待填写 | 待填写 |
| 四类数据对账 | 待填写 | 待填写 |
| 结构反例 | 待填写 | 待填写 |
| 权限正反例 | 待填写 | 待填写 |
| 事务失败回滚 | 待填写 | 待填写 |
| 重复请求边界 | 待填写 | 待填写 |
| 自动过期边界 | 待填写 | 待填写 |
| ER 图和映射人工复核 | 待填写 | 待填写 |

### 差异和遗留问题

待填写。每项差异都要说明：实际现象、影响范围、是否改变数据库、恢复方式和后续负责人。

### 复核人签名

待填写：姓名、日期。
