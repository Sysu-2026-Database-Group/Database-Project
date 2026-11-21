USE [$(DatabaseName)];
GO
SET NOCOUNT ON;

/* Week11 窗口查询提交脚本
   参数仅为演示值，调用方可替换为实际日期。 */

DECLARE @from_date date='2026-09-01',
        @to_date date='2026-09-30',
        @as_of_date date='2026-09-27';

/* 1. 排名查询：按净收入对商品排名。
   指标可选 quantity / revenue / orders；RANK 保留并列。 */
SELECT goods_id,goods_name,net_quantity,net_revenue,total_orders,returned_orders,
       metric_rank,display_order
FROM report.fn_product_sales_rank(@from_date,@to_date,'revenue')
ORDER BY metric_rank,display_order;

/* 2. 累计值查询：按销售日期累计净销量与净收入。
   排序字段：sale_date。 */
SELECT sold_date,daily_net_quantity,daily_net_revenue,
       cumulative_net_quantity,cumulative_net_revenue
FROM report.fn_cumulative_sales_by_date(@from_date,@to_date)
ORDER BY sold_date;

/* 3. 移动平均查询：指定日期及其前 2 个日历日。
   排序字段：sale_date；无销售日期补 0。 */
SELECT sale_date,daily_net_quantity,daily_net_revenue,
       moving_avg_3d_quantity,moving_avg_3d_revenue
FROM report.fn_moving_average_sales(@as_of_date)
ORDER BY sale_date;
