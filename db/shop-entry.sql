:On Error exit
-- P3 public catalogue. A separate identity has no employee/authentication access.
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID('api.usp_operation_read','P') IS NULL
    THROW 52400,N'Install P2 application first.',1;
BEGIN TRANSACTION;
IF DATABASE_PRINCIPAL_ID('bookstore_app_guest') IS NULL CREATE ROLE bookstore_app_guest;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::dbo TO bookstore_app_guest;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::auth TO bookstore_app_guest;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::api TO bookstore_app_guest;
-- An employee connection must not also inherit the public service identity.
DENY EXECUTE ON OBJECT::api.usp_employee_context TO bookstore_app_guest;
GO
CREATE OR ALTER PROCEDURE api.usp_shop_catalog
    @id bigint=NULL,@search nvarchar(100)=N'',@category nvarchar(10)=NULL,@page int=1,@page_size int=20
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(IS_MEMBER('bookstore_app_guest'),0)<>1
        OR IS_MEMBER('bookstore_app_auth')=1 OR IS_MEMBER('bookstore_app_cashier')=1
        OR IS_MEMBER('bookstore_app_inventory')=1 OR IS_MEMBER('bookstore_app_manager')=1
        OR IS_MEMBER('bookstore_app_task')=1
        THROW 52003,N'Use the dedicated public identity.',1;
    IF @page IS NULL OR @page NOT BETWEEN 1 AND 1000000 OR @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 100
        THROW 52204,N'Invalid pagination.',1;
    IF @search IS NULL OR @category NOT IN (N'图书',N'文创') OR (@id IS NOT NULL AND @id<=0)
        THROW 52401,N'Invalid public catalogue filters.',1;
    IF @id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.goods WHERE id=@id AND on_shelf=1 AND price IS NOT NULL)
        THROW 52404,N'Public product not found.',1;
    -- CHARINDEX treats %, _ and brackets literally; all filters are bound.
    SELECT (SELECT @page page,@page_size page_size,
        (SELECT COUNT_BIG(*) FROM dbo.goods g WHERE g.on_shelf=1 AND g.price IS NOT NULL
            AND (@id IS NULL OR g.id=@id) AND (@category IS NULL OR g.category=@category)
            AND (@search=N'' OR CHARINDEX(@search,g.name)>0)) total,
        JSON_QUERY(COALESCE((SELECT g.id,g.category,g.name,CONVERT(varchar(30),g.price) price,
            CAST(CASE WHEN g.stock_total>g.reserved_qty THEN 1 ELSE 0 END AS bit) available,
            g.book_isbn,g.toy_code,b.author,b.publisher,b.page_count,t.spec
            FROM dbo.goods g LEFT JOIN dbo.book b ON b.isbn=g.book_isbn LEFT JOIN dbo.toy t ON t.inner_code=g.toy_code
            WHERE g.on_shelf=1 AND g.price IS NOT NULL AND (@id IS NULL OR g.id=@id)
                AND (@category IS NULL OR g.category=@category) AND (@search=N'' OR CHARINDEX(@search,g.name)>0)
            ORDER BY g.id DESC OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH),N'[]')) records
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_shop_catalog TO bookstore_app_guest;
COMMIT;
PRINT N'shop-entry.sql PASS';
GO
