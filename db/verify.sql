:On Error exit
-- SQLCMD 模式。验证 2026-09-20 样例截面；不使用当前日期自动改变预订状态。
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51200, N'请在无外层事务的新查询窗口执行验证。', 1;
DECLARE @expected_tables TABLE (table_name sysname PRIMARY KEY, row_count int);
INSERT @expected_tables VALUES
(N'goods',4),
(N'book',2),
(N'toy',2),
(N'supplier',3),
(N'supplier_quote',5),
(N'stock_movement',12),
(N'purchase_request',3),
(N'purchase_request_item',5),
(N'sale',3),
(N'sale_item',4),
(N'reservation',2),
(N'reservation_item',2),
(N'goods_return',2),
(N'goods_return_item',2),
(N'card_type',2),
(N'member',2),
(N'point_movement',5),
(N'fund_flow',13),
(N'employee',4);
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>19
    THROW 51201, N'表数不是 19。', 1;
IF EXISTS (SELECT table_name FROM @expected_tables EXCEPT SELECT name FROM sys.tables WHERE schema_id=SCHEMA_ID(N'dbo'))
    THROW 51202, N'表名不符合字典。', 1;
DECLARE @expected_columns TABLE (table_name sysname, column_name sysname, type_name sysname, max_length smallint, precision_value tinyint, scale_value tinyint, nullable bit, identity_value bit, has_default bit);
INSERT @expected_columns VALUES
(N'goods',N'id',N'bigint',8,19,0,0,1,0),
(N'goods',N'category',N'nvarchar',20,0,0,0,0,0),
(N'goods',N'name',N'nvarchar',200,0,0,0,0,0),
(N'goods',N'book_isbn',N'varchar',17,0,0,1,0,0),
(N'goods',N'toy_code',N'varchar',20,0,0,1,0,0),
(N'goods',N'on_shelf',N'bit',1,1,0,0,0,1),
(N'goods',N'price',N'decimal',9,10,2,1,0,0),
(N'goods',N'stock_total',N'int',4,10,0,0,0,1),
(N'goods',N'reserved_qty',N'int',4,10,0,0,0,1),
(N'goods',N'created_by',N'varchar',11,0,0,0,0,0),
(N'goods',N'created_at',N'datetime2',8,27,7,0,0,1),
(N'goods',N'updated_by',N'varchar',11,0,0,1,0,0),
(N'goods',N'updated_at',N'datetime2',8,27,7,1,0,0),
(N'book',N'isbn',N'varchar',17,0,0,0,0,0),
(N'book',N'author',N'nvarchar',200,0,0,0,0,0),
(N'book',N'publisher',N'nvarchar',200,0,0,0,0,0),
(N'book',N'page_count',N'int',4,10,0,0,0,0),
(N'toy',N'inner_code',N'varchar',20,0,0,0,0,0),
(N'toy',N'spec',N'nvarchar',200,0,0,0,0,0),
(N'supplier',N'id',N'bigint',8,19,0,0,1,0),
(N'supplier',N'name',N'nvarchar',200,0,0,0,0,0),
(N'supplier',N'created_by',N'varchar',11,0,0,0,0,0),
(N'supplier',N'created_at',N'datetime2',8,27,7,0,0,1),
(N'supplier_quote',N'supplier_id',N'bigint',8,19,0,0,0,0),
(N'supplier_quote',N'goods_id',N'bigint',8,19,0,0,0,0),
(N'supplier_quote',N'quote_amount',N'decimal',9,10,2,0,0,0),
(N'supplier_quote',N'reported_by',N'varchar',11,0,0,0,0,0),
(N'supplier_quote',N'reported_at',N'datetime2',8,27,7,0,0,1),
(N'stock_movement',N'id',N'bigint',8,19,0,0,1,0),
(N'stock_movement',N'goods_id',N'bigint',8,19,0,0,0,0),
(N'stock_movement',N'change_type',N'nvarchar',20,0,0,0,0,0),
(N'stock_movement',N'quantity',N'int',4,10,0,0,0,0),
(N'stock_movement',N'note',N'nvarchar',400,0,0,1,0,0),
(N'stock_movement',N'changed_by',N'varchar',11,0,0,0,0,0),
(N'stock_movement',N'changed_at',N'datetime2',8,27,7,0,0,1),
(N'stock_movement',N'request_id',N'bigint',8,19,0,1,0,0),
(N'stock_movement',N'sale_id',N'bigint',8,19,0,1,0,0),
(N'stock_movement',N'return_item_id',N'bigint',8,19,0,1,0,0),
(N'purchase_request',N'id',N'bigint',8,19,0,0,1,0),
(N'purchase_request',N'no',N'varchar',20,0,0,0,0,0),
(N'purchase_request',N'supplier_id',N'bigint',8,19,0,0,0,0),
(N'purchase_request',N'status',N'nvarchar',20,0,0,0,0,1),
(N'purchase_request',N'created_by',N'varchar',11,0,0,0,0,0),
(N'purchase_request',N'created_at',N'datetime2',8,27,7,0,0,1),
(N'purchase_request',N'submitted_by',N'varchar',11,0,0,1,0,0),
(N'purchase_request',N'submitted_at',N'datetime2',8,27,7,1,0,0),
(N'purchase_request',N'approved_by',N'varchar',11,0,0,1,0,0),
(N'purchase_request',N'approved_at',N'datetime2',8,27,7,1,0,0),
(N'purchase_request',N'cancelled_by',N'varchar',11,0,0,1,0,0),
(N'purchase_request',N'cancelled_at',N'datetime2',8,27,7,1,0,0),
(N'purchase_request_item',N'id',N'bigint',8,19,0,0,1,0),
(N'purchase_request_item',N'request_id',N'bigint',8,19,0,0,0,0),
(N'purchase_request_item',N'goods_id',N'bigint',8,19,0,0,0,0),
(N'purchase_request_item',N'request_qty',N'int',4,10,0,0,0,0),
(N'purchase_request_item',N'unit_cost',N'decimal',9,10,2,0,0,0),
(N'sale',N'id',N'bigint',8,19,0,0,1,0),
(N'sale',N'no',N'varchar',20,0,0,0,0,0),
(N'sale',N'status',N'nvarchar',20,0,0,0,0,1),
(N'sale',N'cashier_by',N'varchar',11,0,0,0,0,0),
(N'sale',N'sold_at',N'datetime2',8,27,7,0,0,1),
(N'sale',N'card_level',N'nvarchar',20,0,0,1,0,0),
(N'sale',N'member_phone',N'varchar',11,0,0,1,0,0),
(N'sale',N'reservation_id',N'bigint',8,19,0,1,0,0),
(N'sale',N'subtotal_amount',N'decimal',9,10,2,0,0,0),
(N'sale',N'discount_rate',N'decimal',5,3,2,0,0,1),
(N'sale',N'point_deduction_amount',N'decimal',9,10,2,0,0,1),
(N'sale',N'paid_amount',N'decimal',9,10,2,0,0,0),
(N'sale_item',N'id',N'bigint',8,19,0,0,1,0),
(N'sale_item',N'sale_id',N'bigint',8,19,0,0,0,0),
(N'sale_item',N'goods_id',N'bigint',8,19,0,0,0,0),
(N'sale_item',N'quantity',N'int',4,10,0,0,0,0),
(N'sale_item',N'unit_price',N'decimal',9,10,2,0,0,0),
(N'reservation',N'id',N'bigint',8,19,0,0,1,0),
(N'reservation',N'code',N'varchar',20,0,0,0,0,0),
(N'reservation',N'phone',N'varchar',11,0,0,0,0,0),
(N'reservation',N'status',N'nvarchar',20,0,0,0,0,1),
(N'reservation',N'created_at',N'datetime2',8,27,7,0,0,1),
(N'reservation',N'expires_at',N'datetime2',8,27,7,0,0,0),
(N'reservation',N'cancelled_by_employee',N'varchar',11,0,0,1,0,0),
(N'reservation',N'cancelled_at',N'datetime2',8,27,7,1,0,0),
(N'reservation_item',N'id',N'bigint',8,19,0,0,1,0),
(N'reservation_item',N'reservation_id',N'bigint',8,19,0,0,0,0),
(N'reservation_item',N'goods_id',N'bigint',8,19,0,0,0,0),
(N'reservation_item',N'quantity',N'int',4,10,0,0,0,0),
(N'goods_return',N'id',N'bigint',8,19,0,0,1,0),
(N'goods_return',N'no',N'varchar',20,0,0,0,0,0),
(N'goods_return',N'sale_id',N'bigint',8,19,0,0,0,0),
(N'goods_return',N'refund_amount',N'decimal',9,10,2,0,0,0),
(N'goods_return',N'handled_by',N'varchar',11,0,0,0,0,0),
(N'goods_return',N'handled_at',N'datetime2',8,27,7,0,0,1),
(N'goods_return_item',N'id',N'bigint',8,19,0,0,1,0),
(N'goods_return_item',N'return_id',N'bigint',8,19,0,0,0,0),
(N'goods_return_item',N'sale_item_id',N'bigint',8,19,0,0,0,0),
(N'goods_return_item',N'quantity',N'int',4,10,0,0,0,0),
(N'goods_return_item',N'refund_amount',N'decimal',9,10,2,0,0,0),
(N'card_type',N'level',N'nvarchar',20,0,0,0,0,0),
(N'card_type',N'card_fee',N'decimal',9,10,2,0,0,0),
(N'card_type',N'discount_rate',N'decimal',5,3,2,0,0,0),
(N'card_type',N'set_by',N'varchar',11,0,0,0,0,0),
(N'card_type',N'set_at',N'datetime2',8,27,7,0,0,1),
(N'member',N'phone',N'varchar',11,0,0,0,0,0),
(N'member',N'card_level',N'nvarchar',20,0,0,0,0,0),
(N'member',N'opened_by',N'varchar',11,0,0,0,0,0),
(N'member',N'opened_at',N'datetime2',8,27,7,0,0,1),
(N'member',N'updated_by',N'varchar',11,0,0,1,0,0),
(N'member',N'updated_at',N'datetime2',8,27,7,1,0,0),
(N'member',N'expires_at',N'date',3,10,0,0,0,0),
(N'member',N'points_balance',N'int',4,10,0,0,0,1),
(N'point_movement',N'id',N'bigint',8,19,0,0,1,0),
(N'point_movement',N'member_phone',N'varchar',11,0,0,0,0,0),
(N'point_movement',N'change_type',N'nvarchar',20,0,0,0,0,0),
(N'point_movement',N'points',N'int',4,10,0,0,0,0),
(N'point_movement',N'sale_id',N'bigint',8,19,0,1,0,0),
(N'point_movement',N'return_id',N'bigint',8,19,0,1,0,0),
(N'point_movement',N'changed_by',N'varchar',11,0,0,0,0,0),
(N'point_movement',N'changed_at',N'datetime2',8,27,7,0,0,1),
(N'fund_flow',N'id',N'bigint',8,19,0,0,1,0),
(N'fund_flow',N'amount',N'decimal',9,10,2,0,0,0),
(N'fund_flow',N'direction',N'nvarchar',4,0,0,0,0,0),
(N'fund_flow',N'reason_type',N'nvarchar',20,0,0,0,0,0),
(N'fund_flow',N'sale_id',N'bigint',8,19,0,1,0,0),
(N'fund_flow',N'return_id',N'bigint',8,19,0,1,0,0),
(N'fund_flow',N'request_id',N'bigint',8,19,0,1,0,0),
(N'fund_flow',N'member_phone',N'varchar',11,0,0,1,0,0),
(N'fund_flow',N'fund_before',N'decimal',9,12,2,0,0,0),
(N'fund_flow',N'fund_after',N'decimal',9,12,2,0,0,0),
(N'fund_flow',N'recorded_by',N'varchar',11,0,0,0,0,0),
(N'fund_flow',N'recorded_at',N'datetime2',8,27,7,0,0,1),
(N'employee',N'phone',N'varchar',11,0,0,0,0,0),
(N'employee',N'name',N'nvarchar',40,0,0,0,0,0),
(N'employee',N'role',N'nvarchar',20,0,0,0,0,0),
(N'employee',N'created_by',N'varchar',11,0,0,0,0,0),
(N'employee',N'created_at',N'datetime2',8,27,7,0,0,1),
(N'employee',N'updated_by',N'varchar',11,0,0,1,0,0),
(N'employee',N'updated_at',N'datetime2',8,27,7,1,0,0);
IF EXISTS (
    SELECT table_name,column_name,type_name,max_length,precision_value,scale_value,nullable,identity_value,has_default FROM @expected_columns
    EXCEPT
    SELECT t.name,c.name,TYPE_NAME(c.user_type_id),c.max_length,c.precision,c.scale,c.is_nullable,c.is_identity,CAST(CASE WHEN c.default_object_id=0 THEN 0 ELSE 1 END AS bit)
    FROM sys.columns c JOIN sys.tables t ON c.object_id=t.object_id WHERE t.schema_id=SCHEMA_ID(N'dbo')
) OR (SELECT COUNT(*) FROM sys.columns c JOIN sys.tables t ON c.object_id=t.object_id WHERE t.schema_id=SCHEMA_ID(N'dbo'))<>(SELECT COUNT(*) FROM @expected_columns)
    THROW 51203, N'字段类型、长度、精度、可空、默认值存在性或自增属性与字典不一致。', 1;
