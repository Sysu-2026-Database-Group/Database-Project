:On Error exit
-- SQLCMD 模式；DatabaseName 由调用者传入，目标须以 ShiguangBookstoreWeek6 开头。
-- 第六周订单明细与销售统计：SQLCMD 模式，DatabaseName 由调用者指定。
-- 仅查询业务表；中间结果写入会话表变量，不改业务记录。
-- 固定截面：2026-09-29 18:00（含）。请在新窗口完整执行。
USE [$(DatabaseName)];
GO
-- 筛选索引的创建及相关表 DML 所需会话选项，不依赖 SSMS / SQLCMD 默认值。
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;

IF (DB_NAME() <> N'$(DatabaseName)' OR DB_NAME() NOT LIKE N'ShiguangBookstoreWeek6%')
    THROW 51900, N'目标数据库错误，停止查询。', 1;
IF @@TRANCOUNT <> 0
    THROW 51901, N'请使用没有未结束事务的新查询窗口。', 1;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NULL
    THROW 51902, N'缺少第六周迁移表，请先核对工作库。', 1;

DECLARE @as_of DATETIME2 = '2026-09-29T18:00:00';
DECLARE @legacy_end DATETIME2 = '2026-09-21T00:00:00';

DECLARE @detail TABLE (
    sale_no VARCHAR(20), sale_date DATE, goods_ref VARCHAR(20),
    goods_name NVARCHAR(100), sold_qty INT, unit_price DECIMAL(10,2),
    gross_amount DECIMAL(18,2), returned_qty INT, refund_amount DECIMAL(18,2)
);

-- 每条销售明细先汇总其多次退货，避免连接时把销售数量重复累计。
INSERT @detail
SELECT s.no, CONVERT(date,s.sold_at), COALESCE(g.book_isbn,g.toy_code),
       g.name, i.quantity, i.unit_price, i.quantity*i.unit_price,
       COALESCE(r.returned_qty,0), COALESCE(r.refund_amount,0)
FROM dbo.sale s
JOIN dbo.sale_item i ON i.sale_id=s.id
JOIN dbo.goods g ON g.id=i.goods_id
OUTER APPLY (
    SELECT SUM(ri.quantity) AS returned_qty, SUM(ri.refund_amount) AS refund_amount
    FROM dbo.goods_return_item ri
    JOIN dbo.goods_return rh ON rh.id=ri.return_id
    WHERE ri.sale_item_id=i.id AND rh.handled_at<=@as_of
) r
WHERE s.sold_at<=@as_of;

-- 旧明细以 v0.1 样例脚本为预期依据；不使用新增记录抵消旧记录的差异。
DECLARE @legacy_detail TABLE (
    sale_no VARCHAR(20), goods_ref VARCHAR(20), sold_qty INT,
    unit_price DECIMAL(10,2), returned_qty INT, refund_amount DECIMAL(18,2)
);
INSERT @legacy_detail VALUES
('S20260908-01','9787506365437',3,39.00,3,111.15),
('S20260914-01','9787506365437',2,39.00,0,0.00),
('S20260914-01','SP-BAG-001',1,19.00,1,17.85),
('S20260913-01','9787544253994',3,49.00,0,0.00);

IF EXISTS (
    SELECT sale_no,goods_ref,sold_qty,unit_price,returned_qty,refund_amount
    FROM @detail WHERE sale_date<@legacy_end
    EXCEPT SELECT * FROM @legacy_detail
) OR EXISTS (
    SELECT * FROM @legacy_detail
    EXCEPT SELECT sale_no,goods_ref,sold_qty,unit_price,returned_qty,refund_amount
    FROM @detail WHERE sale_date<@legacy_end
)
    THROW 51903, N'旧订单明细与 v0.1 预期不一致。', 1;
IF (SELECT COUNT(*) FROM @detail)<>13
    THROW 51904, N'扩充后销售明细应为 13 行。', 1;

DECLARE @product TABLE (
    goods_ref VARCHAR(20), goods_name NVARCHAR(100), sold_qty INT,
    returned_qty INT, net_qty INT, gross_amount DECIMAL(18,2)
);
INSERT @product
SELECT COALESCE(g.book_isbn,g.toy_code),g.name,
       COALESCE(SUM(d.sold_qty),0), COALESCE(SUM(d.returned_qty),0),
       COALESCE(SUM(d.sold_qty-d.returned_qty),0), COALESCE(SUM(d.gross_amount),0)
FROM dbo.goods g
LEFT JOIN @detail d ON d.goods_ref=COALESCE(g.book_isbn,g.toy_code)
GROUP BY COALESCE(g.book_isbn,g.toy_code),g.name;

DECLARE @expected_product TABLE (
    goods_ref VARCHAR(20), sold_qty INT, returned_qty INT,
    net_qty INT, gross_amount DECIMAL(18,2)
);
INSERT @expected_product VALUES
('9787506365437',5,3,2,195.00), ('9787544253994',3,0,3,147.00),
('SP-BAG-001',1,1,0,19.00), ('SP-MARK-002',0,0,0,0.00),
('9787300000001',0,0,0,0.00), ('SP-NOTE-003',0,0,0,0.00),
('9787111000002',6,2,4,426.00), ('SP-CUP-004',4,2,2,144.00),
('9787040000003',2,1,1,116.00), ('SP-KEY-005',4,1,3,48.00);

