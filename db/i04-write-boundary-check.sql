-- I-04 写入边界测试：只在事务内执行，最后必定回滚
-- 目标库：ShiguangBookstoreWeek3
-- 目的：观察当前数据库是否会阻止直接改库存计数，或在直接取消有效预订时自动释放 reserved_qty。
-- 本脚本不是纯只读脚本，但不会留下业务数据；不要在有外层事务的窗口中执行。

USE [ShiguangBookstoreWeek3];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT <> 0
    THROW 51009, N'请在没有外层事务的新查询窗口执行本脚本。', 1;
GO

/* 测试 1：直接修改 goods.reserved_qty。
   选择仍有可用空间的商品，避免只因 CK_goods_stock 而失败。 */
DECLARE @GoodsId BIGINT;
DECLARE @ReservedBefore INT;

SELECT TOP (1)
    @GoodsId = g.[id]
FROM dbo.[goods] AS g
WHERE g.[stock_total] > g.[reserved_qty]
ORDER BY g.[id];

IF @GoodsId IS NULL
BEGIN
    SELECT N'测试 1' AS [test_name], N'没有 stock_total > reserved_qty 的商品，未执行' AS [result];
END
ELSE
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @ReservedBefore = [reserved_qty]
        FROM dbo.[goods]
        WHERE [id] = @GoodsId;

        UPDATE dbo.[goods]
        SET [reserved_qty] = [reserved_qty] + 1
        WHERE [id] = @GoodsId;

        SELECT
            N'测试 1：直接改 goods.reserved_qty' AS [test_name],
            @GoodsId AS [goods_id],
            @ReservedBefore AS [reserved_before],
            [reserved_qty] AS [reserved_after_direct_update],
            N'如果这里能返回且值增加，说明当前没有写入时的跨表强制；下面会回滚' AS [interpretation]
        FROM dbo.[goods]
        WHERE [id] = @GoodsId;

        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SELECT
            N'测试 1：直接改 goods.reserved_qty' AS [test_name],
            ERROR_NUMBER() AS [error_number],
            ERROR_MESSAGE() AS [error_message],
            N'写入被约束拒绝；事务已回滚' AS [interpretation];
    END CATCH;
END;
GO

/* 测试 2：直接把一条有效预订改为已取消。
   当前 schema 的 CHECK 允许取消留痕，但不负责同步 goods.reserved_qty。 */
DECLARE @ReservationId BIGINT;
DECLARE @ReservationItemId BIGINT;
DECLARE @ReservationGoodsId BIGINT;
DECLARE @ReservationQuantity INT;
DECLARE @GoodsReservedBefore INT;

SELECT TOP (1)
    @ReservationId = r.[id],
    @ReservationItemId = ri.[id],
    @ReservationGoodsId = ri.[goods_id],
    @ReservationQuantity = ri.[quantity]
FROM dbo.[reservation] AS r
JOIN dbo.[reservation_item] AS ri
  ON ri.[reservation_id] = r.[id]
WHERE r.[status] = N'有效'
ORDER BY r.[id], ri.[id];

IF @ReservationId IS NULL
BEGIN
    SELECT N'测试 2' AS [test_name], N'没有 status = 有效的预订，未执行' AS [result];
END
ELSE
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @GoodsReservedBefore = [reserved_qty]
        FROM dbo.[goods]
        WHERE [id] = @ReservationGoodsId;

        UPDATE dbo.[reservation]
        SET [status] = N'已取消',
            [cancelled_at] = [created_at]
        WHERE [id] = @ReservationId;

        SELECT
            N'测试 2：直接取消有效预订' AS [test_name],
            @ReservationId AS [reservation_id],
            @ReservationItemId AS [reservation_item_id],
            @ReservationGoodsId AS [goods_id],
            @ReservationQuantity AS [reservation_quantity],
            @GoodsReservedBefore AS [reserved_before],
            g.[reserved_qty] AS [reserved_after_status_update],
            r.[status] AS [reservation_status_after_update],
            N'若 reserved_qty 未减少，说明状态修改不会自动维护计数；下面会回滚' AS [interpretation]
        FROM dbo.[goods] AS g
        JOIN dbo.[reservation] AS r
          ON r.[id] = @ReservationId
        WHERE g.[id] = @ReservationGoodsId;

        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SELECT
            N'测试 2：直接取消有效预订' AS [test_name],
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
    (SELECT COUNT_BIG(*) FROM dbo.[reservation]) AS [reservation_count],
    (SELECT COUNT_BIG(*) FROM dbo.[reservation_item]) AS [reservation_item_count];
GO