DECLARE @expected_fk TABLE (parent_table sysname,parent_column sysname,referenced_table sysname,referenced_column sysname);
INSERT @expected_fk VALUES
(N'goods',N'book_isbn',N'book',N'isbn'),
(N'goods',N'toy_code',N'toy',N'inner_code'),
(N'goods',N'created_by',N'employee',N'phone'),
(N'goods',N'updated_by',N'employee',N'phone'),
(N'supplier',N'created_by',N'employee',N'phone'),
(N'supplier_quote',N'supplier_id',N'supplier',N'id'),
(N'supplier_quote',N'goods_id',N'goods',N'id'),
(N'supplier_quote',N'reported_by',N'employee',N'phone'),
(N'stock_movement',N'goods_id',N'goods',N'id'),
(N'stock_movement',N'changed_by',N'employee',N'phone'),
(N'stock_movement',N'request_id',N'purchase_request',N'id'),
(N'stock_movement',N'sale_id',N'sale',N'id'),
(N'stock_movement',N'return_item_id',N'goods_return_item',N'id'),
(N'purchase_request',N'supplier_id',N'supplier',N'id'),
(N'purchase_request',N'created_by',N'employee',N'phone'),
(N'purchase_request',N'submitted_by',N'employee',N'phone'),
(N'purchase_request',N'approved_by',N'employee',N'phone'),
(N'purchase_request',N'cancelled_by',N'employee',N'phone'),
(N'purchase_request_item',N'request_id',N'purchase_request',N'id'),
(N'purchase_request_item',N'goods_id',N'goods',N'id'),
(N'sale',N'cashier_by',N'employee',N'phone'),
(N'sale',N'member_phone',N'member',N'phone'),
(N'sale',N'reservation_id',N'reservation',N'id'),
(N'sale_item',N'sale_id',N'sale',N'id'),
(N'sale_item',N'goods_id',N'goods',N'id'),
(N'reservation',N'cancelled_by_employee',N'employee',N'phone'),
(N'reservation_item',N'reservation_id',N'reservation',N'id'),
(N'reservation_item',N'goods_id',N'goods',N'id'),
(N'goods_return',N'sale_id',N'sale',N'id'),
(N'goods_return',N'handled_by',N'employee',N'phone'),
(N'goods_return_item',N'return_id',N'goods_return',N'id'),
(N'goods_return_item',N'sale_item_id',N'sale_item',N'id'),
(N'card_type',N'set_by',N'employee',N'phone'),
(N'member',N'card_level',N'card_type',N'level'),
(N'member',N'opened_by',N'employee',N'phone'),
(N'member',N'updated_by',N'employee',N'phone'),
(N'point_movement',N'member_phone',N'member',N'phone'),
(N'point_movement',N'sale_id',N'sale',N'id'),
(N'point_movement',N'return_id',N'goods_return',N'id'),
(N'point_movement',N'changed_by',N'employee',N'phone'),
(N'fund_flow',N'sale_id',N'sale',N'id'),
(N'fund_flow',N'return_id',N'goods_return',N'id'),
(N'fund_flow',N'request_id',N'purchase_request',N'id'),
(N'fund_flow',N'member_phone',N'member',N'phone'),
(N'fund_flow',N'recorded_by',N'employee',N'phone'),
(N'employee',N'created_by',N'employee',N'phone'),
(N'employee',N'updated_by',N'employee',N'phone');
IF (SELECT COUNT(*) FROM sys.foreign_keys)<>47 OR EXISTS (
    SELECT * FROM @expected_fk EXCEPT
    SELECT OBJECT_NAME(f.parent_object_id),COL_NAME(f.parent_object_id,f.parent_column_id),OBJECT_NAME(f.referenced_object_id),COL_NAME(f.referenced_object_id,f.referenced_column_id)
    FROM sys.foreign_key_columns f
) THROW 51204, N'外键数量或引用列不符。', 1;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
 OR EXISTS (SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
    THROW 51205, N'存在禁用或未信任约束。', 1;
IF (SELECT COUNT(*) FROM sys.key_constraints WHERE type='PK')<>19
 OR (SELECT COUNT(*) FROM sys.key_constraints WHERE type='UQ')<>9
    THROW 51206, N'主键或业务唯一约束数量不符。', 1;
IF EXISTS (SELECT 1 FROM sys.columns c JOIN sys.tables t ON c.object_id=t.object_id
    LEFT JOIN sys.extended_properties p ON p.major_id=c.object_id AND p.minor_id=c.column_id AND p.name=N'MS_Description'
    WHERE t.schema_id=SCHEMA_ID(N'dbo') AND p.value IS NULL)
    THROW 51207, N'字段含义缺少扩展属性。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[goods])<>4 THROW 51208, N'goods 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[book])<>2 THROW 51208, N'book 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[toy])<>2 THROW 51208, N'toy 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[supplier])<>3 THROW 51208, N'supplier 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[supplier_quote])<>5 THROW 51208, N'supplier_quote 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[stock_movement])<>12 THROW 51208, N'stock_movement 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[purchase_request])<>3 THROW 51208, N'purchase_request 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[purchase_request_item])<>5 THROW 51208, N'purchase_request_item 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[sale])<>3 THROW 51208, N'sale 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[sale_item])<>4 THROW 51208, N'sale_item 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[reservation])<>2 THROW 51208, N'reservation 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[reservation_item])<>2 THROW 51208, N'reservation_item 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[goods_return])<>2 THROW 51208, N'goods_return 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[goods_return_item])<>2 THROW 51208, N'goods_return_item 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[card_type])<>2 THROW 51208, N'card_type 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[member])<>2 THROW 51208, N'member 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[point_movement])<>5 THROW 51208, N'point_movement 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[fund_flow])<>13 THROW 51208, N'fund_flow 样例行数不符。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.[employee])<>4 THROW 51208, N'employee 样例行数不符。', 1;

