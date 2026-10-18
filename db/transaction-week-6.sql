-- 第六周事务完整性小测试：中途失败时整笔事务回滚
-- 目标固定为迁移并扩充后的工作副本；本脚本不应留下业务数据。
USE [ShiguangBookstoreWeek6Work];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'ShiguangBookstoreWeek6Work'
    THROW 51700, N'当前数据库不是 ShiguangBookstoreWeek6Work，停止事务测试。', 1;
IF @@TRANCOUNT <> 0
    THROW 51701, N'请在没有外层事务的新查询窗口执行事务测试。', 1;

DECLARE @sale_no VARCHAR(20) = 'W6-TXN-ROLLBACK-01';
IF EXISTS (SELECT 1 FROM dbo.sale WHERE no=@sale_no)
    THROW 51702, N'事务测试单号已存在，请不要重复使用旧测试数据。', 1;

DECLARE @before_sale BIGINT = (SELECT COUNT_BIG(*) FROM dbo.sale);
DECLARE @before_sale_item BIGINT = (SELECT COUNT_BIG(*) FROM dbo.sale_item);
DECLARE @sale_id BIGINT = NULL;
DECLARE @caught_error INT = NULL;
DECLARE @caught_message NVARCHAR(2048) = NULL;
DECLARE @g1 BIGINT, @g2 BIGINT;
SELECT @g1 = MIN(id), @g2 = MAX(id) FROM dbo.goods;
IF @g1 IS NULL OR @g2 IS NULL OR @g1 = @g2
    THROW 51703, N'测试需要至少两个商品。', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- 第一步：先写入一张临时销售单。
    INSERT dbo.sale
        (no, status, cashier_by, sold_at, subtotal_amount,
         discount_rate, point_deduction_amount, paid_amount)
    VALUES
        (@sale_no, N'已付', '13800000003', '2026-10-18T15:00:00',
         10.00, 1.00, 0.00, 10.00);
    SET @sale_id = SCOPE_IDENTITY();

    -- 第二步：先写入一条合法明细。
    INSERT dbo.sale_item (sale_id, goods_id, quantity, unit_price)
    VALUES (@sale_id, @g1, 1, 10.00);

    -- 第三步：故意写入数量 0 的非法明细，触发 CK_sale_item_quantity。
    INSERT dbo.sale_item (sale_id, goods_id, quantity, unit_price)
    VALUES (@sale_id, @g2, 0, 10.00);

    -- 若执行到这里，说明非法写入没有被拒绝。
    THROW 51704, N'非法销售明细意外写入，事务测试失败。', 1;
END TRY
BEGIN CATCH
    SET @caught_error = ERROR_NUMBER();
    SET @caught_message = ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
END CATCH;

IF @caught_error IS NULL
    THROW 51705, N'事务测试没有捕获预期错误。', 1;
IF @caught_error <> 547
BEGIN
    DECLARE @unexpected NVARCHAR(2048) = CONCAT(N'事务测试捕获了非预期错误号 ', @caught_error, N'：', @caught_message);
    THROW 51709, @unexpected, 1;
END;

IF EXISTS (SELECT 1 FROM dbo.sale WHERE no=@sale_no)
    THROW 51706, N'事务失败后临时销售单仍然存在，未完整回滚。', 1;
IF EXISTS (SELECT 1 FROM dbo.sale_item si JOIN dbo.sale s ON s.id=si.sale_id WHERE s.no=@sale_no)
    THROW 51707, N'事务失败后临时销售明细仍然存在，未完整回滚。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.sale) <> @before_sale
   OR (SELECT COUNT_BIG(*) FROM dbo.sale_item) <> @before_sale_item
    THROW 51708, N'事务失败后销售单或明细总行数发生变化。', 1;

SELECT N'transaction-week-6' AS check_name,
       @caught_error AS caught_error,
       @caught_message AS caught_message,
       @before_sale AS sale_count_before,
       (SELECT COUNT_BIG(*) FROM dbo.sale) AS sale_count_after,
       @before_sale_item AS sale_item_count_before,
       (SELECT COUNT_BIG(*) FROM dbo.sale_item) AS sale_item_count_after;
PRINT N'transaction-week-6.sql PASS: mid-transaction failure rolled back sale and sale_item.';
