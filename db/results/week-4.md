# Week 4 execution record

The four Week 4 scripts were added for the existing SQL Server schema. Run them after the
Week 3 scripts in this order: `query.sql`, `view.sql`, `constraint.sql`, `role.sql`.

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/schema.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/sample-data.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/query.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/view.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/constraint.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/role.sql
```

Expected markers are `query.sql PASS`, `view.sql PASS`, `constraint.sql PASS`, and
`role.sql PASS`. The Week 3 baseline remains 19 tables, 77 sample rows, cash balance 1430.30,
and operating result -69.70. The query/view scripts are read-only. Constraint negative cases
run in transactions and roll back. The role script grants no `db_owner`, `CONTROL`, or `ALTER`
permissions; customers remain a business-layer identity rather than a database role.

## 完整性约束补充：会员卡档位关系

数据字典 §3.1（R-17）规定：银卡初始办卡费为 20.00、折扣率为 0.95，金卡初始办卡费为 50.00、折扣率为 0.90；金卡办卡费必须严格高于银卡，金卡折扣率不得高于银卡。

该规则跨越 `card_type` 的两行，不能由单行 `CHECK` 约束表达。Week 4 的 `constraint.sql` 创建 `dbo.tr_card_type_cross_row`，在 `INSERT` 或 `UPDATE` 后检查两档关系。违反规则时触发错误码 `51025`，当前事务回滚。

实际证据：

- 合法正例：金卡办卡费增加 1.00；关系检查通过，事务回滚；输出 `PASS|valid card tier update accepted and rolled back`。
- 非法反例：把金卡办卡费改为银卡办卡费；触发器返回 `51025` 和 `Card tier relation is invalid.`，事务回滚。
- 回滚后基线仍为：银卡 `20.00 / 0.95`，金卡 `50.00 / 0.90`。


## 查询与视图的可复算预期结果

以下结果在 `ShiguangBookstoreWeek4Replay` 上通过只读查询复核，基于 Week 3 的 77 行样例数据。

| 编号 | 业务问题 | 预期结果 |
|---|---|---|
| Q1 | 查询每张销售单的商品明细、会员归属和成交快照 | 4 行销售明细 |
| Q2 | 查询所有商品的销售数量和原始销售金额，并保留无销售商品 | 4 行；商品 1 销量 5、金额 195.00；商品 4 销量 0、金额 0.00 |
| Q3 | 查询库存、已订数量和可售数量 | 4 行；商品 1 可售数量为 0，商品 3 为 10，商品 4 为 19 |
| Q4 | 查询销量至少为 2 件的商品 | 2 行；商品 1 和商品 2 |
| Q5 | 查询消费金额高于会员平均消费的会员 | 结果为空；当前样例只有一个会员有销售记录，没有会员高于会员平均值 |
| Q6 | 查询采购单、供应商、采购明细和供应商报价 | 5 行采购明细 |
| Q7 | 查询销售明细的累计退货数量和剩余可退数量 | 4 行销售明细；存在 2 条退货明细 |

视图预期结果：

| 视图 | 业务含义 | 预期结果 |
|---|---|---|
| `v_sale_detail` | 销售单及其明细 | 4 行 |
| `v_goods_sales_summary` | 所有商品的销量和销售额 | 4 行；包含商品 4 的 0 销售记录 |
| `v_inventory_status` | 商品库存、已订数量和可售数量 | 4 行；商品 1 可售数量 0，商品 3 为 10，商品 4 为 19 |

独立复核结果保存在：

```text
db/results/week-4-expected.txt


## 角色权限矩阵

本矩阵与 `db/role.sql` 的实际 GRANT 和 EXECUTE AS 测试对应。

| 角色 | 能看 | 能改 |
|---|---|---|
| 店长 | 员工、商品、会员卡参数、销售单、销售明细、预订单、预订单明细、会员、采购申请、采购明细、资金流水、库存流水、积分流水 | `goods.price`、`goods.on_shelf`、`card_type.card_fee`、`card_type.discount_rate` |
| 收银员 | 商品、会员、预订单、预订单明细、销售单、销售明细、退货单、退货明细 | 新增会员、新增预订单及明细、新增销售单及明细、新增退货单及明细 |
| 库存管理员 | 商品、图书、文创、供应商、供应商报价、采购申请、采购明细、库存流水 | 新增商品、新增供应商报价、新增采购申请及明细、新增库存流水 |
| 顾客 | 业务层中属于自己的商品公开信息、预订单和单据 | 通过业务层创建自己的预订单；不能直接写数据库表 |

权限边界说明：

- 店长不能直接更新销售单内容；
- 收银员不能修改商品价格；
- 库存管理员不能插入销售单；
- 店长、收银员和库存管理员均未授予 `db_owner`、`CONTROL` 或 `ALTER`；
- 顾客不创建员工式数据库角色，因为顾客是外部主体，不属于店内经营角色；
- 顾客查询通过手机号与预订码等业务凭证验证归属，手机号本身不能单独作为授权凭证。

实际权限证据位于：

```text
db/results/week-4-role.txt
db/results/week-4-replay-role.txt