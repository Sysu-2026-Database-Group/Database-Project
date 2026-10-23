:On Error exit
-- 实例级操作：启用 Windows + SQL Server 身份验证，必须先获准重启实例。
-- 只针对已核对的本机默认实例；不会启用 sa、修改网络协议或开放端口。
USE master;
GO
SET NOCOUNT ON;
IF CONVERT(nvarchar(128),SERVERPROPERTY('MachineName'))<>N'LZQ'
 OR SERVERPROPERTY('InstanceName') IS NOT NULL
    THROW 52030,N'此操作仅用于本机 LZQ 的默认实例。',1;
IF IS_SRVROLEMEMBER(N'sysadmin')<>1
    THROW 52030,N'修改实例认证模式需要 sysadmin。',1;
EXEC master.dbo.xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'LoginMode',REG_DWORD,2;
PRINT N'Mixed authentication configured. Restart MSSQLSERVER to apply; Windows login remains available.';
GO
