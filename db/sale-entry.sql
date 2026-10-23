:On Error exit
-- UTF-8; sqlcmd -f 65001。仅部署到已具备入口基础的 Week7 副本。
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
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID(N'api.usp_require_employee',N'P') IS NULL
    THROW 52100,N'请先在 Week7 副本部署员工入口基础。',1;
IF @@TRANCOUNT<>0 THROW 52100,N'部署不得存在外层事务。',1;
IF EXISTS(SELECT 1 FROM sys.schemas WHERE name=N'api' AND principal_id<>DATABASE_PRINCIPAL_ID(N'dbo'))
    THROW 52100,N'api 模式必须由 dbo 拥有。',1;
BEGIN TRANSACTION;
IF OBJECT_ID(N'api.sale_number',N'SO') IS NULL
    EXEC(N'CREATE SEQUENCE api.sale_number AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 99999999999999999 NO CYCLE');
IF OBJECT_ID(N'api.sale_request',N'U') IS NULL
    CREATE TABLE api.sale_request(
        employee_phone varchar(11) NOT NULL,
        request_key uniqueidentifier NOT NULL,
        payload_hash binary(32) NOT NULL,
        sale_id bigint NOT NULL,
        result_json nvarchar(max) NOT NULL,
        created_at datetime2 NOT NULL CONSTRAINT DF_sale_request_created DEFAULT(SYSDATETIME()),
        CONSTRAINT PK_sale_request PRIMARY KEY(employee_phone,request_key),
        CONSTRAINT UQ_sale_request_sale UNIQUE(sale_id),
        CONSTRAINT FK_sale_request_employee FOREIGN KEY(employee_phone) REFERENCES dbo.employee(phone),
        CONSTRAINT FK_sale_request_sale FOREIGN KEY(sale_id) REFERENCES dbo.sale(id),
        CONSTRAINT CK_sale_request_json CHECK(ISJSON(result_json)=1)
    );
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::api TO bookstore_app_auth,bookstore_app_cashier,bookstore_app_inventory,bookstore_app_manager;
GO
-- 内部计算过程；仅供同所有者过程调用。调用者须已开启事务。
CREATE OR ALTER PROCEDURE api.usp_sale_calculate
    @items nvarchar(max),@member_phone varchar(11),@used_points int,@quote nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT=0 THROW 52100,N'结算计算需要事务。',1;
    IF ISJSON(@items)<>1 OR LEFT(LTRIM(@items),1)<>N'[' OR DATALENGTH(@items)>16000
        THROW 52101,N'商品明细格式不正确。',1;
    DECLARE @lines TABLE(goods_id bigint PRIMARY KEY,quantity int,unit_price decimal(10,2),name nvarchar(100));
    IF (SELECT COUNT(*) FROM OPENJSON(@items)) NOT BETWEEN 1 AND 50
        THROW 52101,N'每单须有1至50种商品。',1;
    IF EXISTS(SELECT 1 FROM OPENJSON(@items) j WHERE j.type<>5)
        THROW 52101,N'商品明细必须为对象。',1;
    IF EXISTS(SELECT 1 FROM OPENJSON(@items) j
        OUTER APPLY(SELECT COUNT(*) AS n FROM OPENJSON(j.value) WHERE [key]='goods_id' AND type=2 AND TRY_CONVERT(bigint,value)>0 AND value NOT LIKE '%[^0-9]%') g
        OUTER APPLY(SELECT COUNT(*) AS n FROM OPENJSON(j.value) WHERE [key]='quantity' AND type=2 AND TRY_CONVERT(int,value) BETWEEN 1 AND 1000 AND value NOT LIKE '%[^0-9]%') q
        WHERE g.n<>1 OR q.n<>1 OR (SELECT COUNT(*) FROM OPENJSON(j.value))<>2)
        THROW 52101,N'商品编号和数量必须为整数，数量范围1至1000。',1;
    IF EXISTS(SELECT goods_id FROM OPENJSON(@items) WITH(goods_id bigint '$.goods_id') GROUP BY goods_id HAVING COUNT(*)>1)
        THROW 52101,N'同一商品不可重复列出。',1;
    IF @used_points IS NULL OR @used_points<0 THROW 52101,N'使用积分必须为非负整数。',1;
    IF @member_phone IS NOT NULL AND (LEN(@member_phone)<>11 OR @member_phone COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%')
        THROW 52101,N'会员手机号格式不正确。',1;
    INSERT @lines(goods_id,quantity) SELECT goods_id,quantity FROM OPENJSON(@items) WITH(goods_id bigint '$.goods_id',quantity int '$.quantity');
    DECLARE @card nvarchar(10)=NULL,@rate decimal(3,2)=1,@balance int=0,@expires date,@active bit=0;
    IF @member_phone IS NOT NULL
    BEGIN
        SELECT @card=card_level,@balance=points_balance,@expires=expires_at FROM dbo.member WITH(UPDLOCK,HOLDLOCK) WHERE phone=@member_phone;
        IF @expires IS NULL THROW 52102,N'会员不存在；非会员请留空会员手机号。',1;
        -- 门店日期固定采用中国标准时间，不接受客户端传入成交日期。
        IF @expires>=CONVERT(date,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time')
        BEGIN
            SET @active=1;
            SELECT @rate=discount_rate FROM dbo.card_type WITH(HOLDLOCK) WHERE [level]=@card;
        END
        ELSE SET @card=NULL;
    END;
    -- 所有请求按商品主码升序取更新锁，减少反向多商品请求的死锁风险。
    DECLARE @goods bigint,@quantity int,@price decimal(10,2),@name nvarchar(100),@available int,@on_shelf bit;
    DECLARE goods_to_lock CURSOR LOCAL FAST_FORWARD FOR SELECT goods_id,quantity FROM @lines ORDER BY goods_id;
    OPEN goods_to_lock;
    FETCH NEXT FROM goods_to_lock INTO @goods,@quantity;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @price=NULL; SET @on_shelf=0;
        SELECT @price=price,@name=name,@available=stock_total-reserved_qty,@on_shelf=on_shelf
        FROM dbo.goods WITH(UPDLOCK,HOLDLOCK) WHERE id=@goods;
        IF @on_shelf<>1 OR @price IS NULL THROW 52103,N'商品不存在、未上架或未定价。',1;
        IF @available<@quantity THROW 52104,N'商品可售量不足，请调整数量后重新预览。',1;
        UPDATE @lines SET unit_price=@price,name=@name WHERE goods_id=@goods;
        FETCH NEXT FROM goods_to_lock INTO @goods,@quantity;
    END;
    CLOSE goods_to_lock; DEALLOCATE goods_to_lock;
    DECLARE @total decimal(20,2)=(SELECT SUM(CONVERT(decimal(20,2),unit_price)*quantity) FROM @lines);
    IF @total>99999999.99 THROW 52101,N'单笔金额超出支持范围。',1;
    DECLARE @subtotal decimal(10,2)=@total,@discounted decimal(10,2)=ROUND(@total*@rate,2),@maximum int=0;
    IF @active=1 AND @balance>0 SET @maximum=CASE WHEN @balance<FLOOR(@discounted*20) THEN @balance ELSE CONVERT(int,FLOOR(@discounted*20)) END;
    IF @used_points>@maximum THROW 52105,N'积分抵扣超过本次上限，请减少使用积分。',1;
    DECLARE @deduction decimal(10,2)=CONVERT(decimal(10,2),@used_points/100.0),@paid decimal(10,2),@earned int=0;
    SET @paid=@discounted-@deduction;
    IF @active=1 SET @earned=CONVERT(int,FLOOR(@paid));
    IF CONVERT(bigint,@balance)-@used_points+@earned>2147483647 THROW 52101,N'会员积分余额超出支持范围。',1;
    SET @quote=(SELECT @member_phone AS member_phone,@active AS member_active,@card AS card_level,@rate AS discount_rate,
        @subtotal AS subtotal_amount,@discounted AS discounted_amount,@used_points AS used_points,@deduction AS point_deduction_amount,
        @paid AS paid_amount,@earned AS earned_points,
        JSON_QUERY((SELECT goods_id,quantity,unit_price,name FROM @lines ORDER BY goods_id FOR JSON PATH)) AS items
        FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.usp_sale_catalog
    @employee_phone varchar(11),@session_version int
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
    SELECT id,name,price,stock_total,reserved_qty,stock_total-reserved_qty AS available_qty,on_shelf
    FROM dbo.goods ORDER BY id;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_sale_quote
    @employee_phone varchar(11),@session_version int,@items nvarchar(max),@member_phone varchar(11)=NULL,@used_points int=0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0 THROW 52100,N'结算入口不得存在外层事务。',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
        DECLARE @quote nvarchar(max);
        EXEC api.usp_sale_calculate @items,@member_phone,@used_points,@quote OUTPUT;
        COMMIT;
        SELECT @quote AS quote_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_sale_result
    @sale_id bigint,@result nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @result=(SELECT s.id,s.no,s.status,s.cashier_by,s.sold_at,s.member_phone,s.card_level,s.subtotal_amount,s.discount_rate,
        s.point_deduction_amount,s.paid_amount,
        ISNULL((SELECT SUM(points) FROM dbo.point_movement WHERE sale_id=s.id AND change_type=N'消费获得'),0) AS earned_points,
        JSON_QUERY((SELECT i.goods_id,g.name,i.quantity,i.unit_price FROM dbo.sale_item i JOIN dbo.goods g ON g.id=i.goods_id WHERE sale_id=s.id ORDER BY i.goods_id FOR JSON PATH)) AS items
        FROM dbo.sale s WHERE s.id=@sale_id FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.usp_sale_create
    @employee_phone varchar(11),@session_version int,@request_key uniqueidentifier,
    @items nvarchar(max),@member_phone varchar(11),@used_points int,@expected_quote nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET ANSI_WARNINGS ON; SET ANSI_PADDING ON; SET CONCAT_NULL_YIELDS_NULL ON; SET ARITHABORT ON; SET NUMERIC_ROUNDABORT OFF;
    IF @@TRANCOUNT<>0 THROW 52100,N'销售入口不得存在外层事务。',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
        IF @request_key IS NULL OR ISJSON(@items)<>1 THROW 52101,N'销售请求格式不正确。',1;
        -- 正规化请求内容：重试不依赖当前价格、会员状态或库存，仍比较原请求内容。
        DECLARE @payload nvarchar(max)=(SELECT @member_phone AS member_phone,@used_points AS used_points,
            JSON_QUERY((SELECT goods_id,quantity FROM OPENJSON(@items) WITH(goods_id bigint '$.goods_id',quantity int '$.quantity') ORDER BY goods_id FOR JSON PATH)) AS items
            FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
        DECLARE @hash binary(32)=HASHBYTES('SHA2_256',@payload),@oldhash binary(32),@result nvarchar(max);
        SELECT @oldhash=payload_hash,@result=result_json FROM api.sale_request WITH(UPDLOCK,HOLDLOCK)
        WHERE employee_phone=@employee_phone AND request_key=@request_key;
        IF @oldhash IS NOT NULL
        BEGIN
            IF @oldhash<>@hash THROW 52106,N'同一请求标识不能用于不同的销售内容。',1;
            COMMIT;
            SELECT @result AS result_json;
            RETURN;
        END;
        DECLARE @quote nvarchar(max);
        EXEC api.usp_sale_calculate @items,@member_phone,@used_points,@quote OUTPUT;
        IF @expected_quote IS NULL OR HASHBYTES('SHA2_256',@quote)<>HASHBYTES('SHA2_256',@expected_quote)
            THROW 52107,N'价格或会员结算条件已变化，请重新预览并确认收款。',1;
        DECLARE @now datetime2=CONVERT(datetime2,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time');
        DECLARE @no varchar(20)='W7S'+RIGHT(REPLICATE('0',17)+CONVERT(varchar(17),NEXT VALUE FOR api.sale_number),17),@sale bigint;
        DECLARE @subtotal decimal(10,2),@rate decimal(3,2),@deduction decimal(10,2),@paid decimal(10,2),@earned int,@card nvarchar(10);
        SELECT @subtotal=subtotal_amount,@rate=discount_rate,@deduction=point_deduction_amount,@paid=paid_amount,@earned=earned_points,@card=card_level
        FROM OPENJSON(@quote) WITH(subtotal_amount decimal(10,2),discount_rate decimal(3,2),point_deduction_amount decimal(10,2),paid_amount decimal(10,2),earned_points int,card_level nvarchar(10));
        INSERT dbo.sale(no,cashier_by,sold_at,member_phone,card_level,subtotal_amount,discount_rate,point_deduction_amount,paid_amount)
        VALUES(@no,@employee_phone,@now,@member_phone,@card,@subtotal,@rate,@deduction,@paid);
        SET @sale=SCOPE_IDENTITY();
        INSERT dbo.sale_item(sale_id,goods_id,quantity,unit_price)
        SELECT @sale,goods_id,quantity,unit_price FROM OPENJSON(@quote,'$.items') WITH(goods_id bigint,quantity int,unit_price decimal(10,2));
        UPDATE g SET stock_total=stock_total-i.quantity FROM dbo.goods g
        JOIN dbo.sale_item i ON i.goods_id=g.id AND i.sale_id=@sale;
        INSERT dbo.stock_movement(goods_id,change_type,quantity,changed_by,changed_at,sale_id)
        SELECT goods_id,N'卖出',-quantity,@employee_phone,@now,@sale FROM dbo.sale_item WHERE sale_id=@sale;
        IF @used_points>0
            INSERT dbo.point_movement(member_phone,change_type,points,sale_id,changed_by,changed_at)
            VALUES(@member_phone,N'抵扣使用',-@used_points,@sale,@employee_phone,@now);
        IF @earned>0
            INSERT dbo.point_movement(member_phone,change_type,points,sale_id,changed_by,changed_at)
            VALUES(@member_phone,N'消费获得',@earned,@sale,@employee_phone,@now);
        IF @used_points>0 OR @earned>0
            UPDATE dbo.member SET points_balance=points_balance-@used_points+@earned WHERE phone=@member_phone;
        -- 锁住最新资金行及末端范围，销售串行追加余额链，避免并发丢失余额。
        IF @paid>0
        BEGIN
            DECLARE @fund decimal(12,2)=0;
            SELECT TOP(1) @fund=fund_after FROM dbo.fund_flow WITH(UPDLOCK,HOLDLOCK) ORDER BY id DESC;
            INSERT dbo.fund_flow(amount,direction,reason_type,sale_id,fund_before,fund_after,recorded_by,recorded_at)
            VALUES(@paid,N'收',N'销售收款',@sale,@fund,@fund+@paid,@employee_phone,@now);
        END;
        EXEC api.usp_sale_result @sale,@result OUTPUT;
        INSERT api.sale_request(employee_phone,request_key,payload_hash,sale_id,result_json)
        VALUES(@employee_phone,@request_key,@hash,@sale,@result);
        COMMIT;
        SELECT @result AS result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_sale_get
    @employee_phone varchar(11),@session_version int,@sale_no varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
    DECLARE @sale bigint,@result nvarchar(max);
    SELECT @sale=id FROM dbo.sale WHERE no=@sale_no AND cashier_by=@employee_phone;
    IF @sale IS NULL THROW 52108,N'销售单不存在或不属于当前收银员。',1;
    EXEC api.usp_sale_result @sale,@result OUTPUT;
    SELECT @result AS result_json;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_sale_catalog TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_sale_quote TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_sale_create TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_sale_get TO bookstore_app_cashier;
COMMIT;
PRINT N'sale-entry.sql PASS: cashier sale preview, atomic creation, idempotency and own receipt installed.';
GO
