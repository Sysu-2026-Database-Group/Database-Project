:On Error exit
USE [$(DatabaseName)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%' OR OBJECT_ID(N'api.usp_require_employee',N'P') IS NULL
    THROW 52100,N'请先部署 Web 入口基础。',1;
GO
CREATE OR ALTER FUNCTION dbo.fn_replenishment_quantity(@goods_id bigint,@target int)
RETURNS int
AS
BEGIN
    DECLARE @available int;
    SELECT @available=stock_total-reserved_qty FROM dbo.goods WHERE id=@goods_id;
    RETURN CASE WHEN @available IS NULL OR @target IS NULL OR @target<0 THEN NULL
                WHEN @target<=@available THEN 0 ELSE @target-@available END;
END;
GO
CREATE OR ALTER FUNCTION dbo.fn_sales_by_goods(@from_date date,@to_date date)
RETURNS TABLE
AS RETURN
(
    SELECT g.id AS goods_id,g.name AS goods_name,SUM(CONVERT(bigint,i.quantity)) AS sold_quantity,
        SUM(CONVERT(decimal(19,2),i.quantity*i.unit_price)) AS gross_sales_amount,
        COUNT_BIG(DISTINCT s.id) AS order_count
    FROM dbo.sale s JOIN dbo.sale_item i ON i.sale_id=s.id JOIN dbo.goods g ON g.id=i.goods_id
    WHERE @from_date<=@to_date AND CONVERT(date,s.sold_at) BETWEEN @from_date AND @to_date
    GROUP BY g.id,g.name
);
GO
IF SCHEMA_ID(N'report') IS NULL EXEC(N'CREATE SCHEMA report');
GO
CREATE OR ALTER FUNCTION report.fn_product_sales_rank(@from_date date,@to_date date,@metric varchar(10))
RETURNS TABLE
AS RETURN
(
    WITH sale_lines AS (
        SELECT s.id AS sale_id,i.id AS sale_item_id,i.goods_id,g.name AS goods_name,
               CONVERT(bigint,i.quantity) AS quantity,
               CONVERT(decimal(19,2),i.quantity*i.unit_price) AS item_gross,
               CONVERT(decimal(19,2),s.paid_amount) AS paid_amount,
               CONVERT(decimal(19,2),s.subtotal_amount) AS subtotal_amount,
               s.sold_at
        FROM dbo.sale s
        JOIN dbo.sale_item i ON i.sale_id=s.id
        JOIN dbo.goods g ON g.id=i.goods_id
        WHERE @from_date IS NOT NULL AND @to_date IS NOT NULL
          AND @from_date<=@to_date
          AND s.sold_at>=@from_date AND s.sold_at<DATEADD(day,1,@to_date)
    ), item_paid AS (
        SELECT l.*,
               CASE WHEN l.subtotal_amount=0 THEN CONVERT(decimal(19,2),0)
                    ELSE CONVERT(decimal(19,2),ROUND(l.paid_amount*l.item_gross/l.subtotal_amount,2))
               END AS allocated_paid
        FROM sale_lines l
    ), returns AS (
        SELECT r.sale_item_id,
               SUM(CONVERT(bigint,r.quantity)) AS returned_quantity,
               SUM(CONVERT(decimal(19,2),r.refund_amount)) AS refund_amount
        FROM dbo.goods_return_item r
        GROUP BY r.sale_item_id
    ), item_net AS (
        SELECT p.goods_id,p.goods_name,p.sale_id,p.quantity,p.item_gross,p.allocated_paid,
               ISNULL(r.returned_quantity,0) AS returned_quantity,
               ISNULL(r.refund_amount,0) AS refund_amount,
               p.quantity-ISNULL(r.returned_quantity,0) AS net_quantity,
               p.allocated_paid-ISNULL(r.refund_amount,0) AS net_revenue,
               CASE WHEN ISNULL(r.returned_quantity,0)>=p.quantity THEN 1 ELSE 0 END AS is_full_return
        FROM item_paid p
        LEFT JOIN returns r ON r.sale_item_id=p.sale_item_id
    ), product AS (
        SELECT goods_id,goods_name,
               SUM(net_quantity) AS net_quantity,
               SUM(item_gross) AS gross_sales_amount,
               SUM(net_revenue) AS net_revenue,
               COUNT_BIG(DISTINCT sale_id) AS total_orders,
               COUNT_BIG(DISTINCT CASE WHEN is_full_return=1 THEN sale_id END) AS returned_orders,
               COUNT_BIG(DISTINCT sale_id)-COUNT_BIG(DISTINCT CASE WHEN is_full_return=1 THEN sale_id END) AS net_orders
        FROM item_net
        GROUP BY goods_id,goods_name
    )
    SELECT goods_id,goods_name,net_quantity,gross_sales_amount,net_revenue,
           total_orders,returned_orders,
           RANK() OVER (
               ORDER BY CASE LOWER(@metric)
                   WHEN N'revenue' THEN CONVERT(decimal(19,2),net_revenue)
                   WHEN N'orders' THEN CONVERT(decimal(19,2),net_orders)
                   ELSE CONVERT(decimal(19,2),net_quantity)
               END DESC
           ) AS metric_rank,
           ROW_NUMBER() OVER (
               ORDER BY CASE LOWER(@metric)
                   WHEN N'revenue' THEN CONVERT(decimal(19,2),net_revenue)
                   WHEN N'orders' THEN CONVERT(decimal(19,2),net_orders)
                   ELSE CONVERT(decimal(19,2),net_quantity)
               END DESC,goods_id
           ) AS display_order
    FROM product
);
GO
CREATE OR ALTER FUNCTION report.fn_sales_net_lines(@from_date date,@to_date date)
RETURNS TABLE
AS RETURN
(
    WITH sale_lines AS (
        SELECT s.id AS sale_id,i.id AS sale_item_id,i.goods_id,g.name AS goods_name,
               CONVERT(date,s.sold_at) AS sold_date,
               CONVERT(bigint,i.quantity) AS quantity,
               CONVERT(decimal(19,2),i.quantity*i.unit_price) AS item_gross,
               CONVERT(decimal(19,2),s.paid_amount) AS paid_amount,
               CONVERT(decimal(19,2),s.subtotal_amount) AS subtotal_amount
        FROM dbo.sale s
        JOIN dbo.sale_item i ON i.sale_id=s.id
        JOIN dbo.goods g ON g.id=i.goods_id
        WHERE @from_date IS NOT NULL AND @to_date IS NOT NULL
          AND @from_date<=@to_date
          AND s.sold_at>=@from_date AND s.sold_at<DATEADD(day,1,@to_date)
    ), item_paid AS (
        SELECT l.*,
               CASE WHEN l.subtotal_amount=0 THEN CONVERT(decimal(19,2),0)
                    ELSE CONVERT(decimal(19,2),ROUND(l.paid_amount*l.item_gross/l.subtotal_amount,2))
               END AS allocated_paid
        FROM sale_lines l
    ), returns AS (
        SELECT r.sale_item_id,
               SUM(CONVERT(bigint,r.quantity)) AS returned_quantity,
               SUM(CONVERT(decimal(19,2),r.refund_amount)) AS refund_amount
        FROM dbo.goods_return_item r
        GROUP BY r.sale_item_id
    )
    SELECT p.sale_id,p.sale_item_id,p.goods_id,p.goods_name,p.sold_date,
           p.quantity-ISNULL(r.returned_quantity,0) AS net_quantity,
           p.allocated_paid-ISNULL(r.refund_amount,0) AS net_revenue
    FROM item_paid p
    LEFT JOIN returns r ON r.sale_item_id=p.sale_item_id
);
GO
CREATE OR ALTER FUNCTION report.fn_cumulative_sales_by_date(@from_date date,@to_date date)
RETURNS TABLE
AS RETURN
(
    WITH daily AS (
        SELECT sold_date,
               SUM(net_quantity) AS daily_net_quantity,
               SUM(net_revenue) AS daily_net_revenue
        FROM report.fn_sales_net_lines(@from_date,@to_date)
        GROUP BY sold_date
    )
    SELECT sold_date,daily_net_quantity,daily_net_revenue,
           SUM(daily_net_quantity) OVER (
               ORDER BY sold_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS cumulative_net_quantity,
           SUM(daily_net_revenue) OVER (
               ORDER BY sold_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS cumulative_net_revenue
    FROM daily
);
GO
CREATE OR ALTER FUNCTION report.fn_cumulative_sales_by_product(@from_date date,@to_date date)
RETURNS TABLE
AS RETURN
(
    WITH product AS (
        SELECT goods_id,goods_name,
               SUM(net_quantity) AS net_quantity,
               SUM(net_revenue) AS net_revenue
        FROM report.fn_sales_net_lines(@from_date,@to_date)
        GROUP BY goods_id,goods_name
    )
    SELECT goods_id,goods_name,net_quantity,net_revenue,
           SUM(net_quantity) OVER (
               ORDER BY net_revenue DESC,goods_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS cumulative_net_quantity,
           SUM(net_revenue) OVER (
               ORDER BY net_revenue DESC,goods_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS cumulative_net_revenue
    FROM product
);
GO
CREATE OR ALTER FUNCTION report.fn_moving_average_sales(@as_of_date date)
RETURNS TABLE
AS RETURN
(
    WITH date_spine AS (
        SELECT DATEADD(day,-2,@as_of_date) AS sale_date
        UNION ALL
        SELECT DATEADD(day,1,sale_date)
        FROM date_spine
        WHERE sale_date<@as_of_date
    ), daily AS (
        SELECT sold_date,
               SUM(net_quantity) AS daily_net_quantity,
               SUM(net_revenue) AS daily_net_revenue
        FROM report.fn_sales_net_lines(DATEADD(day,-2,@as_of_date),@as_of_date)
        GROUP BY sold_date
    ), filled AS (
        SELECT d.sale_date,
               ISNULL(x.daily_net_quantity,0) AS daily_net_quantity,
               ISNULL(x.daily_net_revenue,0) AS daily_net_revenue
        FROM date_spine d
        LEFT JOIN daily x ON x.sold_date=d.sale_date
        WHERE @as_of_date IS NOT NULL
          AND @as_of_date>=CONVERT(date,'0001-01-03')
    )
    SELECT sale_date,daily_net_quantity,daily_net_revenue,
           CONVERT(decimal(19,2),AVG(CONVERT(decimal(19,4),daily_net_quantity)) OVER (
               ORDER BY sale_date
               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
           )) AS moving_avg_3d_quantity,
           CONVERT(decimal(19,2),AVG(daily_net_revenue) OVER (
               ORDER BY sale_date
               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
           )) AS moving_avg_3d_revenue
    FROM filled
);
GO
CREATE OR ALTER FUNCTION dbo.fn_member_discount_rate(@member_phone varchar(11))
RETURNS decimal(3,2)
AS
BEGIN
    IF @member_phone IS NULL RETURN CONVERT(decimal(3,2),1);
    DECLARE @phone varchar(11)=@member_phone,@resolved varchar(11),@level nvarchar(10),@rate decimal(3,2),@expires date;
    SELECT @resolved=member_phone FROM auth.member_contact WHERE contact_phone=@member_phone;
    SET @phone=COALESCE(@resolved,@member_phone);
    SELECT @level=card_level,@expires=expires_at
      FROM dbo.member WITH(HOLDLOCK) WHERE phone=@phone;
    IF @level IS NULL OR @expires IS NULL RETURN NULL;
    IF @expires<CONVERT(date,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'China Standard Time')
        RETURN CONVERT(decimal(3,2),1);
    SELECT @rate=discount_rate FROM dbo.card_type WITH(HOLDLOCK) WHERE [level]=@level;
    RETURN @rate;
END;
GO
CREATE OR ALTER FUNCTION dbo.fn_sale_discount(@subtotal decimal(10,2),@member_phone varchar(11))
RETURNS TABLE
AS RETURN
(
    SELECT r.rate AS discount_rate,
        CONVERT(decimal(10,2),ROUND(@subtotal*r.rate,2)) AS discounted_amount,
        CONVERT(decimal(10,2),@subtotal-ROUND(@subtotal*r.rate,2)) AS discount_amount
    FROM (SELECT dbo.fn_member_discount_rate(@member_phone) AS rate) r
    WHERE @subtotal>=0 AND r.rate>0 AND r.rate<=1
);
GO
