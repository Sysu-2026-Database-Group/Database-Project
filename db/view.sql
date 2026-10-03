:On Error exit
-- Week 4 views. Run after schema.sql and sample-data.sql.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW dbo.[v_sale_detail]
AS
SELECT
    s.[id] AS sale_id,
    s.[no] AS sale_no,
    s.[sold_at],
    s.[status] AS sale_status,
    s.[member_phone],
    si.[id] AS sale_item_id,
    si.[goods_id],
    g.[name] AS goods_name,
    si.[quantity],
    si.[unit_price],
    CAST(si.[quantity] * si.[unit_price] AS DECIMAL(12,2)) AS line_amount
FROM dbo.[sale] AS s
JOIN dbo.[sale_item] AS si ON si.[sale_id] = s.[id]
JOIN dbo.[goods] AS g ON g.[id] = si.[goods_id];
GO

CREATE OR ALTER VIEW dbo.[v_goods_sales_summary]
AS
SELECT
    g.[id] AS goods_id,
    g.[name] AS goods_name,
    g.[category],
    COALESCE(SUM(si.[quantity]), 0) AS sold_quantity,
    CAST(COALESCE(SUM(si.[quantity] * si.[unit_price]), 0.00) AS DECIMAL(12,2)) AS gross_sales_amount
FROM dbo.[goods] AS g
LEFT JOIN dbo.[sale_item] AS si ON si.[goods_id] = g.[id]
GROUP BY g.[id], g.[name], g.[category];
GO

CREATE OR ALTER VIEW dbo.[v_inventory_status]
AS
SELECT
    g.[id] AS goods_id,
    g.[name] AS goods_name,
    g.[category],
    g.[on_shelf],
    g.[price],
    g.[stock_total],
    g.[reserved_qty],
    g.[stock_total] - g.[reserved_qty] AS available_qty,
    CASE WHEN g.[on_shelf] = 1 AND g.[price] IS NOT NULL
              AND g.[stock_total] - g.[reserved_qty] > 0
         THEN CONVERT(bit, 1) ELSE CONVERT(bit, 0) END AS is_sellable
FROM dbo.[goods] AS g;
GO

-- View verification: each view must be queried after creation.
SELECT TOP (20) * FROM dbo.[v_sale_detail] ORDER BY sale_id, sale_item_id;
SELECT TOP (20) * FROM dbo.[v_goods_sales_summary] ORDER BY goods_id;
SELECT TOP (20) * FROM dbo.[v_inventory_status] ORDER BY goods_id;
GO

PRINT N'view.sql PASS';
GO
