:On Error exit
-- P2 incremental entry. No instance settings or existing credentials are changed.
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
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID('api.usp_sale_list','P') IS NULL
    THROW 52300,N'Install the Week7 application first.',1;
BEGIN TRANSACTION;
IF OBJECT_ID('api.operation_request','U') IS NULL
    CREATE TABLE api.operation_request(
        employee_phone varchar(11) NOT NULL REFERENCES dbo.employee(phone),
        request_key uniqueidentifier NOT NULL,
        action varchar(30) NOT NULL,
        payload_hash binary(32) NOT NULL,
        result_json nvarchar(max) NOT NULL CHECK(ISJSON(result_json)=1),
        created_at datetime2 NOT NULL DEFAULT SYSDATETIME(),
        PRIMARY KEY(employee_phone,request_key));
IF OBJECT_ID('api.purchase_number','SO') IS NULL
    EXEC('CREATE SEQUENCE api.purchase_number AS bigint START WITH 1 INCREMENT BY 1 MAXVALUE 99999999999999999 NO CYCLE');
GO
-- Fixed action/role map shared by read, preview and mutation. No dynamic SQL.
CREATE OR ALTER PROCEDURE api.usp_operation_actor
    @employee_phone varchar(11),@session_version int,@action varchar(30)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @role nvarchar(10)=CASE
        WHEN @action IN ('inject','withdraw','price','approve','pay','finance') THEN N'店长'
        WHEN @action IN ('goods_save','supplier_save','quote_save','draft','submit','receive','damage','goods_delete') THEN N'库管'
        WHEN @action IN ('goods','suppliers','quotes','purchases','purchase','stock','cancel')
            THEN CASE WHEN IS_MEMBER('bookstore_app_manager')=1 THEN N'店长' ELSE N'库管' END END;
    IF @role IS NULL THROW 52301,N'Unknown operation.',1;
    EXEC api.usp_require_employee @employee_phone,@session_version,@role;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_operation_read
    @employee_phone varchar(11),@session_version int,@action varchar(30),@id bigint=NULL,@page int=1,@page_size int=20,
    @reason nvarchar(10)=NULL,@from_date date=NULL,@to_date date=NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_operation_actor @employee_phone,@session_version,@action;
    IF @page NOT BETWEEN 1 AND 1000000 OR @page_size NOT BETWEEN 1 AND 100 OR @page IS NULL OR @page_size IS NULL
        THROW 52204,N'Invalid pagination.',1;
    IF (@reason IS NOT NULL AND @reason NOT IN(N'购入',N'卖出',N'退货',N'损坏'))
        OR (@from_date IS NOT NULL AND @to_date IS NOT NULL AND @from_date>@to_date) THROW 52204,N'Invalid stock filters.',1;
    DECLARE @records nvarchar(max),@total bigint;
    IF @action='finance'
    BEGIN
        SELECT (SELECT CONVERT(varchar(30),COALESCE((SELECT TOP(1) fund_after FROM dbo.fund_flow ORDER BY id DESC),0)) AS balance,
            JSON_QUERY(COALESCE((SELECT id,CONVERT(varchar(30),amount) amount,direction,reason_type,request_id,sale_id,return_id,member_phone,
                CONVERT(varchar(30),fund_before) fund_before,CONVERT(varchar(30),fund_after) fund_after,recorded_by,recorded_at
                FROM dbo.fund_flow ORDER BY id DESC OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH),'[]')) records,
            (SELECT COUNT_BIG(*) FROM dbo.fund_flow) total,@page page,@page_size page_size
            FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
        RETURN;
    END;
    IF @action='purchase'
    BEGIN
        IF NOT EXISTS(SELECT 1 FROM dbo.purchase_request WHERE id=@id) THROW 52304,N'Purchase not found.',1;
        SELECT (SELECT p.*,s.name supplier_name,
            CONVERT(varchar(30),(SELECT SUM(CONVERT(decimal(18,2),request_qty)*unit_cost) FROM dbo.purchase_request_item WHERE request_id=p.id)) amount,
            CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.fund_flow WHERE request_id=p.id AND reason_type=N'采购付款') THEN 1 ELSE 0 END AS bit) paid,
            JSON_QUERY(COALESCE((SELECT i.goods_id,g.name,i.request_qty,CONVERT(varchar(30),i.unit_cost) unit_cost
                FROM dbo.purchase_request_item i JOIN dbo.goods g ON g.id=i.goods_id WHERE i.request_id=p.id ORDER BY i.goods_id FOR JSON PATH),N'[]')) items
            FROM dbo.purchase_request p JOIN dbo.supplier s ON s.id=p.supplier_id WHERE p.id=@id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
        RETURN;
    END;
    IF @action='goods'
    BEGIN
        SELECT @total=COUNT_BIG(*) FROM dbo.goods;
        SET @records=(SELECT g.*,b.author,b.publisher,b.page_count,t.spec FROM dbo.goods g
            LEFT JOIN dbo.book b ON b.isbn=g.book_isbn LEFT JOIN dbo.toy t ON t.inner_code=g.toy_code
            ORDER BY g.id DESC OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
    END
    ELSE IF @action='suppliers'
    BEGIN
        SELECT @total=COUNT_BIG(*) FROM dbo.supplier;
        SET @records=(SELECT * FROM dbo.supplier ORDER BY id DESC OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
    END
    ELSE IF @action='quotes'
    BEGIN
        SELECT @total=COUNT_BIG(*) FROM dbo.supplier_quote;
        SET @records=(SELECT q.*,s.name supplier_name,g.name goods_name FROM dbo.supplier_quote q JOIN dbo.supplier s ON s.id=q.supplier_id
            JOIN dbo.goods g ON g.id=q.goods_id ORDER BY q.supplier_id,q.goods_id
            OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
    END
    ELSE IF @action='purchases'
    BEGIN
        SELECT @total=COUNT_BIG(*) FROM dbo.purchase_request;
        SET @records=(SELECT p.*,s.name supplier_name FROM dbo.purchase_request p JOIN dbo.supplier s ON s.id=p.supplier_id ORDER BY p.id DESC
            OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
    END
    ELSE IF @action='stock'
    BEGIN
        SELECT @total=COUNT_BIG(*) FROM dbo.stock_movement WHERE (@id IS NULL OR goods_id=@id)
            AND (@reason IS NULL OR change_type=@reason) AND (@from_date IS NULL OR CONVERT(date,changed_at)>=@from_date)
            AND (@to_date IS NULL OR CONVERT(date,changed_at)<=@to_date);
        SET @records=(SELECT * FROM dbo.stock_movement WHERE (@id IS NULL OR goods_id=@id)
            AND (@reason IS NULL OR change_type=@reason) AND (@from_date IS NULL OR CONVERT(date,changed_at)>=@from_date)
            AND (@to_date IS NULL OR CONVERT(date,changed_at)<=@to_date) ORDER BY id DESC
            OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
    END
    ELSE THROW 52301,N'Unknown read.',1;
    SELECT (SELECT JSON_QUERY(COALESCE(@records,'[]')) records,@total total,@page page,@page_size page_size FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_operation_quote
    @employee_phone varchar(11),@session_version int,@action varchar(30),@payload nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_operation_actor @employee_phone,@session_version,@action;
    DECLARE @amount decimal(10,2),@id bigint=TRY_CONVERT(bigint,JSON_VALUE(@payload,'$.id'));
    IF @action IN ('inject','withdraw') SET @amount=TRY_CONVERT(decimal(10,2),JSON_VALUE(@payload,'$.amount'));
    ELSE IF @action='pay'
    BEGIN
        IF NOT EXISTS(SELECT 1 FROM dbo.purchase_request WHERE id=@id AND status=N'已审批')
            THROW 52302,N'Purchase must be approved.',1;
        IF EXISTS(SELECT 1 FROM dbo.fund_flow WHERE request_id=@id AND reason_type=N'采购付款')
            THROW 52302,N'Purchase already paid.',1;
        SELECT @amount=SUM(CONVERT(decimal(18,2),request_qty)*unit_cost) FROM dbo.purchase_request_item WHERE request_id=@id;
    END
    ELSE THROW 52301,N'No monetary preview for this action.',1;
    IF @amount IS NULL OR @amount<=0 THROW 52301,N'Invalid amount.',1;
    SELECT (SELECT @action action,@id id,CONVERT(varchar(30),@amount) amount,
        CONVERT(varchar(33),DATEADD(minute,10,SYSDATETIME()),126) expires_at
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_operation_write
    @employee_phone varchar(11),@session_version int,@action varchar(30),@request_key uniqueidentifier,
    @payload nvarchar(max),@quote nvarchar(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISJSON(@payload)<>1 OR DATALENGTH(@payload)>24000 OR @request_key IS NULL THROW 52301,N'Invalid request.',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_operation_actor @employee_phone,@session_version,@action;
        DECLARE @hash binary(32)=HASHBYTES('SHA2_256',@payload),@old_hash binary(32),@old_action varchar(30),@result nvarchar(max);
        SELECT @old_hash=payload_hash,@old_action=action,@result=result_json FROM api.operation_request WITH(UPDLOCK,HOLDLOCK)
            WHERE employee_phone=@employee_phone AND request_key=@request_key;
        IF @old_hash IS NOT NULL
        BEGIN
            IF @old_hash<>@hash OR @old_action<>@action THROW 52303,N'Request key conflicts with successful content.',1;
            COMMIT;
            SELECT @result result_json;
            RETURN;
        END;
        DECLARE @id bigint=TRY_CONVERT(bigint,JSON_VALUE(@payload,'$.id')),
            @supplier bigint=TRY_CONVERT(bigint,JSON_VALUE(@payload,'$.supplier_id')),
            @goods bigint=TRY_CONVERT(bigint,JSON_VALUE(@payload,'$.goods_id')),
            @name nvarchar(100)=JSON_VALUE(@payload,'$.name'),@now datetime2=SYSDATETIME(),
            @amount decimal(10,2)=TRY_CONVERT(decimal(10,2),JSON_VALUE(@payload,'$.amount')),
            @status nvarchar(10),@balance decimal(12,2)=0,@lock int;
        IF @action IN ('goods_save','supplier_save','quote_save')
        BEGIN
            EXEC @lock=sys.sp_getapplock @Resource='bookstore-p2-catalog',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
            IF @lock<0 THROW 52302,N'Catalog busy.',1;
        END;
        IF @action='goods_save'
        BEGIN
            DECLARE @category nvarchar(10)=JSON_VALUE(@payload,'$.category'),@code varchar(20)=JSON_VALUE(@payload,'$.code'),
                @author nvarchar(100)=JSON_VALUE(@payload,'$.author'),@publisher nvarchar(100)=JSON_VALUE(@payload,'$.publisher'),
                @pages int=TRY_CONVERT(int,JSON_VALUE(@payload,'$.page_count')),@spec nvarchar(100)=JSON_VALUE(@payload,'$.spec');
            IF NULLIF(LTRIM(RTRIM(@name)),'') IS NULL OR NULLIF(@code,'') IS NULL OR @category NOT IN (N'图书',N'文创') OR @category IS NULL
                THROW 52301,N'Invalid goods fields.',1;
            IF @id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.goods WHERE id=@id AND category=@category
                AND COALESCE(book_isbn,toy_code)=@code) THROW 52302,N'Category and business code cannot change.',1;
            IF @category=N'图书'
            BEGIN
                IF @author IS NULL OR @publisher IS NULL OR @pages IS NULL OR @pages<=0 OR LEN(@code) NOT BETWEEN 10 AND 17
                    THROW 52301,N'Invalid book.',1;
                IF @id IS NULL INSERT dbo.book(isbn,author,publisher,page_count) VALUES(@code,@author,@publisher,@pages);
                ELSE UPDATE dbo.book SET author=@author,publisher=@publisher,page_count=@pages WHERE isbn=@code;
            END
            ELSE
            BEGIN
                IF NULLIF(LTRIM(RTRIM(@spec)),'') IS NULL THROW 52301,N'Invalid creative product.',1;
                IF @id IS NULL INSERT dbo.toy(inner_code,spec) VALUES(@code,@spec);
                ELSE UPDATE dbo.toy SET spec=@spec WHERE inner_code=@code;
            END;
            IF @id IS NULL
            BEGIN
                INSERT dbo.goods(category,name,book_isbn,toy_code,price,on_shelf,stock_total,reserved_qty,created_by)
                    VALUES(@category,@name,CASE WHEN @category=N'图书' THEN @code END,CASE WHEN @category=N'文创' THEN @code END,NULL,0,0,0,@employee_phone);
                SET @id=SCOPE_IDENTITY();
            END
            ELSE UPDATE dbo.goods SET name=@name,updated_by=@employee_phone,updated_at=@now WHERE id=@id;
        END
        ELSE IF @action='supplier_save'
        BEGIN
            IF NULLIF(LTRIM(RTRIM(@name)),'') IS NULL THROW 52301,N'Invalid supplier name.',1;
            IF @id IS NULL
            BEGIN
                INSERT dbo.supplier(name,created_by) VALUES(@name,@employee_phone);
                SET @id=SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                UPDATE dbo.supplier SET name=@name,updated_by=@employee_phone,updated_at=@now WHERE id=@id;
                IF @@ROWCOUNT=0 THROW 52304,N'Supplier not found.',1;
            END;
        END
        ELSE IF @action='quote_save'
        BEGIN
            IF @amount IS NULL OR @amount<=0 THROW 52301,N'Invalid cost.',1;
            UPDATE dbo.supplier_quote SET quote_amount=@amount,reported_by=@employee_phone,reported_at=@now WHERE supplier_id=@supplier AND goods_id=@goods;
            IF @@ROWCOUNT=0 INSERT dbo.supplier_quote(supplier_id,goods_id,quote_amount,reported_by) VALUES(@supplier,@goods,@amount,@employee_phone);
        END
        ELSE IF @action='price'
        BEGIN
            DECLARE @shelf bit=TRY_CONVERT(bit,JSON_VALUE(@payload,'$.on_shelf'));
            IF @amount IS NULL OR @amount<=0 OR @shelf IS NULL THROW 52301,N'Invalid price.',1;
            UPDATE dbo.goods SET price=@amount,on_shelf=@shelf,updated_by=@employee_phone,updated_at=@now WHERE id=@id;
            IF @@ROWCOUNT=0 THROW 52304,N'Goods not found.',1;
        END
        ELSE IF @action IN ('draft','submit','cancel','approve','pay','receive')
        BEGIN
            IF @id IS NOT NULL
            BEGIN
                SELECT @status=status FROM dbo.purchase_request WITH(UPDLOCK,HOLDLOCK) WHERE id=@id;
                IF @status IS NULL THROW 52304,N'Purchase not found.',1;
            END
            ELSE IF @action<>'draft' THROW 52301,N'Purchase required.',1;
            IF @action='draft'
            BEGIN
                IF @id IS NOT NULL AND @status<>N'草稿' THROW 52302,N'Only drafts can be edited.',1;
                DECLARE @items nvarchar(max)=JSON_QUERY(@payload,'$.items');
                DECLARE @lines TABLE(goods_id bigint PRIMARY KEY,quantity int,unit_cost decimal(10,2));
                IF @items IS NULL OR LEFT(@items,1)<>'[' OR (SELECT COUNT(*) FROM OPENJSON(@items))>50 THROW 52301,N'Invalid items.',1;
                INSERT @lines SELECT goods_id,quantity,unit_cost FROM OPENJSON(@items) WITH(goods_id bigint,quantity int,unit_cost decimal(10,2));
                IF EXISTS(SELECT 1 FROM @lines WHERE goods_id IS NULL OR quantity IS NULL OR quantity NOT BETWEEN 1 AND 1000 OR unit_cost IS NULL OR unit_cost<=0)
                    THROW 52301,N'Invalid line.',1;
                IF EXISTS(SELECT 1 FROM @lines l WHERE NOT EXISTS(SELECT 1 FROM dbo.supplier_quote q WHERE q.goods_id=l.goods_id AND q.supplier_id=@supplier))
                    THROW 52301,N'Every item must have a quote from this supplier.',1;
                IF @id IS NULL
                BEGIN
                    DECLARE @number bigint=NEXT VALUE FOR api.purchase_number;
                    INSERT dbo.purchase_request(no,supplier_id,created_by) VALUES('W7P'+RIGHT(REPLICATE('0',17)+CONVERT(varchar(17),@number),17),@supplier,@employee_phone);
                    SET @id=SCOPE_IDENTITY();
                END
                ELSE UPDATE dbo.purchase_request SET supplier_id=@supplier WHERE id=@id;
                DELETE dbo.purchase_request_item WHERE request_id=@id;
                INSERT dbo.purchase_request_item(request_id,goods_id,request_qty,unit_cost) SELECT @id,goods_id,quantity,unit_cost FROM @lines;
            END
            ELSE IF @action='submit'
            BEGIN
                IF @status<>N'草稿' OR NOT EXISTS(SELECT 1 FROM dbo.purchase_request_item WHERE request_id=@id) THROW 52302,N'Only nonempty drafts can submit.',1;
                UPDATE dbo.purchase_request SET status=N'已提交',submitted_by=@employee_phone,submitted_at=@now WHERE id=@id;
            END
            ELSE IF @action='cancel'
            BEGIN
                IF @status NOT IN (N'草稿',N'已提交') THROW 52302,N'Only draft/submitted purchases can cancel.',1;
                UPDATE dbo.purchase_request SET status=N'已取消',cancelled_by=@employee_phone,cancelled_at=@now WHERE id=@id;
            END
            ELSE IF @action='approve'
            BEGIN
                IF @status<>N'已提交' THROW 52302,N'Only submitted purchases can approve.',1;
                UPDATE dbo.purchase_request SET status=N'已审批',approved_by=@employee_phone,approved_at=@now WHERE id=@id;
            END
            ELSE IF @action='pay'
            BEGIN
                IF @status<>N'已审批' OR EXISTS(SELECT 1 FROM dbo.fund_flow WHERE request_id=@id AND reason_type=N'采购付款')
                    THROW 52302,N'Purchase must be approved and unpaid.',1;
                SELECT @amount=SUM(CONVERT(decimal(18,2),request_qty)*unit_cost) FROM dbo.purchase_request_item WHERE request_id=@id;
            END
            ELSE IF @action='receive'
            BEGIN
                IF @status<>N'已审批' OR NOT EXISTS(SELECT 1 FROM dbo.fund_flow WHERE request_id=@id AND reason_type=N'采购付款')
                    THROW 52302,N'Only paid approved purchases can receive.',1;
                DECLARE @receive_goods bigint,@qty int,@current int;
                DECLARE goods_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT goods_id,request_qty FROM dbo.purchase_request_item WHERE request_id=@id ORDER BY goods_id;
                OPEN goods_cursor;
                FETCH NEXT FROM goods_cursor INTO @receive_goods,@qty;
                WHILE @@FETCH_STATUS=0
                BEGIN
                    SELECT @current=stock_total FROM dbo.goods WITH(UPDLOCK,HOLDLOCK) WHERE id=@receive_goods;
                    UPDATE dbo.goods SET stock_total=stock_total+@qty WHERE id=@receive_goods;
                    INSERT dbo.stock_movement(goods_id,change_type,quantity,changed_by,request_id) VALUES(@receive_goods,N'购入',@qty,@employee_phone,@id);
                    FETCH NEXT FROM goods_cursor INTO @receive_goods,@qty;
                END;
                CLOSE goods_cursor;
                DEALLOCATE goods_cursor;
                UPDATE dbo.purchase_request SET status=N'已收货' WHERE id=@id;
            END;
        END
        ELSE IF @action='damage'
        BEGIN
            DECLARE @loss int=TRY_CONVERT(int,JSON_VALUE(@payload,'$.quantity')),@note nvarchar(200)=JSON_VALUE(@payload,'$.note');
            IF @loss IS NULL OR @loss NOT BETWEEN 1 AND 1000 OR NULLIF(LTRIM(RTRIM(@note)),'') IS NULL THROW 52301,N'Quantity and reason required.',1;
            UPDATE dbo.goods WITH(UPDLOCK,HOLDLOCK) SET stock_total=stock_total-@loss WHERE id=@id AND stock_total-reserved_qty>=@loss;
            IF @@ROWCOUNT=0 THROW 52302,N'Insufficient available stock.',1;
            INSERT dbo.stock_movement(goods_id,change_type,quantity,note,changed_by) VALUES(@id,N'损坏',-@loss,@note,@employee_phone);
        END
        ELSE IF @action='goods_delete'
        BEGIN
            IF @id IS NULL THROW 52301,N'Goods required.',1;
            DECLARE @del_stock int,@del_reserved int,@del_shelf bit;
            SELECT @del_stock=stock_total,@del_reserved=reserved_qty,@del_shelf=on_shelf FROM dbo.goods WITH(UPDLOCK,HOLDLOCK) WHERE id=@id;
            IF @del_stock IS NULL THROW 52304,N'Goods not found.',1;
            IF @del_stock<>0 OR @del_reserved<>0 THROW 52307,N'该商品有库存，不能删除。',1;
            IF @del_shelf<>0 THROW 52308,N'请先下架再删除。',1;
            IF EXISTS(SELECT 1 FROM dbo.sale_item WHERE goods_id=@id)
                OR EXISTS(SELECT 1 FROM dbo.purchase_request_item WHERE goods_id=@id)
                OR EXISTS(SELECT 1 FROM dbo.reservation_item WHERE goods_id=@id)
                OR EXISTS(SELECT 1 FROM dbo.stock_movement WHERE goods_id=@id)
                OR EXISTS(SELECT 1 FROM dbo.supplier_quote WHERE goods_id=@id)
                THROW 52309,N'该商品已被单据引用，不能删除。',1;
            DELETE dbo.goods WHERE id=@id;
        END
        ELSE IF @action NOT IN ('inject','withdraw') THROW 52301,N'Unknown write.',1;
        IF @action IN ('inject','withdraw','pay')
        BEGIN
            IF @amount IS NULL OR @amount<=0 OR ISJSON(@quote)<>1
                OR COALESCE(JSON_VALUE(@quote,'$.action'),'')<>@action
                OR COALESCE(TRY_CONVERT(decimal(10,2),JSON_VALUE(@quote,'$.amount')),-1)<>@amount
                OR (@action='pay' AND COALESCE(TRY_CONVERT(bigint,JSON_VALUE(@quote,'$.id')),-1)<>@id)
                OR TRY_CONVERT(datetime2,JSON_VALUE(@quote,'$.expires_at')) IS NULL
                OR TRY_CONVERT(datetime2,JSON_VALUE(@quote,'$.expires_at'))<@now
                THROW 52305,N'Preview expired or changed; preview again.',1;
            -- Same last-row/range locking as sale commit, after purchase/product locks.
            SELECT TOP(1) @balance=fund_after FROM dbo.fund_flow WITH(UPDLOCK,HOLDLOCK) ORDER BY id DESC;
            IF @action IN ('pay','withdraw') AND @balance<@amount THROW 52306,N'Insufficient funds.',1;
            DECLARE @after decimal(12,2)=@balance+CASE WHEN @action='inject' THEN @amount ELSE -@amount END;
            INSERT dbo.fund_flow(amount,direction,reason_type,request_id,fund_before,fund_after,recorded_by)
                VALUES(@amount,CASE WHEN @action='inject' THEN N'收' ELSE N'付' END,
                    CASE WHEN @action='inject' THEN N'注资' WHEN @action='withdraw' THEN N'提现' ELSE N'采购付款' END,CASE WHEN @action='pay' THEN @id END,@balance,@after,@employee_phone);
            IF @action IN ('inject','withdraw') SET @id=SCOPE_IDENTITY();
        END;
        SET @result=(SELECT @action action,@id id,@request_key request_key,CONVERT(varchar(30),@amount) amount FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT api.operation_request(employee_phone,request_key,action,payload_hash,result_json) VALUES(@employee_phone,@request_key,@action,@hash,@result);
        COMMIT;
        SELECT @result result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_operation_read TO bookstore_app_inventory,bookstore_app_manager;
GRANT EXECUTE ON OBJECT::api.usp_operation_quote TO bookstore_app_manager;
GRANT EXECUTE ON OBJECT::api.usp_operation_write TO bookstore_app_inventory,bookstore_app_manager;
COMMIT;
PRINT N'operations-entry.sql PASS';
GO