-- 跨表、跨行关系是验证查询，不是假称已由 CHECK 自动维护。
IF EXISTS (SELECT 1 FROM dbo.goods g OUTER APPLY
    (SELECT SUM(CONVERT(bigint,quantity)) n FROM dbo.stock_movement WHERE goods_id=g.id) m
    OUTER APPLY (SELECT SUM(CONVERT(bigint,i.quantity)) n FROM dbo.reservation_item i
        JOIN dbo.reservation r ON r.id=i.reservation_id WHERE i.goods_id=g.id AND r.status=N'有效') r
    WHERE g.stock_total<>COALESCE(m.n,0) OR g.reserved_qty<>COALESCE(r.n,0))
    THROW 51210, N'库存或已订量与明细不一致。', 1;
IF EXISTS (SELECT 1 FROM dbo.member m OUTER APPLY
    (SELECT SUM(CONVERT(bigint,points)) n FROM dbo.point_movement WHERE member_phone=m.phone) p
    WHERE m.points_balance<>COALESCE(p.n,0))
    THROW 51211, N'积分余额与流水不一致。', 1;
IF EXISTS (SELECT 1 FROM dbo.sale s OUTER APPLY
    (SELECT SUM(unit_price*quantity) amount FROM dbo.sale_item WHERE sale_id=s.id) i
    WHERE s.subtotal_amount<>COALESCE(i.amount,0))
    THROW 51212, N'销售单与明细金额不一致。', 1;
