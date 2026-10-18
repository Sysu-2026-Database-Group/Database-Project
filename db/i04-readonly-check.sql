-- I-04 只读基线核对：库存账面计数与明细重算值
-- 目标库：ShiguangBookstoreWeek3
-- 本脚本只包含 USE、SET 和 SELECT，不执行 INSERT / UPDATE / DELETE / DDL。
-- 第一组结果按商品显示两条等式及差异；第二组结果给出汇总。

USE [ShiguangBookstoreWeek3];
GO
SET NOCOUNT ON;
GO

;WITH InventoryCheck AS
(
    SELECT
        g.[id] AS [goods_id],
        g.[name] AS [goods_name],
        g.[category],
        g.[stock_total],
        g.[reserved_qty],
        COALESCE(m.[movement_total], CONVERT(bigint, 0)) AS [movement_total],
        COALESCE(r.[valid_reserved_total], CONVERT(bigint, 0)) AS [valid_reserved_total],
        CONVERT(bigint, g.[stock_total])
            - COALESCE(m.[movement_total], CONVERT(bigint, 0)) AS [stock_difference],
        CONVERT(bigint, g.[reserved_qty])
            - COALESCE(r.[valid_reserved_total], CONVERT(bigint, 0)) AS [reserved_difference],
        CONVERT(bigint, g.[stock_total]) - CONVERT(bigint, g.[reserved_qty]) AS [available_qty],
        COALESCE(m.[movement_total], CONVERT(bigint, 0))
            - COALESCE(r.[valid_reserved_total], CONVERT(bigint, 0)) AS [recalculated_available_qty]
    FROM dbo.[goods] AS g
    OUTER APPLY
    (
        SELECT SUM(CONVERT(bigint, sm.[quantity])) AS [movement_total]
        FROM dbo.[stock_movement] AS sm
        WHERE sm.[goods_id] = g.[id]
    ) AS m
    OUTER APPLY
    (
        SELECT SUM(CONVERT(bigint, ri.[quantity])) AS [valid_reserved_total]
        FROM dbo.[reservation_item] AS ri
        JOIN dbo.[reservation] AS rv
          ON rv.[id] = ri.[reservation_id]
        WHERE ri.[goods_id] = g.[id]
          AND rv.[status] = N'有效'
    ) AS r
)
SELECT
    [goods_id],
    [goods_name],
    [category],
    [stock_total],
    [movement_total],
    [stock_difference],
    [reserved_qty],
    [valid_reserved_total],
    [reserved_difference],
    [available_qty],
    [recalculated_available_qty],
    CASE
        WHEN [stock_difference] = 0
         AND [reserved_difference] = 0
         AND [reserved_qty] BETWEEN 0 AND [stock_total]
        THEN N'一致'
        ELSE N'不一致'
    END AS [check_result]
FROM InventoryCheck
ORDER BY [goods_id];
GO

;WITH InventoryCheck AS
(
    SELECT
        g.[id] AS [goods_id],
        g.[stock_total],
        g.[reserved_qty],
        COALESCE(m.[movement_total], CONVERT(bigint, 0)) AS [movement_total],
        COALESCE(r.[valid_reserved_total], CONVERT(bigint, 0)) AS [valid_reserved_total]
    FROM dbo.[goods] AS g
    OUTER APPLY
    (
        SELECT SUM(CONVERT(bigint, sm.[quantity])) AS [movement_total]
        FROM dbo.[stock_movement] AS sm
        WHERE sm.[goods_id] = g.[id]
    ) AS m
    OUTER APPLY
    (
        SELECT SUM(CONVERT(bigint, ri.[quantity])) AS [valid_reserved_total]
        FROM dbo.[reservation_item] AS ri
        JOIN dbo.[reservation] AS rv
          ON rv.[id] = ri.[reservation_id]
        WHERE ri.[goods_id] = g.[id]
          AND rv.[status] = N'有效'
    ) AS r
)
SELECT
    N'I-04' AS [check_name],
    COUNT_BIG(*) AS [goods_count],
    SUM(CASE WHEN CONVERT(bigint, [stock_total]) = [movement_total]
                  AND CONVERT(bigint, [reserved_qty]) = [valid_reserved_total]
                  AND [reserved_qty] BETWEEN 0 AND [stock_total]
             THEN CONVERT(bigint, 0) ELSE CONVERT(bigint, 1) END) AS [inconsistent_goods_count],
    SUM(ABS(CONVERT(bigint, [stock_total]) - [movement_total])) AS [total_stock_difference],
    SUM(ABS(CONVERT(bigint, [reserved_qty]) - [valid_reserved_total])) AS [total_reserved_difference]
FROM InventoryCheck;
GO
