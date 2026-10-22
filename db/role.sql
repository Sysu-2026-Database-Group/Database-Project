:On Error exit
-- Week 4 least-privilege roles. Run after schema.sql and sample-data.sql.
USE [$(DatabaseName)];
GO
-- 筛选索引的创建及相关表 DML 所需会话选项，不依赖 SSMS / SQLCMD 默认值。
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;

IF DATABASE_PRINCIPAL_ID(N'bookstore_manager') IS NULL CREATE ROLE [bookstore_manager];
IF DATABASE_PRINCIPAL_ID(N'bookstore_cashier') IS NULL CREATE ROLE [bookstore_cashier];
IF DATABASE_PRINCIPAL_ID(N'bookstore_inventory') IS NULL CREATE ROLE [bookstore_inventory];
IF DATABASE_PRINCIPAL_ID(N'week4_manager_user') IS NULL CREATE USER [week4_manager_user] WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'week4_cashier_user') IS NULL CREATE USER [week4_cashier_user] WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'week4_inventory_user') IS NULL CREATE USER [week4_inventory_user] WITHOUT LOGIN;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'bookstore_manager') AND member_principal_id = DATABASE_PRINCIPAL_ID(N'week4_manager_user')) ALTER ROLE [bookstore_manager] ADD MEMBER [week4_manager_user];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'bookstore_cashier') AND member_principal_id = DATABASE_PRINCIPAL_ID(N'week4_cashier_user')) ALTER ROLE [bookstore_cashier] ADD MEMBER [week4_cashier_user];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'bookstore_inventory') AND member_principal_id = DATABASE_PRINCIPAL_ID(N'week4_inventory_user')) ALTER ROLE [bookstore_inventory] ADD MEMBER [week4_inventory_user];
GO

-- Manager: operational read access, and price/listing/card configuration writes.
GRANT SELECT ON dbo.[employee] TO [bookstore_manager];
GRANT SELECT ON dbo.[goods] TO [bookstore_manager];
GRANT SELECT ON dbo.[sale] TO [bookstore_manager];
GRANT SELECT ON dbo.[sale_item] TO [bookstore_manager];
GRANT SELECT ON dbo.[reservation] TO [bookstore_manager];
GRANT SELECT ON dbo.[reservation_item] TO [bookstore_manager];
GRANT SELECT ON dbo.[member] TO [bookstore_manager];
GRANT SELECT ON dbo.[purchase_request] TO [bookstore_manager];
GRANT SELECT ON dbo.[purchase_request_item] TO [bookstore_manager];
GRANT SELECT ON dbo.[fund_flow] TO [bookstore_manager];
GRANT SELECT ON dbo.[stock_movement] TO [bookstore_manager];
GRANT SELECT ON dbo.[point_movement] TO [bookstore_manager];
GRANT UPDATE ([price], [on_shelf]) ON dbo.[goods] TO [bookstore_manager];
GRANT SELECT, UPDATE ([card_fee], [discount_rate]) ON dbo.[card_type] TO [bookstore_manager];

-- Cashier: sales, reservations, members, and customer-facing reads.
GRANT SELECT ON dbo.[goods] TO [bookstore_cashier];
GRANT SELECT ON dbo.[member] TO [bookstore_cashier];
GRANT SELECT ON dbo.[reservation] TO [bookstore_cashier];
GRANT SELECT ON dbo.[reservation_item] TO [bookstore_cashier];
GRANT INSERT ON dbo.[member] TO [bookstore_cashier];
GRANT INSERT ON dbo.[reservation] TO [bookstore_cashier];
GRANT INSERT ON dbo.[reservation_item] TO [bookstore_cashier];
GRANT SELECT, INSERT ON dbo.[sale] TO [bookstore_cashier];
GRANT SELECT, INSERT ON dbo.[sale_item] TO [bookstore_cashier];
GRANT SELECT, INSERT ON dbo.[goods_return] TO [bookstore_cashier];
GRANT SELECT, INSERT ON dbo.[goods_return_item] TO [bookstore_cashier];