IF EXISTS (SELECT 1 FROM dbo.goods_return r OUTER APPLY
    (SELECT SUM(refund_amount) amount FROM dbo.goods_return_item WHERE return_id=r.id) i
    WHERE r.refund_amount<>COALESCE(i.amount,0))
 OR EXISTS (SELECT 1 FROM dbo.goods_return_item i JOIN dbo.goods_return r ON r.id=i.return_id
    JOIN dbo.sale_item s ON s.id=i.sale_item_id WHERE r.sale_id<>s.sale_id)
 OR EXISTS (SELECT 1 FROM dbo.sale_item s JOIN dbo.goods_return_item i ON i.sale_item_id=s.id
    GROUP BY s.id,s.quantity HAVING SUM(i.quantity)>s.quantity)
    THROW 51213, N'退货金额、原单归属或累计数量不一致。', 1;
IF EXISTS (SELECT 1 FROM dbo.sale s OUTER APPLY
    (SELECT SUM(refund_amount) amount FROM dbo.goods_return WHERE sale_id=s.id) r
    WHERE COALESCE(r.amount,0)>s.paid_amount OR s.status<>
    CASE WHEN COALESCE(r.amount,0)=0 THEN N'已付' WHEN r.amount=s.paid_amount THEN N'已全退' ELSE N'部分退款' END)
    THROW 51214, N'累计退款或销售状态不一致。', 1;
