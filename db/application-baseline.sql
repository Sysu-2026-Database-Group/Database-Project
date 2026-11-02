:On Error exit
-- Current application installation only; no seed data or demonstration writes.
-- Historical constraint.sql/view.sql remain the course evidence sources.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek6Runner%'
   AND DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%'
    THROW 52200, N'Application baseline requires a dedicated Runner or Week7 database.', 1;
IF @@TRANCOUNT <> 0 THROW 52200, N'Installation requires no outer transaction.', 1;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NULL
    THROW 52200, N'Week6 migration must be installed first.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.schema_migration
    WHERE migration_key='W6-NORMALIZATION-1.0' AND status=N'已完成')
    THROW 52200, N'Week6 migration completion record is missing.', 1;
IF EXISTS (SELECT 1 FROM dbo.card_type s CROSS JOIN dbo.card_type g
    WHERE s.level=N'银卡' AND g.level=N'金卡'
      AND (g.card_fee<=s.card_fee OR g.discount_rate>s.discount_rate))
    THROW 52200, N'Existing card tier configuration is invalid; no data was changed.', 1;
BEGIN TRANSACTION;
GO
CREATE OR ALTER TRIGGER dbo.tr_card_type_cross_row
ON dbo.card_type AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.card_type s JOIN dbo.card_type g
        ON s.level=N'银卡' AND g.level=N'金卡'
        WHERE g.card_fee<=s.card_fee OR g.discount_rate>s.discount_rate)
        THROW 51025, 'Card tier relation is invalid.', 1;
END;
GO
ENABLE TRIGGER dbo.tr_card_type_cross_row ON dbo.card_type;
GO
CREATE OR ALTER VIEW dbo.v_sale_detail AS
SELECT s.id AS sale_id,s.no AS sale_no,s.sold_at,s.status AS sale_status,
    s.member_phone,si.id AS sale_item_id,si.goods_id,g.name AS goods_name,
    si.quantity,si.unit_price,
    CAST(si.quantity*si.unit_price AS decimal(12,2)) AS line_amount
FROM dbo.sale s JOIN dbo.sale_item si ON si.sale_id=s.id
JOIN dbo.goods g ON g.id=si.goods_id;
GO
CREATE OR ALTER VIEW dbo.v_goods_sales_summary AS
SELECT g.id AS goods_id,g.name AS goods_name,g.category,
    COALESCE(SUM(si.quantity),0) AS sold_quantity,
    CAST(COALESCE(SUM(si.quantity*si.unit_price),0.00) AS decimal(12,2)) AS gross_sales_amount
FROM dbo.goods g LEFT JOIN dbo.sale_item si ON si.goods_id=g.id
GROUP BY g.id,g.name,g.category;
GO
CREATE OR ALTER VIEW dbo.v_inventory_status AS
SELECT g.id AS goods_id,g.name AS goods_name,g.category,g.on_shelf,g.price,
    g.stock_total,g.reserved_qty,g.stock_total-g.reserved_qty AS available_qty,
    CASE WHEN g.on_shelf=1 AND g.price IS NOT NULL AND g.stock_total-g.reserved_qty>0
        THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END AS is_sellable
FROM dbo.goods g;
GO
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'bookstore_application_baseline')
    EXEC sys.sp_updateextendedproperty @name=N'bookstore_application_baseline',@value=N'1';
ELSE
    EXEC sys.sp_addextendedproperty @name=N'bookstore_application_baseline',@value=N'1';
COMMIT;
PRINT N'application-baseline.sql PASS';
GO
