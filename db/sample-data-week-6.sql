-- 第六周新增样例装载脚本
-- 目标固定为迁移后的工作副本；本脚本不允许在 ShiguangBookstoreWeek3 上执行。
-- 执行前提：已成功执行 db/migration.sql 和 db/migration-check.sql。
-- 本脚本不使用 SQLCMD 变量，避免 SSMS 未启用 SQLCMD 模式时误解析目标库。

USE [ShiguangBookstoreWeek6Work];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'ShiguangBookstoreWeek6Work'
    THROW 51400, N'当前数据库不是 ShiguangBookstoreWeek6Work，停止装载。', 1;
IF DB_NAME() = N'ShiguangBookstoreWeek3'
    THROW 51401, N'禁止在 ShiguangBookstoreWeek3 原始库上装载第六周样例。', 1;
IF @@TRANCOUNT <> 0
    THROW 51402, N'请在没有外层事务的新查询窗口执行样例脚本。', 1;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NULL
    THROW 51403, N'缺少 schema_migration；请先执行迁移脚本。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.schema_migration
    WHERE migration_key = 'W6-NORMALIZATION-1.0'
      AND source_version = 'v0.1'
      AND target_version = 'v0.2-w6'
      AND status = N'已完成'
)
    THROW 51404, N'第六周迁移标记不是已完成，停止装载。', 1;

/*
  业务键清单。脚本用这些键识别重复运行和冲突，不假设 IDENTITY 值连续。
  34 个顶层业务键包括：3 本书、3 件文创、2 家供应商、4 位会员、7 张采购单、
  6 张预订单、6 张销售单和 3 张退货单。
*/
DECLARE @anchor_count int;
SELECT @anchor_count =
      (SELECT COUNT(*) FROM dbo.book WHERE isbn IN ('9787300000001','9787111000002','9787040000003'))
    + (SELECT COUNT(*) FROM dbo.toy WHERE inner_code IN ('SP-NOTE-003','SP-CUP-004','SP-KEY-005'))
    + (SELECT COUNT(*) FROM dbo.supplier WHERE name IN (N'新阅供应链',N'拾光文创工坊'))
    + (SELECT COUNT(*) FROM dbo.member WHERE phone IN ('13900000003','13900000004','13900000005','13900000006'))
    + (SELECT COUNT(*) FROM dbo.purchase_request WHERE no IN
        ('PR20260921-W604','PR20260921-W605','PR20260921-W606','PR20260921-W607',
         'PR20260921-W608','PR20260921-W609','PR20260921-W610'))
    + (SELECT COUNT(*) FROM dbo.reservation WHERE code IN
        ('W6R-2103','W6R-2104','W6R-2105','W6R-2106','W6R-2107','W6R-2108'))
    + (SELECT COUNT(*) FROM dbo.sale WHERE no IN
        ('S20260922-W604','S20260923-W605','S20260924-W606','S20260925-W607',
         'S20260926-W608','S20260927-W609'))
    + (SELECT COUNT(*) FROM dbo.goods_return WHERE no IN
        ('RT20260928-W603','RT20260928-W604','RT20260929-W605'));

/*
  重复运行保护：全部顶层键均存在时，只接受完整且一致的目标截面；任何部分存在、
  数量不符或关键对账不符都停止，不继续插入，避免把半批数据当成完整样例。
*/
IF @anchor_count > 0
BEGIN
    IF @anchor_count <> 34
        THROW 51405, N'发现部分第六周业务键，可能是上次装载中断；请从工作副本备份恢复后重试。', 1;

    DECLARE @rerun_cash DECIMAL(12,2), @rerun_profit DECIMAL(12,2);
    SELECT @rerun_cash = COALESCE(SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END), 0),
           @rerun_profit = COALESCE(SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0
                                             WHEN direction=N'收' THEN amount ELSE -amount END), 0)
    FROM dbo.fund_flow;

    IF (SELECT COUNT_BIG(*) FROM dbo.book) <> 5
       OR (SELECT COUNT_BIG(*) FROM dbo.toy) <> 5
       OR (SELECT COUNT_BIG(*) FROM dbo.goods) <> 10
       OR (SELECT COUNT_BIG(*) FROM dbo.supplier) <> 5
       OR (SELECT COUNT_BIG(*) FROM dbo.supplier_quote) <> 12
       OR (SELECT COUNT_BIG(*) FROM dbo.member) <> 6
       OR (SELECT COUNT_BIG(*) FROM dbo.purchase_request) <> 10
       OR (SELECT COUNT_BIG(*) FROM dbo.purchase_request_item) <> 14
       OR (SELECT COUNT_BIG(*) FROM dbo.reservation) <> 8
       OR (SELECT COUNT_BIG(*) FROM dbo.reservation_item) <> 10
       OR (SELECT COUNT_BIG(*) FROM dbo.sale) <> 9
       OR (SELECT COUNT_BIG(*) FROM dbo.sale_item) <> 13
       OR (SELECT COUNT_BIG(*) FROM dbo.goods_return) <> 5
       OR (SELECT COUNT_BIG(*) FROM dbo.goods_return_item) <> 7
       OR (SELECT COUNT_BIG(*) FROM dbo.stock_movement) <> 31
       OR (SELECT COUNT_BIG(*) FROM dbo.point_movement) <> 13
       OR (SELECT COUNT_BIG(*) FROM dbo.fund_flow) <> 29
       OR @rerun_cash <> 555.30
       OR @rerun_profit <> -944.70
       OR NOT EXISTS (
            SELECT 1 FROM dbo.goods
            WHERE book_isbn='9787111000002' AND on_shelf=1 AND price=75.00
              AND stock_total=10 AND reserved_qty=3
       )
       OR NOT EXISTS (
            SELECT 1 FROM dbo.member
            WHERE phone='13900000003' AND points_balance=122
       )
       OR NOT EXISTS (
            SELECT 1 FROM dbo.member
            WHERE phone='13900000004' AND points_balance=197
       )
        THROW 51406, N'第六周样例键已存在但目标截面不一致，停止重复装载。', 1;

    PRINT N'sample-data-week-6.sql SKIP: W6 sample data already exists and the target snapshot is consistent.';
    RETURN;
