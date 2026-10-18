-- 第六周重复请求边界检查：观察已取消预订再次提交取消是否被数据库自动拒绝
-- 本脚本只在事务内执行直接 DML，最后一定回滚；它不代表完整业务接口。
USE [ShiguangBookstoreWeek6Work];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'ShiguangBookstoreWeek6Work'
    THROW 51800, N'当前数据库不是 ShiguangBookstoreWeek6Work，停止重复请求边界检查。', 1;
IF @@TRANCOUNT <> 0
    THROW 51801, N'请在没有外层事务的新查询窗口执行边界检查。', 1;

DECLARE @code VARCHAR(20) = 'W6R-2108';
DECLARE @before_status NVARCHAR(10), @before_by VARCHAR(11), @before_at DATETIME2;
DECLARE @created_at DATETIME2;
SELECT @before_status=status,
       @before_by=cancelled_by_employee,
       @before_at=cancelled_at,
       @created_at=created_at
FROM dbo.reservation
WHERE code=@code;

IF @before_status IS NULL
    THROW 51802, N'找不到重复取消测试预订 W6R-2108。', 1;
IF @before_status <> N'已取消'
    THROW 51803, N'测试夹具 W6R-2108 当前不是已取消状态。', 1;

DECLARE @rows INT = 0;
DECLARE @accepted BIT = 0;
BEGIN TRY
    BEGIN TRANSACTION;

    -- 模拟同一次取消请求再次提交；沿用已有留痕值，避免引入新的业务事实。
    UPDATE dbo.reservation
    SET status=N'已取消',
        cancelled_by_employee=COALESCE(@before_by, '13800000003'),
        cancelled_at=COALESCE(@before_at, @created_at)
    WHERE code=@code;
    SET @rows = @@ROWCOUNT;
    IF @rows = 1 SET @accepted = 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SELECT N'REJECTED' AS observed_behavior,
           ERROR_NUMBER() AS error_number,
           ERROR_MESSAGE() AS error_message,
           @code AS reservation_code;
    RETURN;
END CATCH;

IF EXISTS (
    SELECT 1 FROM dbo.reservation
    WHERE code=@code
      AND (status<>@before_status
       OR ISNULL(cancelled_by_employee,'')<>ISNULL(@before_by,'')
       OR ISNULL(cancelled_at,'19000101')<>ISNULL(@before_at,'19000101'))
)
    THROW 51804, N'重复取消边界检查回滚后，预订原值发生变化。', 1;

SELECT CASE WHEN @accepted=1
            THEN N'DIRECT_DML_ACCEPTED_NO_IDEMPOTENCY_GUARD'
            ELSE N'NO_ROW_UPDATED'
       END AS observed_behavior,
       @rows AS rows_updated_inside_transaction,
       @code AS reservation_code,
       @before_status AS status_after_rollback,
       @before_by AS cancelled_by_after_rollback,
       @before_at AS cancelled_at_after_rollback;
PRINT N'duplicate-cancel-boundary-check.sql PASS: test transaction rolled back and original reservation values were preserved.';
