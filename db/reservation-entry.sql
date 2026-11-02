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
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID('api.usp_shop_catalog','P') IS NULL
    THROW 52500,N'Install public catalogue first.',1;
BEGIN TRANSACTION;
IF DATABASE_PRINCIPAL_ID('bookstore_app_task') IS NULL CREATE ROLE bookstore_app_task;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::dbo TO bookstore_app_task;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::auth TO bookstore_app_task;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::api TO bookstore_app_task;
IF OBJECT_ID('api.reservation_request','U') IS NULL
    CREATE TABLE api.reservation_request(
        request_key uniqueidentifier NOT NULL PRIMARY KEY,
        payload_hash binary(32) NOT NULL,
        reservation_id bigint NOT NULL REFERENCES dbo.reservation(id),
        code_hash binary(32) NOT NULL,
        created_at datetime2 NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID('api.reservation_cancellation','U') IS NULL
    CREATE TABLE api.reservation_cancellation(
        request_key uniqueidentifier NOT NULL PRIMARY KEY,
        payload_hash binary(32) NOT NULL,
        result_json nvarchar(max) NOT NULL CHECK(ISJSON(result_json)=1));
GO
CREATE OR ALTER PROCEDURE api.usp_reservation_result
    @id bigint,@result nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @result=(SELECT r.code,r.phone,r.status,r.created_at,r.expires_at,
        CAST(CASE WHEN r.status=N'有效' AND r.expires_at>CONVERT(datetime2,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time')
            AND NOT EXISTS(SELECT 1 FROM dbo.reservation_item i JOIN dbo.goods g ON g.id=i.goods_id WHERE i.reservation_id=r.id AND (g.on_shelf=0 OR g.price IS NULL)) THEN 1 ELSE 0 END AS bit) pickup_available,
        JSON_QUERY(COALESCE((SELECT i.goods_id,g.name,i.quantity FROM dbo.reservation_item i JOIN dbo.goods g ON g.id=i.goods_id
            WHERE i.reservation_id=r.id ORDER BY i.goods_id FOR JSON PATH),N'[]')) items
        FROM dbo.reservation r WHERE r.id=@id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.usp_reservation_create
    @request_key uniqueidentifier,@phone varchar(11),@code varchar(20),@items nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISNULL(IS_MEMBER('bookstore_app_guest'),0)<>1 THROW 52003,N'Guest identity required.',1;
    IF @request_key IS NULL OR @phone IS NULL OR LEN(@phone)<>11 OR @phone LIKE '%[^0-9]%'
        OR @code IS NULL OR LEN(@code)<>20 OR @code COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Z2-7]%'
        OR ISJSON(@items)<>1 OR DATALENGTH(@items)>16000 OR LEFT(LTRIM(@items),1)<>'['
        THROW 52501,N'Invalid reservation.',1;
    DECLARE @lines TABLE(goods_id bigint PRIMARY KEY,quantity int);
    IF (SELECT COUNT(*) FROM OPENJSON(@items)) NOT BETWEEN 1 AND 50 THROW 52501,N'Invalid items.',1;
    IF EXISTS(SELECT 1 FROM OPENJSON(@items) WHERE type<>5) THROW 52501,N'Invalid line.',1;
    INSERT @lines SELECT goods_id,quantity FROM OPENJSON(@items) WITH(goods_id bigint,quantity int);
    IF EXISTS(SELECT 1 FROM @lines WHERE goods_id IS NULL OR quantity IS NULL OR goods_id<=0 OR quantity NOT BETWEEN 1 AND 1000)
        THROW 52501,N'Invalid line.',1;
    DECLARE @payload nvarchar(max)=(SELECT @phone phone,JSON_QUERY((SELECT * FROM @lines ORDER BY goods_id FOR JSON PATH)) items FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    DECLARE @hash binary(32)=HASHBYTES('SHA2_256',@payload),@old binary(32),@id bigint,@result nvarchar(max);
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @old=payload_hash,@id=reservation_id FROM api.reservation_request WITH(UPDLOCK,HOLDLOCK) WHERE request_key=@request_key;
        IF @old IS NOT NULL
        BEGIN
            IF @old<>@hash OR NOT EXISTS(SELECT 1 FROM api.reservation_request WHERE request_key=@request_key AND code_hash=HASHBYTES('SHA2_256',@code))
                THROW 52503,N'Request conflict.',1;
        END
        ELSE
        BEGIN
            DECLARE @goods bigint,@qty int,@stock int,@shelf bit,@price decimal(10,2),@now datetime2=CONVERT(datetime2,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time');
            DECLARE locks CURSOR LOCAL FAST_FORWARD FOR SELECT goods_id,quantity FROM @lines ORDER BY goods_id;
            OPEN locks; FETCH NEXT FROM locks INTO @goods,@qty;
            WHILE @@FETCH_STATUS=0
            BEGIN
                SET @shelf=0; SET @stock=0;
                SELECT @stock=stock_total-reserved_qty,@shelf=on_shelf,@price=price FROM dbo.goods WITH(UPDLOCK,HOLDLOCK) WHERE id=@goods;
                IF @shelf<>1 OR @price IS NULL THROW 52103,N'Goods unavailable.',1;
                IF @stock<@qty THROW 52104,N'Insufficient available stock.',1;
                FETCH NEXT FROM locks INTO @goods,@qty;
            END;
            CLOSE locks; DEALLOCATE locks;
            INSERT dbo.reservation(code,phone,created_at,expires_at) VALUES(@code,@phone,@now,DATEADD(day,3,@now));
            SET @id=SCOPE_IDENTITY();
            INSERT dbo.reservation_item(reservation_id,goods_id,quantity) SELECT @id,goods_id,quantity FROM @lines;
            UPDATE g SET reserved_qty=reserved_qty+l.quantity FROM dbo.goods g JOIN @lines l ON g.id=l.goods_id;
            INSERT api.reservation_request(request_key,payload_hash,reservation_id,code_hash) VALUES(@request_key,@hash,@id,HASHBYTES('SHA2_256',@code));
        END;
        EXEC api.usp_reservation_result @id,@result OUTPUT;
        COMMIT; SELECT @result result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_reservation_lookup
    @phone varchar(11),@code varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(IS_MEMBER('bookstore_app_guest'),0)<>1 THROW 52003,N'Guest required.',1;
    DECLARE @id bigint,@result nvarchar(max);
    SELECT @id=id FROM dbo.reservation WHERE phone=@phone AND code=@code;
    IF @id IS NULL THROW 52504,N'Invalid reservation credential.',1;
    EXEC api.usp_reservation_result @id,@result OUTPUT;
    SELECT @result result_json;
END;
GO
-- Shared release routine: caller owns the reservation update lock.
CREATE OR ALTER PROCEDURE api.usp_reservation_release
    @id bigint,@status nvarchar(10),@employee varchar(11)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT=0 THROW 52500,N'Transaction required.',1;
    DECLARE @goods bigint,@qty int,@reserved int;
    DECLARE locks CURSOR LOCAL FAST_FORWARD FOR SELECT goods_id,quantity FROM dbo.reservation_item WHERE reservation_id=@id ORDER BY goods_id;
    OPEN locks; FETCH NEXT FROM locks INTO @goods,@qty;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SELECT @reserved=reserved_qty FROM dbo.goods WITH(UPDLOCK,HOLDLOCK) WHERE id=@goods;
        IF @reserved<@qty THROW 52502,N'Reserved stock inconsistency.',1;
        UPDATE dbo.goods SET reserved_qty=reserved_qty-@qty WHERE id=@goods;
        FETCH NEXT FROM locks INTO @goods,@qty;
    END;
    CLOSE locks; DEALLOCATE locks;
    UPDATE dbo.reservation SET status=@status,
        cancelled_by_employee=CASE WHEN @status=N'已取消' THEN @employee END,
        cancelled_at=CASE WHEN @status=N'已取消' THEN CONVERT(datetime2,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time') END WHERE id=@id;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_reservation_cancel
    @phone varchar(11),@code varchar(20),@employee_phone varchar(11)=NULL,@session_version int=NULL,@request_key uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @employee_phone IS NULL
    BEGIN
        IF ISNULL(IS_MEMBER('bookstore_app_guest'),0)<>1 THROW 52003,N'Guest required.',1;
    END
    ELSE EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @id bigint,@status nvarchar(10),@expiry datetime2,@result nvarchar(max);
        IF @request_key IS NULL THROW 52501,N'Cancellation request key required.',1;
        DECLARE @hash binary(32)=HASHBYTES('SHA2_256',CONCAT(@phone,':',@code,':',COALESCE(@employee_phone,'guest'))),@old binary(32);
        SELECT @old=payload_hash,@result=result_json FROM api.reservation_cancellation WITH(UPDLOCK,HOLDLOCK) WHERE request_key=@request_key;
        IF @old IS NOT NULL
        BEGIN
            IF @old<>@hash THROW 52503,N'Cancellation request conflict.',1;
            COMMIT; SELECT @result result_json; RETURN;
        END;
        SELECT @id=id,@status=status,@expiry=expires_at FROM dbo.reservation WITH(UPDLOCK,HOLDLOCK) WHERE phone=@phone AND code=@code;
        IF @id IS NULL THROW 52504,N'Invalid reservation credential.',1;
        IF @status=N'有效'
        BEGIN
            SET @status=CASE WHEN @expiry<=CONVERT(datetime2,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time') THEN N'已过期' ELSE N'已取消' END;
            EXEC api.usp_reservation_release @id,@status,@employee_phone;
        END
        ELSE THROW 52502,N'Reservation already terminal.',1;
        EXEC api.usp_reservation_result @id,@result OUTPUT;
        INSERT api.reservation_cancellation(request_key,payload_hash,result_json) VALUES(@request_key,@hash,@result);
        COMMIT; SELECT @result result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_reservations_expire @batch_size int=100
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISNULL(IS_MEMBER('bookstore_app_task'),0)<>1 THROW 52003,N'Task identity required.',1;
    IF @batch_size IS NULL OR @batch_size NOT BETWEEN 1 AND 1000 THROW 52501,N'Invalid batch.',1;
    DECLARE @count int=0,@id bigint,@now datetime2;
    WHILE @count<@batch_size
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            SET @id=NULL;
            SET @now=CONVERT(datetime2,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time');
            SELECT TOP(1) @id=id FROM dbo.reservation WITH(UPDLOCK,READPAST,ROWLOCK) WHERE status=N'有效' AND expires_at<=@now ORDER BY id;
            IF @id IS NULL BEGIN COMMIT; BREAK; END;
            EXEC api.usp_reservation_release @id,N'已过期',NULL;
            COMMIT; SET @count=@count+1;
        END TRY
        BEGIN CATCH
            IF XACT_STATE()<>0 ROLLBACK;
            THROW;
        END CATCH;
    END;
    SELECT @count expired_count;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_reservation_create TO bookstore_app_guest;
GRANT EXECUTE ON OBJECT::api.usp_reservation_lookup TO bookstore_app_guest;
GRANT EXECUTE ON OBJECT::api.usp_reservation_cancel TO bookstore_app_guest,bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_reservations_expire TO bookstore_app_task;
COMMIT;
GO
CREATE OR ALTER PROCEDURE api.usp_pickup_quote
    @employee_phone varchar(11),@session_version int,@phone varchar(11),@code varchar(20),@member_phone varchar(11)=NULL,@used_points int=0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0 THROW 52500,N'New transaction required.',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
        DECLARE @id bigint,@status nvarchar(10),@expiry datetime2,@items nvarchar(max),@quote nvarchar(max);
        SELECT @id=id,@status=status,@expiry=expires_at FROM dbo.reservation WITH(UPDLOCK,HOLDLOCK) WHERE phone=@phone AND code=@code;
        IF @id IS NULL THROW 52504,N'Invalid reservation credential.',1;
        IF @status<>N'有效' OR @expiry<=CONVERT(datetime2,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time')
            THROW 52502,N'Reservation no longer available.',1;
        SET @items=(SELECT goods_id,quantity FROM dbo.reservation_item WHERE reservation_id=@id ORDER BY goods_id FOR JSON PATH);
        EXEC api.usp_sale_calculate @items,@member_phone,@used_points,@quote OUTPUT,@id;
        SET @quote=JSON_MODIFY(@quote,'$.confirmation_expires_at',CONVERT(varchar(33),DATEADD(minute,10,SYSUTCDATETIME()),126));
        COMMIT;
        SELECT @quote quote_json,@id reservation_id,@items items_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_pickup_create
    @employee_phone varchar(11),@session_version int,@request_key uniqueidentifier,@phone varchar(11),@code varchar(20),
    @member_phone varchar(11),@used_points int,@expected_quote nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
    DECLARE @id bigint,@items nvarchar(max);
    SELECT @id=id FROM dbo.reservation WHERE phone=@phone AND code=@code;
    IF @id IS NULL THROW 52504,N'Invalid reservation credential.',1;
    SET @items=(SELECT goods_id,quantity FROM dbo.reservation_item WHERE reservation_id=@id ORDER BY goods_id FOR JSON PATH);
    EXEC api.usp_sale_commit @employee_phone,@session_version,@request_key,@items,@member_phone,@used_points,@expected_quote,@id;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_pickup_quote TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_pickup_create TO bookstore_app_cashier;
GO
