:On Error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID('api.operation_request','U') IS NULL THROW 52800,N'Install application first.',1;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.stock_movement') AND name='UX_stock_return_once')
    CREATE UNIQUE INDEX UX_stock_return_once ON dbo.stock_movement(return_item_id) WHERE return_item_id IS NOT NULL;
IF OBJECT_ID('api.return_number','SO') IS NULL EXEC('CREATE SEQUENCE api.return_number AS bigint START WITH 1 INCREMENT BY 1 MAXVALUE 99999999999999999');
GO
CREATE OR ALTER PROCEDURE api.usp_return_source @employee_phone varchar(11),@session_version int,@no varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
    IF NOT EXISTS(SELECT 1 FROM dbo.sale WHERE no=@no) THROW 52804,N'Sale not found.',1;
    SELECT (SELECT s.no,s.sold_at,s.status,CONVERT(varchar(30),s.paid_amount) paid_amount,
        JSON_QUERY(COALESCE((SELECT i.id sale_item_id,i.goods_id,g.name,i.quantity,
            i.quantity-COALESCE((SELECT SUM(quantity) FROM dbo.goods_return_item WHERE sale_item_id=i.id),0) remaining,
            CONVERT(varchar(30),i.unit_price) unit_price FROM dbo.sale_item i JOIN dbo.goods g ON g.id=i.goods_id
            WHERE i.sale_id=s.id ORDER BY i.id FOR JSON PATH),'[]')) items
        FROM dbo.sale s WHERE s.no=@no FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_return_calculate @no varchar(20),@items nvarchar(max),@quote nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sale bigint,@subtotal decimal(10,2),@paid decimal(10,2),@earned int=0,@prior decimal(20,2)=0,@prior_refund decimal(10,2)=0,@prior_points int=0;
    SELECT @sale=id,@subtotal=subtotal_amount,@paid=paid_amount FROM dbo.sale WITH(UPDLOCK,HOLDLOCK) WHERE no=@no;
    IF @sale IS NULL THROW 52804,N'Sale not found.',1;
    IF @subtotal<=0 OR ISJSON(@items)<>1 OR LEFT(LTRIM(@items),1)<>'[' OR DATALENGTH(@items)>16000
        OR (SELECT COUNT(*) FROM OPENJSON(@items)) NOT BETWEEN 1 AND 50 THROW 52801,N'Invalid return.',1;
    DECLARE @lines TABLE(sale_item_id bigint PRIMARY KEY,quantity int,unit_price decimal(10,2),goods_id bigint,name nvarchar(100),refund_amount decimal(10,2));
    INSERT @lines(sale_item_id,quantity) SELECT sale_item_id,quantity FROM OPENJSON(@items) WITH(sale_item_id bigint,quantity int);
    IF EXISTS(SELECT 1 FROM @lines l LEFT JOIN dbo.sale_item i ON i.id=l.sale_item_id AND i.sale_id=@sale
        WHERE i.id IS NULL OR l.quantity IS NULL OR l.quantity<=0 OR l.quantity>i.quantity-COALESCE((SELECT SUM(quantity) FROM dbo.goods_return_item WHERE sale_item_id=i.id),0))
        THROW 52802,N'Quantity exceeds remaining returnable amount.',1;
    UPDATE l SET unit_price=i.unit_price,goods_id=i.goods_id,name=g.name FROM @lines l JOIN dbo.sale_item i ON i.id=l.sale_item_id JOIN dbo.goods g ON g.id=i.goods_id;
    SELECT @earned=COALESCE(SUM(points),0) FROM dbo.point_movement WHERE sale_id=@sale AND change_type=N'消费获得';
    SELECT @prior=COALESCE(SUM(CONVERT(decimal(20,2),r.quantity)*i.unit_price),0) FROM dbo.goods_return_item r JOIN dbo.sale_item i ON i.id=r.sale_item_id WHERE i.sale_id=@sale;
    SELECT @prior_refund=COALESCE(SUM(refund_amount),0) FROM dbo.goods_return WHERE sale_id=@sale;
    SELECT @prior_points=-COALESCE(SUM(points),0) FROM dbo.point_movement WHERE sale_id=@sale AND change_type=N'退货回滚';
    DECLARE @cumulative decimal(20,2)=@prior,@line_id bigint,@qty int,@price decimal(10,2),@before decimal(10,2),@after decimal(10,2);
    DECLARE lines CURSOR LOCAL FAST_FORWARD FOR SELECT sale_item_id,quantity,unit_price FROM @lines ORDER BY sale_item_id;
    OPEN lines; FETCH NEXT FROM lines INTO @line_id,@qty,@price;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @before=ROUND(CONVERT(decimal(28,8),@paid)*@cumulative/@subtotal,2);
        SET @cumulative=@cumulative+@qty*@price;
        SET @after=ROUND(CONVERT(decimal(28,8),@paid)*@cumulative/@subtotal,2);
        UPDATE @lines SET refund_amount=@after-@before WHERE sale_item_id=@line_id;
        FETCH NEXT FROM lines INTO @line_id,@qty,@price;
    END;
    CLOSE lines; DEALLOCATE lines;
    SET @quote=(SELECT @sale sale_id,@no sale_no,
        CONVERT(varchar(30),ROUND(CONVERT(decimal(28,8),@paid)*@cumulative/@subtotal,2)-@prior_refund) refund_amount,
        CONVERT(int,FLOOR(CONVERT(decimal(28,8),@earned)*@cumulative/@subtotal))-@prior_points rollback_points,
        JSON_QUERY((SELECT * FROM @lines ORDER BY sale_item_id FOR JSON PATH)) items FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.usp_return_quote @employee_phone varchar(11),@session_version int,@no varchar(20),@items nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
        DECLARE @quote nvarchar(max);
        EXEC api.usp_return_calculate @no,@items,@quote OUTPUT;
        SET @quote=JSON_MODIFY(@quote,'$.confirmation_expires_at',CONVERT(varchar(33),DATEADD(minute,10,SYSUTCDATETIME()),126));
        COMMIT; SELECT @quote result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_return_create @employee_phone varchar(11),@session_version int,@key uniqueidentifier,@no varchar(20),@items nvarchar(max),@expected nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
        DECLARE @hash binary(32)=HASHBYTES('SHA2_256',CONCAT(@no,':',@items)),@old binary(32),@old_action varchar(30),@result nvarchar(max),@quote nvarchar(max);
        SELECT @old=payload_hash,@old_action=action,@result=result_json FROM api.operation_request WITH(UPDLOCK,HOLDLOCK) WHERE employee_phone=@employee_phone AND request_key=@key;
        IF @old IS NOT NULL
        BEGIN
            IF @old<>@hash OR @old_action<>'return_create' THROW 52303,N'Request conflict.',1;
            COMMIT; SELECT @result result_json; RETURN;
        END;
        IF @key IS NULL THROW 52801,N'Request key required.',1;
        EXEC api.usp_return_calculate @no,@items,@quote OUTPUT;
        IF TRY_CONVERT(datetime2,JSON_VALUE(@expected,'$.confirmation_expires_at')) IS NULL
            OR TRY_CONVERT(datetime2,JSON_VALUE(@expected,'$.confirmation_expires_at'))<=SYSUTCDATETIME()
            THROW 52107,N'Confirmation expired; preview again.',1;
        IF @expected IS NULL OR HASHBYTES('SHA2_256',@quote)<>HASHBYTES('SHA2_256',JSON_MODIFY(@expected,'$.confirmation_expires_at',NULL)) THROW 52107,N'Return conditions changed.',1;
        DECLARE @sale bigint=TRY_CONVERT(bigint,JSON_VALUE(@quote,'$.sale_id')),@refund decimal(10,2)=TRY_CONVERT(decimal(10,2),JSON_VALUE(@quote,'$.refund_amount')),
            @points int=TRY_CONVERT(int,JSON_VALUE(@quote,'$.rollback_points')),@member varchar(11),@return bigint,@balance decimal(12,2)=0,
            @return_no varchar(20)='W7R'+RIGHT(REPLICATE('0',17)+CONVERT(varchar(17),NEXT VALUE FOR api.return_number),17);
        SELECT @member=member_phone FROM dbo.sale WHERE id=@sale;
        IF @member IS NOT NULL
        BEGIN
            DECLARE @member_points int;
            SELECT @member_points=points_balance FROM dbo.member WITH(UPDLOCK,HOLDLOCK) WHERE phone=@member;
            IF CONVERT(bigint,@member_points)-@points< -2147483648 THROW 52802,N'Point balance out of range.',1;
        END;
        INSERT dbo.goods_return(no,sale_id,refund_amount,handled_by) VALUES(@return_no,@sale,@refund,@employee_phone);
        SET @return=SCOPE_IDENTITY();
        INSERT dbo.goods_return_item(return_id,sale_item_id,quantity,refund_amount)
            SELECT @return,sale_item_id,quantity,refund_amount FROM OPENJSON(@quote,'$.items') WITH(sale_item_id bigint,quantity int,refund_amount decimal(10,2));
        IF @points>0
        BEGIN
            INSERT dbo.point_movement(member_phone,change_type,points,sale_id,return_id,changed_by) VALUES(@member,N'退货回滚',-@points,@sale,@return,@employee_phone);
            UPDATE dbo.member SET points_balance=points_balance-@points WHERE phone=@member;
        END;
        IF @refund>0
        BEGIN
            SELECT TOP(1) @balance=fund_after FROM dbo.fund_flow WITH(UPDLOCK,HOLDLOCK) ORDER BY id DESC;
            IF @balance<@refund THROW 52306,N'Insufficient funds.',1;
            INSERT dbo.fund_flow(amount,direction,reason_type,sale_id,return_id,fund_before,fund_after,recorded_by)
                VALUES(@refund,N'付',N'退货退款',@sale,@return,@balance,@balance-@refund,@employee_phone);
        END;
        UPDATE dbo.sale SET status=CASE WHEN NOT EXISTS(SELECT 1 FROM dbo.sale_item i WHERE i.sale_id=@sale AND i.quantity>COALESCE((SELECT SUM(quantity) FROM dbo.goods_return_item WHERE sale_item_id=i.id),0)) THEN N'已全退' ELSE N'部分退款' END WHERE id=@sale;
        SET @result=JSON_MODIFY(JSON_MODIFY(@quote,'$.return_id',@return),'$.return_no',@return_no);
        INSERT api.operation_request(employee_phone,request_key,action,payload_hash,result_json) VALUES(@employee_phone,@key,'return_create',@hash,@result);
        COMMIT; SELECT @result result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_return_pending @employee_phone varchar(11),@session_version int,@page int=1,@page_size int=20
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'库管';
    IF @page IS NULL OR @page NOT BETWEEN 1 AND 1000000 OR @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 100 THROW 52204,N'Invalid pagination.',1;
    SELECT (SELECT @page page,@page_size page_size,
        JSON_QUERY(COALESCE((SELECT i.id return_item_id,r.no return_no,s.goods_id,g.name,i.quantity,r.handled_at
            FROM dbo.goods_return_item i JOIN dbo.goods_return r ON r.id=i.return_id JOIN dbo.sale_item s ON s.id=i.sale_item_id JOIN dbo.goods g ON g.id=s.goods_id
            WHERE NOT EXISTS(SELECT 1 FROM dbo.stock_movement WHERE return_item_id=i.id) ORDER BY i.id
            OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH),'[]')) records FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_return_recover @employee_phone varchar(11),@session_version int,@key uniqueidentifier,@item bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'库管';
        DECLARE @hash binary(32)=HASHBYTES('SHA2_256',CONVERT(varchar(30),@item)),@old binary(32),@old_action varchar(30),@result nvarchar(max),@goods bigint,@qty int;
        SELECT @old=payload_hash,@old_action=action,@result=result_json FROM api.operation_request WITH(UPDLOCK,HOLDLOCK) WHERE employee_phone=@employee_phone AND request_key=@key;
        IF @old IS NOT NULL
        BEGIN
            IF @old<>@hash OR @old_action<>'return_recover' THROW 52303,N'Request conflict.',1;
            COMMIT; SELECT @result result_json; RETURN;
        END;
        IF @key IS NULL THROW 52801,N'Request required.',1;
        SELECT @goods=s.goods_id,@qty=i.quantity FROM dbo.goods_return_item i WITH(UPDLOCK,HOLDLOCK) JOIN dbo.sale_item s ON s.id=i.sale_item_id WHERE i.id=@item;
        IF @goods IS NULL OR EXISTS(SELECT 1 FROM dbo.stock_movement WHERE return_item_id=@item) THROW 52802,N'Return missing or already recovered.',1;
        UPDATE dbo.goods SET stock_total=stock_total+@qty WHERE id=@goods;
        INSERT dbo.stock_movement(goods_id,change_type,quantity,changed_by,return_item_id) VALUES(@goods,N'退货',@qty,@employee_phone,@item);
        SET @result=(SELECT @item return_item_id,@goods goods_id,@qty quantity FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT api.operation_request(employee_phone,request_key,action,payload_hash,result_json) VALUES(@employee_phone,@key,'return_recover',@hash,@result);
        COMMIT; SELECT @result result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_return_source TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_return_quote TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_return_create TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_return_pending TO bookstore_app_inventory;
GRANT EXECUTE ON OBJECT::api.usp_return_recover TO bookstore_app_inventory;
GO
