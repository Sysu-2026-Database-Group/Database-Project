# 第六周工作副本迁移前基线记录

> **当前状态（2026-10-22）**：本文件是当时的逐项反馈，不是当前审核结论；"非作者复核"门槛已由 `docs/project-conventions.md` 取消，当前结论见 `docs/reviews/review-week-6.md`，Reviewer B 独立复现见 `db/results/week-6/acceptance-b-20261022/`。

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 核对脚本：[`db/checks/verify.sql`](../../../checks/verify.sql)
- 执行方式：SSMS SQLCMD 模式，`DatabaseName = ShiguangBookstoreWeek6Work`
- 用户反馈：结果符合预期

## 核对口径

| 检查项 | 预期值 | 用户反馈 |
|---|---:|---|
| 表数量 | 19 | 符合预期 |
| 外码数量 | 47 | 符合预期 |
| 旧样例总行数 | 77 | 符合预期 |
| 现金余额 | 1430.30 | 符合预期 |
| 经营盈亏 | -69.70 | 符合预期 |
| 反例测试 | 16 个全部 `PASS` | 符合预期 |

本次基线通过后，才允许在该工作副本执行 `db/migration.sql`。原始 `ShiguangBookstoreWeek3` 未执行迁移。
