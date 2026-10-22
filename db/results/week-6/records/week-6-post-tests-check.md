# 第六周测试后最终只读核对记录

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 核对脚本：[`db/regression.sql`](../../../regression.sql)
- 执行目的：确认反例、角色权限和事务失败测试没有污染扩充后的合法样例
- 用户反馈：符合预期结果

## 核对结果

最终只读回归再次通过：旧商品 / 会员 / 资金截面、W6-S01—W6-S11 终态、库存 / 预订 / 积分 / 销售 / 退货 / 采购对账均保持一致。

| 项目 | 结果 |
|---|---:|
| `goods` | 10 |
| `member` | 6 |
| `purchase_request` | 10 |
| `reservation` | 8 |
| `sale` | 9 |
| `goods_return` | 5 |
| `stock_movement` | 31 |
| `point_movement` | 13 |
| `fund_flow` | 29 |
| 扩充后现金余额 | 555.30 |
| 扩充后经营盈亏 | -944.70 |
| 脚本结论 | `regression.sql READONLY PASS` |

这次核对是只读操作，没有修改业务表；原始数据库 `ShiguangBookstoreWeek3` 仍未被写入。
