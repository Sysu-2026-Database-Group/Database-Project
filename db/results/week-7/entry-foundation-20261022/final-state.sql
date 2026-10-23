:On Error exit
USE [ShiguangBookstoreWeek7Entry20261022];
GO
SET NOCOUNT ON;
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>21
    THROW 52020,N'Week7 用户表数量不符。',1;
IF (SELECT COUNT(*) FROM sys.foreign_keys)<>50
    THROW 52020,N'Week7 外码数量不符。',1;
IF EXISTS(SELECT 1 FROM auth.employee_credential)
    THROW 52020,N'测试凭据未回滚。',1;
IF EXISTS(SELECT 1 FROM sys.database_principals WHERE name LIKE N'entry[_]test[_]%')
    THROW 52020,N'测试用户未回滚。',1;
IF (SELECT COUNT(*) FROM sys.database_principals WHERE type='R' AND name IN
    ('bookstore_app_auth','bookstore_app_cashier','bookstore_app_inventory','bookstore_app_manager'))<>4
    THROW 52020,N'应用角色数量不符。',1;
IF (SELECT COUNT(*) FROM sys.procedures WHERE schema_id=SCHEMA_ID(N'api'))<>4
    THROW 52020,N'入口过程数量不符。',1;
IF (SELECT COUNT(*) FROM ShiguangBookstoreWeek6Work.sys.tables WHERE is_ms_shipped=0)<>20
 OR (SELECT COUNT(*) FROM ShiguangBookstoreWeek6Work.sys.foreign_keys)<>49
    THROW 52020,N'Week6 来源库结构计数不符。',1;

-- 此处比较所有业务列，包括 legacy-snapshot.sql 特意排除的 supplier 新增留痕列。
DECLARE @result TABLE(table_name sysname, source_sha256 varchar(64), target_sha256 varchar(64));
DECLARE @table sysname,@columns nvarchar(max),@keys nvarchar(max),@sql nvarchar(max),@source varchar(64),@target varchar(64);
DECLARE tables_to_compare CURSOR LOCAL FAST_FORWARD FOR
 SELECT name FROM sys.tables WHERE schema_id=SCHEMA_ID(N'dbo') AND name<>N'schema_migration' AND is_ms_shipped=0 ORDER BY name;
OPEN tables_to_compare;
FETCH NEXT FROM tables_to_compare INTO @table;
WHILE @@FETCH_STATUS=0
BEGIN
    SELECT @columns=STRING_AGG(CONVERT(nvarchar(max),QUOTENAME(name)),N',') WITHIN GROUP(ORDER BY column_id)
    FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.'+QUOTENAME(@table));
    SELECT @keys=STRING_AGG(CONVERT(nvarchar(max),QUOTENAME(c.name)),N',') WITHIN GROUP(ORDER BY ic.key_ordinal)
    FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
    JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
    WHERE i.object_id=OBJECT_ID(N'dbo.'+QUOTENAME(@table)) AND i.is_primary_key=1;
    IF @keys IS NULL THROW 52020,N'业务表缺少主键。',1;
    SET @sql=N'SELECT @s=CONVERT(varchar(64),HASHBYTES(''SHA2_256'',(SELECT '+@columns
      +N' FROM ShiguangBookstoreWeek6Work.dbo.'+QUOTENAME(@table)+N' ORDER BY '+@keys+N' FOR JSON PATH,INCLUDE_NULL_VALUES)),2);'
      +N'SELECT @t=CONVERT(varchar(64),HASHBYTES(''SHA2_256'',(SELECT '+@columns
      +N' FROM dbo.'+QUOTENAME(@table)+N' ORDER BY '+@keys+N' FOR JSON PATH,INCLUDE_NULL_VALUES)),2);';
    EXEC sys.sp_executesql @sql,N'@s varchar(64) OUTPUT,@t varchar(64) OUTPUT',@s=@source OUTPUT,@t=@target OUTPUT;
    INSERT @result VALUES(@table,@source,@target);
    FETCH NEXT FROM tables_to_compare INTO @table;
END;
CLOSE tables_to_compare;
DEALLOCATE tables_to_compare;
IF (SELECT COUNT(*) FROM @result)<>19 OR EXISTS(SELECT 1 FROM @result WHERE source_sha256<>target_sha256)
    THROW 52020,N'来源与副本的完整业务数据不一致。',1;
SELECT * FROM @result ORDER BY table_name;
SELECT DB_NAME() AS test_database,SUSER_SNAME() AS executed_by,
 CONVERT(int,SERVERPROPERTY('IsIntegratedSecurityOnly')) AS windows_authentication_only,
 (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0) AS user_tables,
 (SELECT COUNT(*) FROM sys.foreign_keys) AS foreign_keys,
 (SELECT COUNT(*) FROM auth.employee_credential) AS remaining_credentials,
 (SELECT COUNT(*) FROM sys.database_principals WHERE name LIKE N'entry[_]test[_]%') AS remaining_test_users;
PRINT N'final-state.sql PASS: 19 complete business tables match source; test users and credentials rolled back.';
GO