IF EXISTS (SELECT 1 FROM dbo.point_movement p JOIN dbo.goods_return r ON r.id=p.return_id
    JOIN dbo.sale s ON s.id=r.sale_id WHERE p.sale_id<>r.sale_id OR p.member_phone<>s.member_phone OR s.member_phone IS NULL)
    THROW 51215, N'退货积分关联原单或会员错误。', 1;
IF EXISTS (SELECT 1 FROM dbo.fund_flow f JOIN dbo.goods_return r ON r.id=f.return_id
    WHERE f.sale_id<>r.sale_id OR f.amount<>r.refund_amount)
    THROW 51216, N'退款流水与退货单不符。', 1;
IF EXISTS (SELECT 1 FROM dbo.sale s OUTER APPLY
    (SELECT COUNT(*) n,SUM(amount) amount FROM dbo.fund_flow WHERE sale_id=s.id AND reason_type=N'销售收款') f
    WHERE f.n<>1 OR f.amount<>s.paid_amount)
    THROW 51217, N'销售收款不符。', 1;
IF EXISTS (SELECT 1 FROM dbo.goods_return r OUTER APPLY
    (SELECT COUNT(*) n,SUM(amount) amount FROM dbo.fund_flow WHERE return_id=r.id) f
    WHERE (r.refund_amount>0 AND (f.n<>1 OR f.amount<>r.refund_amount)) OR (r.refund_amount=0 AND f.n<>0))
    THROW 51218, N'退款笔数或金额不符。', 1;
