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
SET XACT_ABORT OFF;

IF OBJECT_ID(N'dbo.tr_stock_movement_guard',N'TR') IS NULL
   OR EXISTS(SELECT 1 FROM sys.triggers WHERE name='tr_stock_movement_guard' AND is_disabled=1)
    THROW 53131,N'库存审计触发器不存在或被禁用。',1;

DECLARE @goods_id bigint,@before int=10,@request_id bigint,@employee varchar(11);
SELECT TOP (1) @goods_id=id FROM dbo.goods WHERE reserved_qty<=@before ORDER BY id;
SELECT TOP (1) @request_id=id FROM dbo.purchase_request ORDER BY id;
SELECT TOP (1) @employee=phone FROM dbo.employee ORDER BY phone;
IF @goods_id IS NULL OR @request_id IS NULL OR @employee IS NULL
    THROW 53132,N'触发器测试前置数据不足。',1;

-- 1. 单条正常插入：先改 goods，再插一条流水。
BEGIN TRAN;
BEGIN TRY
    UPDATE dbo.goods SET stock_total=@before WHERE id=@goods_id;
    UPDATE dbo.goods SET stock_total=@before+1 WHERE id=@goods_id;
    INSERT dbo.stock_movement(goods_id,change_type,stock_before,stock_after,quantity,changed_by,request_id)
        VALUES(@goods_id,N'购入',@before,@before+1,1,@employee,@request_id);
    PRINT N'W11-T01 single insert PASS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    THROW;
END CATCH;
IF @@TRANCOUNT>0 ROLLBACK;

-- 2. 单条修改：减少库存并写损坏流水。
BEGIN TRAN;
BEGIN TRY
    UPDATE dbo.goods SET stock_total=@before WHERE id=@goods_id;
    UPDATE dbo.goods SET stock_total=@before-1 WHERE id=@goods_id;
    INSERT dbo.stock_movement(goods_id,change_type,stock_before,stock_after,quantity,note,changed_by)
        VALUES(@goods_id,N'损坏',@before,@before-1,-1,N'trigger single update',@employee);
    PRINT N'W11-T02 single update PASS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    THROW;
END CATCH;
IF @@TRANCOUNT>0 ROLLBACK;

-- 3. 多条插入：一次插两行，最后一条 after 与 goods 一致。
BEGIN TRAN;
BEGIN TRY
    UPDATE dbo.goods SET stock_total=@before WHERE id=@goods_id;
    UPDATE dbo.goods SET stock_total=@before+2 WHERE id=@goods_id;
    INSERT dbo.stock_movement(goods_id,change_type,stock_before,stock_after,quantity,changed_by,request_id)
        VALUES
        (@goods_id,N'购入',@before,@before+1,1,@employee,@request_id),
        (@goods_id,N'购入',@before+1,@before+2,1,@employee,@request_id);
    PRINT N'W11-T03 multiple insert PASS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    THROW;
END CATCH;
IF @@TRANCOUNT>0 ROLLBACK;

-- 4. 非法插入：after 与 goods 不一致，触发器必须拒绝。
BEGIN TRAN;
BEGIN TRY
    INSERT dbo.stock_movement(goods_id,change_type,stock_before,stock_after,quantity,changed_by,request_id)
        VALUES(@goods_id,N'购入',@before,@before+1,1,@employee,@request_id);
    THROW 53133,N'触发器未拒绝与当前库存不一致的流水。',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() NOT IN (52401,52403,547)
    BEGIN
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END
    PRINT N'W11-T04 trigger rejection PASS: ' + CONVERT(varchar(10),ERROR_NUMBER());
END CATCH;
IF @@TRANCOUNT>0 ROLLBACK;

SELECT N'W11-T01～T04' test_case,N'单条插入/单条修改/多条插入/触发器拒绝' scope;
