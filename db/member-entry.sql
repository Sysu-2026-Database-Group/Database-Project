:On Error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID('api.operation_request','U') IS NULL THROW 52700,N'Install application first.',1;
IF OBJECT_ID('dbo.member_service','U') IS NULL
CREATE TABLE dbo.member_service(
    id bigint IDENTITY PRIMARY KEY,member_phone varchar(11) NOT NULL REFERENCES dbo.member(phone),
    operation varchar(10) NOT NULL,old_level nvarchar(10) NULL,new_level nvarchar(10) NOT NULL,
    old_expiry date NULL,new_expiry date NOT NULL,amount decimal(10,2) NOT NULL CHECK(amount>0),
    silver_fee decimal(10,2) NOT NULL,gold_fee decimal(10,2) NOT NULL,
    fund_flow_id bigint NOT NULL UNIQUE REFERENCES dbo.fund_flow(id),handled_by varchar(11) NOT NULL REFERENCES dbo.employee(phone),handled_at datetime2 NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID('auth.member_access','U') IS NULL
CREATE TABLE auth.member_access(member_phone varchar(11) PRIMARY KEY REFERENCES dbo.member(phone),token_hash binary(32) NOT NULL,
    issued_by varchar(11) NOT NULL REFERENCES dbo.employee(phone),issued_at datetime2 NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID('auth.member_contact','U') IS NULL
CREATE TABLE auth.member_contact(member_phone varchar(11) PRIMARY KEY REFERENCES dbo.member(phone),contact_phone varchar(11) NOT NULL UNIQUE,
    updated_by varchar(11) NOT NULL REFERENCES dbo.employee(phone),updated_at datetime2 NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID('dbo.member_contact_history','U') IS NULL
CREATE TABLE dbo.member_contact_history(id bigint IDENTITY PRIMARY KEY,member_phone varchar(11) NOT NULL REFERENCES dbo.member(phone),
    old_contact varchar(11) NOT NULL,new_contact varchar(11) NOT NULL,changed_by varchar(11) NOT NULL REFERENCES dbo.employee(phone),changed_at datetime2 NOT NULL DEFAULT SYSDATETIME());
GO
CREATE OR ALTER PROCEDURE api.usp_member_read @employee_phone varchar(11),@session_version int,@phone varchar(11)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
    SELECT (SELECT m.phone,m.card_level,m.expires_at,m.points_balance,COALESCE(c.contact_phone,m.phone) contact_phone,
        JSON_QUERY(COALESCE((SELECT id,operation,old_level,new_level,old_expiry,new_expiry,amount,handled_by,handled_at FROM dbo.member_service WHERE member_phone=m.phone ORDER BY id DESC FOR JSON PATH),'[]')) history
        FROM dbo.member m LEFT JOIN auth.member_contact c ON c.member_phone=m.phone
        WHERE m.phone=@phone OR c.contact_phone=@phone FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_member_calculate @phone varchar(11),@level nvarchar(10),@operation varchar(10),@quote nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today date=CONVERT(date,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time'),
        @old nvarchar(10),@expiry date,@silver decimal(10,2),@gold decimal(10,2),@amount decimal(10,2),@next date,@base date;
    SELECT @phone=member_phone FROM auth.member_contact WHERE contact_phone=@phone;
    SELECT @old=card_level,@expiry=expires_at FROM dbo.member WITH(UPDLOCK,HOLDLOCK) WHERE phone=@phone;
    SELECT @silver=card_fee FROM dbo.card_type WITH(HOLDLOCK) WHERE level=N'银卡';
    SELECT @gold=card_fee FROM dbo.card_type WITH(HOLDLOCK) WHERE level=N'金卡';
    IF @phone IS NULL OR LEN(@phone)<>11 OR @phone LIKE '%[^0-9]%' OR @level IS NULL OR @level NOT IN(N'银卡',N'金卡')
        OR (@old=N'金卡' AND @level=N'银卡') THROW 52701,N'Invalid member or downgrade.',1;
    IF @operation='upgrade'
    BEGIN
        IF @old IS NULL OR @old<>N'银卡' OR @level<>N'金卡' OR @expiry<@today THROW 52701,N'Only active silver may upgrade.',1;
        SET @amount=@gold-@silver; SET @next=@expiry;
    END
    ELSE IF @operation='buy'
    BEGIN
        SET @amount=CASE @level WHEN N'银卡' THEN @silver ELSE @gold END;
        SET @base=CASE WHEN @expiry>=@today THEN @expiry ELSE @today END;
        SET @next=DATEADD(year,1,@base);
        IF MONTH(@base)=2 AND DAY(@base)=29 AND DAY(@next)=28 SET @next=DATEADD(day,1,@next);
    END
    ELSE THROW 52701,N'Invalid member action.',1;
    SET @quote=(SELECT @phone phone,@operation operation,@old old_level,@level new_level,@expiry old_expiry,@next new_expiry,
        CONVERT(varchar(30),@amount) amount,CONVERT(varchar(30),@silver) silver_fee,CONVERT(varchar(30),@gold) gold_fee
        FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.usp_member_quote @employee_phone varchar(11),@session_version int,@phone varchar(11),@level nvarchar(10),@operation varchar(10)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
        DECLARE @quote nvarchar(max);
        EXEC api.usp_member_calculate @phone,@level,@operation,@quote OUTPUT;
        SET @quote=JSON_MODIFY(@quote,'$.confirmation_expires_at',CONVERT(varchar(33),DATEADD(minute,10,SYSUTCDATETIME()),126));
        COMMIT; SELECT @quote result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_member_create
    @employee_phone varchar(11),@session_version int,@key uniqueidentifier,@phone varchar(11),@level nvarchar(10),@operation varchar(10),@expected nvarchar(max),@token_hash binary(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
        DECLARE @payload nvarchar(max)=(SELECT @phone phone,@level level,@operation operation FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
            @old binary(32),@hash binary(32),@old_action varchar(30),@result nvarchar(max),@quote nvarchar(max);
        SET @hash=HASHBYTES('SHA2_256',@payload);
        SELECT @old=payload_hash,@old_action=action,@result=result_json FROM api.operation_request WITH(UPDLOCK,HOLDLOCK) WHERE employee_phone=@employee_phone AND request_key=@key;
        IF @old IS NOT NULL
        BEGIN
            IF @old<>@hash OR @old_action<>'member_create' THROW 52303,N'Request conflict.',1;
            COMMIT; SELECT @result result_json; RETURN;
        END;
        IF @key IS NULL THROW 52701,N'Request key required.',1;
        EXEC api.usp_member_calculate @phone,@level,@operation,@quote OUTPUT;
        IF TRY_CONVERT(datetime2,JSON_VALUE(@expected,'$.confirmation_expires_at')) IS NULL
            OR TRY_CONVERT(datetime2,JSON_VALUE(@expected,'$.confirmation_expires_at'))<=SYSUTCDATETIME()
            THROW 52107,N'Confirmation expired; preview again.',1;
        IF @expected IS NULL OR HASHBYTES('SHA2_256',JSON_MODIFY(@expected,'$.confirmation_expires_at',NULL))<>HASHBYTES('SHA2_256',@quote) THROW 52107,N'Membership conditions changed.',1;
        SET @phone=JSON_VALUE(@quote,'$.phone');
        DECLARE @expiry date=TRY_CONVERT(date,JSON_VALUE(@quote,'$.new_expiry')),@amount decimal(10,2)=TRY_CONVERT(decimal(10,2),JSON_VALUE(@quote,'$.amount')),
            @balance decimal(12,2)=0,@flow bigint;
        IF EXISTS(SELECT 1 FROM dbo.member WHERE phone=@phone)
            UPDATE dbo.member SET card_level=@level,expires_at=@expiry,updated_by=@employee_phone,updated_at=SYSDATETIME() WHERE phone=@phone;
        ELSE INSERT dbo.member(phone,card_level,opened_by,expires_at) VALUES(@phone,@level,@employee_phone,@expiry);
        SELECT TOP(1) @balance=fund_after FROM dbo.fund_flow WITH(UPDLOCK,HOLDLOCK) ORDER BY id DESC;
        INSERT dbo.fund_flow(amount,direction,reason_type,member_phone,fund_before,fund_after,recorded_by)
            VALUES(@amount,N'收',N'办卡费',@phone,@balance,@balance+@amount,@employee_phone);
        SET @flow=SCOPE_IDENTITY();
        INSERT dbo.member_service(member_phone,operation,old_level,new_level,old_expiry,new_expiry,amount,silver_fee,gold_fee,fund_flow_id,handled_by)
            VALUES(@phone,@operation,JSON_VALUE(@quote,'$.old_level'),@level,TRY_CONVERT(date,JSON_VALUE(@quote,'$.old_expiry')),@expiry,@amount,
                TRY_CONVERT(decimal(10,2),JSON_VALUE(@quote,'$.silver_fee')),TRY_CONVERT(decimal(10,2),JSON_VALUE(@quote,'$.gold_fee')),@flow,@employee_phone);
        SET @result=JSON_MODIFY(@quote,'$.service_id',CONVERT(bigint,SCOPE_IDENTITY()));
        IF @token_hash IS NULL THROW 52701,N'Token hash required.',1;
        UPDATE auth.member_access SET token_hash=@token_hash,issued_by=@employee_phone,issued_at=SYSDATETIME() WHERE member_phone=@phone;
        IF @@ROWCOUNT=0 INSERT auth.member_access(member_phone,token_hash,issued_by) VALUES(@phone,@token_hash,@employee_phone);
        INSERT api.operation_request(employee_phone,request_key,action,payload_hash,result_json) VALUES(@employee_phone,@key,'member_create',@hash,@result);
        COMMIT; SELECT @result result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_member_read TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_member_quote TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_member_create TO bookstore_app_cashier;
GO
CREATE OR ALTER PROCEDURE api.usp_member_contact
    @employee_phone varchar(11),@session_version int,@key uniqueidentifier,@phone varchar(11),@contact varchar(11),@token_hash binary(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'收银员';
        IF @key IS NULL OR @token_hash IS NULL OR @contact IS NULL OR LEN(@contact)<>11 OR @contact LIKE '%[^0-9]%'
            THROW 52701,N'Invalid contact.',1;
        DECLARE @old_contact varchar(11),@old_hash binary(32),@old_action varchar(30),@result nvarchar(max),@hash binary(32)=HASHBYTES('SHA2_256',CONCAT(@phone,':',@contact,':',CONVERT(varchar(64),@token_hash,2)));
        SELECT @old_hash=payload_hash,@old_action=action,@result=result_json FROM api.operation_request WITH(UPDLOCK,HOLDLOCK) WHERE employee_phone=@employee_phone AND request_key=@key;
        IF @old_hash IS NOT NULL
        BEGIN
            IF @old_hash<>@hash OR @old_action<>'member_contact' THROW 52303,N'Request conflict.',1;
            COMMIT; SELECT @result result_json; RETURN;
        END;
        IF NOT EXISTS(SELECT 1 FROM dbo.member WITH(UPDLOCK,HOLDLOCK) WHERE phone=@phone) THROW 52701,N'Member not found.',1;
        IF EXISTS(SELECT 1 FROM dbo.member WHERE phone=@contact AND phone<>@phone)
            OR EXISTS(SELECT 1 FROM auth.member_contact WHERE contact_phone=@contact AND member_phone<>@phone)
            THROW 52701,N'Contact already belongs to another member.',1;
        SELECT @old_contact=contact_phone FROM auth.member_contact WHERE member_phone=@phone;
        SET @old_contact=COALESCE(@old_contact,@phone);
        UPDATE auth.member_contact SET contact_phone=@contact,updated_by=@employee_phone,updated_at=SYSDATETIME() WHERE member_phone=@phone;
        IF @@ROWCOUNT=0 INSERT auth.member_contact(member_phone,contact_phone,updated_by) VALUES(@phone,@contact,@employee_phone);
        IF @old_contact<>@contact INSERT dbo.member_contact_history(member_phone,old_contact,new_contact,changed_by) VALUES(@phone,@old_contact,@contact,@employee_phone);
        UPDATE auth.member_access SET token_hash=@token_hash,issued_by=@employee_phone,issued_at=SYSDATETIME() WHERE member_phone=@phone;
        IF @@ROWCOUNT=0 INSERT auth.member_access(member_phone,token_hash,issued_by) VALUES(@phone,@token_hash,@employee_phone);
        SET @result=(SELECT @phone member_phone,@contact contact_phone FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT api.operation_request(employee_phone,request_key,action,payload_hash,result_json) VALUES(@employee_phone,@key,'member_contact',@hash,@result);
        COMMIT; SELECT @result result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_member_self @contact varchar(11),@token_hash binary(32)
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(IS_MEMBER('bookstore_app_guest'),0)<>1 THROW 52003,N'Guest required.',1;
    DECLARE @phone varchar(11);
    SELECT @phone=a.member_phone FROM auth.member_access a JOIN dbo.member m ON m.phone=a.member_phone
        LEFT JOIN auth.member_contact c ON c.member_phone=a.member_phone
        WHERE COALESCE(c.contact_phone,m.phone)=@contact AND a.token_hash=@token_hash;
    IF @phone IS NULL THROW 52704,N'Invalid self-service credential.',1;
    SELECT (SELECT m.phone member_id,COALESCE(c.contact_phone,m.phone) contact_phone,m.card_level,m.expires_at,m.points_balance,
        JSON_QUERY(COALESCE((SELECT s.no,s.sold_at,s.paid_amount,s.status,
            JSON_QUERY((SELECT g.name,i.quantity,i.unit_price FROM dbo.sale_item i JOIN dbo.goods g ON g.id=i.goods_id WHERE i.sale_id=s.id ORDER BY i.id FOR JSON PATH)) items
            FROM dbo.sale s WHERE s.member_phone=m.phone ORDER BY s.id DESC FOR JSON PATH),'[]')) sales,
        JSON_QUERY(COALESCE((SELECT p.change_type,p.points,p.changed_at,s.no sale_no,r.no return_no FROM dbo.point_movement p
            LEFT JOIN dbo.sale s ON s.id=p.sale_id LEFT JOIN dbo.goods_return r ON r.id=p.return_id
            WHERE p.member_phone=m.phone ORDER BY p.id DESC FOR JSON PATH),'[]')) points,
        JSON_QUERY(COALESCE((SELECT r.no,s.no sale_no,r.refund_amount,r.handled_at,
            JSON_QUERY((SELECT i.sale_item_id,i.quantity,i.refund_amount FROM dbo.goods_return_item i WHERE i.return_id=r.id ORDER BY i.id FOR JSON PATH)) items
            FROM dbo.goods_return r JOIN dbo.sale s ON s.id=r.sale_id WHERE s.member_phone=m.phone ORDER BY r.id DESC FOR JSON PATH),'[]')) returns
        FROM dbo.member m LEFT JOIN auth.member_contact c ON c.member_phone=m.phone WHERE m.phone=@phone FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_member_contact TO bookstore_app_cashier;
GRANT EXECUTE ON OBJECT::api.usp_member_self TO bookstore_app_guest;
GO
