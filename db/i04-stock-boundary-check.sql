-- I-04 库存流水侧边界测试：只在事务内执行，最后必定回滚
-- 目标库：ShiguangBookstoreWeek3
-- 目的：观察直接改 goods.stock_total 或 stock_movement.quantity 时，当前数据库是否自动同步另一侧。
-- 本脚本不是纯只读脚本，但不会留下业务数据；请在没有外层事务的新查询窗口中执行。

USE [ShiguangBookstoreWeek3];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT <> 0
    THROW 51009, N'请在没有外层事务的新查询窗口执行本脚本。', 1;
GO

/* 测试 1：直接修改 goods.stock_total。
   加 1 不会触发 CK_goods_stock 的负数或大小关系错误。 */
DECLARE @GoodsId BIGINT;
DECLARE @StockBefore INT;

SELECT TOP (1)
    @GoodsId = g.[id]
FROM dbo.[goods] AS g
WHERE g.[stock_total] >= 0
ORDER BY g.[id];

IF @GoodsId IS NULL
BEGIN
    SELECT N'测试 1' AS [test_name], N'没有商品，未执行' AS [result];
END
ELSE
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @StockBefore = [stock_total]
        FROM dbo.[goods]
        WHERE [id] = @GoodsId;

        UPDATE dbo.[goods]
        SET [stock_total] = [stock_total] + 1
        WHERE [id] = @GoodsId;

        SELECT
            N'测试 1：直接改 goods.stock_total' AS [test_name],
            @GoodsId AS [goods_id],
            @StockBefore AS [stock_before],
            [stock_total] AS [stock_after_direct_update],
            N'如果这里能返回且值增加，说明当前没有写入时的库存流水等式强制；下面会回滚' AS [interpretation]
        FROM dbo.[goods]
        WHERE [id] = @GoodsId;

        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SELECT
            N'测试 1：直接改 goods.stock_total' AS [test_name],
            ERROR_NUMBER() AS [error_number],
            ERROR_MESSAGE() AS [error_message],
            N'写入被约束拒绝；事务已回滚' AS [interpretation];
    END CATCH;
END;
GO

/* 测试 2：直接修改一条库存流水数量。
   保持数量符号不变，避免只因 CK_stock_movement_source 失败。 */
DECLARE @MovementId BIGINT;
DECLARE @MovementGoodsId BIGINT;
DECLARE @MovementBefore INT;
DECLARE @MovementDelta INT;
DECLARE @MovementStockBefore INT;

SELECT TOP (1)
    @MovementId = sm.[id],
    @MovementGoodsId = sm.[goods_id],
    @MovementBefore = sm.[quantity],
    @MovementDelta = CASE WHEN sm.[quantity] > 0 THEN 1 ELSE -1 END
FROM dbo.[stock_movement] AS sm
WHERE sm.[quantity] <> 0
ORDER BY sm.[id];

IF @MovementId IS NULL
BEGIN
    SELECT N'测试 2' AS [test_name], N'没有库存流水，未执行' AS [result];
END
ELSE
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @MovementStockBefore = [stock_total]
        FROM dbo.[goods]
        WHERE [id] = @MovementGoodsId;

        UPDATE dbo.[stock_movement]
        SET [quantity] = [quantity] + @MovementDelta
        WHERE [id] = @MovementId;

        SELECT
            N'测试 2：直接改 stock_movement.quantity' AS [test_name],
            @MovementId AS [movement_id],
            @MovementGoodsId AS [goods_id],
            @MovementBefore AS [movement_before],
            [quantity] AS [movement_after_direct_update],
            @MovementStockBefore AS [stock_before],
            g.[stock_total] AS [stock_after_movement_update],
            N'如果流水值能改变而 stock_total 不同步，说明当前没有写入时的库存计数维护；下面会回滚' AS [interpretation]
        FROM dbo.[stock_movement] AS sm
        JOIN dbo.[goods] AS g
          ON g.[id] = sm.[goods_id]
        WHERE sm.[id] = @MovementId;

        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SELECT
            N'测试 2：直接改 stock_movement.quantity' AS [test_name],
            ERROR_NUMBER() AS [error_number],
            ERROR_MESSAGE() AS [error_message],
            N'写入被约束拒绝；事务已回滚' AS [interpretation];
    END CATCH;
END;
GO

-- 最后确认测试没有留下状态变化。
SELECT
    N'回滚后检查' AS [check_name],
    (SELECT COUNT_BIG(*) FROM dbo.[goods]) AS [goods_count],
    (SELECT COUNT_BIG(*) FROM dbo.[stock_movement]) AS [stock_movement_count];
GO
