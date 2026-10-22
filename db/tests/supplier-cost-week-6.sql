:On Error exit
-- SQLCMD 模式；DatabaseName 由调用者传入，目标须以 ShiguangBookstoreWeek6 开头。
-- W6-S11 供应商报价与采购批次成本：SQLCMD 模式，DatabaseName 由调用者指定。
-- 只读业务表；会话表变量保存中间结果，不更新报价或采购成本。
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
IF (DB_NAME()<>N'$(DatabaseName)' OR DB_NAME() NOT LIKE N'ShiguangBookstoreWeek6%')
    THROW 51940, N'目标数据库错误，停止供应商统计。', 1;
IF @@TRANCOUNT<>0
    THROW 51941, N'请使用没有未结束事务的新查询窗口。', 1;
IF OBJECT_ID(N'dbo.schema_migration',N'U') IS NULL
    THROW 51942, N'缺少第六周迁移表，请先核对工作库。', 1;

DECLARE @start_at DATETIME2='2026-09-21T00:00:00';
DECLARE @as_of DATETIME2='2026-09-29T18:00:00';
DECLARE @quotes TABLE (
    supplier_name NVARCHAR(100),goods_ref VARCHAR(20),quote_amount DECIMAL(10,2)
);
-- 当前报价表没有完整历史版本；本脚本只核对已装载的固定样例基线。
INSERT @quotes
SELECT s.name,COALESCE(g.book_isbn,g.toy_code),q.quote_amount
FROM dbo.supplier_quote q
JOIN dbo.supplier s ON s.id=q.supplier_id
JOIN dbo.goods g ON g.id=q.goods_id
WHERE COALESCE(g.book_isbn,g.toy_code) IN
      ('9787111000002','SP-CUP-004','9787040000003','SP-KEY-005');

DECLARE @expected_quotes TABLE (
    supplier_name NVARCHAR(100),goods_ref VARCHAR(20),quote_amount DECIMAL(10,2)
);
INSERT @expected_quotes VALUES
(N'新阅供应链','9787111000002',55.00),(N'新阅供应链','SP-CUP-004',30.00),
(N'新阅供应链','9787040000003',48.00),(N'拾光文创工坊','9787111000002',57.00),
(N'拾光文创工坊','SP-CUP-004',28.00),(N'拾光文创工坊','9787040000003',50.00),
(N'拾光文创工坊','SP-KEY-005',8.00);
IF EXISTS (SELECT * FROM @quotes EXCEPT SELECT * FROM @expected_quotes)
 OR EXISTS (SELECT * FROM @expected_quotes EXCEPT SELECT * FROM @quotes)
    THROW 51943, N'新商品的七条供应商报价与预期不一致。', 1;

DECLARE @batches TABLE (
    purchase_no VARCHAR(20),supplier_name NVARCHAR(100),goods_ref VARCHAR(20),
    request_qty INT,unit_cost DECIMAL(10,2),received_qty BIGINT
);
-- 只统计本周已收货采购；草稿、提交、审批及取消均不计作实际进货。
-- 对每个采购单/商品单独汇总入库，不把采购明细连接到整单付款。
INSERT @batches
SELECT p.no,s.name,COALESCE(g.book_isbn,g.toy_code),i.request_qty,i.unit_cost,
       COALESCE(m.qty,0)
FROM dbo.purchase_request p
JOIN dbo.supplier s ON s.id=p.supplier_id
JOIN dbo.purchase_request_item i ON i.request_id=p.id
JOIN dbo.goods g ON g.id=i.goods_id
OUTER APPLY (
    SELECT SUM(CONVERT(bigint,quantity)) AS qty FROM dbo.stock_movement
    WHERE request_id=p.id AND goods_id=i.goods_id AND change_type=N'购入'
      AND changed_at<=@as_of
) m
WHERE p.status=N'已收货' AND p.created_at>=@start_at AND p.created_at<=@as_of;