IF EXISTS (SELECT 1 FROM dbo.purchase_request p OUTER APPLY
    (SELECT SUM(request_qty*unit_cost) amount FROM dbo.purchase_request_item WHERE request_id=p.id) i
    OUTER APPLY (SELECT COUNT(*) n,SUM(amount) amount,MIN(recorded_at) paid_at FROM dbo.fund_flow WHERE request_id=p.id) f
    OUTER APPLY (SELECT MIN(changed_at) received_at FROM dbo.stock_movement WHERE request_id=p.id) m
    WHERE p.status=N'已收货' AND (f.n<>1 OR f.amount<>i.amount OR f.paid_at<p.approved_at OR f.paid_at>m.received_at))
 OR EXISTS (SELECT 1 FROM dbo.purchase_request_item i JOIN dbo.purchase_request p ON p.id=i.request_id
    OUTER APPLY (SELECT SUM(quantity) n FROM dbo.stock_movement WHERE request_id=i.request_id AND goods_id=i.goods_id) m
    WHERE p.status=N'已收货' AND COALESCE(m.n,0)<>i.request_qty)
    THROW 51219, N'采购付款、时序或足量入库不一致。', 1;
IF EXISTS (SELECT 1 FROM dbo.goods_return_item i JOIN dbo.sale_item s ON s.id=i.sale_item_id
    OUTER APPLY (SELECT SUM(quantity) n FROM dbo.stock_movement WHERE return_item_id=i.id AND goods_id=s.goods_id) m
    WHERE COALESCE(m.n,0)<>i.quantity)
 OR EXISTS (SELECT 1 FROM dbo.sale_item s OUTER APPLY
    (SELECT SUM(quantity) n FROM dbo.stock_movement WHERE sale_id=s.sale_id AND goods_id=s.goods_id) m
    WHERE COALESCE(m.n,0)<>-s.quantity)
    THROW 51220, N'销售或退货数量与库存流水不一致。', 1;
