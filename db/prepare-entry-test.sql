:On Error exit
-- 管理员手动入口：从已迁移的 Week6Work 建立全新副本，不覆盖已有库或文件。
-- sqlcmd -S localhost -E -C -b -f 65001 -i db/prepare-entry-test.sql -v DatabaseName=ShiguangBookstoreWeek7EntryYYYYMMDDHHMMSS
USE master;
GO
SET NOCOUNT ON;
DECLARE @target sysname=N'$(DatabaseName)', @source sysname=N'ShiguangBookstoreWeek6Work';
IF @target NOT LIKE N'ShiguangBookstoreWeek7%' OR @target COLLATE Latin1_General_100_BIN2 LIKE N'%[^A-Za-z0-9_]%'
    THROW 52010,N'目标必须为新的 ShiguangBookstoreWeek7 副本。',1;
IF DB_ID(@target) IS NOT NULL THROW 52010,N'目标已存在，禁止覆盖。',1;
IF DB_ID(@source) IS NULL THROW 52010,N'来源 Week6Work 不存在。',1;
IF NOT EXISTS(SELECT 1 FROM ShiguangBookstoreWeek6Work.dbo.schema_migration WHERE migration_key='W6-NORMALIZATION-1.0' AND status=N'已完成')
    THROW 52010,N'来源尚未完成第六周迁移。',1;
IF (SELECT COUNT(*) FROM sys.master_files WHERE database_id=DB_ID(@source))<>2
    THROW 52010,N'此入口要求来源恰有一个数据文件和一个日志文件。',1;
DECLARE @data_dir nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath'));
DECLARE @backup_dir nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
IF @data_dir IS NULL OR @backup_dir IS NULL THROW 52010,N'无法取得实例文件目录。',1;
IF RIGHT(@data_dir,1)<>N'\' SET @data_dir+=N'\';
IF RIGHT(@backup_dir,1)<>N'\' SET @backup_dir+=N'\';
DECLARE @backup nvarchar(4000)=@backup_dir+@target+N'.bak', @data nvarchar(4000)=@data_dir+@target+N'.mdf',
    @log nvarchar(4000)=@data_dir+@target+N'_log.ldf';
IF EXISTS(SELECT 1 FROM (VALUES(@backup),(@data),(@log)) p(path)
    CROSS APPLY sys.dm_os_file_exists(p.path) f WHERE f.file_exists=1 OR f.file_is_a_directory=1)
    THROW 52010,N'目标文件已存在，禁止覆盖。',1;
DECLARE @logical_data sysname=(SELECT name FROM sys.master_files WHERE database_id=DB_ID(@source) AND type=0);
DECLARE @logical_log sysname=(SELECT name FROM sys.master_files WHERE database_id=DB_ID(@source) AND type=1);
DECLARE @sql nvarchar(max)=N'BACKUP DATABASE '+QUOTENAME(@source)+N' TO DISK=N'''+REPLACE(@backup,'''','''''')+N''' WITH COPY_ONLY,CHECKSUM; '
    +N'RESTORE VERIFYONLY FROM DISK=N'''+REPLACE(@backup,'''','''''')+N''' WITH CHECKSUM; '
    +N'RESTORE DATABASE '+QUOTENAME(@target)+N' FROM DISK=N'''+REPLACE(@backup,'''','''''')+N''' WITH CHECKSUM, MOVE N'''
    +REPLACE(@logical_data,'''','''''')+N''' TO N'''+REPLACE(@data,'''','''''')+N''', MOVE N'''+REPLACE(@logical_log,'''','''''')
    +N''' TO N'''+REPLACE(@log,'''','''''')+N''';';
EXEC(@sql);
SELECT @source AS source_database,@target AS test_database,@backup AS copy_only_backup;
GO
