:On Error exit
-- 第 11 周：库存审计触发器
-- 库存由 usp_adjust_stock 统一写入 goods 和 stock_movement；
-- 本触发器只做数据库层重复校验，不负责业务写入。
USE [$(DatabaseName)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER TRIGGER dbo.tr_stock_movement_guard
ON dbo.stock_movement
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. 行内：前后数量、差值、非负；与 CHECK 重复，保留为触发器自检。
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.stock_before < 0
           OR i.stock_after < 0
           OR i.quantity <> i.stock_after - i.stock_before
    )
        THROW 52401, N'库存流水前后数量或差值不合法。', 1;

    -- 2. 同一商品最后一条插入流水的 after 必须等于 goods 当前库存。
    IF EXISTS (
        SELECT 1
        FROM (
            SELECT i.goods_id, i.stock_after,
                   ROW_NUMBER() OVER (PARTITION BY i.goods_id ORDER BY i.id DESC) AS rn
            FROM inserted i
        ) latest
        JOIN dbo.goods g ON g.id = latest.goods_id
        WHERE latest.rn = 1
          AND latest.stock_after <> g.stock_total
    )
        THROW 52403, N'库存流水与商品当前库存不一致。', 1;
END;
GO