DECLARE @expected_batches TABLE (
    purchase_no VARCHAR(20),supplier_name NVARCHAR(100),goods_ref VARCHAR(20),
    request_qty INT,unit_cost DECIMAL(10,2),received_qty BIGINT
);
INSERT @expected_batches VALUES
('PR20260921-W608',N'新阅供应链','9787111000002',10,55.00,10),
('PR20260921-W608',N'新阅供应链','SP-CUP-004',7,30.00,7),
('PR20260921-W609',N'拾光文创工坊','9787040000003',6,48.00,6),
('PR20260921-W609',N'拾光文创工坊','SP-KEY-005',21,8.00,21),
('PR20260921-W610',N'新阅供应链','9787111000002',4,53.00,4);
IF EXISTS (SELECT * FROM @batches EXCEPT SELECT * FROM @expected_batches)
 OR EXISTS (SELECT * FROM @expected_batches EXCEPT SELECT * FROM @batches)
    THROW 51944, N'五条采购批次明细、成本或入库数量与预期不一致。', 1;

DECLARE @supplier_totals TABLE (
    supplier_name NVARCHAR(100),purchase_count INT,purchased_qty BIGINT,
    purchase_amount DECIMAL(18,2),payment_count INT,paid_amount DECIMAL(18,2)
);
;WITH purchases AS (
    SELECT supplier_name,COUNT(DISTINCT purchase_no) AS n,
           SUM(CONVERT(bigint,request_qty)) AS qty,SUM(request_qty*unit_cost) AS amount
    FROM @batches GROUP BY supplier_name
)
INSERT @supplier_totals
SELECT a.supplier_name,a.n,a.qty,a.amount,f.n,COALESCE(f.amount,0)
FROM purchases a
OUTER APPLY (
    SELECT COUNT(*) AS n,SUM(ff.amount) AS amount
    FROM dbo.fund_flow ff
    JOIN dbo.purchase_request p ON p.id=ff.request_id
    JOIN dbo.supplier s ON s.id=p.supplier_id
    WHERE s.name=a.supplier_name AND p.status=N'已收货'
      AND p.created_at>=@start_at AND p.created_at<=@as_of
      AND ff.reason_type=N'采购付款' AND ff.direction=N'付' AND ff.recorded_at<=@as_of
) f;

DECLARE @expected_totals TABLE (
    supplier_name NVARCHAR(100),purchase_count INT,purchased_qty BIGINT,
    purchase_amount DECIMAL(18,2),payment_count INT,paid_amount DECIMAL(18,2)
);
INSERT @expected_totals VALUES
(N'新阅供应链',2,21,972.00,2,972.00),
(N'拾光文创工坊',1,27,456.00,1,456.00);
IF EXISTS (SELECT * FROM @supplier_totals EXCEPT SELECT * FROM @expected_totals)
 OR EXISTS (SELECT * FROM @expected_totals EXCEPT SELECT * FROM @supplier_totals)
    THROW 51945, N'按供应商汇总的采购或付款与预期不一致。', 1;

-- 结果 1：七条当前报价；窗口函数在同一商品内比较，不影响历史成本。
SELECT *,MIN(quote_amount) OVER (PARTITION BY goods_ref) AS lowest_current_quote,
       N'PASS' AS check_result
FROM @quotes ORDER BY goods_ref,supplier_name;

-- 结果 2：五条批次明细。成本减当前报价仅用于观察差异，不要求为零。
SELECT b.*,b.request_qty*b.unit_cost AS batch_amount,q.quote_amount AS current_quote,
       b.unit_cost-q.quote_amount AS cost_minus_current_quote,N'PASS' AS check_result
FROM @batches b
JOIN @quotes q ON q.supplier_name=b.supplier_name AND q.goods_ref=b.goods_ref
ORDER BY b.purchase_no,b.goods_ref;

-- 结果 3：两家供应商的采购、入库数量及付款对账。
SELECT *,N'PASS' AS check_result FROM @supplier_totals ORDER BY supplier_name;

PRINT N'supplier-cost-week-6.sql PASS: 7 quotes, 5 received batch lines and 2 supplier totals match expectations.';
-- purchased_qty 为不同商品数量的合计，不表示这些商品具有相同规格或单位。
-- 采购支出不是已售商品成本；本查询不计算销售毛利或库存计价。