END;

/* 只允许从迁移后、尚未扩充的工作副本开始。 */
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0) <> 20
    THROW 51410, N'迁移后用户表数量不是 20，停止装载。', 1;
IF (SELECT COUNT(*) FROM sys.foreign_keys) <> 49
    THROW 51411, N'迁移后外码数量不是 49，停止装载。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.employee) <> 4
   OR (SELECT COUNT_BIG(*) FROM dbo.card_type) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.book) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.toy) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.goods) <> 4
   OR (SELECT COUNT_BIG(*) FROM dbo.supplier) <> 3
   OR (SELECT COUNT_BIG(*) FROM dbo.supplier_quote) <> 5
   OR (SELECT COUNT_BIG(*) FROM dbo.member) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.purchase_request) <> 3
   OR (SELECT COUNT_BIG(*) FROM dbo.purchase_request_item) <> 5
   OR (SELECT COUNT_BIG(*) FROM dbo.reservation) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.reservation_item) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.sale) <> 3
   OR (SELECT COUNT_BIG(*) FROM dbo.sale_item) <> 4
   OR (SELECT COUNT_BIG(*) FROM dbo.goods_return) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.goods_return_item) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.stock_movement) <> 12
   OR (SELECT COUNT_BIG(*) FROM dbo.point_movement) <> 5
   OR (SELECT COUNT_BIG(*) FROM dbo.fund_flow) <> 13
    THROW 51412, N'目标不是迁移后未扩充的旧基线，停止装载。', 1;

/* 旧基线关键快照：只检查行数不足以证明旧业务事实没有被改写。 */
IF NOT EXISTS (
    SELECT 1 FROM dbo.goods
    WHERE id=1 AND category=N'图书' AND name=N'活着'
      AND book_isbn='9787506365437' AND on_shelf=1 AND price=39.00
      AND stock_total=6 AND reserved_qty=6
)
    THROW 51417, N'旧商品 id=1 快照不一致，停止装载。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.goods
    WHERE id=2 AND category=N'图书' AND name=N'百年孤独'
      AND book_isbn='9787544253994' AND on_shelf=1 AND price=49.00
      AND stock_total=0 AND reserved_qty=0
)
    THROW 51418, N'旧商品 id=2 快照不一致，停止装载。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.goods
    WHERE id=3 AND category=N'文创' AND name=N'拾光帆布袋'
      AND toy_code='SP-BAG-001' AND on_shelf=1 AND price=19.00
      AND stock_total=10 AND reserved_qty=0
)
    THROW 51419, N'旧商品 id=3 快照不一致，停止装载。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.goods
    WHERE id=4 AND category=N'文创' AND name=N'拾光书签'
      AND toy_code='SP-MARK-002' AND on_shelf=1 AND price=6.00
      AND stock_total=19 AND reserved_qty=0
)
    THROW 51420, N'旧商品 id=4 快照不一致，停止装载。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.member
    WHERE phone='13900000001' AND card_level=N'金卡' AND points_balance=-26
)
    THROW 51421, N'旧会员 13900000001 快照不一致，停止装载。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.member
    WHERE phone='13900000002' AND card_level=N'金卡' AND points_balance=0
)
    THROW 51422, N'旧会员 13900000002 快照不一致，停止装载。', 1;

DECLARE @legacy_cash DECIMAL(12,2), @legacy_profit DECIMAL(12,2);
SELECT @legacy_cash = COALESCE(SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END), 0),
       @legacy_profit = COALESCE(SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0
                                          WHEN direction=N'收' THEN amount ELSE -amount END), 0)
