# 第六周新增样例装载记录

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 装载脚本：[`db/sample-data-week-6.sql`](../../../sample-data-week-6.sql)
- 规划清单：[`docs/design/sample-data-week-6-plan.md`](../../../../docs/design/sample-data-week-6-plan.md)
- 执行方式：在 SSMS 新查询窗口执行完整脚本；脚本固定使用 `USE [ShiguangBookstoreWeek6Work]`
- 用户反馈：符合实验预期

## 预期截面与反馈

用户确认装载结果符合脚本预期。由于本次反馈没有复制 SSMS 的原始结果网格和消息文本，下面记录脚本定义的验收截面；原始 SSMS 输出仍应作为后续非作者复核证据补存。

| 项目 | 预期值 |
|---|---:|
| 用户表 | 20 |
| 外码 | 49 |
| 全部用户表计划行数 | 199 |
| 商品 `goods` | 10 |
| 会员 `member` | 6 |
| 采购申请 `purchase_request` | 10 |
| 预订单 `reservation` | 8 |
| 销售单 `sale` | 9 |
| 退货单 `goods_return` | 5 |
| 库存流水 `stock_movement` | 31 |
| 积分流水 `point_movement` | 13 |
| 资金流水 `fund_flow` | 29 |
| 扩充后现金余额 | 555.30 |
| 扩充后经营盈亏 | -944.70 |
| 脚本结论 | `sample-data-week-6.sql PASS` |

`199` 行由迁移后的 77 行旧业务数据、121 行新增业务数据和 1 行 `schema_migration` 元数据组成。扩充脚本保留旧商品、旧会员、旧单据及旧流水；扩充前的旧资金截面仍为现金 `1430.30`、经营盈亏 `-69.70`。

本记录确认的是新增样例装载结果，不代表完整回归已经完成。下一步执行只读回归脚本 [`db/regression.sql`](../../../regression.sql)，核对旧快照、W6-S01—W6-S11 终态和跨表账目；结构性反例、权限与事务回滚测试另行分步执行。
