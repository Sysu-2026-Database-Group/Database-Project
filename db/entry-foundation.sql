:On Error exit
-- 第七周入口基础。仅向全新 Week7 练习副本部署；来源须已完成第六周迁移。
-- 不重新执行 role.sql；该文件仍是第4/6周历史验收入口。
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%'
    THROW 52000, N'入口基础只允许部署到 ShiguangBookstoreWeek7 专用副本。', 1;
IF @@TRANCOUNT<>0 THROW 52000, N'部署时不得存在外层事务。', 1;
IF OBJECT_ID(N'dbo.schema_migration',N'U') IS NULL
    THROW 52000, N'请先从已完成第六周迁移的数据库建立副本。', 1;
IF NOT EXISTS(SELECT 1 FROM dbo.schema_migration WHERE migration_key='W6-NORMALIZATION-1.0' AND status=N'已完成')
    THROW 52000, N'第六周迁移完成记录不存在。', 1;
IF EXISTS(SELECT 1 FROM sys.schemas WHERE name IN(N'auth',N'api') AND principal_id<>DATABASE_PRINCIPAL_ID(N'dbo'))
    THROW 52000, N'入口模式必须由 dbo 拥有，以保持静态 SQL 所有权链。', 1;
BEGIN TRANSACTION;
IF SCHEMA_ID(N'auth') IS NULL EXEC(N'CREATE SCHEMA auth AUTHORIZATION dbo');
IF SCHEMA_ID(N'api') IS NULL EXEC(N'CREATE SCHEMA api AUTHORIZATION dbo');
IF OBJECT_ID(N'auth.employee_credential',N'U') IS NULL
BEGIN
    CREATE TABLE auth.employee_credential (
        employee_phone VARCHAR(11) NOT NULL CONSTRAINT PK_employee_credential PRIMARY KEY,
        password_hash VARCHAR(512) NOT NULL,
        enabled BIT NOT NULL CONSTRAINT DF_employee_credential_enabled DEFAULT (1),
        session_version INT NOT NULL CONSTRAINT DF_employee_credential_version DEFAULT (1),
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_employee_credential_updated DEFAULT (SYSDATETIME()),
        CONSTRAINT FK_employee_credential_employee FOREIGN KEY(employee_phone) REFERENCES dbo.employee(phone),
        CONSTRAINT CK_employee_credential_hash CHECK(LEN(password_hash)>20),
        CONSTRAINT CK_employee_credential_version CHECK(session_version>0)
    );
END;
IF DATABASE_PRINCIPAL_ID(N'bookstore_app_auth') IS NULL CREATE ROLE bookstore_app_auth;
IF DATABASE_PRINCIPAL_ID(N'bookstore_app_cashier') IS NULL CREATE ROLE bookstore_app_cashier;
IF DATABASE_PRINCIPAL_ID(N'bookstore_app_inventory') IS NULL CREATE ROLE bookstore_app_inventory;
IF DATABASE_PRINCIPAL_ID(N'bookstore_app_manager') IS NULL CREATE ROLE bookstore_app_manager;
-- 新应用账号只加入对应的一个新角色，不能加入旧角色、db_datareader/db_datawriter/db_owner。
-- 静态存储过程与表同属 dbo，可经所有权链访问；直接操作底表仍被拒绝。
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO bookstore_app_auth, bookstore_app_cashier, bookstore_app_inventory, bookstore_app_manager;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::auth TO bookstore_app_auth, bookstore_app_cashier, bookstore_app_inventory, bookstore_app_manager;
GO
CREATE OR ALTER PROCEDURE api.usp_employee_login_lookup
    @employee_phone VARCHAR(11)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.phone, e.name, e.role, c.password_hash, c.enabled, c.session_version
    FROM dbo.employee e JOIN auth.employee_credential c ON c.employee_phone=e.phone
    WHERE e.phone=@employee_phone;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_employee_session_lookup
    @employee_phone VARCHAR(11), @session_version INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.phone, e.name, e.role, c.session_version
    FROM dbo.employee e JOIN auth.employee_credential c ON c.employee_phone=e.phone
    WHERE e.phone=@employee_phone AND c.enabled=1 AND c.session_version=@session_version;
END;
GO
-- 内部辅助过程：不授予运行账号直接 EXECUTE；业务过程用固定岗位调用它。
-- @employee_phone / @session_version 由 Flask 已验证会话提供，不接收前端操作人字段。
CREATE OR ALTER PROCEDURE api.usp_require_employee
    @employee_phone VARCHAR(11), @session_version INT, @required_role NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @db_role sysname = CASE @required_role
        WHEN N'收银员' THEN N'bookstore_app_cashier'
        WHEN N'库管' THEN N'bookstore_app_inventory'
        WHEN N'店长' THEN N'bookstore_app_manager' END;
    IF @db_role IS NULL OR ISNULL(IS_MEMBER(@db_role),0)<>1
        THROW 52003, N'数据库调用身份不具备该岗位权限。', 1;
    IF (ISNULL(IS_MEMBER(N'bookstore_app_cashier'),0)+ISNULL(IS_MEMBER(N'bookstore_app_inventory'),0)
        +ISNULL(IS_MEMBER(N'bookstore_app_manager'),0)+ISNULL(IS_MEMBER(N'bookstore_app_auth'),0))<>1
        THROW 52003, N'应用数据库账号必须只属于一个应用角色。', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.employee e JOIN auth.employee_credential c ON c.employee_phone=e.phone
        WHERE e.phone=@employee_phone AND e.role=@required_role AND c.enabled=1 AND c.session_version=@session_version)
        THROW 52001, N'员工会话已失效或岗位不匹配，请重新登录。', 1;
END;
GO
-- 第一个受控读取入口，用于验证身份链；不声称已经实现销售。
CREATE OR ALTER PROCEDURE api.usp_employee_context
    @employee_phone VARCHAR(11), @session_version INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @role NVARCHAR(10) = CASE
        WHEN IS_MEMBER(N'bookstore_app_cashier')=1 THEN N'收银员'
        WHEN IS_MEMBER(N'bookstore_app_inventory')=1 THEN N'库管'
        WHEN IS_MEMBER(N'bookstore_app_manager')=1 THEN N'店长' END;
    EXEC api.usp_require_employee @employee_phone, @session_version, @role;
    SELECT phone,name,role FROM dbo.employee WHERE phone=@employee_phone;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_employee_login_lookup TO bookstore_app_auth;
GRANT EXECUTE ON OBJECT::api.usp_employee_session_lookup TO bookstore_app_auth;
GRANT EXECUTE ON OBJECT::api.usp_employee_context TO bookstore_app_cashier, bookstore_app_inventory, bookstore_app_manager;
COMMIT;
PRINT N'entry-foundation.sql PASS: credential storage and restricted procedure roles installed; no runtime logins provisioned.';
GO