-- Inventory: goods, suppliers, purchasing and stock movement records.
GRANT SELECT ON dbo.[goods] TO [bookstore_inventory];
GRANT SELECT ON dbo.[book] TO [bookstore_inventory];
GRANT SELECT ON dbo.[toy] TO [bookstore_inventory];
GRANT SELECT ON dbo.[supplier] TO [bookstore_inventory];
GRANT SELECT ON dbo.[supplier_quote] TO [bookstore_inventory];
GRANT SELECT ON dbo.[purchase_request] TO [bookstore_inventory];
GRANT SELECT ON dbo.[purchase_request_item] TO [bookstore_inventory];
GRANT SELECT ON dbo.[stock_movement] TO [bookstore_inventory];
GRANT INSERT ON dbo.[goods] TO [bookstore_inventory];
GRANT INSERT ON dbo.[supplier_quote] TO [bookstore_inventory];
GRANT INSERT ON dbo.[purchase_request] TO [bookstore_inventory];
GRANT INSERT ON dbo.[purchase_request_item] TO [bookstore_inventory];
GRANT INSERT ON dbo.[stock_movement] TO [bookstore_inventory];
GO

PRINT N'ROLE PERMISSION SUMMARY';
SELECT dp.name AS principal_name, p.permission_name, p.state_desc,
       OBJECT_SCHEMA_NAME(p.major_id) AS schema_name, OBJECT_NAME(p.major_id) AS object_name,
       p.class_desc
FROM sys.database_permissions AS p
JOIN sys.database_principals AS dp ON dp.principal_id = p.grantee_principal_id
WHERE dp.name IN (N'bookstore_manager', N'bookstore_cashier', N'bookstore_inventory')
ORDER BY dp.name, object_name, p.permission_name;
GO

PRINT N'ROLE TEST: cashier can read goods';
EXECUTE AS USER = N'week4_cashier_user';
SELECT N'PASS' AS result, COUNT_BIG(*) AS visible_goods FROM dbo.[goods];
REVERT;
GO

PRINT N'ROLE TEST: cashier cannot update price';
EXECUTE AS USER = N'week4_cashier_user';
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.[goods] SET [price] = [price] WHERE [id] = 1;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    REVERT;
    THROW 51030, N'Cashier unexpectedly has price update permission.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF USER_NAME() = N'week4_cashier_user' REVERT;
    -- 只有对象 / 列权限拒绝才算通过；约束、对象不存在等错误必须上抛。
    IF ERROR_NUMBER() <> 229 THROW;
    SELECT N'PASS' AS result, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO

PRINT N'ROLE TEST: inventory cannot insert a sale';
EXECUTE AS USER = N'week4_inventory_user';
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.[sale] ([no], [cashier_by], [subtotal_amount], [paid_amount])
    VALUES (N'W4-UNAUTHORIZED', N'13800000002', 0.00, 0.00);
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    REVERT;
    THROW 51031, N'Inventory role unexpectedly has sale insert permission.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF USER_NAME() = N'week4_inventory_user' REVERT;
    IF ERROR_NUMBER() <> 229 THROW;
    SELECT N'PASS' AS result, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO

PRINT N'ROLE TEST: manager can read funds';
EXECUTE AS USER = N'week4_manager_user';
SELECT N'PASS' AS result, COUNT_BIG(*) AS visible_fund_rows FROM dbo.[fund_flow];
REVERT;
GO
PRINT N'ROLE TEST: manager cannot edit completed sale content';
EXECUTE AS USER = N'week4_manager_user';
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.[sale]
    SET [paid_amount] = [paid_amount]
    WHERE [id] = 1;

    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    REVERT;
    THROW 51032, N'Manager unexpectedly has permission to update sale content.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF USER_NAME() = N'week4_manager_user'
        REVERT;

    IF ERROR_NUMBER() <> 229
        THROW;

    SELECT N'PASS' AS result,
           ERROR_NUMBER() AS error_number,
           ERROR_MESSAGE() AS error_message;
END CATCH;
GO

PRINT N'ROLE TEST: inventory can add a supplier quote';
EXECUTE AS USER = N'week4_inventory_user';

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.[supplier_quote]
        ([supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at])
    VALUES
        (3, 4, 2.75, N'13800000002', '2026-09-20T12:00:00');

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    REVERT;

    SELECT N'PASS' AS result,
           N'inventory supplier quote insert succeeded and was rolled back' AS detail;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    IF USER_NAME() = N'week4_inventory_user'
        REVERT;

    THROW;
END CATCH;
GO
