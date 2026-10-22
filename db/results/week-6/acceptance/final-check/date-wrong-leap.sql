:On Error exit
-- SQLCMD 模式；DatabaseName 由调用者传入，目标须以 ShiguangBookstoreWeek6 开头。
-- W6-S05 静态规则示例与成交卡档快照；不代表会员办理入口已实现。
-- 只读会员、卡档和销售表；不修改有效期、卡档或成交记录。
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
    THROW 51960, N'目标数据库错误，停止会员核对。', 1;
IF @@TRANCOUNT<>0
    THROW 51961, N'请使用没有未结束事务的新查询窗口。', 1;
IF OBJECT_ID(N'dbo.schema_migration',N'U') IS NULL
    THROW 51962, N'缺少第六周迁移表，请先核对工作库。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.member)<>6 OR (SELECT COUNT_BIG(*) FROM dbo.card_type)<>2
    THROW 51963, N'会员或卡档数量不是第六周样例预期。', 1;

-- 独立给定查询日期和预期，避免从 expires_at 反推恒真边界。
DECLARE @cases TABLE (
    case_name varchar(40), opened_date date, expiry_date date, as_of_date date, expected_valid bit
);
INSERT @cases VALUES
('before_open','20260921','20270921','20260920',0),
('opening_day','20260921','20270921','20260921',1),
('before_expiry','20260921','20270921','20270920',1),
('expiry_day','20260921','20270921','20270921',1),
('after_expiry','20260921','20270921','20270922',0);
IF EXISTS (SELECT 1 FROM @cases
    WHERE CONVERT(bit,CASE WHEN as_of_date BETWEEN opened_date AND expiry_date THEN 1 ELSE 0 END)<>expected_valid)
    THROW 51966, N'固定日期有效期规则与独立预期不一致。', 1;
SELECT *,CONVERT(bit,CASE WHEN as_of_date BETWEEN opened_date AND expiry_date THEN 1 ELSE 0 END) AS actual_valid
FROM @cases ORDER BY as_of_date;

-- R-18/R-24：闰日顺延至3月1日；有效重买从原到期日起，过期重买从办理日起。
-- 这些是可执行规则示例，不调用或证明尚未实现的收费、续费和重买入口。
DECLARE @renewal TABLE (
    case_name varchar(40), expires_at date, purchased_on date, expected_expiry date
);
INSERT @renewal VALUES
('expired_rebuy','20250920','20260921','20270921'),
('valid_rebuy','20270921','20260921','20280921'),
('expiry_day_rebuy','20270921','20270921','20280921'),
('leap_first_purchase',NULL,'20240229','20250301'),
('leap_valid_rebuy','20240229','20240228','20250301'),
('ordinary_feb28',NULL,'20230228','20240228');
DECLARE @renewal_actual TABLE (case_name varchar(40), expected_expiry date, actual_expiry date);
INSERT @renewal_actual
SELECT r.case_name,r.expected_expiry,
       CASE WHEN MONTH(b.base_date)=2 AND DAY(b.base_date)=29
            THEN DATEFROMPARTS(YEAR(b.base_date)+1,2,28)
            ELSE DATEADD(year,1,b.base_date) END
FROM @renewal r
CROSS APPLY (SELECT CASE WHEN r.expires_at>=r.purchased_on THEN r.expires_at ELSE r.purchased_on END AS base_date) b;
IF EXISTS (SELECT 1 FROM @renewal_actual WHERE actual_expiry<>expected_expiry)
    THROW 51967, N'有效/过期重买或闰日日期规则与独立预期不一致。', 1;
SELECT * FROM @renewal_actual ORDER BY case_name;

-- 当前六名会员只作静态数据展示，不作为独立业务边界测试。
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

SELECT *,N'STATIC_DATA_ONLY' AS observation_scope FROM @boundary ORDER BY phone;
SELECT * FROM @snap ORDER BY sale_no;
SELECT (SELECT COUNT(*) FROM @boundary) AS member_count,
       (SELECT COUNT(*) FROM @snap) AS snapshot_sale_count,
       (SELECT COUNT(*) FROM @cases) AS fixed_date_rule_cases,
       (SELECT COUNT(*) FROM @renewal_actual) AS renewal_date_rule_cases,
       (SELECT COUNT(*) FROM @boundary WHERE valid_on_expiry_day=1 AND valid_on_next_day=0) AS static_date_observations,
       N'PASS' AS result;

PRINT N'member-validity-week-6.sql PASS: 11 fixed-input date rule examples and five sales snapshots; no membership action endpoint tested.';
-- 本查询是数据与规则的只读核对，不实现开卡、续费、过期重买或权限入口。

