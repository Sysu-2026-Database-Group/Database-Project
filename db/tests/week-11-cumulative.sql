USE [$(DatabaseName)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;

DECLARE @from_date date='2026-09-01',@to_date date='2026-09-30';

-- 1. 按日期累计：日期升序、累计值单调、最后一行等于总净额。
IF EXISTS (
    SELECT 1 FROM (
        SELECT sold_date,daily_net_quantity,daily_net_revenue,
               cumulative_net_quantity,cumulative_net_revenue,
               LAG(cumulative_net_quantity) OVER (ORDER BY sold_date) AS previous_quantity,
               LAG(cumulative_net_revenue) OVER (ORDER BY sold_date) AS previous_revenue
        FROM report.fn_cumulative_sales_by_date(@from_date,@to_date)
    ) x
    WHERE previous_quantity IS NOT NULL
      AND (cumulative_net_quantity<previous_quantity OR cumulative_net_revenue<previous_revenue)
)
    THROW 53111,N'按日期累计值出现倒退。',1;

IF (SELECT SUM(daily_net_quantity) FROM report.fn_cumulative_sales_by_date(@from_date,@to_date))
   <> (SELECT MAX(cumulative_net_quantity) FROM report.fn_cumulative_sales_by_date(@from_date,@to_date))
   OR (SELECT SUM(daily_net_revenue) FROM report.fn_cumulative_sales_by_date(@from_date,@to_date))
   <> (SELECT MAX(cumulative_net_revenue) FROM report.fn_cumulative_sales_by_date(@from_date,@to_date))
    THROW 53112,N'按日期累计最后一行不等于总净额。',1;

-- 2. 按商品累计：按净收入降序、累计值单调、最后一行等于总净额。
IF EXISTS (
    SELECT 1 FROM (
        SELECT goods_id,net_revenue,cumulative_net_quantity,cumulative_net_revenue,
               LAG(cumulative_net_quantity) OVER (ORDER BY net_revenue DESC,goods_id) AS previous_quantity,
               LAG(cumulative_net_revenue) OVER (ORDER BY net_revenue DESC,goods_id) AS previous_revenue
        FROM report.fn_cumulative_sales_by_product(@from_date,@to_date)
    ) x
    WHERE previous_quantity IS NOT NULL
      AND (cumulative_net_quantity<previous_quantity OR cumulative_net_revenue<previous_revenue)
)
    THROW 53113,N'按商品累计值出现倒退。',1;

IF (SELECT SUM(net_quantity) FROM report.fn_cumulative_sales_by_product(@from_date,@to_date))
   <> (SELECT MAX(cumulative_net_quantity) FROM report.fn_cumulative_sales_by_product(@from_date,@to_date))
   OR (SELECT SUM(net_revenue) FROM report.fn_cumulative_sales_by_product(@from_date,@to_date))
   <> (SELECT MAX(cumulative_net_revenue) FROM report.fn_cumulative_sales_by_product(@from_date,@to_date))
    THROW 53114,N'按商品累计最后一行不等于总净额。',1;

-- 3. 空区间不返回数据。
IF EXISTS(SELECT 1 FROM report.fn_cumulative_sales_by_date('2020-01-01','2020-01-02'))
   OR EXISTS(SELECT 1 FROM report.fn_cumulative_sales_by_product('2020-01-01','2020-01-02'))
    THROW 53115,N'累计查询空区间处理错误。',1;

SELECT N'W11-C01～C03' test_case,N'日期累计/商品累计/空区间' scope,
       (SELECT COUNT(*) FROM report.fn_cumulative_sales_by_date(@from_date,@to_date)) date_rows,
       (SELECT COUNT(*) FROM report.fn_cumulative_sales_by_product(@from_date,@to_date)) product_rows;
