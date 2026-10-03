:On Error exit
-- Week 4 constraint verification. Existing Week 3 constraints are exercised here;
-- no duplicate constraint names are created.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;

/* Cross-row rule R-17: tier configuration cannot be expressed by a row CHECK. */
IF OBJECT_ID(N'dbo.tr_card_type_cross_row', N'TR') IS NULL
    EXEC(N'
CREATE TRIGGER dbo.tr_card_type_cross_row
ON dbo.card_type
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @silver nvarchar(10) = NCHAR(38134) + NCHAR(21345);
    DECLARE @gold nvarchar(10) = NCHAR(37329) + NCHAR(21345);
    IF EXISTS (
        SELECT 1
        FROM dbo.card_type AS s
        JOIN dbo.card_type AS g ON s.[level] = @silver AND g.[level] = @gold
        WHERE g.[card_fee] <= s.[card_fee]
           OR g.[discount_rate] > s.[discount_rate]
    )
        THROW 51025, ''Card tier relation is invalid.'', 1;
END');
GO

PRINT N'CARD TIER BASELINE';
SELECT [level], [card_fee], [discount_rate]
FROM dbo.[card_type]
ORDER BY [level];
GO

PRINT N'LEGAL TEST: card tier update is accepted';
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.[card_type]
    SET [card_fee] = [card_fee] + 1.00
    WHERE [level] = NCHAR(37329) + NCHAR(21345);
    IF NOT EXISTS (
        SELECT 1 FROM dbo.[card_type] AS s CROSS JOIN dbo.[card_type] AS g
        WHERE s.[level] = NCHAR(38134) + NCHAR(21345)
          AND g.[level] = NCHAR(37329) + NCHAR(21345)
          AND g.[card_fee] > s.[card_fee]
          AND g.[discount_rate] <= s.[discount_rate])
        THROW 51026, N'Valid tier update was not retained.', 1;
    ROLLBACK TRANSACTION;
    SELECT N'PASS' AS result, N'valid card tier update accepted and rolled back' AS detail;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

PRINT N'ILLEGAL TEST 0: gold card fee cannot be less than silver';
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.[card_type]
    SET [card_fee] = (SELECT [card_fee] FROM dbo.[card_type] WHERE [level] = NCHAR(38134) + NCHAR(21345))
    WHERE [level] = NCHAR(37329) + NCHAR(21345);
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW 51027, N'Expected cross-row card tier rejection did not occur.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 51027 THROW;
    SELECT N'PASS' AS result, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO

PRINT N'CONSTRAINT BASELINE';
SELECT name AS constraint_name, type_desc
FROM sys.objects
WHERE parent_object_id IN (SELECT object_id FROM sys.tables WHERE is_ms_shipped = 0)
  AND type IN ('PK','UQ','F','C','D')
ORDER BY type_desc, name;
GO

PRINT N'LEGAL DATA CHECK';
SELECT COUNT_BIG(*) AS legal_goods_count
FROM dbo.[goods]
WHERE [stock_total] >= [reserved_qty]
  AND ([on_shelf] = 0 OR [price] IS NOT NULL);
GO

PRINT N'ILLEGAL TEST 1: reserved quantity cannot exceed stock';
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.[goods]
    SET [reserved_qty] = [stock_total] + 1
    WHERE [id] = 1;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW 51020, N'Expected CK_goods_stock rejection did not occur.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 51020 THROW;
    SELECT N'PASS' AS result, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO

PRINT N'ILLEGAL TEST 2: sale item quantity must be positive';
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.[sale_item] ([sale_id], [goods_id], [quantity], [unit_price])
    VALUES (1, 4, 0, 6.00);
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW 51021, N'Expected CK_sale_item_quantity rejection did not occur.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 51021 THROW;
    SELECT N'PASS' AS result, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO

PRINT N'ILLEGAL TEST 3: foreign key must reject an unknown goods row';
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.[sale_item] ([sale_id], [goods_id], [quantity], [unit_price])
    VALUES (1, 999999, 1, 1.00);
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW 51022, N'Expected sale_item goods foreign key rejection did not occur.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 51022 THROW;
    SELECT N'PASS' AS result, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO

PRINT N'ILLEGAL TEST 4: duplicate sale number must be rejected';
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.[sale] ([no], [status], [cashier_by], [sold_at], [subtotal_amount], [discount_rate], [point_deduction_amount], [paid_amount])
    VALUES (N'S20260908-01', NCHAR(24050) + NCHAR(20184), N'13800000003', '2026-09-20T12:00:00', 0.00, 1.00, 0.00, 0.00);
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW 51023, N'Expected UQ_sale_no rejection did not occur.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 51023 THROW;
    SELECT N'PASS' AS result, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO

PRINT N'ILLEGAL TEST 5: fund flow balance must reconcile';
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.[fund_flow] ([amount], [direction], [reason_type], [fund_before], [fund_after], [recorded_by], [recorded_at])
    VALUES (10.00, NCHAR(25910), NCHAR(27880) + NCHAR(36164), 100.00, 100.00, N'13800000001', '2026-09-20T12:00:00');
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW 51024, N'Expected CK_fund_flow_balance rejection did not occur.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 51024 THROW;
    SELECT N'PASS' AS result, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
