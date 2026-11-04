:On Error exit
-- Cashier's own documents; no shop-wide browsing authorization.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%'
    OR OBJECT_ID(N'api.usp_sale_get',N'P') IS NULL
    THROW 52203,N'Install employee and sale entry on the Week7 copy first.',1;
BEGIN TRANSACTION;
GO
CREATE OR ALTER PROCEDURE api.usp_sale_list
    @employee_phone varchar(11),@session_version int,@page int=1,@page_size int=20
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
    IF @page IS NULL OR @page NOT BETWEEN 1 AND 1000000
        OR @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 100
        THROW 52204,N'Invalid pagination.',1;
    SELECT (SELECT @page AS page,@page_size AS page_size,
        (SELECT COUNT_BIG(*) FROM dbo.sale WHERE cashier_by=@employee_phone) AS total,
        JSON_QUERY(COALESCE((SELECT no,status,sold_at,CONVERT(varchar(30),paid_amount) AS paid_amount
            FROM dbo.sale WHERE cashier_by=@employee_phone ORDER BY sold_at DESC,id DESC
            OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH),N'[]')) AS records
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS result_json;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_sale_list TO bookstore_app_cashier;
COMMIT;
PRINT N'workspace-entry.sql PASS';
GO
