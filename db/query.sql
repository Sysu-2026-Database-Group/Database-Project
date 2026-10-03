:On Error exit
-- Week 4 query deliverable. Run after schema.sql and sample-data.sql.
-- The fixed as-of timestamp keeps results reproducible against the Week 3 seed.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;

DECLARE @AsOf DATETIME2 = '2026-09-20T12:00:00';

/* Q1. What was sold on each receipt, to whom, and at what snapshot price?
   LEFT JOIN keeps non-member sales in the result. */
SELECT
    s.[no] AS sale_no,
    s.[sold_at],
    COALESCE(m.[phone], 'NON_MEMBER') AS member_phone,
    g.[name] AS goods_name,
    si.[quantity],
    si.[unit_price],
    CAST(si.[quantity] * si.[unit_price] AS DECIMAL(12,2)) AS line_amount,
    s.[status] AS sale_status
FROM dbo.[sale] AS s
JOIN dbo.[sale_item] AS si ON si.[sale_id] = s.[id]
JOIN dbo.[goods] AS g ON g.[id] = si.[goods_id]
LEFT JOIN dbo.[member] AS m ON m.[phone] = s.[member_phone]
ORDER BY s.[sold_at], s.[id], si.[id];
GO

/* Q2. Which goods have sales, including goods with no sale rows?
   LEFT JOIN is required because an inner join would hide unsold goods. */
SELECT
    g.[id] AS goods_id,
    g.[name] AS goods_name,
    g.[category],
    COALESCE(SUM(si.[quantity]), 0) AS sold_quantity,
    COALESCE(SUM(si.[quantity] * si.[unit_price]), 0.00) AS gross_sales_amount
FROM dbo.[goods] AS g
LEFT JOIN dbo.[sale_item] AS si ON si.[goods_id] = g.[id]
LEFT JOIN dbo.[sale] AS s ON s.[id] = si.[sale_id]
GROUP BY g.[id], g.[name], g.[category]
ORDER BY g.[id];
GO

/* Q3. What is the stock position at the Week 3 business cut-off?
   The reservation join counts only effective, unexpired reservations. */
DECLARE @AsOf DATETIME2 = '2026-09-20T12:00:00';

SELECT
    g.[id] AS goods_id,
    g.[name] AS goods_name,
    g.[stock_total],
    g.[reserved_qty],
    g.[stock_total] - g.[reserved_qty] AS available_qty,
    COALESCE(SUM(CASE WHEN r.[status] = NCHAR(26377) + NCHAR(25928) AND r.[expires_at] > @AsOf
                      THEN ri.[quantity] ELSE 0 END), 0) AS reservation_detail_qty,
    CASE WHEN g.[on_shelf] = 1 AND g.[price] IS NOT NULL
              AND g.[stock_total] - g.[reserved_qty] > 0
         THEN 'SELLABLE' ELSE 'NOT_SELLABLE' END AS saleability
FROM dbo.[goods] AS g
LEFT JOIN dbo.[reservation_item] AS ri ON ri.[goods_id] = g.[id]
LEFT JOIN dbo.[reservation] AS r ON r.[id] = ri.[reservation_id]
GROUP BY g.[id], g.[name], g.[stock_total], g.[reserved_qty], g.[on_shelf], g.[price]
ORDER BY g.[id];
GO

/* Q4. Which goods sold at least two units?  This demonstrates GROUP BY + HAVING. */
SELECT
    g.[id] AS goods_id,
    g.[name] AS goods_name,
    SUM(si.[quantity]) AS sold_quantity,
    CAST(SUM(si.[quantity] * si.[unit_price]) AS DECIMAL(12,2)) AS gross_sales_amount
FROM dbo.[goods] AS g
JOIN dbo.[sale_item] AS si ON si.[goods_id] = g.[id]
GROUP BY g.[id], g.[name]
HAVING SUM(si.[quantity]) >= 2
ORDER BY sold_quantity DESC, g.[id];
GO

/* Q5. Which members spent more than the average member spending?
   The scalar subquery supplies the comparison value. */
WITH member_spend AS (
    SELECT
        m.[phone],
        m.[card_level],
        SUM(s.[paid_amount]) AS paid_amount,
        COUNT_BIG(*) AS sale_count
    FROM dbo.[member] AS m
    JOIN dbo.[sale] AS s ON s.[member_phone] = m.[phone]
    GROUP BY m.[phone], m.[card_level]
)
SELECT
    [phone] AS member_phone,
    [card_level],
    [paid_amount],
    [sale_count]
FROM member_spend
WHERE [paid_amount] > (SELECT AVG(CAST([paid_amount] AS DECIMAL(12,2))) FROM member_spend)
ORDER BY [paid_amount] DESC;
GO

/* Q6. How do purchase requests connect suppliers, items, and quoted costs? */
SELECT
    pr.[no] AS purchase_no,
    su.[name] AS supplier_name,
    g.[name] AS goods_name,
    pri.[request_qty],
    pri.[unit_cost],
    sq.[quote_amount],
    pr.[status]
FROM dbo.[purchase_request] AS pr
JOIN dbo.[supplier] AS su ON su.[id] = pr.[supplier_id]
JOIN dbo.[purchase_request_item] AS pri ON pri.[request_id] = pr.[id]
JOIN dbo.[goods] AS g ON g.[id] = pri.[goods_id]
LEFT JOIN dbo.[supplier_quote] AS sq
    ON sq.[supplier_id] = pr.[supplier_id] AND sq.[goods_id] = pri.[goods_id]
ORDER BY pr.[id], pri.[id];
GO

/* Q7. How much of each sold line has been returned? */
SELECT
    s.[no] AS sale_no,
    g.[name] AS goods_name,
    si.[quantity] AS sold_quantity,
    COALESCE(SUM(gri.[quantity]), 0) AS returned_quantity,
    si.[quantity] - COALESCE(SUM(gri.[quantity]), 0) AS remaining_quantity,
    COALESCE(SUM(gri.[refund_amount]), 0.00) AS refunded_amount
FROM dbo.[sale] AS s
JOIN dbo.[sale_item] AS si ON si.[sale_id] = s.[id]
JOIN dbo.[goods] AS g ON g.[id] = si.[goods_id]
LEFT JOIN dbo.[goods_return_item] AS gri ON gri.[sale_item_id] = si.[id]
GROUP BY s.[no], g.[name], si.[quantity], si.[id]
ORDER BY s.[no], si.[id];
GO

PRINT N'query.sql PASS';
GO
