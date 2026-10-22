# 第六周反例回归记录

> **当前状态（2026-10-22）**：本文件是当时的逐项反馈，不是当前审核结论；"非作者复核"门槛已由 `docs/project-conventions.md` 取消，当前结论见 `docs/reviews/review-week-6.md`，Reviewer B 独立复现见 `db/results/week-6/acceptance-b-20261022/`。

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 回归脚本：[`db/tests/regression-negative.sql`](../../../tests/regression-negative.sql)
- 执行方式：在 SSMS 新查询窗口执行完整脚本；22 个案例分别在独立事务中尝试，成功或失败后均回滚
- 用户反馈：符合预期结果

## 核对结果

| 项目 | 结果 |
|---|---:|
| 反例总数 | 22 |
| `result = PASS` | 22 / 22 |
| 覆盖范围 | 主键、业务唯一键、筛选唯一索引、外码、非空、CHECK、来源约束和资金余额边界 |
| 回滚后商品行数 | 与测试前相同 |
| 回滚后销售行数 | 与测试前相同 |
| 回滚后积分流水行数 | 与测试前相同 |
| 回滚后资金流水行数 | 与测试前相同 |
| 回滚后现金与经营盈亏 | 与测试前相同 |
| 脚本结论 | `regression-negative.sql PASS: 22 implemented constraint cases rejected and rolled back.` |

其中“同一退货不能重复回滚积分”使用已有回滚记录 `S20260927-W609` + `RT20260928-W604`，验证 `UX_point_movement_return` 的重复拒绝。此前使用散客退货 `RT20260928-W603` 时，目标退货没有已有积分回滚，插入行为本身合法；该测试数据已在脚本中修正后重新执行。

本次反例回归只验证迁移后已由 DDL 明确实现的拒绝边界，不等于状态单向推进、重复请求幂等、自动过期、并发控制或完整岗位流程已经实现。原始数据库 `ShiguangBookstoreWeek3` 未被写入。

原始 SSMS 结果网格未复制到仓库，因此本文件记录的是用户执行后的反馈，不替代后续非作者复核。角色权限测试已另行记录；下一步可在独立事务或可恢复副本中测试事务失败回滚和重复请求边界。
