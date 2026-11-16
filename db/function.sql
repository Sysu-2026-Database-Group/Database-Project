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
CREATE OR ALTER FUNCTION dbo.fn_sale_discount(@subtotal decimal(10,2),@rate decimal(3,2))
RETURNS TABLE
AS RETURN
(
    SELECT @rate AS discount_rate,a.discounted_amount,
        CONVERT(decimal(10,2),@subtotal-a.discounted_amount) AS discount_amount
    FROM (VALUES(CONVERT(decimal(10,2),ROUND(@subtotal*@rate,2)))) a(discounted_amount)
    WHERE @subtotal>=0 AND @rate>0 AND @rate<=1
);
GO
