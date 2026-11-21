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

DECLARE @as_of date='2026-09-30';

-- 1. 固定 3 行，日期为指定日期及前 2 个日历日。
IF (SELECT COUNT(*) FROM report.fn_moving_average_sales(@as_of))<>3
   OR (SELECT MIN(sale_date) FROM report.fn_moving_average_sales(@as_of))<>DATEADD(day,-2,@as_of)
   OR (SELECT MAX(sale_date) FROM report.fn_moving_average_sales(@as_of))<>@as_of
    THROW 53121,N'移动平均窗口不是指定日期及前 2 天。',1;

-- 2. 指定日期的 3 日均值 = 三天日值之和 / 3。
IF EXISTS (
    SELECT 1
    FROM (
        SELECT sale_date,daily_net_quantity,moving_avg_3d_quantity
        FROM report.fn_moving_average_sales(@as_of)
    ) x
    WHERE sale_date=@as_of
      AND moving_avg_3d_quantity <>
          (SELECT CONVERT(decimal(19,2),SUM(daily_net_quantity)/3.0)
           FROM report.fn_moving_average_sales(@as_of))
)
    THROW 53122,N'指定日期的 3 日平均净销量错误。',1;

IF EXISTS (
    SELECT 1
    FROM report.fn_moving_average_sales(@as_of)
    WHERE sale_date=@as_of
      AND moving_avg_3d_revenue <>
          (SELECT CONVERT(decimal(19,2),SUM(daily_net_revenue)/3.0)
           FROM report.fn_moving_average_sales(@as_of))
)
    THROW 53123,N'指定日期的 3 日平均净收入错误。',1;

-- 3. 无销售窗口仍返回 3 行 0 值。
IF (SELECT COUNT(*) FROM report.fn_moving_average_sales('2020-01-01'))<>3
   OR EXISTS(SELECT 1 FROM report.fn_moving_average_sales('2020-01-01')
             WHERE daily_net_quantity<>0 OR daily_net_revenue<>0)
    THROW 53124,N'无销售窗口未按 0 补齐。',1;

-- 4. 跨月窗口仍为 3 个日历日。
IF (SELECT COUNT(*) FROM report.fn_moving_average_sales('2026-10-01'))<>3
   OR (SELECT MIN(sale_date) FROM report.fn_moving_average_sales('2026-10-01'))<>'2026-09-29'
    THROW 53125,N'跨月移动平均窗口错误。',1;

-- 5. 空日期不返回数据。
IF EXISTS(SELECT 1 FROM report.fn_moving_average_sales(NULL))
    THROW 53126,N'空指定日期处理错误。',1;

SELECT N'W11-M01～M05' test_case,N'3日窗口/均值/补0/跨月/空日期' scope,
       COUNT(*) row_count,MIN(sale_date) window_start,MAX(sale_date) window_end
FROM report.fn_moving_average_sales(@as_of);