FROM dbo.fund_flow;
IF @legacy_cash <> 1430.30 OR @legacy_profit <> -69.70
    THROW 51423, N'旧资金截面不一致，停止装载。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.member
    WHERE phone IN ('13900000003','13900000004','13900000005','13900000006')
)
    THROW 51413, N'新增会员手机号已存在，停止装载。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.book
    WHERE isbn IN ('9787300000001','9787111000002','9787040000003')
)
    THROW 51414, N'新增 ISBN 已存在，停止装载。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.toy
    WHERE inner_code IN ('SP-NOTE-003','SP-CUP-004','SP-KEY-005')
)
    THROW 51415, N'新增文创内部编码已存在，停止装载。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.supplier
    WHERE name IN (N'新阅供应链',N'拾光文创工坊')
)
    THROW 51416, N'新增供应商名称已存在，停止装载。', 1;

DECLARE @manager VARCHAR(11) = '13800000001';
DECLARE @warehouse VARCHAR(11) = '13800000002';
DECLARE @cashier VARCHAR(11) = '13800000003';
DECLARE @cashier2 VARCHAR(11) = '13800000004';

DECLARE @sup04 BIGINT, @sup05 BIGINT;
DECLARE @g05 BIGINT, @g06 BIGINT, @g07 BIGINT, @g08 BIGINT, @g09 BIGINT, @g10 BIGINT;
DECLARE @pr04 BIGINT, @pr05 BIGINT, @pr06 BIGINT, @pr07 BIGINT, @pr08 BIGINT, @pr09 BIGINT, @pr10 BIGINT;
DECLARE @r03 BIGINT, @r04 BIGINT, @r05 BIGINT, @r06 BIGINT, @r07 BIGINT, @r08 BIGINT;
DECLARE @s04 BIGINT, @s05 BIGINT, @s06 BIGINT, @s07 BIGINT, @s08 BIGINT, @s09 BIGINT;
DECLARE @rt03 BIGINT, @rt04 BIGINT, @rt05 BIGINT;
DECLARE @rti03_g09 BIGINT, @rti03_g10 BIGINT, @rti04_g07 BIGINT, @rti05_g07 BIGINT, @rti05_g08 BIGINT;
DECLARE @si_s04_g07 BIGINT, @si_s05_g10 BIGINT, @si_s06_g07 BIGINT, @si_s06_g08 BIGINT,
        @si_s07_g07 BIGINT, @si_s08_g09 BIGINT, @si_s08_g10 BIGINT, @si_s09_g07 BIGINT, @si_s09_g08 BIGINT;

