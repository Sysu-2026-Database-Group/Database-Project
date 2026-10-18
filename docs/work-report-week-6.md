# 第六周已完成工作报告

> **报告日期：** 2026-10-18  
> **项目：** 拾光书店（单门店 + 线上预订到店自提）  
> **执行工作库：** `ShiguangBookstoreWeek6Work`  
> **说明：** 本报告汇总当前已有的脚本、结果记录和用户执行反馈。它是阶段工作报告，不代表非作者独立复核或第六周最终验收已经完成。

## 1. 工作概况

第六周围绕函数依赖与规范化、数据库迁移、旧场景保留、新场景扩充和回归验证开展工作。迁移及新增样例在从 `ShiguangBookstoreWeek3` 备份还原的 `ShiguangBookstoreWeek6Work` 工作副本上执行；原始库没有作为迁移或样例写入目标。

当前已有可检查的设计文档、迁移和样例脚本、回归脚本及逐项结果记录。主要脚本在 SQL Server Management Studio（SSMS）中执行后，用户反馈结果符合预期。后续组员仍需独立复现并完成文档和 ER 图复核。

## 2. 已完成工作

### 2.1 迁移前基线与备份

- 核对迁移前结构为 19 张用户表、47 条外键、77 行旧业务数据。
- 记录旧业务基线：现金余额 `1430.30`，经营盈亏 `-69.70`；`verify.sql` 中 16 个原有反例全部通过。
- 备份并将工作副本还原为 `ShiguangBookstoreWeek6Work`，之后以该副本作为迁移和扩充的目标。
- 保存记录：[`week-6-backup.md`](../db/results/week-6-backup.md)、[`week-6-baseline.md`](../db/results/week-6-baseline.md)、[`week-6-work-baseline.md`](../db/results/week-6-work-baseline.md)、[`week-6-restore.md`](../db/results/week-6-restore.md)。

### 2.2 规范化与迁移设计

- 编写 19 张表的规范化分析初稿，涵盖关系模式、候选码、函数依赖、更新异常、范式判断以及保留或分解理由，见 [`design-normalization-v1.0.md`](design-normalization-v1.0.md)。
- 编写迁移脚本，新增迁移元数据表及供应商留痕字段，补充约束与唯一索引，并检查重复数据；旧业务表保留，不删除或覆盖。
- 在工作副本执行迁移，并核对迁移后 20 张用户表、49 条外键、1 条迁移记录及 77 行旧业务数据。旧现金和经营盈亏截面仍为 `1430.30 / -69.70`。
- 保存迁移和迁移后核对记录：[`migration.md`](../db/results/week-6-migration.md)、[`migration-check.md`](../db/results/week-6-migration-check.md)。

### 2.3 新场景扩充

- 编写 [`sample-data-week-6.sql`](../db/sample-data-week-6.sql) 及场景规划；扩充 W6-S01 至 W6-S11，保留原场景和原有记录。
- 扩充后的主要数量为：商品 10、会员 6、采购申请 10、预订单 8、销售单 9、退货单 5、库存流水 31、积分流水 13、资金流水 29。
- 扩充后现金余额为 `555.30`，经营盈亏为 `-944.70`。这是扩充后新的业务截面，与扩充前 `1430.30 / -69.70` 的旧截面不同，不能直接当作旧数据丢失。
- 样例装载记录：[`sample-data.md`](../db/results/week-6-sample-data.md)。

### 2.4 回归与专项验证

- 只读回归检查迁移后结构、旧场景、新场景和跨表账目；用户反馈符合预期，结果记录为 `regression.sql READONLY PASS`。
- 22 个结构约束反例均按预期被拒绝并回滚，涵盖键、外键、非空、CHECK、来源和资金余额等约束。
- 角色权限测试覆盖授权读取/写入和越权拒绝；中途失败事务测试触发预期 CHECK 错误并回滚临时单据及明细。
- 完成价格快照、供应商留痕、唯一索引、销售统计、库存查询、供应商成本和会员有效期等专项检查；各项结果记录在 `db/results/week-6-*.md`。
- 主要结果：[`post-tests-check.md`](../db/results/week-6-post-tests-check.md)、[`regression-negative.md`](../db/results/week-6-regression-negative.md)、[`role.md`](../db/results/week-6-role.md)、[`transaction.md`](../db/results/week-6-transaction.md)。

## 3. 已确认的限制与未实现边界

以下是已记录的边界结果，不应描述为功能通过：

- **重复取消幂等：** 对已取消预订再次执行直接 DML 会被接受；测试事务已回滚，当前没有数据库级幂等保护。见 [`duplicate-request-boundary.md`](../db/results/week-6-duplicate-request-boundary.md)。
- **自动过期：** 固定测试时刻发现 2 条已过期但状态仍为有效的预订，结果为 `AUTO_EXPIRY_NOT_APPLIED`。当前没有自动过期处理入口。见 [`auto-expiry-boundary.md`](../db/results/week-6-auto-expiry-boundary.md)。
- **状态机、并发与完整业务入口：** 已有约束反例、权限边界和单个中途失败事务的验证，尚未证明完整业务状态机、并发库存控制或所有业务操作均通过受控事务入口执行。
- **会员续费与权益恢复：** 已有会员有效期及成交卡档查询记录；自动续费和过期后重买流程不属于本轮已验证功能。

## 4. 仍需接手完成

1. 由非作者组员在一次性复核副本独立复现迁移、样例装载、只读回归、反例、权限、事务和专项检查，并记录环境、命令、完整输出及差异。不得把已有执行反馈直接改写成独立复核结论。
2. 统一复核 [`design-normalization-v1.0.md`](design-normalization-v1.0.md) 的 19 张表分析。目前是 **19/19 初稿待统一核对**，不是 19 张表均已审核通过；需记录审核人、日期、逐表结论和修订位置。
3. 对照当前 ER 图源、PNG、映射和审查记录进行全图最终人工复核，确认版本对应、联系引用、基数、标签和图面可读性。
4. 对照 [`plan-week6-6.md`](../drafts/plan-week6-6.md) 与 [`task-week-6.md`](task-week-6.md) 完成验收状态、问题处理结果和正式交付文档的统一收口。

交接细目见 [`remaining-issues-week-6.md`](remaining-issues-week-6.md)，逐项执行记录见 [`review-week-6.md`](review-week-6.md)。

## 5. 结论

第六周的迁移、样例扩充和主要数据库检查已有脚本及执行结果记录，原始旧场景保留并与新增场景分开核对。项目目前处于**阶段工作已完成、待非作者复核和交付收口**的状态。完成上述接手事项之前，不应将第六周标记为最终验收全部通过。
