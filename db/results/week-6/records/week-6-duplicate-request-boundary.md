# 第六周重复请求边界记录

> **当前状态（2026-10-22）**：本文件是当时的逐项反馈，不是当前审核结论；"非作者复核"门槛已由 `docs/project-conventions.md` 取消，当前结论见 `docs/reviews/review-week-6.md`，Reviewer B 独立复现见 `db/results/week-6/acceptance-b-20261022/`。

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 检查脚本：[`db/tests/duplicate-cancel-boundary-check.sql`](../../../tests/duplicate-cancel-boundary-check.sql)
- 执行对象：已取消预订 `W6R-2108`
- 用户反馈：符合预期

## 核对结果

脚本在独立事务中模拟对已取消预订再次提交取消请求。直接 `UPDATE` 被数据库接受，结果标记为 `DIRECT_DML_ACCEPTED_NO_IDEMPOTENCY_GUARD`；随后事务回滚，预订状态、取消人和取消时间均恢复原值。

| 项目 | 结果 |
|---|---|
| 重复取消直接 DML | 被接受（当前没有状态终态 / 幂等保护） |
| 测试事务 | 已回滚 |
| 预订原值 | 回滚后保持不变 |
| 脚本结论 | `duplicate-cancel-boundary-check.sql PASS` |

该结果只说明当前表和直接 DML 的能力边界，不代表业务入口允许重复取消。若要满足 R-12 / R-22，应在受控存储过程或应用事务入口中检查终态，并让重复请求返回原结果而不重复释放库存、积分或资金。原始数据库 `ShiguangBookstoreWeek3` 未被写入。