IF EXISTS (SELECT 1 FROM dbo.stock_movement m JOIN dbo.employee e ON e.phone=m.changed_by
    WHERE e.role<>CASE WHEN m.change_type=N'卖出' THEN N'收银员' ELSE N'库管' END)
 OR EXISTS (SELECT 1 FROM dbo.fund_flow f JOIN dbo.employee e ON e.phone=f.recorded_by
    WHERE e.role<>CASE WHEN f.reason_type IN (N'采购付款',N'注资',N'提现') THEN N'店长' ELSE N'收银员' END)
    THROW 51221, N'样例操作人角色不符。', 1;
IF EXISTS (SELECT 1 FROM dbo.card_type silver CROSS JOIN dbo.card_type gold
    WHERE silver.level=N'银卡' AND gold.level=N'金卡' AND (gold.card_fee<=silver.card_fee OR gold.discount_rate>silver.discount_rate))
    THROW 51222, N'卡费或折扣档位顺序不符。', 1;
IF EXISTS (SELECT 1 FROM (SELECT fund_before,
    LAG(fund_after,1,CONVERT(decimal(12,2),0)) OVER(ORDER BY recorded_at,id) previous_after FROM dbo.fund_flow) x
    WHERE x.fund_before<>x.previous_after)
    THROW 51223, N'资金链不连续。', 1;
DECLARE @cash decimal(12,2), @profit decimal(12,2);
SELECT @cash=SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END),
    @profit=SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0 WHEN direction=N'收' THEN amount ELSE -amount END)
    FROM dbo.fund_flow;
IF @cash<>1430.30 OR @profit<>-69.70 THROW 51224, N'基线余额或盈亏错误。', 1;
SELECT N'baseline' AS check_name,19 AS tables,47 AS foreign_keys,77 AS sample_rows,@cash AS cash_balance,@profit AS operating_result;

-- 基础约束正例：默认值和两种可空销售关联都能实际装载。
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.toy (inner_code,spec) VALUES ('VERIFY-W3',N'基础约束正例');
    INSERT dbo.goods (category,name,toy_code,created_by) VALUES (N'文创',N'正例商品','VERIFY-W3','13800000002');
    DECLARE @good bigint=SCOPE_IDENTITY();
    IF NOT EXISTS (SELECT 1 FROM dbo.goods WHERE id=@good AND on_shelf=0 AND stock_total=0 AND reserved_qty=0 AND price IS NULL AND created_at IS NOT NULL)
        THROW 51225, N'默认值正例未通过。', 1;
    -- 仅验证列约束的可空组合，不把这个未提交单头当作完整业务交易。
    INSERT dbo.sale (no,cashier_by,card_level,member_phone,reservation_id,subtotal_amount,discount_rate,point_deduction_amount,paid_amount)
        VALUES ('VERIFY-W3-S','13800000003',N'金卡','13900000001',2,10,0.9,0,9);
    ROLLBACK;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;

