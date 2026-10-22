:On Error exit
-- 按主键排序，对 19 张旧业务表的完整旧列计算 SHA-256；不改业务表。
-- supplier 的两列 W6 新增留痕不属于旧列；schema_migration 不属于旧业务表。
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
DECLARE @result TABLE (table_name sysname, row_count bigint, content_sha256 varchar(64));
DECLARE @table sysname, @columns nvarchar(max), @keys nvarchar(max), @sql nvarchar(max);
DECLARE @count bigint, @hash varchar(64);
DECLARE legacy_tables CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.tables
    WHERE schema_id=SCHEMA_ID(N'dbo') AND is_ms_shipped=0 AND name<>N'schema_migration'
    ORDER BY name;
OPEN legacy_tables;
FETCH NEXT FROM legacy_tables INTO @table;
WHILE @@FETCH_STATUS=0
BEGIN
    SELECT @columns=STRING_AGG(CONVERT(nvarchar(max),QUOTENAME(name)),N',') WITHIN GROUP (ORDER BY column_id)
    FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.'+QUOTENAME(@table))
      AND NOT (@table=N'supplier' AND name IN (N'updated_by',N'updated_at'));
    SELECT @keys=STRING_AGG(CONVERT(nvarchar(max),QUOTENAME(c.name)),N',') WITHIN GROUP (ORDER BY ic.key_ordinal)
    FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
    JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
    WHERE i.object_id=OBJECT_ID(N'dbo.'+QUOTENAME(@table)) AND i.is_primary_key=1;
    IF @keys IS NULL THROW 51980,N'快照对象缺少主键，无法稳定排序。',1;
    SET @sql=N'SELECT @n=COUNT_BIG(*) FROM dbo.'+QUOTENAME(@table)+N';
      SELECT @h=CONVERT(varchar(64),HASHBYTES(''SHA2_256'',
        (SELECT '+@columns+N' FROM dbo.'+QUOTENAME(@table)+N' ORDER BY '+@keys+N' FOR JSON PATH,INCLUDE_NULL_VALUES)),2);';
    EXEC sys.sp_executesql @sql,N'@n bigint OUTPUT,@h varchar(64) OUTPUT',@n=@count OUTPUT,@h=@hash OUTPUT;
    INSERT @result VALUES(@table,@count,@hash);
    FETCH NEXT FROM legacy_tables INTO @table;
END;
CLOSE legacy_tables;
DEALLOCATE legacy_tables;
IF (SELECT COUNT(*) FROM @result)<>19 THROW 51981,N'旧业务表快照不是19项。',1;
SELECT table_name,row_count,content_sha256 FROM @result ORDER BY table_name;
