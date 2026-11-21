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

-- 1. 净销量/净收入/订单数：全退商品应为 0，且订单数区分总单与退货单。
IF NOT EXISTS (
    SELECT 1 FROM report.fn_product_sales_rank(@from_date,@to_date,'quantity')
    WHERE goods_name=N'SQL Server 实战' AND net_quantity=4 AND net_revenue=255.39
      AND total_orders=4 AND returned_orders=1
)
    THROW 53101,N'排名净销量/净收入/订单数基线错误。',1;
IF NOT EXISTS (
    SELECT 1 FROM report.fn_product_sales_rank(@from_date,@to_date,'quantity')
    WHERE goods_name=N'拾光帆布袋' AND net_quantity=0 AND net_revenue=0
      AND total_orders=1 AND returned_orders=1
)
    THROW 53102,N'全部退货商品未按全退口径处理。',1;

-- 2. 排名指标切换：三种口径均可返回，且净订单不展示为负。
IF NOT EXISTS(SELECT 1 FROM report.fn_product_sales_rank(@from_date,@to_date,'revenue'))
   OR NOT EXISTS(SELECT 1 FROM report.fn_product_sales_rank(@from_date,@to_date,'orders'))
   OR EXISTS(
       SELECT 1 FROM report.fn_product_sales_rank(@from_date,@to_date,'orders')
       WHERE total_orders < returned_orders
   )
    THROW 53103,N'排名指标切换或订单数口径错误。',1;

-- 3. 空区间返回空集；非法日期不产生虚假行。
IF EXISTS(SELECT 1 FROM report.fn_product_sales_rank('2020-01-01','2020-01-02','quantity'))
   OR EXISTS(SELECT 1 FROM report.fn_product_sales_rank('2026-09-30','2026-09-01','quantity'))
    THROW 53104,N'空区间/反序日期处理错误。',1;

-- 4. 名次并列由 RANK 决定，展示序号稳定。
IF EXISTS(
    SELECT 1 FROM report.fn_product_sales_rank(@from_date,@to_date,'quantity')
    WHERE metric_rank<1 OR display_order<1
)
    THROW 53105,N'排名或展示序号不合法。',1;

SELECT N'W11-W01～W04' test_case,N'净销量/净收入/净订单/空区间' scope,
       COUNT(*) row_count
FROM report.fn_product_sales_rank(@from_date,@to_date,'quantity');