IF EXISTS (
    SELECT goods_ref,sold_qty,returned_qty,net_qty,gross_amount FROM @product
    EXCEPT SELECT * FROM @expected_product
) OR EXISTS (
    SELECT * FROM @expected_product
    EXCEPT SELECT goods_ref,sold_qty,returned_qty,net_qty,gross_amount FROM @product
)
    THROW 51905, N'逐商品销量、退货量或折前金额与预期不一致。', 1;

-- 销售按成交日；退款按实际受理日，包含仅有退款的日期。
-- 分别汇总单头，再按日合并，不把单头实付连接到多条销售/退货明细。
DECLARE @daily TABLE (
    business_date DATE, sale_count INT, paid_amount DECIMAL(18,2),
    return_count INT, refund_amount DECIMAL(18,2), net_receipts DECIMAL(18,2)
);
;WITH sales AS (
    SELECT CONVERT(date,sold_at) AS d, COUNT(*) AS n, SUM(paid_amount) AS amount
    FROM dbo.sale WHERE sold_at<=@as_of GROUP BY CONVERT(date,sold_at)
), refunds AS (
    SELECT CONVERT(date,handled_at) AS d, COUNT(*) AS n, SUM(refund_amount) AS amount
    FROM dbo.goods_return WHERE handled_at<=@as_of GROUP BY CONVERT(date,handled_at)
)
INSERT @daily
SELECT COALESCE(s.d,r.d), COALESCE(s.n,0), COALESCE(s.amount,0),
       COALESCE(r.n,0), COALESCE(r.amount,0), COALESCE(s.amount,0)-COALESCE(r.amount,0)
FROM sales s FULL OUTER JOIN refunds r ON r.d=s.d;

DECLARE @expected_daily TABLE (
    business_date DATE, sale_count INT, paid_amount DECIMAL(18,2),
    return_count INT, refund_amount DECIMAL(18,2), net_receipts DECIMAL(18,2)
);
INSERT @expected_daily VALUES
('20260908',1,111.15,0,0.00,111.15),
('20260913',1,147.00,0,0.00,147.00),
('20260914',1,91.15,0,0.00,91.15),
('20260915',0,0.00,1,17.85,-17.85),
('20260916',0,0.00,1,111.15,-111.15),
('20260922',1,64.60,0,0.00,64.60),
('20260923',1,10.80,0,0.00,10.80),
('20260924',1,187.20,0,0.00,187.20),
('20260925',1,68.40,0,0.00,68.40),
('20260926',1,152.00,0,0.00,152.00),
('20260927',1,210.80,0,0.00,210.80),
('20260928',0,0.00,2,141.22,-141.22),
('20260929',0,0.00,1,139.58,-139.58);

IF EXISTS (SELECT * FROM @daily EXCEPT SELECT * FROM @expected_daily)
 OR EXISTS (SELECT * FROM @expected_daily EXCEPT SELECT * FROM @daily)
    THROW 51906, N'按日实付或退款与预期不一致。', 1;
IF (SELECT SUM(refund_amount) FROM @detail)<>(SELECT SUM(refund_amount) FROM @daily)
    THROW 51907, N'退货明细与退货单头金额不一致。', 1;
IF (SELECT SUM(gross_amount) FROM @detail)<>
   (SELECT SUM(subtotal_amount) FROM dbo.sale WHERE sold_at<=@as_of)
    THROW 51908, N'销售明细折前金额与单头小计不一致。', 1;

-- 四个结果集：明细、逐商品、逐日、旧/新增/合计。
SELECT sale_no,sale_date,goods_ref,goods_name,sold_qty,unit_price,gross_amount,
       returned_qty,sold_qty-returned_qty AS net_qty,refund_amount
FROM @detail ORDER BY sale_date,sale_no,goods_ref;

SELECT * FROM @product ORDER BY goods_ref;
SELECT * FROM @daily ORDER BY business_date;

;WITH scopes AS (
    SELECT 1 AS seq,N'旧样例' AS scope_name,CONVERT(datetime2,'1900-01-01') AS from_at,@legacy_end AS until_at
    UNION ALL SELECT 2,N'第六周新增',@legacy_end,DATEADD(second,1,@as_of)
    UNION ALL SELECT 3,N'合计',CONVERT(datetime2,'1900-01-01'),DATEADD(second,1,@as_of)
)
SELECT sc.scope_name, s.sale_count, d.detail_count,d.sold_qty,d.returned_qty,
       d.sold_qty-d.returned_qty AS net_qty,d.gross_amount,
       s.paid_amount,d.refund_amount,s.paid_amount-d.refund_amount AS net_sales_receipts,
       N'PASS' AS check_result
FROM scopes sc
CROSS APPLY (
    SELECT COUNT(*) AS sale_count,SUM(paid_amount) AS paid_amount FROM dbo.sale
    WHERE sold_at>=sc.from_at AND sold_at<sc.until_at AND sold_at<=@as_of
) s
CROSS APPLY (
    SELECT COUNT(*) AS detail_count,SUM(sold_qty) AS sold_qty,
           SUM(returned_qty) AS returned_qty,SUM(gross_amount) AS gross_amount,
           SUM(refund_amount) AS refund_amount
    FROM @detail WHERE sc.seq=3
                    OR (sc.seq=1 AND sale_date<CONVERT(date,@legacy_end))
                    OR (sc.seq=2 AND sale_date>=CONVERT(date,@legacy_end))
) d
ORDER BY sc.seq;

PRINT N'sales-statistics-week-6.sql PASS: legacy details, product quantities and daily receipts match expectations.';
-- net_sales_receipts 只含销售收款减退款，不是全店现金余额或经营盈亏。
-- 不按当前 sale.status 过滤已全退订单；其原销量仍计入，再减实际退货量。
