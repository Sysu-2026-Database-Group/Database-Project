# 第六周事务完整性回归记录

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 事务脚本：[`db/transaction-week-6.sql`](../../db/transaction-week-6.sql)
- 执行方式：在 SSMS 新查询窗口执行；脚本显式开启 `XACT_ABORT`，在独立事务中制造销售明细 CHECK 失败
- 用户反馈：符合预期结果

## 核对结果

脚本先插入临时销售单 `W6-TXN-ROLLBACK-01`，再插入一条合法明细，随后尝试插入数量为 0 的非法明细。数据库返回预期的 `547`，CATCH 块回滚整个事务。

| 检查项 | 结果 |
|---|---|
| 预期错误 | `547`，`CK_sale_item_quantity` 拒绝数量为 0 |
| 临时销售单 | 回滚后不存在 |
| 临时销售明细 | 回滚后不存在 |
| `sale` 行数 | 测试前后相同 |
| `sale_item` 行数 | 测试前后相同 |
| 脚本结论 | `transaction-week-6.sql PASS: mid-transaction failure rolled back sale and sale_item.` |

本次测试证明该事务脚本中的中途 CHECK 失败不会留下销售单或部分明细；它不代表所有采购、取货、退货和资金流程都已经由统一事务入口实现。原始数据库 `ShiguangBookstoreWeek3` 未被写入。
