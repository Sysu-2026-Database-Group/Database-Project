# 第 10 周现状核对与调用路径

对应[第 10 周任务说明 §2.3 第 1 步](../tasks/task-week-10.md)。核对日期为 2026-11-16，仓库基线为 `4af6c68`。本文记录源码审查、数据库只读查询和后续实施决定。

## 1. 数据库基线

以本机 `localhost` 上的 `ShiguangBookstoreWeek7Accept20261107` 作为现状核对对象。通过 `sqlcmd` 查询 `sys.databases`、`sys.objects`、`sys.columns`、`sys.check_constraints` 和业务汇总。该库在线，SQL Server 版本为 `17.0.1000.7`。确认已有销售、预订取货、库管和店长入口过程，以及 `v_sale_detail`、`v_goods_sales_summary` 视图。对象目录查询没有返回自定义标量或表值函数。

实查有 11 个商品，当前均未被预订占用。销售单共 10 笔（已付 5、部分退款 2、已全退 3），含 14 行、26 件；成交时原价合计 1,107.00 元，等于明细数量乘快照单价的合计；成交时实收合计 1,055.10 元。以上为全库查询截面，实收按销售单记录汇总，退款另有记录。

实施和异常用例使用独立的 Web v1.0 副本。仓库已有统一入口可从脚本建基线、创建运行库并安装角色入口。现有入口的数据库命名守卫要求 `ShiguangBookstoreWeek7%`，新副本可用该前缀及 Week10 后缀。此次仅查询验收库，独立施工副本尚未创建。 [统一入口说明](../design/unified-entry.md) · [数据库命名守卫示例](../../db/management-entry.sql#L6)

## 2. 逐项调用路径与处理决定

| 业务 | 已查到的调用路径与执行位置 | 第 10 周处理决定 |
| --- | --- | --- |
| 销售统计过程 | 店长经营报表 `/management/reports` → `management.page()` → `DAO.management_read()` → `api.usp_management_read('reports')`。Web 解析日期并提前检查顺序，SQL 再检查日期顺序并汇总资金流水；现有结果是资金余额、经营收入、支出和利润。全店单据同一路由的 `sales` 分支读销售单与明细。 [路由](../../app/management.py#L24) · [DAO](../../app/dao.py#L224) · [SQL](../../db/management-entry.sql#L9) | 新增带必填起止日期的销售统计过程，通过店长入口展示销售销量、订单数、金额和商品明细。沿用 SQL 端授权，保留现有经营报表口径。起止日期必填和顺序由新 SQL 入口校验，Web 继续处理日期输入格式与错误展示。 |
| 销售汇总表值函数 | 现有数据库视图 `v_sale_detail` 提供销售时间、数量及成交单价，`v_goods_sales_summary` 按商品汇总全时期销量和原价金额并保留无销量商品。未在当前 Web 调用点找到对该视图的直接引用。 [视图](../../db/application-baseline.sql#L38) · [第 6 周统计脚本](../../db/tests/sales-statistics-week-6.sql) | 新增按日期范围筛选的表值函数，输出商品编号、名称、销售数量、商品金额及去重订单数。统计过程复用该函数的商品明细，订单总数与实收从单头独立汇总。两个历史视图继续供既有查询使用。 |
| 库存调整 | `/inventory` 报损表单 → `POST /operations/damage` → `OperationsService.write()/normalize()` → `DAO.operation_write()` → `api.usp_operation_write('damage')`。Web 解析编号、正数数量和原因；SQL 再校验库管角色、数量范围和原因，按可售量扣减，并在同一事务写入损坏流水。采购收货由同一过程中 `receive` 分支增库存、记购入流水。报损分支当前将不存在商品和可售量不足都落到同一个错误。 [表单](../../app/templates/operations.html#L32) · [路由](../../app/routes/operations.py#L130) · [服务](../../app/operations.py#L104) · [DAO](../../app/dao.py#L191) · [SQL](../../db/operations-entry.sql#L287) | 将四类现有库存写入收拢到带参数的内部调整过程，复用原事务、角色和请求去重方式。校验数量方向及业务来源，保留既有单据关联和预订量保护。 |
| 补货量与补货选择 | `/purchases`、`/purchases/<id>` → 操作路由 → `DAO.operation_read()` → `api.usp_operation_read('purchases'/'purchase')` 读取采购；保存草稿时 Web 解析库管手填的商品和数量，经 `OperationsService.write()` 走 `api.usp_operation_write('draft')`，由 SQL 校验并保存。当前路径中未发现目标可售量、自动算建议量或补货候选入口。 [路由](../../app/routes/operations.py#L44) · [草稿表单解析](../../app/routes/operations.py#L83) · [SQL 草稿](../../db/operations-entry.sql#L235) | 新增补货标量函数和库管补货选择的 SQL 查询入口，目标可售量由页面传入。把查询得到的建议量提供给库管选择，实际保存仍复用采购草稿。 |
| 订单完成 | `POST /sales` → `SalesService.create()` → `DAO.sale_create()` → `api.usp_sale_create` → `api.usp_sale_commit`。到店自提 `POST /pickups` → `ReservationService.confirm()` → `DAO.pickup_create()` → `api.usp_pickup_create` → 同一提交过程。Web 处理会话、表单和签名确认凭据；SQL 检查预览一致性、请求重试、库存及预订状态，并在同一事务写入单头、明细、库存及相应账目。 [销售路由](../../app/routes/sales.py#L64) · [销售服务](../../app/sales.py#L54) · [自提入口](../../app/reservations.py#L144) · [自提 SQL](../../db/reservation-entry.sql#L234) · [提交过程](../../db/sale-entry.sql#L155) | 复用销售和自提的共享提交过程及现有事务和去重；接入折扣函数后，在两条页面路径分别做回归。会话、请求格式和签名确认仍由 Web 处理。 |
| 折扣和成交快照 | 销售预览与自提预览分别走 `api.usp_sale_quote`、`api.usp_pickup_quote`；两者与提交过程共同调用 `api.usp_sale_calculate`。SQL 识别会员有效期和档位，取当前折扣率，先打折再扣积分。Web 展示报价。成交时单头保存卡档、原价小计、折扣率、积分抵扣及实收；明细保存数量与单价快照。 [销售预览](../../app/sales.py#L54) · [自提预览](../../app/reservations.py#L49) · [SQL 计算](../../db/sale-entry.sql#L39) · [快照写入](../../db/sale-entry.sql#L198) | 将折扣计算抽成 SQL 函数并从原计算过程调用。会员当天有效性、档位读取与加锁继续由现有过程控制，函数据结算上下文返回折扣率、折后金额及优惠金额。保持现有舍入顺序和报价字段，复用原成交快照。 |

本次在上述路径中查到的 Web 逻辑主要是参数解析、规则预检、权限预检、确认凭据与结果展示。成交、库存写入、折扣计算和资金汇总的权威实现均已在 SQL Server。后续按清单复用现有 SQL、集中新业务计算和约束，并为新增能力接入 Web；新的 SQL 入口需能独立校验业务参数。

## 3. 库存与金额口径

- **补货与减库存。** `stock_total` 包含已订未取数量，可售量为 `stock_total - reserved_qty`。现有约束保证 `0 <= reserved_qty <= stock_total`。补货函数取本次查询传入的目标可售量，建议量为目标量减可售量，最低为 0。当前库没有预订占用样例，后续要在施工副本准备在架 12、已订 4、目标 10 的用例，预期建议量为 2。 [商品表](../../db/schema.sql#L91) · [库存视图](../../db/application-baseline.sql#L53)
- **库存调整流水。** `CK_stock_movement_source` 目前只接受购入、卖出、退货、损坏。正向流水必须关联采购单或退货明细；现有可独立记原因的损坏流水只允许负数。调整过程沿用这四类原来源约束。Web 入口沿用现有角色：库管收货、退货回收与报损，收银员在销售或预订取货时扣库存。 [流水约束](../../db/schema.sql#L295)
- **本周销售统计。** 采用成交时口径，按 `sale.sold_at` 的门店当地日期筛选，包含起止当天。已付、部分退款、已全退均对应发生过的成交，销售订单数和销量按原成交统计，后续退款继续单列。总计和商品销售额均提供成交时原价口径，按明细 `quantity × unit_price` 求和；另在单头层独立汇总成交时实收 `sale.paid_amount`，标明实收含积分抵扣影响。商品订单数按 `sale_id` 去重，整店订单数按单头计数。合法空区间总计为 0，表值函数与商品明细返回空集。 [销售表](../../db/schema.sql#L226) · [销售时间与快照写入](../../db/sale-entry.sql#L195)
- **实际优惠金额。** 以历史单头数据计算 `subtotal_amount - ROUND(subtotal_amount * discount_rate, 2)`，其中 `discount_rate` 是成交时的折后倍率。积分抵扣单列，之后的商品调价与档位调整不参与历史优惠计算。 [金额一致性约束](../../db/schema.sql#L245)

以上为第 1 步的基线核对。

## 4. 第 2、3 步实施对应

| 业务 | 实施后的调用路径 |
| --- | --- |
| 销售统计 | 店长经营报表增加销售统计入口。`GET /management/sales-statistics` → `DAO.sales_statistics()` → `api.usp_sales_statistics` → `dbo.fn_sales_by_goods`。原经营收支查询继续走 `usp_management_read('reports')`。 [Web](../../app/management.py#L24) · [SQL](../../db/procedure.sql) |
| 补货建议 | 库管采购页增加按商品查询入口。`GET /purchases/replenishment` → `DAO.replenishment()` → `api.usp_replenishment` → `dbo.fn_replenishment_quantity`。目标可售量由库管输入，结果供填写采购草稿。 [Web](../../app/routes/operations.py#L75) · [函数](../../db/function.sql) |
| 库存调整 | 采购收货和报损通过 `usp_operation_write`，结算和取货通过 `usp_sale_commit`，退货回收通过 `usp_return_recover`，都调用内部 `usp_adjust_stock`。调用方保留单据校验、事务及请求去重。内部过程按流水类型核验库管或收银员身份，应用账号通过原业务入口操作。 [Web](../../app/routes/operations.py) · [现有写入入口](../../db/operations-entry.sql) · [共用过程](../../db/procedure.sql) |
| 订单完成和折扣 | 原销售、取货预览和提交继续调用 `usp_sale_calculate`。`dbo.fn_member_discount_rate(member_phone)` 先按会员卡档/有效期取得倍率，`dbo.fn_sale_discount(subtotal, member_phone)` 再计算折后金额；沿用现有的会员有效期、锁、积分规则和成交快照。 [成交过程](../../db/sale-entry.sql) · [函数](../../db/function.sql) |

统一安装入口先安装函数和过程，再安装依赖的销售与库存操作入口。已有完整 Web v1.0 库的增量顺序见[应用使用说明](../../app/README.md)。权限检查验证店长和库管各自的过程权限，库存共用过程由既有业务过程调用，应用角色无直接执行权限。

第 4、5 步的 SQL 直调、页面回归和数据恢复证据见[第 10 周测试与验收记录](../../db/results/week-10/README.md)。
