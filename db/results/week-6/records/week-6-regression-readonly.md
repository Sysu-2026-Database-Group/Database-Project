# 第六周只读回归记录

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 回归脚本：[`db/regression.sql`](../../../regression.sql)
- 执行方式：在 SSMS 新查询窗口执行完整脚本；脚本只读，不写入业务表
- 用户反馈：每一项都符合预期

## 核对结果

用户确认脚本输出的结构、旧场景快照、W6-S01—W6-S11 终态和跨表对账均符合预期。关键截面如下：

| 项目 | 结果 |
|---|---:|
| 用户表 | 20 |
| 外码 | 49 |
| 商品 `goods` | 10 |
| 会员 `member` | 6 |
| 采购申请 `purchase_request` | 10 |
| 预订单 `reservation` | 8 |
| 销售单 `sale` | 9 |
| 退货单 `goods_return` | 5 |
| 库存流水 `stock_movement` | 31 |
| 积分流水 `point_movement` | 13 |
| 资金流水 `fund_flow` | 29 |
| 旧资金截面现金 | 1430.30 |
| 旧资金截面经营盈亏 | -69.70 |
| 扩充后现金余额 | 555.30 |
| 扩充后经营盈亏 | -944.70 |
| 脚本结论 | `regression.sql READONLY PASS` |

本轮只读回归没有修改数据库，也没有执行非法输入、权限或中途失败测试。原始数据库 `ShiguangBookstoreWeek3` 仍未修改。

随后已执行 [`db/tests/regression-negative.sql`](../../../tests/regression-negative.sql)，22 个由 DDL 明确实现的反例全部通过并逐项回滚；结果见 [`week-6-regression-negative.md`](week-6-regression-negative.md)。权限、事务失败、重复请求和自动处理测试仍另行分步执行。
