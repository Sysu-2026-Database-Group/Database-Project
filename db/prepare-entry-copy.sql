:On Error exit
-- Runner-owned copy: source is a freshly built Week6 baseline, target is new Week7.
USE master;
GO
SET NOCOUNT ON;
DECLARE @source sysname=N'$(SourceDatabaseName)', @target sysname=N'$(DatabaseName)';
IF @source NOT LIKE N'ShiguangBookstoreWeek6Runner%' OR @target NOT LIKE N'ShiguangBookstoreWeek7%'
 OR @source COLLATE Latin1_General_100_BIN2 LIKE N'%[^A-Za-z0-9_]%'
 OR @target COLLATE Latin1_General_100_BIN2 LIKE N'%[^A-Za-z0-9_]%'
 OR @source=@target
    THROW 52200,N'Invalid runner source or target database.',1;
IF DB_ID(@source) IS NULL OR DB_ID(@target) IS NOT NULL
    THROW 52200,N'Source missing or target already exists; no overwrite allowed.',1;
IF (SELECT COUNT(*) FROM sys.master_files WHERE database_id=DB_ID(@source))<>2
    THROW 52200,N'Expected one data file and one log file.',1;
DECLARE @data_dir nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')),
 @backup_dir nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
IF @data_dir IS NULL OR @backup_dir IS NULL THROW 52200,N'Cannot resolve instance paths.',1;
IF RIGHT(@data_dir,1)<>N'\' SET @data_dir+=N'\';
IF RIGHT(@backup_dir,1)<>N'\' SET @backup_dir+=N'\';
DECLARE @backup nvarchar(4000)=@backup_dir+@target+N'.bak', @data nvarchar(4000)=@data_dir+@target+N'.mdf',
 @log nvarchar(4000)=@data_dir+@target+N'_log.ldf';
IF EXISTS(SELECT 1 FROM (VALUES(@backup),(@data),(@log)) p(path)
 CROSS APPLY sys.dm_os_file_exists(p.path) f WHERE f.file_exists=1 OR f.file_is_a_directory=1)
    THROW 52200,N'Target backup or database files exist; no overwrite allowed.',1;
DECLARE @logical_data sysname=(SELECT name FROM sys.master_files WHERE database_id=DB_ID(@source) AND type=0),
 @logical_log sysname=(SELECT name FROM sys.master_files WHERE database_id=DB_ID(@source) AND type=1);
DECLARE @sql nvarchar(max)=N'BACKUP DATABASE '+QUOTENAME(@source)+N' TO DISK=N'''+REPLACE(@backup,'''','''''')+N''' WITH COPY_ONLY,CHECKSUM; '
 +N'RESTORE VERIFYONLY FROM DISK=N'''+REPLACE(@backup,'''','''''')+N''' WITH CHECKSUM; '
 +N'RESTORE DATABASE '+QUOTENAME(@target)+N' FROM DISK=N'''+REPLACE(@backup,'''','''''')+N''' WITH CHECKSUM, MOVE N'''
 +REPLACE(@logical_data,'''','''''')+N''' TO N'''+REPLACE(@data,'''','''''')+N''', MOVE N'''+REPLACE(@logical_log,'''','''''')
 +N''' TO N'''+REPLACE(@log,'''','''''')+N''';';
EXEC(@sql);
SELECT @source AS source_database,@target AS target_database,@backup AS retained_backup;
GO
