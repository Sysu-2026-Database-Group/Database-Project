-- W6-S05 会员有效期与成交卡档快照：普通 T-SQL，无需 SQLCMD 模式。
-- 只读会员、卡档和销售表；不修改有效期、卡档或成交记录。
USE [ShiguangBookstoreWeek6Work];
GO
SET NOCOUNT ON;
IF DB_NAME()<>N'ShiguangBookstoreWeek6Work'
    THROW 51960, N'目标数据库错误，停止会员核对。', 1;
IF @@TRANCOUNT<>0
    THROW 51961, N'请使用没有未结束事务的新查询窗口。', 1;
IF OBJECT_ID(N'dbo.schema_migration',N'U') IS NULL
    THROW 51962, N'缺少第六周迁移表，请先核对工作库。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.member)<>6 OR (SELECT COUNT_BIG(*) FROM dbo.card_type)<>2
    THROW 51963, N'会员或卡档数量不是第六周样例预期。', 1;

-- 课程要求“到期当天有效、次日失效”。这里使用日期边界，避免受执行当天时间影响。
DECLARE @boundary TABLE (
    phone VARCHAR(11),card_level NVARCHAR(10),opened_date DATE,expires_at DATE,
    valid_on_expiry_day bit,valid_on_next_day bit,points_balance INT
);
INSERT @boundary
SELECT phone,card_level,CONVERT(date,opened_at),expires_at,
       CONVERT(bit,CASE WHEN dates.expiry_day BETWEEN CONVERT(date,opened_at) AND expires_at THEN 1 ELSE 0 END),
       CONVERT(bit,CASE WHEN dates.next_day BETWEEN CONVERT(date,opened_at) AND expires_at THEN 1 ELSE 0 END),
       points_balance
FROM dbo.member
CROSS APPLY (SELECT expires_at AS expiry_day,DATEADD(day,1,expires_at) AS next_day) dates;

-- 显式检查边界判定：每个会员在自己的到期日为有效，次日为无效。
IF EXISTS (SELECT 1 FROM dbo.member WHERE expires_at<=CONVERT(date,opened_at))
    THROW 51964, N'存在不晚于开卡日的会员有效期。', 1;

DECLARE @expected_snapshot TABLE (
    sale_no VARCHAR(20),member_phone VARCHAR(11),sale_card_level NVARCHAR(10),
    sale_discount_rate DECIMAL(3,2),paid_amount DECIMAL(10,2),card_fee DECIMAL(10,2),
    current_card_level NVARCHAR(10),snapshot_check NVARCHAR(10)
);
INSERT @expected_snapshot VALUES
('S20260922-W604','13900000003',N'银卡',0.95,64.60,20.00,N'银卡',N'PASS'),
('S20260923-W605','13900000004',N'金卡',0.90,10.80,50.00,N'金卡',N'PASS'),
('S20260924-W606','13900000004',N'金卡',0.90,187.20,50.00,N'金卡',N'PASS'),
('S20260925-W607','13900000003',N'银卡',0.95,68.40,20.00,N'银卡',N'PASS'),
('S20260927-W609','13900000003',N'银卡',0.95,210.80,20.00,N'银卡',N'PASS');

DECLARE @snap TABLE (
    sale_no VARCHAR(20),member_phone VARCHAR(11),sale_card_level NVARCHAR(10),
    sale_discount_rate DECIMAL(3,2),paid_amount DECIMAL(10,2),card_fee DECIMAL(10,2),
    current_card_level NVARCHAR(10),snapshot_check NVARCHAR(10)
);
INSERT @snap
SELECT s.no,s.member_phone,s.card_level,s.discount_rate,s.paid_amount,
       ct.card_fee,m.card_level,
       CASE WHEN s.card_level=m.card_level AND s.discount_rate=ct.discount_rate THEN N'PASS' ELSE N'FAIL' END
FROM dbo.sale s
JOIN dbo.member m ON m.phone=s.member_phone
JOIN dbo.card_type ct ON ct.[level]=s.card_level
WHERE s.no IN ('S20260922-W604','S20260923-W605','S20260924-W606','S20260925-W607','S20260927-W609');

IF EXISTS (SELECT * FROM @snap EXCEPT SELECT * FROM @expected_snapshot)
 OR EXISTS (SELECT * FROM @expected_snapshot EXCEPT SELECT * FROM @snap)
    THROW 51965, N'第六周会员销售的卡档、折扣或实付快照与预期不一致。', 1;

SELECT *,N'PASS' AS boundary_check FROM @boundary ORDER BY phone;
SELECT * FROM @snap ORDER BY sale_no;
SELECT (SELECT COUNT(*) FROM @boundary) AS member_count,
       (SELECT COUNT(*) FROM @snap) AS snapshot_sale_count,
       (SELECT COUNT(*) FROM @boundary WHERE valid_on_expiry_day=1 AND valid_on_next_day=0) AS boundary_pass_count,
       N'PASS' AS result;

PRINT N'member-validity-week-6.sql PASS: expiry-day boundaries and five sales card snapshots match expectations.';
-- 本查询是数据与规则的只读核对，不实现开卡、续费、过期重买或权限入口。
