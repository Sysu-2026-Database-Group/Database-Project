# 第六周迁移执行记录

> **当前状态（2026-10-22）**：本文件是当时的逐项反馈，不是当前审核结论；"非作者复核"门槛已由 `docs/project-conventions.md` 取消，当前结论见 `docs/reviews/review-week-6.md`，Reviewer B 独立复现见 `db/results/week-6/acceptance-b-20261022/`。

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 迁移脚本：[`db/migration.sql`](../../../migration.sql)
- 执行方式：SSMS SQLCMD 模式；首次编译问题修订后重新执行
- 用户反馈：迁移结果符合预期

## 预期且已由用户确认的结果

| 项目 | 结果 |
|---|---:|
| 迁移后用户表 | 20 |
| 迁移后外码 | 49 |
| `schema_migration` 记录 | 1 |
| 旧供应商 NULL 留痕行 | 3 |

迁移脚本包含事务和失败回滚；旧 19 张业务表与旧业务记录原地保留。原始 `ShiguangBookstoreWeek3` 未执行迁移。

迁移后的独立只读核对已由用户在工作副本执行并反馈符合预期，记录见 [`db/results/week-6/records/week-6-migration-check.md`](week-6-migration-check.md)。原始 SSMS 结果网格尚未复制到仓库；该反馈不替代后续非作者复核。


## 2026-10-21 技术收口实测（AI自检）

早期SSMS反馈保留原来源；本轮输出另在[final-check/08-migration.txt](../acceptance/final-check/08-migration.txt)。

| 项目 | 预期 | 本轮实际 |
|---|---|---|
| 用户表/外码/迁移记录/旧供应商空审计 | 20 / 49 / 1 / 3 | 20 / 49 / 1 / 3 |
| 商品图书/文创引用重复组 | 0 / 0 | 0 / 0 |
| 预订对应销售重复组 | 0 | 0 |
| 积分获得/抵扣/退货回滚重复组 | 0 / 0 / 0 | 0 / 0 / 0 |

当前允许AI自检，不另留非作者人工复跑任务；唯一ER人工验收入口见正式验收记录。
