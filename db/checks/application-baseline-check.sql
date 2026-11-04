:On Error exit
-- Read-only structural checks. No historical sample counts are assumed.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.schema_migration',N'U') IS NULL
    THROW 52201, N'Missing migration table.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.schema_migration
    WHERE migration_key='W6-NORMALIZATION-1.0' AND status=N'已完成')
    THROW 52201, N'Missing completed Week6 migration.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
    WHERE class=0 AND name=N'bookstore_application_baseline' AND CONVERT(nvarchar(20),value)=N'1')
    THROW 52201, N'Missing application baseline version 1; run application-baseline.sql on the designated copy.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.triggers WHERE object_id=OBJECT_ID(N'dbo.tr_card_type_cross_row',N'TR')
    AND parent_id=OBJECT_ID(N'dbo.card_type') AND is_disabled=0 AND is_not_for_replication=0)
    THROW 52201, N'Missing or disabled card tier trigger.', 1;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
   OR EXISTS (SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
    THROW 52201, N'Disabled or untrusted business constraints.', 1;
DECLARE @tables TABLE(name sysname);
INSERT @tables VALUES ('employee'),('supplier'),('supplier_quote'),('goods'),('book'),('toy'),
    ('card_type'),('member'),('purchase_request'),('purchase_request_item'),('sale'),('sale_item'),
    ('reservation'),('reservation_item'),('goods_return'),('goods_return_item'),
    ('stock_movement'),('point_movement'),('fund_flow');
IF EXISTS (SELECT 1 FROM @tables WHERE OBJECT_ID(N'dbo.'+name,N'U') IS NULL)
    THROW 52201, N'Missing business table.', 1;
DECLARE @indexes TABLE(table_name sysname,index_name sysname);
INSERT @indexes VALUES ('goods','UX_goods_book_isbn'),('goods','UX_goods_toy_code'),
    ('sale','UX_sale_reservation_id'),('point_movement','UX_point_movement_earn'),
    ('point_movement','UX_point_movement_use'),('point_movement','UX_point_movement_return');
IF EXISTS (SELECT 1 FROM @indexes r LEFT JOIN sys.indexes i
    ON i.object_id=OBJECT_ID(N'dbo.'+r.table_name) AND i.name=r.index_name
    WHERE i.index_id IS NULL OR i.is_unique<>1 OR i.has_filter<>1 OR i.is_disabled=1)
    THROW 52201, N'Missing or disabled business unique index.', 1;
IF COL_LENGTH(N'dbo.supplier',N'updated_by') IS NULL
    OR COL_LENGTH(N'dbo.supplier',N'updated_at') IS NULL
    OR COL_LENGTH(N'dbo.goods',N'reserved_qty') IS NULL
    THROW 52201, N'Missing application columns.', 1;
IF OBJECT_ID(N'dbo.v_sale_detail',N'V') IS NULL
    OR OBJECT_ID(N'dbo.v_goods_sales_summary',N'V') IS NULL
    OR OBJECT_ID(N'dbo.v_inventory_status',N'V') IS NULL
    THROW 52201, N'Missing application view.', 1;
-- Compile all published columns, including empty databases.
EXEC(N'SELECT TOP(0) sale_id,sale_no,sold_at,sale_status,member_phone,sale_item_id,goods_id,
    goods_name,quantity,unit_price,line_amount FROM dbo.v_sale_detail');
EXEC(N'SELECT TOP(0) goods_id,goods_name,category,sold_quantity,gross_sales_amount FROM dbo.v_goods_sales_summary');
EXEC(N'SELECT TOP(0) goods_id,goods_name,category,on_shelf,price,stock_total,reserved_qty,available_qty,is_sellable
    FROM dbo.v_inventory_status');
PRINT N'application-baseline-check.sql PASS';
GO
