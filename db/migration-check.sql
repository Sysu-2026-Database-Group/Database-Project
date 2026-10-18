-- 第六周迁移后只读核对
-- 目标固定为从 v0.1 备份还原的工作副本；本脚本不写入业务表。
USE [ShiguangBookstoreWeek6Work];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'ShiguangBookstoreWeek6Work'
    THROW 51300, N'当前数据库不是 ShiguangBookstoreWeek6Work，停止核对。', 1;

IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) <> 20
    THROW 51301, N'迁移后用户表数量不是 20。', 1;
IF (SELECT COUNT(*) FROM sys.foreign_keys) <> 49
    THROW 51302, N'迁移后外码数量不是 49。', 1;
IF (SELECT COUNT(*) FROM sys.key_constraints WHERE type = 'PK') <> 20
    THROW 51303, N'迁移后主键数量不是 20。', 1;
IF (SELECT COUNT(*) FROM sys.key_constraints WHERE type = 'UQ') <> 10
    THROW 51304, N'迁移后业务唯一约束数量不是 10。', 1;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE is_disabled = 1 OR is_not_trusted = 1)
    THROW 51305, N'迁移后存在禁用或未信任的外码。', 1;
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE is_disabled = 1 OR is_not_trusted = 1)
    THROW 51306, N'迁移后存在禁用或未信任的 CHECK 约束。', 1;

IF NOT EXISTS (
    SELECT 1 FROM dbo.schema_migration
    WHERE migration_key = 'W6-NORMALIZATION-1.0'
      AND source_version = 'v0.1'
      AND target_version = 'v0.2-w6'
      AND status = N'已完成'
)
    THROW 51307, N'缺少已完成的 W6-NORMALIZATION-1.0 迁移记录。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.schema_migration) <> 1
    THROW 51308, N'schema_migration 记录数量不是 1。', 1;

IF COL_LENGTH(N'dbo.supplier', N'updated_by') IS NULL
   OR COL_LENGTH(N'dbo.supplier', N'updated_at') IS NULL
    THROW 51309, N'supplier 修改留痕字段未创建。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.supplier) <> 3
   OR EXISTS (SELECT 1 FROM dbo.supplier WHERE updated_by IS NOT NULL OR updated_at IS NOT NULL)
    THROW 51310, N'旧供应商数量或 NULL 留痕状态不符。', 1;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_supplier_updated_by')
    THROW 51311, N'supplier.updated_by 外码未创建。', 1;

DECLARE @required_indexes TABLE (table_name sysname NOT NULL, index_name sysname NOT NULL);
INSERT @required_indexes VALUES
    (N'goods', N'UX_goods_book_isbn'),
    (N'goods', N'UX_goods_toy_code'),
    (N'sale', N'UX_sale_reservation_id'),
    (N'point_movement', N'UX_point_movement_earn'),
    (N'point_movement', N'UX_point_movement_use'),
    (N'point_movement', N'UX_point_movement_return');
IF EXISTS (
    SELECT 1
    FROM @required_indexes r
    LEFT JOIN sys.tables t ON t.schema_id = SCHEMA_ID(N'dbo') AND t.name = r.table_name
    LEFT JOIN sys.indexes i ON i.object_id = t.object_id AND i.name = r.index_name
    WHERE i.index_id IS NULL OR i.is_unique <> 1 OR i.has_filter <> 1
)
    THROW 51312, N'迁移筛选唯一索引缺失、非唯一或未设置筛选。', 1;

IF (SELECT COUNT_BIG(*) FROM dbo.goods) <> 4 THROW 51320, N'goods 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.book) <> 2 THROW 51320, N'book 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.toy) <> 2 THROW 51320, N'toy 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.supplier) <> 3 THROW 51320, N'supplier 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.supplier_quote) <> 5 THROW 51320, N'supplier_quote 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.stock_movement) <> 12 THROW 51320, N'stock_movement 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.purchase_request) <> 3 THROW 51320, N'purchase_request 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.purchase_request_item) <> 5 THROW 51320, N'purchase_request_item 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.sale) <> 3 THROW 51320, N'sale 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.sale_item) <> 4 THROW 51320, N'sale_item 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.reservation) <> 2 THROW 51320, N'reservation 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.reservation_item) <> 2 THROW 51320, N'reservation_item 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.goods_return) <> 2 THROW 51320, N'goods_return 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.goods_return_item) <> 2 THROW 51320, N'goods_return_item 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.card_type) <> 2 THROW 51320, N'card_type 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.member) <> 2 THROW 51320, N'member 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.point_movement) <> 5 THROW 51320, N'point_movement 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.fund_flow) <> 13 THROW 51320, N'fund_flow 旧行数改变。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.employee) <> 4 THROW 51320, N'employee 旧行数改变。', 1;

