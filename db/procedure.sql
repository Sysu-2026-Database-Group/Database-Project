:On Error exit
USE [$(DatabaseName)];
GO
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID(N'dbo.fn_sales_by_goods',N'IF') IS NULL
    THROW 52100,N'请先部署 function.sql。',1;
BEGIN TRANSACTION;
GO
-- 调用方校验业务单据，在同一事务中更新状态、库存和流水。
CREATE OR ALTER PROCEDURE api.usp_adjust_stock
    @goods_id bigint,@delta int,@change_type nvarchar(10),@employee_phone varchar(11),
    @session_version int,@source_id bigint=NULL,@reason nvarchar(max)=NULL,@changed_at datetime2=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET ARITHABORT ON;
    SET NUMERIC_ROUNDABORT OFF;
    IF @@TRANCOUNT=0 THROW 52301,N'库存调整需要调用方事务。',1;
    IF @goods_id IS NULL OR @goods_id<=0 OR @delta IS NULL OR @delta=0
       OR @change_type IS NULL OR @change_type NOT IN(N'购入',N'卖出',N'退货',N'损坏')
       OR (@change_type IN(N'购入',N'退货') AND @delta<0)
       OR (@change_type=N'卖出' AND @delta>0)
       OR (@change_type<>N'损坏' AND (@source_id IS NULL OR @source_id<=0))
       OR (@change_type=N'损坏' AND (@source_id IS NOT NULL OR @delta NOT BETWEEN -1000 AND -1
           OR NULLIF(LTRIM(RTRIM(@reason)),N'') IS NULL OR DATALENGTH(@reason)>400))
        THROW 52301,N'库存变动类型、来源或数量无效。',1;
    DECLARE @role nvarchar(10)=CASE WHEN @change_type=N'卖出' THEN N'收银员' ELSE N'库管' END;
    EXEC api.usp_require_employee @employee_phone,@session_version,@role;
    DECLARE @stock int,@reserved int;
    SELECT @stock=stock_total,@reserved=reserved_qty FROM dbo.goods WITH(UPDLOCK,HOLDLOCK) WHERE id=@goods_id;
    IF @stock IS NULL
    BEGIN
        IF @change_type=N'损坏' THROW 52302,N'可售量不足。',1;
        THROW 52304,N'商品不存在。',1;
    END;
    DECLARE @new_reserved bigint=@reserved;
    IF @change_type=N'卖出' AND EXISTS(SELECT 1 FROM dbo.sale WHERE id=@source_id AND reservation_id IS NOT NULL)
        SET @new_reserved=CONVERT(bigint,@reserved)+@delta;
    DECLARE @new_stock bigint=CONVERT(bigint,@stock)+@delta;
    IF @new_reserved<0 OR @new_stock<@new_reserved THROW 52302,N'可售量不足。',1;
    IF @new_stock>2147483647 THROW 52301,N'调整后库存超出支持范围。',1;
    UPDATE dbo.goods SET stock_total=@new_stock,reserved_qty=@new_reserved WHERE id=@goods_id;
    INSERT dbo.stock_movement(goods_id,change_type,stock_before,stock_after,quantity,note,changed_by,changed_at,request_id,sale_id,return_item_id)
    VALUES(@goods_id,@change_type,@stock,@new_stock,@delta,@reason,@employee_phone,COALESCE(@changed_at,SYSDATETIME()),
           CASE WHEN @change_type=N'购入' THEN @source_id END,
           CASE WHEN @change_type=N'卖出' THEN @source_id END,
           CASE WHEN @change_type=N'退货' THEN @source_id END);
END;
GO
CREATE OR ALTER PROCEDURE api.usp_replenishment
    @employee_phone varchar(11),@session_version int,@goods_id bigint,@target int
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'库管';
    IF @goods_id IS NULL OR @goods_id<=0
        THROW 52301,N'请提供有效的商品编号。',1;
    IF NOT EXISTS(SELECT 1 FROM dbo.goods WITH(HOLDLOCK) WHERE id=@goods_id)
        THROW 52304,N'商品不存在。',1;
    IF @target IS NULL OR @target<0
        THROW 52301,N'请提供非负的目标可售量。',1;
    DECLARE @result nvarchar(max);
    SELECT @result=(SELECT id AS goods_id,name,stock_total,reserved_qty,
        stock_total-reserved_qty AS available,@target AS target,
        dbo.fn_replenishment_quantity(id,@target) AS suggested_quantity
        FROM dbo.goods WITH(HOLDLOCK) WHERE id=@goods_id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    IF NULLIF(@result,N'') IS NULL THROW 52304,N'商品不存在。',1;
    SELECT @result AS result_json;
END;
GO
CREATE OR ALTER PROCEDURE api.usp_sales_statistics
    @employee_phone varchar(11),@session_version int,@from_date date,@to_date date
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.usp_require_employee @employee_phone,@session_version,N'店长';
    IF @from_date IS NULL OR @to_date IS NULL OR @from_date>@to_date
        THROW 53001,N'请填写有效的起止日期。',1;
    SET XACT_ABORT ON;
    DECLARE @goods TABLE(goods_id bigint PRIMARY KEY,goods_name nvarchar(100),
        sold_quantity bigint,gross_sales_amount decimal(38,2),order_count bigint);
    DECLARE @orders bigint,@paid decimal(38,2);
    BEGIN TRANSACTION;
    SELECT @orders=COUNT_BIG(*),@paid=COALESCE(SUM(s.paid_amount),0)
        FROM dbo.sale s WITH(HOLDLOCK) WHERE CONVERT(date,s.sold_at) BETWEEN @from_date AND @to_date;
    INSERT @goods SELECT goods_id,goods_name,sold_quantity,gross_sales_amount,order_count
        FROM dbo.fn_sales_by_goods(@from_date,@to_date);
    COMMIT;
    SELECT (SELECT @orders AS order_count,@paid AS paid_amount,
        COALESCE((SELECT SUM(sold_quantity) FROM @goods),0) AS sold_quantity,
        COALESCE((SELECT SUM(gross_sales_amount) FROM @goods),0) AS gross_sales_amount,
        JSON_QUERY(COALESCE((SELECT goods_id,goods_name,sold_quantity,gross_sales_amount,order_count
                            FROM @goods ORDER BY goods_id FOR JSON PATH),N'[]')) AS records
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS result_json;
END;
GO
GRANT EXECUTE ON OBJECT::api.usp_replenishment TO bookstore_app_inventory;
GRANT EXECUTE ON OBJECT::api.usp_sales_statistics TO bookstore_app_manager;
COMMIT;
GO
