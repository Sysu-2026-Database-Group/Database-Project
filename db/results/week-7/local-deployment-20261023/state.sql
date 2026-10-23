:On Error exit
USE ShiguangBookstoreWeek7EntryYourRun;
GO
SET NOCOUNT ON;
SELECT CONVERT(int,SERVERPROPERTY('IsIntegratedSecurityOnly')) AS windows_only,DB_NAME() AS configured_database;
SELECT name,is_disabled,IS_SRVROLEMEMBER(N'sysadmin',name) AS sysadmin_member
FROM sys.server_principals WHERE name LIKE N'bookstore[_]w7[_]yourrun[_]%' ORDER BY name;
SELECT member.name AS service_user,role.name AS database_role
FROM sys.database_role_members m
JOIN sys.database_principals member ON m.member_principal_id=member.principal_id
JOIN sys.database_principals role ON m.role_principal_id=role.principal_id
WHERE member.name LIKE N'bookstore[_]w7[_]yourrun[_]%' ORDER BY member.name,role.name;
SELECT e.phone,e.role,c.enabled,c.session_version
FROM dbo.employee e JOIN auth.employee_credential c ON e.phone=c.employee_phone ORDER BY e.phone;
SELECT (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0) AS user_tables,
 (SELECT COUNT(*) FROM sys.foreign_keys) AS foreign_keys,
 (SELECT COUNT(*) FROM ShiguangBookstoreWeek6Work.sys.tables WHERE is_ms_shipped=0) AS source_tables,
 (SELECT COUNT(*) FROM ShiguangBookstoreWeek6Work.sys.foreign_keys) AS source_foreign_keys;
GO
