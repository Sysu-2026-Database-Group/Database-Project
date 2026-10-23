:On Error exit
USE ShiguangBookstoreWeek7SaleTests20261023;
GO
SET NOCOUNT ON;
IF EXISTS(SELECT 1 FROM api.sale_request) OR EXISTS(SELECT 1 FROM dbo.sale WHERE no LIKE 'W7S%')
    THROW 52190,N'销售测试数据未清理。',1;
IF EXISTS(SELECT 1 FROM auth.employee_credential) OR EXISTS(SELECT 1 FROM sys.database_principals WHERE name LIKE N'bookstore[_]w7[_]yourrun[_]%')
    THROW 52190,N'销售测试凭据或用户未清理。',1;
IF OBJECT_ID(N'dbo.sale_test_fail_fund',N'TR') IS NOT NULL
    THROW 52190,N'故障注入触发器未清理。',1;
SELECT DB_NAME() AS test_database,(SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0) AS user_tables,
 (SELECT COUNT(*) FROM sys.foreign_keys) AS foreign_keys,(SELECT COUNT(*) FROM sys.procedures WHERE schema_id=SCHEMA_ID(N'api')) AS api_procedures;
USE ShiguangBookstoreWeek7EntryYourRun;
IF EXISTS(SELECT 1 FROM api.sale_request) OR EXISTS(SELECT 1 FROM dbo.sale WHERE no LIKE 'W7S%')
    THROW 52190,N'运行副本被写入了销售测试数据。',1;
IF (SELECT COUNT(*) FROM auth.employee_credential)<>4
    THROW 52190,N'运行员工凭据数量异常。',1;
SELECT DB_NAME() AS runtime_database,(SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0) AS user_tables,
 (SELECT COUNT(*) FROM sys.foreign_keys) AS foreign_keys,(SELECT COUNT(*) FROM sys.procedures WHERE schema_id=SCHEMA_ID(N'api')) AS api_procedures,
 (SELECT COUNT(*) FROM api.sale_request) AS sale_requests;
PRINT N'final-state.sql PASS: test data and fault injection cleaned; runtime has no test sales; employee credentials retained.';
GO