-- 每个反例独立事务：必须得到指定错误号，否则验证失败；所有更改回滚。
DECLARE @cases TABLE (case_id int IDENTITY PRIMARY KEY, label nvarchar(100), sql_text nvarchar(max), expected_error int);
INSERT @cases(label,sql_text,expected_error) VALUES
(N'主键重复',N'INSERT dbo.book(isbn,author,publisher,page_count) SELECT isbn,author,publisher,page_count FROM dbo.book WHERE isbn=''9787506365437''',2627),
(N'业务唯一键重复',N'INSERT dbo.supplier(name,created_by) SELECT name,created_by FROM dbo.supplier WHERE id=1',2627),
(N'外键不存在',N'INSERT dbo.supplier_quote(supplier_id,goods_id,quote_amount,reported_by) VALUES(999999,1,10,''13800000002'')',547),
(N'非空约束',N'INSERT dbo.toy(inner_code,spec) VALUES(''INVALID-W3'',NULL)',515),
(N'价格必须正数',N'UPDATE dbo.goods SET price=-1 WHERE id=1',547),
(N'类别与细节互斥',N'UPDATE dbo.goods SET toy_code=''SP-BAG-001'' WHERE id=1',547),
(N'已订不能超过在架',N'UPDATE dbo.goods SET reserved_qty=7 WHERE id=1',547),
(N'报损必须原因',N'UPDATE dbo.stock_movement SET note=NULL WHERE id=12',547),
(N'预订恰好三天',N'UPDATE dbo.reservation SET expires_at=DATEADD(day,4,created_at) WHERE id=2',547),
(N'取消态不得保留审批信息',N'UPDATE dbo.purchase_request SET status=N''已取消'',cancelled_by=''13800000001'',cancelled_at=SYSDATETIME() WHERE id=1',547),
(N'抵扣超百分之二十',N'UPDATE dbo.sale SET point_deduction_amount=19,paid_amount=73.15 WHERE id=2',547),
(N'卡费必须大于零',N'UPDATE dbo.card_type SET card_fee=0 WHERE level=N''银卡''',547),
(N'资金前后金额一致',N'UPDATE dbo.fund_flow SET fund_after=fund_after+1 WHERE id=1',547),
(N'操作人与时刻成对',N'UPDATE dbo.member SET updated_at=NULL WHERE phone=''13900000001''',547),
(N'手机格式',N'INSERT dbo.employee(phone,name,role,created_by) VALUES(''123'',N''非法账号'',N''收银员'',''13800000001'')',547),
(N'流水来源必填',N'UPDATE dbo.stock_movement SET request_id=NULL WHERE id=1',547);
DECLARE @id int=1,@label nvarchar(100),@sql nvarchar(max),@expected int,@actual int;
DECLARE @results TABLE (case_id int,label nvarchar(100),actual_error int,result varchar(10));
WHILE @id<=(SELECT COUNT(*) FROM @cases)
BEGIN
    SELECT @label=label,@sql=sql_text,@expected=expected_error FROM @cases WHERE case_id=@id;
    SET @actual=0;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC sys.sp_executesql @sql;
        ROLLBACK;
    END TRY
    BEGIN CATCH
        SET @actual=ERROR_NUMBER();
        IF XACT_STATE()<>0 ROLLBACK;
    END CATCH;
    IF @actual<>@expected
    BEGIN
        DECLARE @message nvarchar(2048)=CONCAT(@label,N'：预期错误 ',@expected,N'，实际 ',@actual);
        THROW 51230,@message,1;
    END;
    INSERT @results VALUES(@id,@label,@actual,'PASS');
    SET @id+=1;
END;
SELECT * FROM @results ORDER BY case_id;
PRINT N'verify.sql PASS: metadata, baseline reconciliation, defaults and 16 negative cases.';
