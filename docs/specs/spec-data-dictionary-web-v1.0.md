# Web v1.0 当前数据字典

本文记录 Web v1.0 随第 10 周存储过程与函数交付后的表结构。共 29 张用户表，其中 21 张对应业务实体，8 张用于认证、请求处理或迁移。业务关系见 [Web v1.0 ER 图源](../../ER/er-diagram-web-v1.0.drawio)和 [PNG](../../ER/er-diagram-web-v1.0.png)，设计理由和事务约束见[Web 增量模型](../design/web-model-extension.md)。

字段、主键、唯一性、外键和 CHECK 取自 2026-11-16 [第 10 周验收](../../db/results/week-10/README.md)的 AuthTests 和 SaleTests 副本系统目录，两库的这些定义一致。按[安装入口](../../scripts/project_runner.py)复现时，先建立旧基线，再执行第六周迁移和 Web 增量。原字典和各周验收材料见[课程归档](../archive/README.md)。

## 表与实体清单

### 业务实体（21 张）

| 表 | 记录内容 | 建表脚本 |
|---|---|---|
| [`dbo.book`](#dbo-book) | 图书档案 | [schema.sql](../../db/schema.sql) |
| [`dbo.toy`](#dbo-toy) | 文创商品档案 | [schema.sql](../../db/schema.sql) |
| [`dbo.supplier`](#dbo-supplier) | 供应商档案 | [schema.sql](../../db/schema.sql) |
| [`dbo.supplier_quote`](#dbo-supplier_quote) | 供应商对商品的当前报价 | [schema.sql](../../db/schema.sql) |
| [`dbo.goods`](#dbo-goods) | 商品档案、售价及库存计数 | [schema.sql](../../db/schema.sql) |
| [`dbo.stock_movement`](#dbo-stock_movement) | 库存变动及来源 | [schema.sql](../../db/schema.sql) |
| [`dbo.purchase_request`](#dbo-purchase_request) | 采购单及状态 | [schema.sql](../../db/schema.sql) |
| [`dbo.purchase_request_item`](#dbo-purchase_request_item) | 采购商品及数量、价格 | [schema.sql](../../db/schema.sql) |
| [`dbo.sale`](#dbo-sale) | 销售单及结算快照 | [schema.sql](../../db/schema.sql) |
| [`dbo.sale_item`](#dbo-sale_item) | 销售商品及成交快照 | [schema.sql](../../db/schema.sql) |
| [`dbo.reservation`](#dbo-reservation) | 预订单、取货凭证及状态 | [schema.sql](../../db/schema.sql) |
| [`dbo.reservation_item`](#dbo-reservation_item) | 预订商品及保留数量 | [schema.sql](../../db/schema.sql) |
| [`dbo.goods_return`](#dbo-goods_return) | 退货单及原销售单 | [schema.sql](../../db/schema.sql) |
| [`dbo.goods_return_item`](#dbo-goods_return_item) | 退货对应的原销售明细及数量、退款 | [schema.sql](../../db/schema.sql) |
| [`dbo.card_type`](#dbo-card_type) | 会员卡档位及当前费率参数 | [schema.sql](../../db/schema.sql) |
| [`dbo.member`](#dbo-member) | 会员稳定标识、当前档位及积分余额 | [schema.sql](../../db/schema.sql) |
| [`dbo.point_movement`](#dbo-point_movement) | 积分获得、抵扣和退款回滚 | [schema.sql](../../db/schema.sql) |
| [`dbo.fund_flow`](#dbo-fund_flow) | 资金收付及前后余额 | [schema.sql](../../db/schema.sql) |
| [`dbo.employee`](#dbo-employee) | 员工及岗位档案 | [schema.sql](../../db/schema.sql) |
| [`dbo.member_service`](#dbo-member_service) | 开卡、续费及升级留痕与收费快照 | [member-entry.sql](../../db/member-entry.sql) |
| [`dbo.member_contact_history`](#dbo-member_contact_history) | 每次改号的原号码、新号码及经办信息 | [member-entry.sql](../../db/member-entry.sql) |

### 技术表（8 张）

| 表 | 记录内容 | 建表脚本 |
|---|---|---|
| [`dbo.schema_migration`](#dbo-schema_migration) | 结构迁移记录 | [migration.sql](../../db/migration.sql) |
| [`auth.employee_credential`](#auth-employee_credential) | 员工凭证和会话版本 | [entry-foundation.sql](../../db/entry-foundation.sql) |
| [`auth.member_access`](#auth-member_access) | 会员自助查询凭证摘要 | [member-entry.sql](../../db/member-entry.sql) |
| [`auth.member_contact`](#auth-member_contact) | 会员当前联系号码映射 | [member-entry.sql](../../db/member-entry.sql) |
| [`api.operation_request`](#api-operation_request) | 员工操作幂等请求及结果 | [operations-entry.sql](../../db/operations-entry.sql) |
| [`api.sale_request`](#api-sale_request) | 销售与取货结算幂等请求及结果 | [sale-entry.sql](../../db/sale-entry.sql) |
| [`api.reservation_request`](#api-reservation_request) | 顾客预订幂等请求及结果 | [reservation-entry.sql](../../db/reservation-entry.sql) |
| [`api.reservation_cancellation`](#api-reservation_cancellation) | 顾客取消预订的重试结果 | [reservation-entry.sql](../../db/reservation-entry.sql) |

基线表的后续结构变更见[第 4 周约束脚本](../../db/constraint-ddl.sql)、[第 6 周迁移](../../db/migration.sql)和 [Web 退货回收增量](../../db/return-entry.sql)。跨表业务规则由约束、触发器和受限存储过程共同执行。过程与函数的调用参数见[数据库对象调用约定](../../db/results/week-10/object-contracts.md)。

## 字段、键和约束

可空性以系统目录为准。唯一索引附带过滤条件时，仅在满足该条件的行上保证唯一。未单独标注的外键使用 SQL Server 默认的 NO ACTION。

### dbo-book

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `isbn` | `varchar(17)` | 否 | — |
| `author` | `nvarchar(100)` | 否 | — |
| `publisher` | `nvarchar(100)` | 否 | — |
| `page_count` | `int` | 否 | — |

- 主键 `isbn`。
- CHECK `CK_book_author_text` `(len(ltrim(rtrim([author])))>(0))`。
- CHECK `CK_book_isbn` `(len([isbn])>=(10) AND len([isbn])<=(17))`。
- CHECK `CK_book_isbn_text` `(len(ltrim(rtrim([isbn])))>(0))`。
- CHECK `CK_book_pages` `([page_count]>(0))`。
- CHECK `CK_book_publisher_text` `(len(ltrim(rtrim([publisher])))>(0))`。

### dbo-toy

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `inner_code` | `varchar(20)` | 否 | — |
| `spec` | `nvarchar(100)` | 否 | — |

- 主键 `inner_code`。
- CHECK `CK_toy_inner_code_text` `(len(ltrim(rtrim([inner_code])))>(0))`。
- CHECK `CK_toy_spec_text` `(len(ltrim(rtrim([spec])))>(0))`。

### dbo-supplier

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `name` | `nvarchar(100)` | 否 | — |
| `created_by` | `varchar(11)` | 否 | — |
| `created_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `updated_by` | `varchar(11)` | 是 | — |
| `updated_at` | `datetime2(7)` | 是 | — |

- 主键 `id`。
- 唯一约束 `name`。
- 外键 `created_by` → `dbo.employee(phone)`。
- 外键 `updated_by` → `dbo.employee(phone)`。
- CHECK `CK_supplier_created_by_phone` `([created_by] IS NULL OR len([created_by])=(11) AND NOT ([created_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_supplier_created_by_text` `(len(ltrim(rtrim([created_by])))>(0))`。
- CHECK `CK_supplier_name_text` `(len(ltrim(rtrim([name])))>(0))`。
- CHECK `CK_supplier_updated_by_pair` `([updated_by] IS NULL AND [updated_at] IS NULL OR [updated_by] IS NOT NULL AND [updated_at] IS NOT NULL)`。
- CHECK `CK_supplier_updated_by_phone` `([updated_by] IS NULL OR len([updated_by])=(11) AND NOT ([updated_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。

### dbo-supplier_quote

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `supplier_id` | `bigint` | 否 | — |
| `goods_id` | `bigint` | 否 | — |
| `quote_amount` | `decimal(10,2)` | 否 | — |
| `reported_by` | `varchar(11)` | 否 | — |
| `reported_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `supplier_id, goods_id`。
- 外键 `goods_id` → `dbo.goods(id)`。
- 外键 `reported_by` → `dbo.employee(phone)`。
- 外键 `supplier_id` → `dbo.supplier(id)`。
- CHECK `CK_supplier_quote_amount` `([quote_amount]>(0))`。
- CHECK `CK_supplier_quote_reported_by_phone` `([reported_by] IS NULL OR len([reported_by])=(11) AND NOT ([reported_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_supplier_quote_reported_by_text` `(len(ltrim(rtrim([reported_by])))>(0))`。

### dbo-goods

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `category` | `nvarchar(10)` | 否 | — |
| `name` | `nvarchar(100)` | 否 | — |
| `book_isbn` | `varchar(17)` | 是 | — |
| `toy_code` | `varchar(20)` | 是 | — |
| `on_shelf` | `bit` | 否 | `((0))` |
| `price` | `decimal(10,2)` | 是 | — |
| `stock_total` | `int` | 否 | `((0))` |
| `reserved_qty` | `int` | 否 | `((0))` |
| `created_by` | `varchar(11)` | 否 | — |
| `created_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `updated_by` | `varchar(11)` | 是 | — |
| `updated_at` | `datetime2(7)` | 是 | — |

- 主键 `id`。
- 唯一索引 `book_isbn`，过滤条件 `([book_isbn] IS NOT NULL)`。
- 唯一索引 `toy_code`，过滤条件 `([toy_code] IS NOT NULL)`。
- 外键 `book_isbn` → `dbo.book(isbn)`。
- 外键 `created_by` → `dbo.employee(phone)`。
- 外键 `toy_code` → `dbo.toy(inner_code)`。
- 外键 `updated_by` → `dbo.employee(phone)`。
- CHECK `CK_goods_category` `([category]=N'图书' AND [book_isbn] IS NOT NULL AND [toy_code] IS NULL OR [category]=N'文创' AND [toy_code] IS NOT NULL AND [book_isbn] IS NULL)`。
- CHECK `CK_goods_created_by_phone` `([created_by] IS NULL OR len([created_by])=(11) AND NOT ([created_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_goods_created_by_text` `(len(ltrim(rtrim([created_by])))>(0))`。
- CHECK `CK_goods_listing` `([on_shelf]=(0) OR [price] IS NOT NULL)`。
- CHECK `CK_goods_name_text` `(len(ltrim(rtrim([name])))>(0))`。
- CHECK `CK_goods_price` `([price] IS NULL OR [price]>(0))`。
- CHECK `CK_goods_stock` `([stock_total]>=(0) AND [reserved_qty]>=(0) AND [reserved_qty]<=[stock_total])`。
- CHECK `CK_goods_updated_by_pair` `([updated_by] IS NULL AND [updated_at] IS NULL OR [updated_by] IS NOT NULL AND [updated_at] IS NOT NULL)`。
- CHECK `CK_goods_updated_by_phone` `([updated_by] IS NULL OR len([updated_by])=(11) AND NOT ([updated_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。

### dbo-stock_movement

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `goods_id` | `bigint` | 否 | — |
| `change_type` | `nvarchar(10)` | 否 | — |
| `stock_before` | `int` | 否 | 调整前物理库存 `goods.stock_total` |
| `stock_after` | `int` | 否 | 调整后物理库存 `goods.stock_total` |
| `quantity` | `int` | 否 | 变化量，`stock_after - stock_before` |
| `note` | `nvarchar(200)` | 是 | — |
| `changed_by` | `varchar(11)` | 否 | — |
| `changed_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `request_id` | `bigint` | 是 | — |
| `sale_id` | `bigint` | 是 | — |
| `return_item_id` | `bigint` | 是 | — |

- 主键 `id`。
- 唯一索引 `return_item_id`，过滤条件 `([return_item_id] IS NOT NULL)`。
- 外键 `changed_by` → `dbo.employee(phone)`。
- 外键 `goods_id` → `dbo.goods(id)`。
- 外键 `request_id` → `dbo.purchase_request(id)`。
- 外键 `return_item_id` → `dbo.goods_return_item(id)`。
- 外键 `sale_id` → `dbo.sale(id)`。
- CHECK `CK_stock_movement_changed_by_phone` `([changed_by] IS NULL OR len([changed_by])=(11) AND NOT ([changed_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_stock_movement_changed_by_text` `(len(ltrim(rtrim([changed_by])))>(0))`。
- CHECK `CK_stock_movement_bounds` `([stock_before]>=(0) AND [stock_after]>=(0))`。
- CHECK `CK_stock_movement_delta` `([quantity]=[stock_after]-[stock_before])`。
- CHECK `CK_stock_movement_source` `([change_type]=N'购入' AND [stock_after]>[stock_before] AND [request_id] IS NOT NULL AND [sale_id] IS NULL AND [return_item_id] IS NULL OR [change_type]=N'卖出' AND [stock_after]<[stock_before] AND [sale_id] IS NOT NULL AND [request_id] IS NULL AND [return_item_id] IS NULL OR [change_type]=N'退货' AND [stock_after]>[stock_before] AND [return_item_id] IS NOT NULL AND [request_id] IS NULL AND [sale_id] IS NULL OR [change_type]=N'损坏' AND [stock_after]<[stock_before] AND [stock_before]-[stock_after] BETWEEN (1) AND (1000) AND [request_id] IS NULL AND [sale_id] IS NULL AND [return_item_id] IS NULL AND [note] IS NOT NULL AND len(ltrim(rtrim([note])))>(0))`。

### dbo-purchase_request

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `no` | `varchar(20)` | 否 | — |
| `supplier_id` | `bigint` | 否 | — |
| `status` | `nvarchar(10)` | 否 | `(N'草稿')` |
| `created_by` | `varchar(11)` | 否 | — |
| `created_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `submitted_by` | `varchar(11)` | 是 | — |
| `submitted_at` | `datetime2(7)` | 是 | — |
| `approved_by` | `varchar(11)` | 是 | — |
| `approved_at` | `datetime2(7)` | 是 | — |
| `cancelled_by` | `varchar(11)` | 是 | — |
| `cancelled_at` | `datetime2(7)` | 是 | — |

- 主键 `id`。
- 唯一约束 `no`。
- 外键 `approved_by` → `dbo.employee(phone)`。
- 外键 `cancelled_by` → `dbo.employee(phone)`。
- 外键 `created_by` → `dbo.employee(phone)`。
- 外键 `submitted_by` → `dbo.employee(phone)`。
- 外键 `supplier_id` → `dbo.supplier(id)`。
- CHECK `CK_purchase_request_approved_by_pair` `([approved_by] IS NULL AND [approved_at] IS NULL OR [approved_by] IS NOT NULL AND [approved_at] IS NOT NULL)`。
- CHECK `CK_purchase_request_approved_by_phone` `([approved_by] IS NULL OR len([approved_by])=(11) AND NOT ([approved_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_purchase_request_cancelled_by_pair` `([cancelled_by] IS NULL AND [cancelled_at] IS NULL OR [cancelled_by] IS NOT NULL AND [cancelled_at] IS NOT NULL)`。
- CHECK `CK_purchase_request_cancelled_by_phone` `([cancelled_by] IS NULL OR len([cancelled_by])=(11) AND NOT ([cancelled_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_purchase_request_created_by_phone` `([created_by] IS NULL OR len([created_by])=(11) AND NOT ([created_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_purchase_request_created_by_text` `(len(ltrim(rtrim([created_by])))>(0))`。
- CHECK `CK_purchase_request_no_text` `(len(ltrim(rtrim([no])))>(0))`。
- CHECK `CK_purchase_request_stage` `([status]=N'草稿' AND [submitted_by] IS NULL AND [approved_by] IS NULL AND [cancelled_by] IS NULL OR [status]=N'已提交' AND [submitted_by] IS NOT NULL AND [approved_by] IS NULL AND [cancelled_by] IS NULL OR ([status]=N'已收货' OR [status]=N'已审批') AND [submitted_by] IS NOT NULL AND [approved_by] IS NOT NULL AND [cancelled_by] IS NULL OR [status]=N'已取消' AND [cancelled_by] IS NOT NULL AND [approved_by] IS NULL)`。
- CHECK `CK_purchase_request_status` `([status]=N'已取消' OR [status]=N'已收货' OR [status]=N'已审批' OR [status]=N'已提交' OR [status]=N'草稿')`。
- CHECK `CK_purchase_request_submitted_by_pair` `([submitted_by] IS NULL AND [submitted_at] IS NULL OR [submitted_by] IS NOT NULL AND [submitted_at] IS NOT NULL)`。
- CHECK `CK_purchase_request_submitted_by_phone` `([submitted_by] IS NULL OR len([submitted_by])=(11) AND NOT ([submitted_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_purchase_request_times` `(([submitted_at] IS NULL OR [submitted_at]>=[created_at]) AND ([approved_at] IS NULL OR [approved_at]>=[submitted_at]) AND ([cancelled_at] IS NULL OR [cancelled_at]>=[created_at]))`。

### dbo-purchase_request_item

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `request_id` | `bigint` | 否 | — |
| `goods_id` | `bigint` | 否 | — |
| `request_qty` | `int` | 否 | — |
| `unit_cost` | `decimal(10,2)` | 否 | — |

- 主键 `id`。
- 唯一约束 `request_id, goods_id`。
- 外键 `goods_id` → `dbo.goods(id)`。
- 外键 `request_id` → `dbo.purchase_request(id)`。
- CHECK `CK_purchase_request_item_cost` `([unit_cost]>(0))`。
- CHECK `CK_purchase_request_item_quantity` `([request_qty]>(0))`。

### dbo-sale

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `no` | `varchar(20)` | 否 | — |
| `status` | `nvarchar(10)` | 否 | `(N'已付')` |
| `cashier_by` | `varchar(11)` | 否 | — |
| `sold_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `card_level` | `nvarchar(10)` | 是 | — |
| `member_phone` | `varchar(11)` | 是 | — |
| `reservation_id` | `bigint` | 是 | — |
| `subtotal_amount` | `decimal(10,2)` | 否 | — |
| `discount_rate` | `decimal(3,2)` | 否 | `((1.00))` |
| `point_deduction_amount` | `decimal(10,2)` | 否 | `((0))` |
| `paid_amount` | `decimal(10,2)` | 否 | — |

- 主键 `id`。
- 唯一约束 `no`。
- 唯一索引 `reservation_id`，过滤条件 `([reservation_id] IS NOT NULL)`。
- 外键 `cashier_by` → `dbo.employee(phone)`。
- 外键 `member_phone` → `dbo.member(phone)`。
- 外键 `reservation_id` → `dbo.reservation(id)`。
- CHECK `CK_sale_amount` `([subtotal_amount]>=(0) AND [point_deduction_amount]>=(0) AND [paid_amount]>=(0) AND [point_deduction_amount]<=floor((round([subtotal_amount]*[discount_rate],(2))*(0.20))*(100))/(100.0) AND [paid_amount]=(round([subtotal_amount]*[discount_rate],(2))-[point_deduction_amount]))`。
- CHECK `CK_sale_card` `([card_level] IS NULL AND [discount_rate]=(1) AND [point_deduction_amount]=(0) OR [card_level] IS NOT NULL AND ([card_level]=N'金卡' OR [card_level]=N'银卡') AND [member_phone] IS NOT NULL)`。
- CHECK `CK_sale_cashier_by_phone` `([cashier_by] IS NULL OR len([cashier_by])=(11) AND NOT ([cashier_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_sale_cashier_by_text` `(len(ltrim(rtrim([cashier_by])))>(0))`。
- CHECK `CK_sale_member_phone_phone` `([member_phone] IS NULL OR len([member_phone])=(11) AND NOT ([member_phone]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_sale_no_text` `(len(ltrim(rtrim([no])))>(0))`。
- CHECK `CK_sale_rate` `([discount_rate]>(0) AND [discount_rate]<=(1))`。
- CHECK `CK_sale_status` `([status]=N'已全退' OR [status]=N'部分退款' OR [status]=N'已付')`。

### dbo-sale_item

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `sale_id` | `bigint` | 否 | — |
| `goods_id` | `bigint` | 否 | — |
| `quantity` | `int` | 否 | — |
| `unit_price` | `decimal(10,2)` | 否 | — |

- 主键 `id`。
- 唯一约束 `sale_id, goods_id`。
- 外键 `goods_id` → `dbo.goods(id)`。
- 外键 `sale_id` → `dbo.sale(id)`。
- CHECK `CK_sale_item_price` `([unit_price]>=(0))`。
- CHECK `CK_sale_item_quantity` `([quantity]>(0))`。

### dbo-reservation

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `code` | `varchar(20)` | 否 | — |
| `phone` | `varchar(11)` | 否 | — |
| `status` | `nvarchar(10)` | 否 | `(N'有效')` |
| `created_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `expires_at` | `datetime2(7)` | 否 | — |
| `cancelled_by_employee` | `varchar(11)` | 是 | — |
| `cancelled_at` | `datetime2(7)` | 是 | — |

- 主键 `id`。
- 唯一约束 `code`。
- 外键 `cancelled_by_employee` → `dbo.employee(phone)`。
- CHECK `CK_reservation_cancel` `([status]=N'已取消' AND [cancelled_at] IS NOT NULL AND [cancelled_at]>=[created_at] OR [status]<>N'已取消' AND [cancelled_at] IS NULL AND [cancelled_by_employee] IS NULL)`。
- CHECK `CK_reservation_cancelled_by_employee_phone` `([cancelled_by_employee] IS NULL OR len([cancelled_by_employee])=(11) AND NOT ([cancelled_by_employee]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_reservation_code_text` `(len(ltrim(rtrim([code])))>(0))`。
- CHECK `CK_reservation_expiry` `([expires_at]=dateadd(day,(3),[created_at]))`。
- CHECK `CK_reservation_phone_phone` `([phone] IS NULL OR len([phone])=(11) AND NOT ([phone]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_reservation_phone_text` `(len(ltrim(rtrim([phone])))>(0))`。
- CHECK `CK_reservation_status` `([status]=N'已取消' OR [status]=N'已过期' OR [status]=N'已取' OR [status]=N'有效')`。

### dbo-reservation_item

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `reservation_id` | `bigint` | 否 | — |
| `goods_id` | `bigint` | 否 | — |
| `quantity` | `int` | 否 | — |

- 主键 `id`。
- 唯一约束 `reservation_id, goods_id`。
- 外键 `goods_id` → `dbo.goods(id)`。
- 外键 `reservation_id` → `dbo.reservation(id)`。
- CHECK `CK_reservation_item_quantity` `([quantity]>(0))`。

### dbo-goods_return

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `no` | `varchar(20)` | 否 | — |
| `sale_id` | `bigint` | 否 | — |
| `refund_amount` | `decimal(10,2)` | 否 | — |
| `handled_by` | `varchar(11)` | 否 | — |
| `handled_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `id`。
- 唯一约束 `no`。
- 外键 `handled_by` → `dbo.employee(phone)`。
- 外键 `sale_id` → `dbo.sale(id)`。
- CHECK `CK_goods_return_amount` `([refund_amount]>=(0))`。
- CHECK `CK_goods_return_handled_by_phone` `([handled_by] IS NULL OR len([handled_by])=(11) AND NOT ([handled_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_goods_return_handled_by_text` `(len(ltrim(rtrim([handled_by])))>(0))`。
- CHECK `CK_goods_return_no_text` `(len(ltrim(rtrim([no])))>(0))`。

### dbo-goods_return_item

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `return_id` | `bigint` | 否 | — |
| `sale_item_id` | `bigint` | 否 | — |
| `quantity` | `int` | 否 | — |
| `refund_amount` | `decimal(10,2)` | 否 | — |

- 主键 `id`。
- 唯一约束 `return_id, sale_item_id`。
- 外键 `return_id` → `dbo.goods_return(id)`。
- 外键 `sale_item_id` → `dbo.sale_item(id)`。
- CHECK `CK_goods_return_item_amount` `([refund_amount]>=(0))`。
- CHECK `CK_goods_return_item_quantity` `([quantity]>(0))`。

### dbo-card_type

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `level` | `nvarchar(10)` | 否 | — |
| `card_fee` | `decimal(10,2)` | 否 | — |
| `discount_rate` | `decimal(3,2)` | 否 | — |
| `set_by` | `varchar(11)` | 否 | — |
| `set_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `level`。
- 外键 `set_by` → `dbo.employee(phone)`。
- CHECK `CK_card_type_fee` `([card_fee]>(0))`。
- CHECK `CK_card_type_level` `([level]=N'金卡' OR [level]=N'银卡')`。
- CHECK `CK_card_type_rate` `([discount_rate]>(0) AND [discount_rate]<=(1))`。
- CHECK `CK_card_type_set_by_phone` `([set_by] IS NULL OR len([set_by])=(11) AND NOT ([set_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_card_type_set_by_text` `(len(ltrim(rtrim([set_by])))>(0))`。

### dbo-member

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `phone` | `varchar(11)` | 否 | — |
| `card_level` | `nvarchar(10)` | 否 | — |
| `opened_by` | `varchar(11)` | 否 | — |
| `opened_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `updated_by` | `varchar(11)` | 是 | — |
| `updated_at` | `datetime2(7)` | 是 | — |
| `expires_at` | `date` | 否 | — |
| `points_balance` | `int` | 否 | `((0))` |

- 主键 `phone`。
- 外键 `card_level` → `dbo.card_type(level)`。
- 外键 `opened_by` → `dbo.employee(phone)`。
- 外键 `updated_by` → `dbo.employee(phone)`。
- CHECK `CK_member_card_level_text` `(len(ltrim(rtrim([card_level])))>(0))`。
- CHECK `CK_member_expiry` `([expires_at]>CONVERT([date],[opened_at]))`。
- CHECK `CK_member_opened_by_phone` `([opened_by] IS NULL OR len([opened_by])=(11) AND NOT ([opened_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_member_opened_by_text` `(len(ltrim(rtrim([opened_by])))>(0))`。
- CHECK `CK_member_phone_phone` `([phone] IS NULL OR len([phone])=(11) AND NOT ([phone]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_member_phone_text` `(len(ltrim(rtrim([phone])))>(0))`。
- CHECK `CK_member_updated_by_pair` `([updated_by] IS NULL AND [updated_at] IS NULL OR [updated_by] IS NOT NULL AND [updated_at] IS NOT NULL)`。
- CHECK `CK_member_updated_by_phone` `([updated_by] IS NULL OR len([updated_by])=(11) AND NOT ([updated_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。

### dbo-point_movement

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `member_phone` | `varchar(11)` | 否 | — |
| `change_type` | `nvarchar(10)` | 否 | — |
| `points` | `int` | 否 | — |
| `sale_id` | `bigint` | 是 | — |
| `return_id` | `bigint` | 是 | — |
| `changed_by` | `varchar(11)` | 否 | — |
| `changed_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `id`。
- 唯一索引 `sale_id`，过滤条件 `([change_type]=N'消费获得')`。
- 唯一索引 `return_id`，过滤条件 `([change_type]=N'退货回滚')`。
- 唯一索引 `sale_id`，过滤条件 `([change_type]=N'抵扣使用')`。
- 外键 `changed_by` → `dbo.employee(phone)`。
- 外键 `member_phone` → `dbo.member(phone)`。
- 外键 `return_id` → `dbo.goods_return(id)`。
- 外键 `sale_id` → `dbo.sale(id)`。
- CHECK `CK_point_movement_changed_by_phone` `([changed_by] IS NULL OR len([changed_by])=(11) AND NOT ([changed_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_point_movement_changed_by_text` `(len(ltrim(rtrim([changed_by])))>(0))`。
- CHECK `CK_point_movement_kind` `([change_type]=N'消费获得' AND [points]>(0) AND [sale_id] IS NOT NULL AND [return_id] IS NULL OR [change_type]=N'抵扣使用' AND [points]<(0) AND [sale_id] IS NOT NULL AND [return_id] IS NULL OR [change_type]=N'退货回滚' AND [points]<(0) AND [sale_id] IS NOT NULL AND [return_id] IS NOT NULL)`。
- CHECK `CK_point_movement_member_phone_phone` `([member_phone] IS NULL OR len([member_phone])=(11) AND NOT ([member_phone]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_point_movement_member_phone_text` `(len(ltrim(rtrim([member_phone])))>(0))`。

### dbo-fund_flow

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `amount` | `decimal(10,2)` | 否 | — |
| `direction` | `nvarchar(2)` | 否 | — |
| `reason_type` | `nvarchar(10)` | 否 | — |
| `sale_id` | `bigint` | 是 | — |
| `return_id` | `bigint` | 是 | — |
| `request_id` | `bigint` | 是 | — |
| `member_phone` | `varchar(11)` | 是 | — |
| `fund_before` | `decimal(12,2)` | 否 | — |
| `fund_after` | `decimal(12,2)` | 否 | — |
| `recorded_by` | `varchar(11)` | 否 | — |
| `recorded_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `id`。
- 外键 `member_phone` → `dbo.member(phone)`。
- 外键 `recorded_by` → `dbo.employee(phone)`。
- 外键 `request_id` → `dbo.purchase_request(id)`。
- 外键 `return_id` → `dbo.goods_return(id)`。
- 外键 `sale_id` → `dbo.sale(id)`。
- CHECK `CK_fund_flow_amount` `([amount]>(0) AND [fund_before]>=(0) AND [fund_after]>=(0))`。
- CHECK `CK_fund_flow_balance` `([direction]=N'收' AND [fund_after]=([fund_before]+[amount]) OR [direction]=N'付' AND [fund_after]=([fund_before]-[amount]))`。
- CHECK `CK_fund_flow_member_phone_phone` `([member_phone] IS NULL OR len([member_phone])=(11) AND NOT ([member_phone]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_fund_flow_recorded_by_phone` `([recorded_by] IS NULL OR len([recorded_by])=(11) AND NOT ([recorded_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_fund_flow_recorded_by_text` `(len(ltrim(rtrim([recorded_by])))>(0))`。
- CHECK `CK_fund_flow_source` `([reason_type]=N'销售收款' AND [direction]=N'收' AND [sale_id] IS NOT NULL AND [return_id] IS NULL AND [request_id] IS NULL AND [member_phone] IS NULL OR [reason_type]=N'采购付款' AND [direction]=N'付' AND [request_id] IS NOT NULL AND [sale_id] IS NULL AND [return_id] IS NULL AND [member_phone] IS NULL OR [reason_type]=N'退货退款' AND [direction]=N'付' AND [sale_id] IS NOT NULL AND [return_id] IS NOT NULL AND [request_id] IS NULL AND [member_phone] IS NULL OR [reason_type]=N'办卡费' AND [direction]=N'收' AND [member_phone] IS NOT NULL AND [sale_id] IS NULL AND [return_id] IS NULL AND [request_id] IS NULL OR ([reason_type]=N'提现' OR [reason_type]=N'注资') AND [sale_id] IS NULL AND [return_id] IS NULL AND [request_id] IS NULL AND [member_phone] IS NULL AND ([reason_type]=N'注资' AND [direction]=N'收' OR [reason_type]=N'提现' AND [direction]=N'付'))`。

### dbo-employee

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `phone` | `varchar(11)` | 否 | — |
| `name` | `nvarchar(20)` | 否 | — |
| `role` | `nvarchar(10)` | 否 | — |
| `created_by` | `varchar(11)` | 否 | — |
| `created_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `updated_by` | `varchar(11)` | 是 | — |
| `updated_at` | `datetime2(7)` | 是 | — |

- 主键 `phone`。
- 外键 `created_by` → `dbo.employee(phone)`。
- 外键 `updated_by` → `dbo.employee(phone)`。
- CHECK `CK_employee_created_by_phone` `([created_by] IS NULL OR len([created_by])=(11) AND NOT ([created_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_employee_created_by_text` `(len(ltrim(rtrim([created_by])))>(0))`。
- CHECK `CK_employee_name_text` `(len(ltrim(rtrim([name])))>(0))`。
- CHECK `CK_employee_phone_phone` `([phone] IS NULL OR len([phone])=(11) AND NOT ([phone]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_employee_phone_text` `(len(ltrim(rtrim([phone])))>(0))`。
- CHECK `CK_employee_role` `([role]=N'店长' OR [role]=N'收银员' OR [role]=N'库管')`。
- CHECK `CK_employee_updated_by_pair` `([updated_by] IS NULL AND [updated_at] IS NULL OR [updated_by] IS NOT NULL AND [updated_at] IS NOT NULL)`。
- CHECK `CK_employee_updated_by_phone` `([updated_by] IS NULL OR len([updated_by])=(11) AND NOT ([updated_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。

### dbo-member_service

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `member_phone` | `varchar(11)` | 否 | — |
| `operation` | `varchar(10)` | 否 | — |
| `old_level` | `nvarchar(10)` | 是 | — |
| `new_level` | `nvarchar(10)` | 否 | — |
| `old_expiry` | `date` | 是 | — |
| `new_expiry` | `date` | 否 | — |
| `amount` | `decimal(10,2)` | 否 | — |
| `silver_fee` | `decimal(10,2)` | 否 | — |
| `gold_fee` | `decimal(10,2)` | 否 | — |
| `fund_flow_id` | `bigint` | 否 | — |
| `handled_by` | `varchar(11)` | 否 | — |
| `handled_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `id`。
- 唯一约束 `fund_flow_id`。
- 外键 `fund_flow_id` → `dbo.fund_flow(id)`。
- 外键 `handled_by` → `dbo.employee(phone)`。
- 外键 `member_phone` → `dbo.member(phone)`。
- CHECK `([amount]>(0))`。

### dbo-member_contact_history

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `id` | `bigint` | 否 | `IDENTITY(1,1)` |
| `member_phone` | `varchar(11)` | 否 | — |
| `old_contact` | `varchar(11)` | 否 | — |
| `new_contact` | `varchar(11)` | 否 | — |
| `changed_by` | `varchar(11)` | 否 | — |
| `changed_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `id`。
- 外键 `changed_by` → `dbo.employee(phone)`。
- 外键 `member_phone` → `dbo.member(phone)`。

### dbo-schema_migration

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `migration_key` | `varchar(64)` | 否 | — |
| `source_version` | `varchar(32)` | 否 | — |
| `target_version` | `varchar(32)` | 否 | — |
| `applied_at` | `datetime2(7)` | 否 | `(sysdatetime())` |
| `applied_by` | `varchar(11)` | 是 | — |
| `status` | `nvarchar(10)` | 否 | — |
| `notes` | `nvarchar(400)` | 否 | — |

- 主键 `migration_key`。
- 唯一约束 `target_version`。
- 外键 `applied_by` → `dbo.employee(phone)`。
- CHECK `CK_schema_migration_applied_by_phone` `([applied_by] IS NULL OR len([applied_by])=(11) AND NOT ([applied_by]) collate Latin1_General_100_BIN2 like '%[^0-9]%')`。
- CHECK `CK_schema_migration_status` `([status]=N'已回滚' OR [status]=N'已完成')`。

### auth-employee_credential

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `employee_phone` | `varchar(11)` | 否 | — |
| `password_hash` | `varchar(512)` | 否 | — |
| `enabled` | `bit` | 否 | `((1))` |
| `session_version` | `int` | 否 | `((1))` |
| `updated_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `employee_phone`。
- 外键 `employee_phone` → `dbo.employee(phone)`。
- CHECK `CK_employee_credential_hash` `(len([password_hash])>(20))`。
- CHECK `CK_employee_credential_version` `([session_version]>(0))`。

### auth-member_access

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `member_phone` | `varchar(11)` | 否 | — |
| `token_hash` | `binary(32)` | 否 | — |
| `issued_by` | `varchar(11)` | 否 | — |
| `issued_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `member_phone`。
- 外键 `issued_by` → `dbo.employee(phone)`。
- 外键 `member_phone` → `dbo.member(phone)`。

### auth-member_contact

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `member_phone` | `varchar(11)` | 否 | — |
| `contact_phone` | `varchar(11)` | 否 | — |
| `updated_by` | `varchar(11)` | 否 | — |
| `updated_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `member_phone`。
- 唯一约束 `contact_phone`。
- 外键 `member_phone` → `dbo.member(phone)`。
- 外键 `updated_by` → `dbo.employee(phone)`。

### api-operation_request

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `employee_phone` | `varchar(11)` | 否 | — |
| `request_key` | `uniqueidentifier` | 否 | — |
| `action` | `varchar(30)` | 否 | — |
| `payload_hash` | `binary(32)` | 否 | — |
| `result_json` | `nvarchar(max)` | 否 | — |
| `created_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `employee_phone, request_key`。
- 外键 `employee_phone` → `dbo.employee(phone)`。
- CHECK `(isjson([result_json])=(1))`。

### api-sale_request

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `employee_phone` | `varchar(11)` | 否 | — |
| `request_key` | `uniqueidentifier` | 否 | — |
| `payload_hash` | `binary(32)` | 否 | — |
| `sale_id` | `bigint` | 否 | — |
| `result_json` | `nvarchar(max)` | 否 | — |
| `created_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `employee_phone, request_key`。
- 唯一约束 `sale_id`。
- 外键 `employee_phone` → `dbo.employee(phone)`。
- 外键 `sale_id` → `dbo.sale(id)`。
- CHECK `CK_sale_request_json` `(isjson([result_json])=(1))`。

### api-reservation_request

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `request_key` | `uniqueidentifier` | 否 | — |
| `payload_hash` | `binary(32)` | 否 | — |
| `reservation_id` | `bigint` | 否 | — |
| `code_hash` | `binary(32)` | 否 | — |
| `created_at` | `datetime2(7)` | 否 | `(sysdatetime())` |

- 主键 `request_key`。
- 外键 `reservation_id` → `dbo.reservation(id)`。

### api-reservation_cancellation

| 字段 | SQL Server 类型 | 可空 | 默认值或生成方式 |
|---|---|---|---|
| `request_key` | `uniqueidentifier` | 否 | — |
| `payload_hash` | `binary(32)` | 否 | — |
| `result_json` | `nvarchar(max)` | 否 | — |

- 主键 `request_key`。
- CHECK `(isjson([result_json])=(1))`。
