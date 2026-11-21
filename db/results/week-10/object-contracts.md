# 第 10 周数据库对象调用约定

Web 业务过程接收 `employee_phone varchar(11)` 和 `session_version int`，由 SQL Server 核对启用状态、岗位和会话。岗位不符或会话失效时返回现有授权错误。应用通过 DAO 绑定参数。金额以元为单位，数量以件为单位。

| 对象 | 入口和参数 | 读取或写入 | 结果与异常 |
| --- | --- | --- | --- |
| `dbo.fn_sales_by_goods` | `SELECT`，`from_date date`、`to_date date` | 读 `sale.sold_at`、`sale_item.quantity/unit_price`、`goods.id/name`。按门店当地成交日包含起止当天，退款单独统计。 | 每商品一行，返回 `goods_id`、`goods_name`、`sold_quantity`、`gross_sales_amount`、`order_count`。空值、反序日期或没有销售时返回空集。 |
| `api.usp_sales_statistics` | 店长，身份参数加 `from_date date`、`to_date date` | 在同一个查询事务中汇总 `sale.id/paid_amount` 和表值函数结果；整店订单按单头计数，避免多明细重复计算实收。 | 一行 `result_json`，含总订单、销量、成交原价、成交实收和 `records`。无销售时总计为 0 且明细为 `[]`；日期空值或反序报 `53001`。 |
| `dbo.fn_replenishment_quantity` | 标量函数，`goods_id bigint`、`target int` | 读 `goods.stock_total - reserved_qty`；目标量是本次查询参数。 | 返回 `max(0, 目标可售量 − 当前可售量)`。未知商品、空参数或负目标返回 `NULL`。 |
| `api.usp_replenishment` | 库管，身份参数加 `goods_id bigint`、`target int` | 调用补货标量函数并返回商品库存，不创建采购草稿。 | 一行 `result_json`，含商品编号、名称、在架、已订、可售、目标和建议量。商品存在性先于 target 校验：未知商品（无论 target 是否合法）返回 `52304`；`goods_id` 非正或合法商品但 target 为空/负返回 `52301`。 |
| `api.usp_adjust_stock` | 仅由既有过程在活动事务中执行。身份参数加 `goods_id bigint`、`delta int`、`change_type nvarchar(10)`、可选 `source_id bigint`、`reason nvarchar(max)`、`changed_at datetime2` | 更新 `goods.stock_total/reserved_qty`，并插入带 `stock_before/stock_after/quantity` 的 `stock_movement`；前后数量均为物理库存 `goods.stock_total`。来源为采购单、销售单或退货明细。库管负责购入、退货和损坏，收银员负责卖出。报损无单据来源，必须有文字原因。 | 通过写入结果表达成功，事务由调用方提交。缺事务、类型、来源或数量非法报 `52301`，库存不足报 `52302`。未知商品按入口返回 `52302`（报损）或 `52304`。 |
| `dbo.fn_member_discount_rate` | `SELECT`，`member_phone varchar(11)` | 解析会员联系方式映射，读取会员卡档与到期日；会员有效时取 `card_type.discount_rate`。 | 返回会员适用倍率；空会员返回 `1.00`；未知会员返回 `NULL`；过期会员返回 `1.00`。 |
| `dbo.fn_sale_discount` | `SELECT`，`subtotal decimal(10,2)`、`member_phone varchar(11)` | 先调用 `fn_member_discount_rate` 取得倍率，再计算折后金额及优惠金额。订单先应用折扣，再单独扣积分；成交时将折扣倍率和相关金额保存到 `sale`，将成交单价保存到 `sale_item`。 | 返回 `discount_rate`、`discounted_amount`、`discount_amount`。空值、负小计或未知会员时返回空集；结算过程遇到无效折扣报 `52101`。 |
| `api.usp_sale_create` | 收银员，身份参数加 `request_key uniqueidentifier`、`items nvarchar(max)`、`member_phone varchar(11)`、`used_points int`、`expected_quote nvarchar(max)`。先通过 `usp_sale_quote` 取得报价。 | 同一事务写成交单、明细、库存和相关积分、资金流水。 | 一行 `result_json` 为成交回执。同键同内容返回原回执；同键异内容报 `52106`；报价过期或结果变化报 `52107`。 |
| `api.usp_pickup_create` | 收银员，身份参数加 `request_key uniqueidentifier`、预订 `phone varchar(11)` 和 `code varchar(20)`、`member_phone varchar(11)`、`used_points int`、`expected_quote nvarchar(max)`。先通过 `usp_pickup_quote` 取得报价。 | 复用成交事务，扣除在架与本单占用的已订量，并将本单状态置为已取。 | 一行 `result_json` 为成交回执。同键同内容返回原回执；凭证不存在报 `52504`，已取或过期的预订报 `52502`。 |

表值函数允许在 SQL 中直接查询行集，便于过程复用与对账。标量补货函数返回单一计算值。写入、岗位校验、请求去重与事务边界由过程处理。完整对象定义见 [function.sql](../../function.sql)、[procedure.sql](../../procedure.sql)、[sale-entry.sql](../../sale-entry.sql) 和 [reservation-entry.sql](../../reservation-entry.sql)。