-- 旧关键快照：迁移不能改写商品、细节、销售和会员事实。
IF NOT EXISTS (SELECT 1 FROM dbo.goods WHERE id=1 AND category=N'图书' AND name=N'活着' AND book_isbn='9787506365437' AND stock_total=6 AND reserved_qty=6)
    THROW 51321, N'旧商品 1 快照改变。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.goods WHERE id=2 AND category=N'图书' AND name=N'百年孤独' AND book_isbn='9787544253994' AND stock_total=0 AND reserved_qty=0)
    THROW 51321, N'旧商品 2 快照改变。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.goods WHERE id=3 AND category=N'文创' AND toy_code='SP-BAG-001' AND stock_total=10 AND reserved_qty=0)
    THROW 51321, N'旧商品 3 快照改变。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.goods WHERE id=4 AND category=N'文创' AND toy_code='SP-MARK-002' AND stock_total=19 AND reserved_qty=0)
    THROW 51321, N'旧商品 4 快照改变。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.member WHERE phone='13900000001' AND card_level=N'金卡' AND points_balance=-26)
    THROW 51322, N'旧会员积分快照改变。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.member WHERE phone='13900000002' AND card_level=N'金卡' AND points_balance=0)
    THROW 51322, N'旧会员 2 快照改变。', 1;

-- 四类跨表对账：迁移后旧截面仍应保持一致。
IF EXISTS (
    SELECT 1 FROM dbo.goods g
    OUTER APPLY (SELECT SUM(CONVERT(bigint, quantity)) AS n FROM dbo.stock_movement WHERE goods_id=g.id) m
    OUTER APPLY (SELECT SUM(CONVERT(bigint, i.quantity)) AS n FROM dbo.reservation_item i
                 JOIN dbo.reservation r ON r.id=i.reservation_id
                 WHERE i.goods_id=g.id AND r.status=N'有效') r
    WHERE g.stock_total<>COALESCE(m.n,0) OR g.reserved_qty<>COALESCE(r.n,0)
)
    THROW 51330, N'迁移后库存或有效已订量对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.member m
    OUTER APPLY (SELECT SUM(CONVERT(bigint, points)) AS n FROM dbo.point_movement WHERE member_phone=m.phone) p
    WHERE m.points_balance<>COALESCE(p.n,0)
)
    THROW 51331, N'迁移后积分余额对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sale s
    OUTER APPLY (SELECT SUM(unit_price*quantity) AS amount FROM dbo.sale_item WHERE sale_id=s.id) i
    WHERE s.subtotal_amount<>COALESCE(i.amount,0)
)
    THROW 51332, N'迁移后销售金额对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM (SELECT fund_before,
        LAG(fund_after,1,CONVERT(decimal(12,2),0)) OVER (ORDER BY recorded_at,id) AS previous_after
        FROM dbo.fund_flow) x
    WHERE x.fund_before<>x.previous_after
)
    THROW 51333, N'迁移后资金链不连续。', 1;

DECLARE @cash decimal(12,2), @profit decimal(12,2);
SELECT @cash = SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END),
       @profit = SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0
                          WHEN direction=N'收' THEN amount ELSE -amount END)
FROM dbo.fund_flow;
IF @cash <> 1430.30 OR @profit <> -69.70
    THROW 51334, N'迁移后现金余额或经营盈亏改变。', 1;

SELECT N'migration-check' AS check_name,
       DB_NAME() AS database_name,
       20 AS user_tables,
       49 AS foreign_keys,
       77 AS legacy_rows,
       @cash AS cash_balance,
       @profit AS operating_result,
       (SELECT COUNT_BIG(*) FROM dbo.schema_migration) AS migration_records;
PRINT N'migration-check.sql PASS: migrated structure and v0.1 business facts are preserved.';
