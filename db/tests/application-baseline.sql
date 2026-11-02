:On Error exit
-- Isolated test copies only. Every business edit below is rolled back.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek6Runner%'
    THROW 52202, N'Baseline mutation tests require a new Runner copy.', 1;
IF @@TRANCOUNT<>0 THROW 52202, N'No outer transaction allowed.', 1;
IF (SELECT COUNT(*) FROM dbo.card_type WHERE level IN(N'银卡',N'金卡'))<>2
    THROW 52202, N'Both sample tiers are required.', 1;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.card_type SET card_fee=card_fee+1 WHERE level=N'金卡';
    ROLLBACK;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
PRINT N'PASS: legal tier change';
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.card_type SET card_fee=(SELECT card_fee FROM dbo.card_type WHERE level=N'银卡')
    WHERE level=N'金卡';
    ROLLBACK;
    THROW 52202, N'Expected fee rejection was not raised.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    IF ERROR_NUMBER()<>51025 THROW;
END CATCH;
PRINT N'PASS: equal gold fee rejected with 51025';
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.card_type SET discount_rate=(SELECT discount_rate+0.01 FROM dbo.card_type WHERE level=N'银卡')
    WHERE level=N'金卡';
    ROLLBACK;
    THROW 52202, N'Expected discount rejection was not raised.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    IF ERROR_NUMBER()<>51025 THROW;
END CATCH;
PRINT N'PASS: worse gold discount rejected with 51025';
-- Compare the actual view contract to its defining business expression.
IF EXISTS(SELECT goods_id,available_qty,is_sellable FROM dbo.v_inventory_status
    EXCEPT SELECT id,stock_total-reserved_qty,CONVERT(bit,CASE WHEN on_shelf=1
        AND price IS NOT NULL AND stock_total-reserved_qty>0 THEN 1 ELSE 0 END) FROM dbo.goods)
    THROW 52202, N'Inventory view values do not match business data.', 1;
PRINT N'application baseline rule tests PASS';
GO