BEGIN TRY
    BEGIN TRANSACTION;

    /* 新的图书和文创细节。 */
    INSERT dbo.book (isbn, author, publisher, page_count) VALUES
        ('9787300000001', N'王珊', N'高等教育出版社', 520),
        ('9787111000002', N'李明', N'机械工业出版社', 360),
        ('9787040000003', N'周宁', N'清华大学出版社', 280);

    INSERT dbo.toy (inner_code, spec) VALUES
        ('SP-NOTE-003', N'A6 80页米白纸便签本'),
        ('SP-CUP-004', N'350ml 304不锈钢保温杯'),
        ('SP-KEY-005', N'金属书本造型钥匙扣');

    /* 新供应商和会员。M05 是过期后重买的终态；过期前状态在独立事务中验证。 */
    INSERT dbo.supplier (name, created_by, created_at) VALUES
        (N'新阅供应链', @warehouse, '2026-09-21T08:00:00'),
        (N'拾光文创工坊', @warehouse, '2026-09-21T08:05:00');
    SELECT @sup04 = id FROM dbo.supplier WHERE name=N'新阅供应链';
    SELECT @sup05 = id FROM dbo.supplier WHERE name=N'拾光文创工坊';

    INSERT dbo.member (phone, card_level, opened_by, opened_at, updated_by, updated_at, expires_at, points_balance) VALUES
        ('13900000003', N'银卡', @cashier, '2026-09-21T09:00:00', NULL, NULL, '2027-09-21', 0),
        ('13900000004', N'金卡', @cashier, '2026-09-21T09:05:00', NULL, NULL, '2027-09-21', 0),
        ('13900000005', N'金卡', @cashier, '2026-09-21T09:10:00', @cashier, '2026-09-21T09:10:00', '2027-09-21', 0),
        ('13900000006', N'银卡', @cashier, '2026-09-21T09:15:00', NULL, NULL, '2027-09-21', 0);

    /* 先建商品的最终价格和上架状态，库存计数在流水及预订写入后统一落账。 */
    INSERT dbo.goods
        (category, name, book_isbn, toy_code, on_shelf, price, stock_total, reserved_qty, created_by, created_at, updated_by, updated_at)
    VALUES
        (N'图书', N'数据库系统概论', '9787300000001', NULL, 0, NULL, 0, 0, @warehouse, '2026-09-21T08:30:00', NULL, NULL),
        (N'文创', N'拾光便签本', NULL, 'SP-NOTE-003', 0, 29.00, 0, 0, @warehouse, '2026-09-21T08:35:00', NULL, NULL),
        (N'图书', N'SQL Server 实战', '9787111000002', NULL, 1, 75.00, 0, 0, @warehouse, '2026-09-21T08:40:00', @manager, '2026-09-25T18:00:00'),
        (N'文创', N'拾光保温杯', NULL, 'SP-CUP-004', 1, 36.00, 0, 0, @warehouse, '2026-09-21T08:45:00', NULL, NULL),
        (N'图书', N'数据建模入门', '9787040000003', NULL, 1, 58.00, 0, 0, @warehouse, '2026-09-21T08:50:00', NULL, NULL),
        (N'文创', N'拾光钥匙扣', NULL, 'SP-KEY-005', 1, 12.00, 0, 0, @warehouse, '2026-09-21T08:55:00', NULL, NULL);

    SELECT @g05 = id FROM dbo.goods WHERE book_isbn='9787300000001';
    SELECT @g06 = id FROM dbo.goods WHERE toy_code='SP-NOTE-003';
    SELECT @g07 = id FROM dbo.goods WHERE book_isbn='9787111000002';
    SELECT @g08 = id FROM dbo.goods WHERE toy_code='SP-CUP-004';
    SELECT @g09 = id FROM dbo.goods WHERE book_isbn='9787040000003';
    SELECT @g10 = id FROM dbo.goods WHERE toy_code='SP-KEY-005';
    IF @g05 IS NULL OR @g06 IS NULL OR @g07 IS NULL OR @g08 IS NULL OR @g09 IS NULL OR @g10 IS NULL
        THROW 51424, N'新增商品业务键未能解析为 goods.id。', 1;

    /* 当前报价：同一商品由多家供应商报价；采购明细保留历史批次成本。 */
    INSERT dbo.supplier_quote (supplier_id, goods_id, quote_amount, reported_by, reported_at) VALUES
        (@sup04, @g07, 55.00, @warehouse, '2026-09-21T09:20:00'),
        (@sup04, @g08, 30.00, @warehouse, '2026-09-21T09:21:00'),
        (@sup04, @g09, 48.00, @warehouse, '2026-09-21T09:22:00'),
        (@sup05, @g07, 57.00, @warehouse, '2026-09-21T09:23:00'),
        (@sup05, @g08, 28.00, @warehouse, '2026-09-21T09:24:00'),
        (@sup05, @g09, 50.00, @warehouse, '2026-09-21T09:25:00'),
        (@sup05, @g10, 8.00, @warehouse, '2026-09-21T09:26:00');

    /* 采购申请阶段：只有 PR08—PR10 已收货并产生付款和入库流水。 */
    INSERT dbo.purchase_request
        (no, supplier_id, status, created_by, created_at, submitted_by, submitted_at, approved_by, approved_at, cancelled_by, cancelled_at)
    VALUES
        ('PR20260921-W604', @sup04, N'草稿', @warehouse, '2026-09-21T08:00:00', NULL, NULL, NULL, NULL, NULL, NULL),
        ('PR20260921-W605', @sup04, N'已提交', @warehouse, '2026-09-21T08:05:00', @warehouse, '2026-09-21T08:15:00', NULL, NULL, NULL, NULL),
        ('PR20260921-W606', @sup04, N'已审批', @warehouse, '2026-09-21T08:10:00', @warehouse, '2026-09-21T08:20:00', @manager, '2026-09-21T08:30:00', NULL, NULL),
        ('PR20260921-W607', @sup05, N'已取消', @warehouse, '2026-09-21T08:15:00', NULL, NULL, NULL, NULL, @manager, '2026-09-21T08:25:00'),
        ('PR20260921-W608', @sup04, N'已收货', @warehouse, '2026-09-21T08:20:00', @warehouse, '2026-09-21T08:30:00', @manager, '2026-09-21T08:40:00', NULL, NULL),
        ('PR20260921-W609', @sup05, N'已收货', @warehouse, '2026-09-21T08:25:00', @warehouse, '2026-09-21T08:35:00', @manager, '2026-09-21T08:45:00', NULL, NULL),
        ('PR20260921-W610', @sup04, N'已收货', @warehouse, '2026-09-21T08:30:00', @warehouse, '2026-09-21T08:40:00', @manager, '2026-09-21T08:50:00', NULL, NULL);
    SELECT @pr04 = id FROM dbo.purchase_request WHERE no='PR20260921-W604';
    SELECT @pr05 = id FROM dbo.purchase_request WHERE no='PR20260921-W605';
    SELECT @pr06 = id FROM dbo.purchase_request WHERE no='PR20260921-W606';
    SELECT @pr07 = id FROM dbo.purchase_request WHERE no='PR20260921-W607';
    SELECT @pr08 = id FROM dbo.purchase_request WHERE no='PR20260921-W608';
    SELECT @pr09 = id FROM dbo.purchase_request WHERE no='PR20260921-W609';
    SELECT @pr10 = id FROM dbo.purchase_request WHERE no='PR20260921-W610';

    INSERT dbo.purchase_request_item (request_id, goods_id, request_qty, unit_cost) VALUES
        (@pr04, @g05, 1, 40.00),
        (@pr05, @g06, 1, 20.00),
        (@pr06, @g07, 1, 55.00),
        (@pr07, @g08, 1, 30.00),
        (@pr08, @g07, 10, 55.00),
        (@pr08, @g08, 7, 30.00),
        (@pr09, @g09, 6, 48.00),
        (@pr09, @g10, 21, 8.00),
        (@pr10, @g07, 4, 53.00);

    /* 预订有效期均严格为创建时刻加三天。R05 是扩充截面仍有效的占用。 */
    INSERT dbo.reservation
        (code, phone, status, created_at, expires_at, cancelled_by_employee, cancelled_at)
    VALUES
        ('W6R-2103', '13900000006', N'已取消', '2026-09-21T09:00:00', '2026-09-24T09:00:00', @cashier, '2026-09-21T10:00:00'),
        ('W6R-2104', '13900000006', N'已过期', '2026-09-21T09:30:00', '2026-09-24T09:30:00', NULL, NULL),
        ('W6R-2105', '13900000003', N'有效', '2026-09-27T09:00:00', '2026-09-30T09:00:00', NULL, NULL),
        ('W6R-2106', '13900000004', N'已取', '2026-09-22T09:00:00', '2026-09-25T09:00:00', NULL, NULL),
        ('W6R-2107', '13900000003', N'已取', '2026-09-23T09:00:00', '2026-09-26T09:00:00', NULL, NULL),
        ('W6R-2108', '13900000006', N'已取消', '2026-09-26T09:00:00', '2026-09-29T09:00:00', @cashier, '2026-09-26T11:00:00');
    SELECT @r03 = id FROM dbo.reservation WHERE code='W6R-2103';
    SELECT @r04 = id FROM dbo.reservation WHERE code='W6R-2104';
    SELECT @r05 = id FROM dbo.reservation WHERE code='W6R-2105';
    SELECT @r06 = id FROM dbo.reservation WHERE code='W6R-2106';
    SELECT @r07 = id FROM dbo.reservation WHERE code='W6R-2107';
    SELECT @r08 = id FROM dbo.reservation WHERE code='W6R-2108';

    INSERT dbo.reservation_item (reservation_id, goods_id, quantity) VALUES
        (@r03, @g08, 1),
        (@r04, @g09, 1),
        (@r05, @g07, 3),
        (@r06, @g07, 2),
        (@r06, @g08, 2),
        (@r07, @g07, 1),
        (@r08, @g09, 1),
        (@r08, @g10, 2);

    /* 销售单保留成交时的卡档位、折扣、原价和行价快照。 */
    INSERT dbo.sale
        (no, status, cashier_by, sold_at, card_level, member_phone, reservation_id, subtotal_amount, discount_rate, point_deduction_amount, paid_amount)
    VALUES
        ('S20260922-W604', N'已付', @cashier, '2026-09-22T11:00:00', N'银卡', '13900000003', NULL, 68.00, 0.95, 0.00, 64.60),
        ('S20260923-W605', N'已付', @cashier, '2026-09-23T11:00:00', N'金卡', '13900000004', NULL, 12.00, 0.90, 0.00, 10.80),
        ('S20260924-W606', N'已付', @cashier, '2026-09-24T14:00:00', N'金卡', '13900000004', @r06, 208.00, 0.90, 0.00, 187.20),
        ('S20260925-W607', N'已付', @cashier, '2026-09-25T14:00:00', N'银卡', '13900000003', @r07, 72.00, 0.95, 0.00, 68.40),
        ('S20260926-W608', N'部分退款', @cashier, '2026-09-26T14:00:00', NULL, NULL, NULL, 152.00, 1.00, 0.00, 152.00),
        ('S20260927-W609', N'已全退', @cashier, '2026-09-27T14:00:00', N'银卡', '13900000003', NULL, 222.00, 0.95, 0.10, 210.80);
    SELECT @s04 = id FROM dbo.sale WHERE no='S20260922-W604';
    SELECT @s05 = id FROM dbo.sale WHERE no='S20260923-W605';
    SELECT @s06 = id FROM dbo.sale WHERE no='S20260924-W606';
    SELECT @s07 = id FROM dbo.sale WHERE no='S20260925-W607';
    SELECT @s08 = id FROM dbo.sale WHERE no='S20260926-W608';
    SELECT @s09 = id FROM dbo.sale WHERE no='S20260927-W609';

    INSERT dbo.sale_item (sale_id, goods_id, quantity, unit_price) VALUES
        (@s04, @g07, 1, 68.00),
        (@s05, @g10, 1, 12.00),
        (@s06, @g07, 2, 68.00),
        (@s06, @g08, 2, 36.00),
        (@s07, @g07, 1, 72.00),
        (@s08, @g09, 2, 58.00),
        (@s08, @g10, 3, 12.00),
        (@s09, @g07, 2, 75.00),
        (@s09, @g08, 2, 36.00);
    SELECT @si_s04_g07 = id FROM dbo.sale_item WHERE sale_id=@s04 AND goods_id=@g07;
    SELECT @si_s05_g10 = id FROM dbo.sale_item WHERE sale_id=@s05 AND goods_id=@g10;
    SELECT @si_s06_g07 = id FROM dbo.sale_item WHERE sale_id=@s06 AND goods_id=@g07;
    SELECT @si_s06_g08 = id FROM dbo.sale_item WHERE sale_id=@s06 AND goods_id=@g08;
    SELECT @si_s07_g07 = id FROM dbo.sale_item WHERE sale_id=@s07 AND goods_id=@g07;
    SELECT @si_s08_g09 = id FROM dbo.sale_item WHERE sale_id=@s08 AND goods_id=@g09;
    SELECT @si_s08_g10 = id FROM dbo.sale_item WHERE sale_id=@s08 AND goods_id=@g10;
    SELECT @si_s09_g07 = id FROM dbo.sale_item WHERE sale_id=@s09 AND goods_id=@g07;
    SELECT @si_s09_g08 = id FROM dbo.sale_item WHERE sale_id=@s09 AND goods_id=@g08;

    /* 散客多行退货，以及同一销售单的分次全退。 */
    INSERT dbo.goods_return (no, sale_id, refund_amount, handled_by, handled_at) VALUES
        ('RT20260928-W603', @s08, 70.00, @cashier2, '2026-09-28T10:00:00'),
        ('RT20260928-W604', @s09, 71.22, @cashier2, '2026-09-28T11:00:00'),
        ('RT20260929-W605', @s09, 139.58, @cashier2, '2026-09-29T10:00:00');
    SELECT @rt03 = id FROM dbo.goods_return WHERE no='RT20260928-W603';
    SELECT @rt04 = id FROM dbo.goods_return WHERE no='RT20260928-W604';
    SELECT @rt05 = id FROM dbo.goods_return WHERE no='RT20260929-W605';

    INSERT dbo.goods_return_item (return_id, sale_item_id, quantity, refund_amount) VALUES
        (@rt03, @si_s08_g09, 1, 58.00),
        (@rt03, @si_s08_g10, 1, 12.00),
        (@rt04, @si_s09_g07, 1, 71.22),
        (@rt05, @si_s09_g07, 1, 71.22),
        (@rt05, @si_s09_g08, 2, 68.36);
    SELECT @rti03_g09 = id FROM dbo.goods_return_item WHERE return_id=@rt03 AND sale_item_id=@si_s08_g09;
    SELECT @rti03_g10 = id FROM dbo.goods_return_item WHERE return_id=@rt03 AND sale_item_id=@si_s08_g10;
    SELECT @rti04_g07 = id FROM dbo.goods_return_item WHERE return_id=@rt04 AND sale_item_id=@si_s09_g07;
    SELECT @rti05_g07 = id FROM dbo.goods_return_item WHERE return_id=@rt05 AND sale_item_id=@si_s09_g07;
    SELECT @rti05_g08 = id FROM dbo.goods_return_item WHERE return_id=@rt05 AND sale_item_id=@si_s09_g08;

    /* 库存流水：5 条购入、9 条卖出、5 条退货；数量按 R-21 保存正负号。 */
    INSERT dbo.stock_movement
        (goods_id, change_type, quantity, note, changed_by, changed_at, request_id, sale_id, return_item_id)
    VALUES
        (@g07, N'购入', 10, NULL, @warehouse, '2026-09-21T10:40:00', @pr08, NULL, NULL),
        (@g08, N'购入', 7, NULL, @warehouse, '2026-09-21T10:41:00', @pr08, NULL, NULL),
        (@g09, N'购入', 6, NULL, @warehouse, '2026-09-21T10:42:00', @pr09, NULL, NULL),
        (@g10, N'购入', 21, NULL, @warehouse, '2026-09-21T10:43:00', @pr09, NULL, NULL),
        (@g07, N'购入', 4, NULL, @warehouse, '2026-09-21T10:44:00', @pr10, NULL, NULL),
        (@g07, N'卖出', -1, NULL, @cashier, '2026-09-22T11:00:00', NULL, @s04, NULL),
        (@g10, N'卖出', -1, NULL, @cashier, '2026-09-23T11:00:00', NULL, @s05, NULL),
        (@g07, N'卖出', -2, NULL, @cashier, '2026-09-24T14:00:00', NULL, @s06, NULL),
        (@g08, N'卖出', -2, NULL, @cashier, '2026-09-24T14:01:00', NULL, @s06, NULL),
        (@g07, N'卖出', -1, NULL, @cashier, '2026-09-25T14:00:00', NULL, @s07, NULL),
        (@g09, N'卖出', -2, NULL, @cashier, '2026-09-26T14:00:00', NULL, @s08, NULL),
        (@g10, N'卖出', -3, NULL, @cashier, '2026-09-26T14:01:00', NULL, @s08, NULL),
        (@g07, N'卖出', -2, NULL, @cashier, '2026-09-27T14:00:00', NULL, @s09, NULL),
        (@g08, N'卖出', -2, NULL, @cashier, '2026-09-27T14:01:00', NULL, @s09, NULL),
        (@g09, N'退货', 1, NULL, @warehouse, '2026-09-28T10:05:00', NULL, NULL, @rti03_g09),
        (@g10, N'退货', 1, NULL, @warehouse, '2026-09-28T10:06:00', NULL, NULL, @rti03_g10),
        (@g07, N'退货', 1, NULL, @warehouse, '2026-09-28T11:05:00', NULL, NULL, @rti04_g07),
        (@g07, N'退货', 1, NULL, @warehouse, '2026-09-29T10:05:00', NULL, NULL, @rti05_g07),
        (@g08, N'退货', 2, NULL, @warehouse, '2026-09-29T10:06:00', NULL, NULL, @rti05_g08);

    /* 积分流水：S09 的抵扣保留，后续退货只回滚原获得积分，不返还已抵扣积分。 */
    INSERT dbo.point_movement
        (member_phone, change_type, points, sale_id, return_id, changed_by, changed_at)
    VALUES
        ('13900000003', N'消费获得', 64, @s04, NULL, @cashier, '2026-09-22T11:00:00'),
        ('13900000004', N'消费获得', 10, @s05, NULL, @cashier, '2026-09-23T11:00:00'),
        ('13900000004', N'消费获得', 187, @s06, NULL, @cashier, '2026-09-24T14:00:00'),
        ('13900000003', N'消费获得', 68, @s07, NULL, @cashier, '2026-09-25T14:00:00'),
        ('13900000003', N'抵扣使用', -10, @s09, NULL, @cashier, '2026-09-27T14:00:00'),
        ('13900000003', N'消费获得', 210, @s09, NULL, @cashier, '2026-09-27T14:00:01'),
        ('13900000003', N'退货回滚', -70, @s09, @rt04, @cashier2, '2026-09-28T11:00:00'),
        ('13900000003', N'退货回滚', -140, @s09, @rt05, @cashier2, '2026-09-29T10:00:00');

    /* 资金流水必须接续旧基线最后余额 1430.30，前后余额逐行连续。 */
    INSERT dbo.fund_flow
        (amount, direction, reason_type, sale_id, return_id, request_id, member_phone, fund_before, fund_after, recorded_by, recorded_at)
    VALUES
        (20.00, N'收', N'办卡费', NULL, NULL, NULL, '13900000003', 1430.30, 1450.30, @cashier, '2026-09-21T09:00:00'),
        (50.00, N'收', N'办卡费', NULL, NULL, NULL, '13900000004', 1450.30, 1500.30, @cashier, '2026-09-21T09:05:00'),
        (50.00, N'收', N'办卡费', NULL, NULL, NULL, '13900000005', 1500.30, 1550.30, @cashier, '2026-09-21T09:10:00'),
        (20.00, N'收', N'办卡费', NULL, NULL, NULL, '13900000006', 1550.30, 1570.30, @cashier, '2026-09-21T09:15:00'),
        (760.00, N'付', N'采购付款', NULL, NULL, @pr08, NULL, 1570.30, 810.30, @manager, '2026-09-21T10:30:00'),
        (456.00, N'付', N'采购付款', NULL, NULL, @pr09, NULL, 810.30, 354.30, @manager, '2026-09-21T10:31:00'),
        (212.00, N'付', N'采购付款', NULL, NULL, @pr10, NULL, 354.30, 142.30, @manager, '2026-09-21T10:32:00'),
        (64.60, N'收', N'销售收款', @s04, NULL, NULL, NULL, 142.30, 206.90, @cashier, '2026-09-22T11:00:00'),
        (10.80, N'收', N'销售收款', @s05, NULL, NULL, NULL, 206.90, 217.70, @cashier, '2026-09-23T11:00:00'),
        (187.20, N'收', N'销售收款', @s06, NULL, NULL, NULL, 217.70, 404.90, @cashier, '2026-09-24T14:00:00'),
        (68.40, N'收', N'销售收款', @s07, NULL, NULL, NULL, 404.90, 473.30, @cashier, '2026-09-25T14:00:00'),
        (152.00, N'收', N'销售收款', @s08, NULL, NULL, NULL, 473.30, 625.30, @cashier, '2026-09-26T14:00:00'),
        (210.80, N'收', N'销售收款', @s09, NULL, NULL, NULL, 625.30, 836.10, @cashier, '2026-09-27T14:00:00'),
        (70.00, N'付', N'退货退款', @s08, @rt03, NULL, NULL, 836.10, 766.10, @cashier2, '2026-09-28T10:00:00'),
        (71.22, N'付', N'退货退款', @s09, @rt04, NULL, NULL, 766.10, 694.88, @cashier2, '2026-09-28T11:00:00'),
        (139.58, N'付', N'退货退款', @s09, @rt05, NULL, NULL, 694.88, 555.30, @cashier2, '2026-09-29T10:00:00');

    /* 计数列和积分余额是当前模型中的冗余快照，最后按本批流水落账。 */
    UPDATE dbo.goods SET stock_total=10, reserved_qty=3 WHERE id=@g07;
    UPDATE dbo.goods SET stock_total=5, reserved_qty=0 WHERE id=@g08;
    UPDATE dbo.goods SET stock_total=5, reserved_qty=0 WHERE id=@g09;
    UPDATE dbo.goods SET stock_total=18, reserved_qty=0 WHERE id=@g10;
    UPDATE dbo.member SET points_balance=122 WHERE phone='13900000003';
    UPDATE dbo.member SET points_balance=197 WHERE phone='13900000004';

    /* 提交前断言：行数、四类账目和资金链必须与规划截面一致。 */
    IF (SELECT COUNT_BIG(*) FROM dbo.book) <> 5
       OR (SELECT COUNT_BIG(*) FROM dbo.toy) <> 5
       OR (SELECT COUNT_BIG(*) FROM dbo.goods) <> 10
       OR (SELECT COUNT_BIG(*) FROM dbo.supplier) <> 5
       OR (SELECT COUNT_BIG(*) FROM dbo.supplier_quote) <> 12
       OR (SELECT COUNT_BIG(*) FROM dbo.member) <> 6
       OR (SELECT COUNT_BIG(*) FROM dbo.purchase_request) <> 10
       OR (SELECT COUNT_BIG(*) FROM dbo.purchase_request_item) <> 14
       OR (SELECT COUNT_BIG(*) FROM dbo.reservation) <> 8
       OR (SELECT COUNT_BIG(*) FROM dbo.reservation_item) <> 10
       OR (SELECT COUNT_BIG(*) FROM dbo.sale) <> 9
       OR (SELECT COUNT_BIG(*) FROM dbo.sale_item) <> 13
       OR (SELECT COUNT_BIG(*) FROM dbo.goods_return) <> 5
       OR (SELECT COUNT_BIG(*) FROM dbo.goods_return_item) <> 7
       OR (SELECT COUNT_BIG(*) FROM dbo.stock_movement) <> 31
       OR (SELECT COUNT_BIG(*) FROM dbo.point_movement) <> 13
       OR (SELECT COUNT_BIG(*) FROM dbo.fund_flow) <> 29
        THROW 51430, N'样例装载后的逐表数量不符合预期。', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.goods g
        OUTER APPLY (SELECT SUM(CONVERT(bigint, quantity)) AS n FROM dbo.stock_movement m WHERE m.goods_id=g.id) sm
        OUTER APPLY (SELECT SUM(CONVERT(bigint, quantity)) AS n FROM dbo.reservation_item i
                     JOIN dbo.reservation r ON r.id=i.reservation_id
                     WHERE i.goods_id=g.id AND r.status=N'有效') rq
        WHERE g.stock_total<>COALESCE(sm.n,0) OR g.reserved_qty<>COALESCE(rq.n,0)
    )
        THROW 51431, N'新增样例库存或有效预订对账失败。', 1;
    IF EXISTS (
        SELECT 1 FROM dbo.member m
        OUTER APPLY (SELECT SUM(CONVERT(bigint, points)) AS n FROM dbo.point_movement p WHERE p.member_phone=m.phone) pm
        WHERE m.points_balance<>COALESCE(pm.n,0)
    )
        THROW 51432, N'新增样例积分余额对账失败。', 1;
    IF EXISTS (
        SELECT 1 FROM dbo.sale s
        OUTER APPLY (SELECT SUM(unit_price*quantity) AS amount FROM dbo.sale_item i WHERE i.sale_id=s.id) si
        WHERE s.subtotal_amount<>COALESCE(si.amount,0)
    )
        THROW 51433, N'新增样例销售单头金额与明细不一致。', 1;
    IF EXISTS (
        SELECT 1 FROM (SELECT fund_before,
            LAG(fund_after,1,CONVERT(decimal(12,2),0)) OVER (ORDER BY recorded_at,id) AS previous_after
            FROM dbo.fund_flow) x
        WHERE x.fund_before<>x.previous_after
    )
        THROW 51434, N'新增样例资金链不连续。', 1;

    DECLARE @cash_after DECIMAL(12,2), @profit_after DECIMAL(12,2);
    SELECT @cash_after = SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END),
           @profit_after = SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0
                                    WHEN direction=N'收' THEN amount ELSE -amount END)
    FROM dbo.fund_flow;
    IF @cash_after <> 555.30 OR @profit_after <> -944.70
        THROW 51435, N'新增样例现金余额或经营盈亏不符合预期。', 1;

    COMMIT;

    SELECT N'sample-data-week-6' AS check_name,
           DB_NAME() AS database_name,
           199 AS planned_user_rows,
           (SELECT COUNT_BIG(*) FROM dbo.goods) AS goods_count,
           (SELECT COUNT_BIG(*) FROM dbo.member) AS member_count,
           (SELECT COUNT_BIG(*) FROM dbo.sale) AS sale_count,
           (SELECT COUNT_BIG(*) FROM dbo.goods_return) AS return_count,
           @cash_after AS cash_balance,
           @profit_after AS operating_result;
    PRINT N'sample-data-week-6.sql PASS: W6-S01 to W6-S11 loaded; legacy rows retained.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK;
    THROW;
END CATCH;
