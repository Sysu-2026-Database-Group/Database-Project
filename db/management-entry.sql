:On Error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID('api.operation_request','U') IS NULL
    THROW 52600,N'Install P2 first.',1;
GO
CREATE OR ALTER PROCEDURE api.usp_management_read
    @employee_phone varchar(11),@session_version int,@action varchar(20),@page int=1,@page_size int=20,@from_date date=NULL,@to_date date=NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'店长';
    IF @page IS NULL OR @page NOT BETWEEN 1 AND 1000000 OR @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 100
        OR (@from_date IS NOT NULL AND @to_date IS NOT NULL AND @from_date>@to_date) THROW 52204,N'Invalid pagination or date range.',1;
    IF @action='employees'
        SELECT (SELECT @page page,@page_size page_size,(SELECT COUNT_BIG(*) FROM dbo.employee) total,
            JSON_QUERY(COALESCE((SELECT e.phone,e.name,e.role,c.enabled,c.session_version,e.created_by,e.created_at,e.updated_by,e.updated_at
            FROM dbo.employee e LEFT JOIN auth.employee_credential c ON c.employee_phone=e.phone ORDER BY e.phone
            OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH),'[]')) records FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
    ELSE IF @action='cards'
        SELECT (SELECT JSON_QUERY((SELECT level,CONVERT(varchar(30),card_fee) card_fee,CONVERT(varchar(20),discount_rate) discount_rate,set_by,set_at
            FROM dbo.card_type ORDER BY level FOR JSON PATH)) records FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
    ELSE IF @action='reports'
        SELECT (SELECT CONVERT(varchar(30),COALESCE((SELECT TOP(1) fund_after FROM dbo.fund_flow ORDER BY id DESC),0)) cash_balance,
            CONVERT(varchar(30),COALESCE(SUM(CASE WHEN direction=N'收' THEN amount ELSE 0 END),0)) operating_income,
            CONVERT(varchar(30),COALESCE(SUM(CASE WHEN direction=N'付' THEN amount ELSE 0 END),0)) operating_expense,
            CONVERT(varchar(30),COALESCE(SUM(CASE WHEN direction=N'收' THEN amount ELSE -amount END),0)) operating_profit
            FROM dbo.fund_flow WHERE reason_type NOT IN (N'注资',N'提现')
                AND (@from_date IS NULL OR CONVERT(date,recorded_at)>=@from_date)
                AND (@to_date IS NULL OR CONVERT(date,recorded_at)<=@to_date) FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
    ELSE IF @action IN ('sales','returns','reservations')
    BEGIN
        DECLARE @records nvarchar(max),@total bigint;
        IF @action='sales'
        BEGIN
            SELECT @total=COUNT_BIG(*) FROM dbo.sale;
            SET @records=(SELECT s.no,s.status,s.cashier_by,s.member_phone,s.reservation_id,s.sold_at,
                CONVERT(varchar(30),s.paid_amount) paid_amount,
                JSON_QUERY((SELECT i.goods_id,g.name,i.quantity,i.unit_price FROM dbo.sale_item i JOIN dbo.goods g ON g.id=i.goods_id WHERE i.sale_id=s.id ORDER BY i.id FOR JSON PATH)) items
                FROM dbo.sale s ORDER BY s.id DESC OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
        END
        ELSE IF @action='returns'
        BEGIN
            SELECT @total=COUNT_BIG(*) FROM dbo.goods_return;
            SET @records=(SELECT r.no,s.no sale_no,CONVERT(varchar(30),r.refund_amount) refund_amount,r.handled_by,r.handled_at,
                JSON_QUERY((SELECT i.id,i.sale_item_id,i.quantity,i.refund_amount,
                    CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.stock_movement WHERE return_item_id=i.id) THEN 1 ELSE 0 END AS bit) recovered
                    FROM dbo.goods_return_item i WHERE i.return_id=r.id ORDER BY i.id FOR JSON PATH)) items
                FROM dbo.goods_return r JOIN dbo.sale s ON s.id=r.sale_id ORDER BY r.id DESC
                OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
        END
        ELSE
        BEGIN
            SELECT @total=COUNT_BIG(*) FROM dbo.reservation;
            SET @records=(SELECT r.id,r.phone,r.status,r.created_at,r.expires_at,(SELECT TOP(1) cashier_by FROM dbo.sale WHERE reservation_id=r.id) picked_by,(SELECT TOP(1) sold_at FROM dbo.sale WHERE reservation_id=r.id) picked_at,r.cancelled_by_employee,r.cancelled_at,
                JSON_QUERY((SELECT goods_id,quantity FROM dbo.reservation_item WHERE reservation_id=r.id ORDER BY goods_id FOR JSON PATH)) items
                FROM dbo.reservation r ORDER BY r.id DESC OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
        END;
        SELECT (SELECT @page page,@page_size page_size,@total total,JSON_QUERY(COALESCE(@records,'[]')) records FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) result_json;
    END
    ELSE THROW 52601,N'Unknown management read.',1;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_management_write
    @employee_phone varchar(11),@session_version int,@request_key uniqueidentifier,@action varchar(20),@payload nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @request_key IS NULL OR ISJSON(@payload)<>1 THROW 52601,N'Invalid request.',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_require_employee @employee_phone,@session_version,N'店长';
        DECLARE @hash binary(32)=HASHBYTES('SHA2_256',@payload),@old binary(32),@old_action varchar(30),@result nvarchar(max),@lock int;
        SELECT @old=payload_hash,@old_action=action,@result=result_json FROM api.operation_request WITH(UPDLOCK,HOLDLOCK)
            WHERE employee_phone=@employee_phone AND request_key=@request_key;
        IF @old IS NOT NULL
        BEGIN
            IF @old<>@hash OR @old_action<>@action THROW 52303,N'Request conflict.',1;
            COMMIT; SELECT @result result_json; RETURN;
        END;
        EXEC @lock=sys.sp_getapplock @Resource='bookstore-management',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
        IF @lock<0 THROW 52602,N'Management busy.',1;
        DECLARE @phone varchar(11)=JSON_VALUE(@payload,'$.phone'),@name nvarchar(20)=JSON_VALUE(@payload,'$.name'),
            @role nvarchar(10)=JSON_VALUE(@payload,'$.role'),@enabled bit=TRY_CONVERT(bit,JSON_VALUE(@payload,'$.enabled')),
            @password varchar(512)=JSON_VALUE(@payload,'$.password_hash'),@now datetime2=SYSDATETIME();
        IF @action='employee_save'
        BEGIN
            IF @phone IS NULL OR LEN(@phone)<>11 OR @phone LIKE '%[^0-9]%' OR NULLIF(LTRIM(RTRIM(@name)),'') IS NULL
                OR @role IS NULL OR @role NOT IN (N'店长',N'收银员',N'库管') OR @enabled IS NULL THROW 52601,N'Invalid employee.',1;
            IF EXISTS(SELECT 1 FROM dbo.employee e JOIN auth.employee_credential c ON e.phone=c.employee_phone
                WHERE e.phone=@phone AND e.role=N'店长' AND c.enabled=1) AND (@role<>N'店长' OR @enabled=0)
                AND (SELECT COUNT(*) FROM dbo.employee e WITH(UPDLOCK,HOLDLOCK) JOIN auth.employee_credential c ON e.phone=c.employee_phone WHERE e.role=N'店长' AND c.enabled=1)<=1
                THROW 52602,N'Cannot remove the last enabled manager.',1;
            IF EXISTS(SELECT 1 FROM dbo.employee WHERE phone=@phone)
                UPDATE dbo.employee SET name=@name,role=@role,updated_by=@employee_phone,updated_at=@now WHERE phone=@phone;
            ELSE
            BEGIN
                IF @password IS NULL THROW 52601,N'New employee password required.',1;
                INSERT dbo.employee(phone,name,role,created_by) VALUES(@phone,@name,@role,@employee_phone);
            END;
            UPDATE auth.employee_credential SET enabled=@enabled,password_hash=COALESCE(@password,password_hash),session_version=session_version+1,updated_at=@now
                WHERE employee_phone=@phone;
            IF @@ROWCOUNT=0
            BEGIN
                IF @password IS NULL OR LEN(@password)<20 THROW 52601,N'Password required.',1;
                INSERT auth.employee_credential(employee_phone,password_hash,enabled) VALUES(@phone,@password,@enabled);
            END;
        END
        ELSE IF @action='cards_save'
        BEGIN
            DECLARE @silver_fee decimal(10,2)=TRY_CONVERT(decimal(10,2),JSON_VALUE(@payload,'$.silver_fee')),
                @gold_fee decimal(10,2)=TRY_CONVERT(decimal(10,2),JSON_VALUE(@payload,'$.gold_fee')),
                @silver_rate decimal(3,2)=TRY_CONVERT(decimal(3,2),JSON_VALUE(@payload,'$.silver_rate')),
                @gold_rate decimal(3,2)=TRY_CONVERT(decimal(3,2),JSON_VALUE(@payload,'$.gold_rate'));
            IF @silver_fee IS NULL OR @gold_fee IS NULL OR @silver_fee<=0 OR @gold_fee<=@silver_fee
                OR @silver_rate IS NULL OR @gold_rate IS NULL OR @silver_rate<=0 OR @silver_rate>1 OR @gold_rate<=0 OR @gold_rate>@silver_rate
                THROW 52601,N'Invalid card tiers.',1;
            UPDATE dbo.card_type SET card_fee=CASE level WHEN N'银卡' THEN @silver_fee ELSE @gold_fee END,
                discount_rate=CASE level WHEN N'银卡' THEN @silver_rate ELSE @gold_rate END,set_by=@employee_phone,set_at=@now;
        END
        ELSE THROW 52601,N'Unknown write.',1;
        SET @result=(SELECT @action action,@phone phone,@request_key request_key FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        INSERT api.operation_request(employee_phone,request_key,action,payload_hash,result_json) VALUES(@employee_phone,@request_key,@action,@hash,@result);
        COMMIT; SELECT @result result_json;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_management_read TO bookstore_app_manager;
GRANT EXECUTE ON OBJECT::api.usp_management_write TO bookstore_app_manager;
GO
