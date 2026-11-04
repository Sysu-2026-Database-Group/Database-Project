:On Error exit
-- Administrative, read-only deployment diagnostics. Checks precise role grants.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
DECLARE @expected TABLE(role_name sysname,procedure_name sysname);
INSERT @expected VALUES
    ('bookstore_app_auth','usp_employee_login_lookup'),
    ('bookstore_app_auth','usp_employee_session_lookup'),
    ('bookstore_app_cashier','usp_employee_context'),
    ('bookstore_app_inventory','usp_employee_context'),
    ('bookstore_app_manager','usp_employee_context'),
    ('bookstore_app_cashier','usp_sale_catalog'),
    ('bookstore_app_cashier','usp_sale_quote'),
    ('bookstore_app_cashier','usp_sale_create'),
    ('bookstore_app_cashier','usp_sale_get'),
    ('bookstore_app_cashier','usp_sale_list'),
    ('bookstore_app_inventory','usp_operation_read'),
    ('bookstore_app_manager','usp_operation_read'),
    ('bookstore_app_inventory','usp_operation_write'),
    ('bookstore_app_manager','usp_operation_write'),
    ('bookstore_app_manager','usp_operation_quote'),
    ('bookstore_app_guest','usp_shop_catalog'),
    ('bookstore_app_guest','usp_reservation_create'),
    ('bookstore_app_guest','usp_reservation_lookup'),
    ('bookstore_app_guest','usp_reservation_cancel'),
    ('bookstore_app_cashier','usp_reservation_cancel'),
    ('bookstore_app_cashier','usp_pickup_quote'),
    ('bookstore_app_cashier','usp_pickup_create'),
    ('bookstore_app_task','usp_reservations_expire'),
    ('bookstore_app_manager','usp_management_read'),
    ('bookstore_app_manager','usp_management_write'),
    ('bookstore_app_cashier','usp_member_read'),
    ('bookstore_app_cashier','usp_member_quote'),
    ('bookstore_app_cashier','usp_member_create'),
    ('bookstore_app_cashier','usp_member_contact'),
    ('bookstore_app_guest','usp_member_self'),
    ('bookstore_app_cashier','usp_return_source'),
    ('bookstore_app_cashier','usp_return_quote'),
    ('bookstore_app_cashier','usp_return_create'),
    ('bookstore_app_inventory','usp_return_pending'),
    ('bookstore_app_inventory','usp_return_recover');
IF EXISTS (SELECT 1 FROM @expected e LEFT JOIN sys.database_permissions p
    ON p.grantee_principal_id=DATABASE_PRINCIPAL_ID(e.role_name)
    AND p.class=1 AND p.major_id=OBJECT_ID(N'api.'+e.procedure_name,N'P')
    AND p.minor_id=0 AND p.permission_name=N'EXECUTE' AND p.state='G'
    WHERE p.major_id IS NULL)
    THROW 52205,N'Missing application role or precise procedure grant.',1;
IF EXISTS (SELECT 1 FROM sys.database_permissions p
    JOIN sys.database_principals r ON r.principal_id=p.grantee_principal_id
    WHERE (r.name IN ('bookstore_app_auth','bookstore_app_cashier','bookstore_app_inventory','bookstore_app_manager','bookstore_app_guest','bookstore_app_task')
           OR r.name='public') AND p.state IN('G','W')
    AND NOT (r.name='public' AND p.class=0 AND p.permission_name IN ('CONNECT','VIEW ANY COLUMN MASTER KEY DEFINITION','VIEW ANY COLUMN ENCRYPTION KEY DEFINITION'))
    AND NOT (r.name='public' AND p.class=1 AND OBJECT_SCHEMA_NAME(p.major_id) IN ('sys','INFORMATION_SCHEMA'))
    AND NOT EXISTS(SELECT 1 FROM @expected e WHERE e.role_name=r.name
        AND p.class=1 AND p.minor_id=0 AND p.major_id=OBJECT_ID(N'api.'+e.procedure_name,N'P')
        AND p.permission_name=N'EXECUTE' AND p.state='G'))
    THROW 52205,N'Unexpected application/public grant; do not grant schema-wide access.',1;
IF EXISTS(SELECT 1 FROM sys.database_role_members m JOIN sys.database_principals r
    ON r.principal_id=m.member_principal_id
    WHERE r.name IN ('bookstore_app_auth','bookstore_app_cashier','bookstore_app_inventory','bookstore_app_manager','bookstore_app_guest','bookstore_app_task'))
    THROW 52205,N'Application roles must not inherit another role.',1;
IF EXISTS (SELECT 1 FROM (VALUES ('bookstore_app_auth'),('bookstore_app_cashier'),
    ('bookstore_app_inventory'),('bookstore_app_manager'),('bookstore_app_guest'),('bookstore_app_task')) roles(name)
    CROSS JOIN (VALUES ('dbo'),('auth'),('api')) schemas(name)
    CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) actions(name)
    WHERE NOT EXISTS (SELECT 1 FROM sys.database_permissions p
        WHERE p.grantee_principal_id=DATABASE_PRINCIPAL_ID(roles.name)
        AND p.class=3 AND p.major_id=SCHEMA_ID(schemas.name)
        AND p.permission_name=actions.name AND p.state='D'))
    THROW 52205,N'Missing explicit application table-access denial.',1;
IF EXISTS(SELECT 1 FROM sys.schemas WHERE name IN('dbo','auth','api') AND principal_id<>DATABASE_PRINCIPAL_ID('dbo'))
    THROW 52205,N'Unexpected schema owner.',1;
IF OBJECT_ID(N'auth.employee_credential',N'U') IS NULL OR OBJECT_ID(N'api.sale_request',N'U') IS NULL
    OR OBJECT_ID(N'api.sale_number',N'SO') IS NULL
    OR OBJECT_ID(N'api.usp_require_employee',N'P') IS NULL
    OR OBJECT_ID(N'api.usp_sale_calculate',N'P') IS NULL
    OR OBJECT_ID(N'api.usp_sale_result',N'P') IS NULL
    OR OBJECT_ID(N'api.operation_request',N'U') IS NULL
    OR OBJECT_ID(N'api.purchase_number',N'SO') IS NULL
    OR OBJECT_ID(N'api.usp_operation_actor',N'P') IS NULL
    OR OBJECT_ID(N'api.usp_sale_commit',N'P') IS NULL
    OR OBJECT_ID(N'api.reservation_request',N'U') IS NULL
    OR OBJECT_ID(N'api.reservation_cancellation',N'U') IS NULL
    OR OBJECT_ID(N'api.usp_reservation_release',N'P') IS NULL
    OR OBJECT_ID(N'dbo.member_service',N'U') IS NULL
    OR OBJECT_ID(N'dbo.member_contact_history',N'U') IS NULL
    OR OBJECT_ID(N'auth.member_access',N'U') IS NULL
    OR OBJECT_ID(N'auth.member_contact',N'U') IS NULL
    OR OBJECT_ID(N'api.usp_member_calculate',N'P') IS NULL
    OR OBJECT_ID(N'api.usp_return_calculate',N'P') IS NULL
    OR NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.stock_movement') AND name='UX_stock_return_once' AND is_unique=1 AND is_disabled=0)
    THROW 52205,N'Missing application storage, sequence or internal procedure.',1;
PRINT N'application-permissions-check.sql PASS';
GO
