-- 第六周扩充后的只读回归核对
-- 本阶段只读取 ShiguangBookstoreWeek6Work，不写入业务表，也不执行反例事务。
-- 结构性非法操作、权限和事务回滚测试在本只读核对通过后分步执行。

USE [ShiguangBookstoreWeek6Work];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'ShiguangBookstoreWeek6Work'
    THROW 51500, N'当前数据库不是 ShiguangBookstoreWeek6Work，停止回归。', 1;
IF @@TRANCOUNT <> 0
    THROW 51501, N'请在没有外层事务的新查询窗口执行回归脚本。', 1;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NULL
    THROW 51502, N'缺少 schema_migration；请先完成第六周迁移。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.schema_migration
    WHERE migration_key='W6-NORMALIZATION-1.0'
      AND source_version='v0.1'
      AND target_version='v0.2-w6'
      AND status=N'已完成'
)
    THROW 51503, N'第六周迁移标记不是已完成，停止回归。', 1;

/* 1. 目标结构和扩充后的逐表数量。 */
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0) <> 20
    THROW 51510, N'用户表数量不是 20。', 1;
IF (SELECT COUNT(*) FROM sys.foreign_keys) <> 49
    THROW 51511, N'外码数量不是 49。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.employee) <> 4
   OR (SELECT COUNT_BIG(*) FROM dbo.card_type) <> 2
   OR (SELECT COUNT_BIG(*) FROM dbo.book) <> 5
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
    THROW 51512, N'扩充后的逐表数量不符合预期。', 1;

/* 2. 旧场景快照仍可追溯。扩充后的资金总额会变化，旧资金按日期截面核对。 */
IF NOT EXISTS (
    SELECT 1 FROM dbo.goods
    WHERE id=1 AND category=N'图书' AND name=N'活着'
      AND book_isbn='9787506365437' AND on_shelf=1 AND price=39.00
      AND stock_total=6 AND reserved_qty=6
)
 OR NOT EXISTS (
    SELECT 1 FROM dbo.goods
    WHERE id=2 AND category=N'图书' AND name=N'百年孤独'
      AND book_isbn='9787544253994' AND on_shelf=1 AND price=49.00
      AND stock_total=0 AND reserved_qty=0
)
 OR NOT EXISTS (
    SELECT 1 FROM dbo.goods
    WHERE id=3 AND category=N'文创' AND name=N'拾光帆布袋'
      AND toy_code='SP-BAG-001' AND on_shelf=1 AND price=19.00
      AND stock_total=10 AND reserved_qty=0
)
 OR NOT EXISTS (
    SELECT 1 FROM dbo.goods
    WHERE id=4 AND category=N'文创' AND name=N'拾光书签'
      AND toy_code='SP-MARK-002' AND on_shelf=1 AND price=6.00
      AND stock_total=19 AND reserved_qty=0
)
    THROW 51520, N'旧商品快照不一致。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.member WHERE phone='13900000001' AND card_level=N'金卡' AND points_balance=-26)
 OR NOT EXISTS (SELECT 1 FROM dbo.member WHERE phone='13900000002' AND card_level=N'金卡' AND points_balance=0)
    THROW 51521, N'旧会员快照不一致。', 1;

DECLARE @legacy_cash DECIMAL(12,2), @legacy_profit DECIMAL(12,2);
SELECT @legacy_cash = COALESCE(SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END),0),
       @legacy_profit = COALESCE(SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0
                                          WHEN direction=N'收' THEN amount ELSE -amount END),0)
FROM dbo.fund_flow
WHERE recorded_at < '2026-09-21T00:00:00';
IF @legacy_cash <> 1430.30 OR @legacy_profit <> -69.70
    THROW 51522, N'旧资金截面不一致。', 1;

/* 3. 新对象和各场景终态。 */
IF NOT EXISTS (SELECT 1 FROM dbo.goods WHERE book_isbn='9787300000001' AND on_shelf=0 AND price IS NULL AND stock_total=0 AND reserved_qty=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.goods WHERE toy_code='SP-NOTE-003' AND on_shelf=0 AND price=29.00 AND stock_total=0 AND reserved_qty=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.goods WHERE book_isbn='9787111000002' AND on_shelf=1 AND price=75.00 AND stock_total=10 AND reserved_qty=3)
 OR NOT EXISTS (SELECT 1 FROM dbo.goods WHERE toy_code='SP-CUP-004' AND on_shelf=1 AND price=36.00 AND stock_total=5 AND reserved_qty=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.goods WHERE book_isbn='9787040000003' AND on_shelf=1 AND price=58.00 AND stock_total=5 AND reserved_qty=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.goods WHERE toy_code='SP-KEY-005' AND on_shelf=1 AND price=12.00 AND stock_total=18 AND reserved_qty=0)
    THROW 51530, N'商品展示、定价或库存终态不符合 W6-S01/W6-S02。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.member WHERE phone='13900000003' AND card_level=N'银卡' AND points_balance=122)
 OR NOT EXISTS (SELECT 1 FROM dbo.member WHERE phone='13900000004' AND card_level=N'金卡' AND points_balance=197)
 OR NOT EXISTS (SELECT 1 FROM dbo.member WHERE phone='13900000005' AND card_level=N'金卡' AND points_balance=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.member WHERE phone='13900000006' AND card_level=N'银卡' AND points_balance=0)
    THROW 51531, N'新增会员或积分终态不符合 W6-S04/W6-S05。', 1;
IF EXISTS (
    SELECT 1 FROM (VALUES
        ('PR20260921-W604',N'草稿'),('PR20260921-W605',N'已提交'),
        ('PR20260921-W606',N'已审批'),('PR20260921-W607',N'已取消'),
        ('PR20260921-W608',N'已收货'),('PR20260921-W609',N'已收货'),
        ('PR20260921-W610',N'已收货')
    ) v(request_no,expected_status)
    LEFT JOIN dbo.purchase_request p ON p.no=v.request_no
    WHERE p.id IS NULL OR p.status<>v.expected_status
)
    THROW 51532, N'采购阶段终态不符合 W6-S03。', 1;
IF EXISTS (
    SELECT 1 FROM (VALUES
        ('W6R-2103',N'已取消'),('W6R-2104',N'已过期'),('W6R-2105',N'有效'),
        ('W6R-2106',N'已取'),('W6R-2107',N'已取'),('W6R-2108',N'已取消')
    ) v(reservation_code,expected_status)
    LEFT JOIN dbo.reservation r ON r.code=v.reservation_code
    WHERE r.id IS NULL OR r.status<>v.expected_status
)
    THROW 51533, N'预订状态终态不符合 W6-S02/W6-S06/W6-S07/W6-S08。', 1;
IF EXISTS (
    SELECT 1 FROM (VALUES
        ('S20260922-W604',N'已付'),('S20260923-W605',N'已付'),
        ('S20260924-W606',N'已付'),('S20260925-W607',N'已付'),
        ('S20260926-W608',N'部分退款'),('S20260927-W609',N'已全退')
    ) v(sale_no,expected_status)
    LEFT JOIN dbo.sale s ON s.no=v.sale_no
    WHERE s.id IS NULL OR s.status<>v.expected_status
)
    THROW 51534, N'销售状态终态不符合 W6-S04/W6-S07/W6-S09/W6-S10。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.goods_return WHERE no='RT20260928-W603' AND refund_amount=70.00)
 OR NOT EXISTS (SELECT 1 FROM dbo.goods_return WHERE no='RT20260928-W604' AND refund_amount=71.22)
 OR NOT EXISTS (SELECT 1 FROM dbo.goods_return WHERE no='RT20260929-W605' AND refund_amount=139.58)
    THROW 51535, N'退货金额终态不符合 W6-S09/W6-S10。', 1;

/* 4. 库存、预订、积分、销售、退货和采购的跨表对账。 */
IF EXISTS (
    SELECT 1 FROM dbo.goods g
    OUTER APPLY (SELECT SUM(CONVERT(bigint,quantity)) AS n FROM dbo.stock_movement m WHERE m.goods_id=g.id) sm
    OUTER APPLY (SELECT SUM(CONVERT(bigint,i.quantity)) AS n
                 FROM dbo.reservation_item i JOIN dbo.reservation r ON r.id=i.reservation_id
                 WHERE i.goods_id=g.id AND r.status=N'有效') rq
    WHERE g.stock_total<>COALESCE(sm.n,0) OR g.reserved_qty<>COALESCE(rq.n,0)
)
    THROW 51540, N'库存或有效预订数量对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.member m
    OUTER APPLY (SELECT SUM(CONVERT(bigint,points)) AS n FROM dbo.point_movement p WHERE p.member_phone=m.phone) pm
    WHERE m.points_balance<>COALESCE(pm.n,0)
)
    THROW 51541, N'积分余额与积分流水对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sale s
    OUTER APPLY (SELECT SUM(unit_price*quantity) AS amount FROM dbo.sale_item i WHERE i.sale_id=s.id) si
    WHERE s.subtotal_amount<>COALESCE(si.amount,0)
)
    THROW 51542, N'销售单头金额与明细对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.goods_return r
    OUTER APPLY (SELECT SUM(refund_amount) AS amount FROM dbo.goods_return_item i WHERE i.return_id=r.id) ri
    WHERE r.refund_amount<>COALESCE(ri.amount,0)
)
 OR EXISTS (
    SELECT 1 FROM dbo.goods_return_item i
    JOIN dbo.goods_return r ON r.id=i.return_id
    JOIN dbo.sale_item s ON s.id=i.sale_item_id
    WHERE r.sale_id<>s.sale_id
)
 OR EXISTS (
    SELECT 1 FROM dbo.sale_item s
    OUTER APPLY (SELECT SUM(quantity) AS n FROM dbo.goods_return_item i WHERE i.sale_item_id=s.id) ri
    WHERE COALESCE(ri.n,0)>s.quantity
)
    THROW 51543, N'退货金额、原单归属或累计数量对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sale s
    OUTER APPLY (SELECT SUM(refund_amount) AS amount FROM dbo.goods_return r WHERE r.sale_id=s.id) rr
    WHERE COALESCE(rr.amount,0)>s.paid_amount
       OR s.status<>CASE WHEN COALESCE(rr.amount,0)=0 THEN N'已付'
                         WHEN rr.amount=s.paid_amount THEN N'已全退'
                         ELSE N'部分退款' END
)
    THROW 51544, N'累计退款或销售状态对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sale_item s
    OUTER APPLY (SELECT SUM(quantity) AS n FROM dbo.stock_movement m
                 WHERE m.sale_id=s.sale_id AND m.goods_id=s.goods_id) sm
    WHERE COALESCE(sm.n,0)<>-s.quantity
)
 OR EXISTS (
    SELECT 1 FROM dbo.goods_return_item i
    JOIN dbo.sale_item s ON s.id=i.sale_item_id
    OUTER APPLY (SELECT SUM(quantity) AS n FROM dbo.stock_movement m
                 WHERE m.return_item_id=i.id AND m.goods_id=s.goods_id) sm
    WHERE COALESCE(sm.n,0)<>i.quantity
)
    THROW 51545, N'销售出库或退货入库数量对账失败。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.purchase_request p
    OUTER APPLY (SELECT SUM(request_qty*unit_cost) AS amount
                 FROM dbo.purchase_request_item i WHERE i.request_id=p.id) pi
    OUTER APPLY (SELECT COUNT(*) AS n, SUM(amount) AS amount,
                        MIN(recorded_at) AS paid_at
                 FROM dbo.fund_flow f WHERE f.request_id=p.id) ff
    OUTER APPLY (SELECT MIN(changed_at) AS received_at
                 FROM dbo.stock_movement m WHERE m.request_id=p.id) sm
    WHERE p.status=N'已收货'
      AND (ff.n<>1 OR ff.amount<>pi.amount OR ff.paid_at<p.approved_at OR ff.paid_at>sm.received_at)
)
 OR EXISTS (
    SELECT 1 FROM dbo.purchase_request_item i
    JOIN dbo.purchase_request p ON p.id=i.request_id
    OUTER APPLY (SELECT SUM(quantity) AS n FROM dbo.stock_movement m
                 WHERE m.request_id=i.request_id AND m.goods_id=i.goods_id) sm
    WHERE p.status=N'已收货' AND COALESCE(sm.n,0)<>i.request_qty
)
    THROW 51546, N'采购付款、付款时序或入库数量对账失败。', 1;

/* 5. 积分来源、销售收款、退货退款和资金链。 */
IF EXISTS (
    SELECT 1 FROM dbo.sale s
    OUTER APPLY (SELECT SUM(points) AS earned FROM dbo.point_movement p
                 WHERE p.sale_id=s.id AND p.change_type=N'消费获得') e
    OUTER APPLY (SELECT SUM(points) AS used FROM dbo.point_movement p
                 WHERE p.sale_id=s.id AND p.change_type=N'抵扣使用') u
    WHERE s.member_phone IS NULL
      AND (COALESCE(e.earned,0)<>0 OR COALESCE(u.used,0)<>0)
)
    THROW 51550, N'散客销售产生了积分流水。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sale s
    OUTER APPLY (SELECT SUM(points) AS earned FROM dbo.point_movement p
                 WHERE p.sale_id=s.id AND p.change_type=N'消费获得') e
    OUTER APPLY (SELECT SUM(points) AS used FROM dbo.point_movement p
                 WHERE p.sale_id=s.id AND p.change_type=N'抵扣使用') u
    WHERE s.member_phone IS NOT NULL
      AND (COALESCE(e.earned,0)<>FLOOR(s.paid_amount)
           OR COALESCE(u.used,0)<>-CONVERT(int,ROUND(s.point_deduction_amount*100,0)))
)
    THROW 51551, N'会员销售的获得或抵扣积分算式不一致。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.point_movement p
    JOIN dbo.goods_return r ON r.id=p.return_id
    JOIN dbo.sale s ON s.id=r.sale_id
    WHERE p.sale_id IS NULL OR p.sale_id<>r.sale_id
       OR s.member_phone IS NULL OR p.member_phone<>s.member_phone
)
    THROW 51552, N'退货回滚积分未正确指向原销售单或会员。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sale s
    OUTER APPLY (SELECT COUNT(*) AS n, SUM(amount) AS amount
                 FROM dbo.fund_flow f WHERE f.sale_id=s.id AND f.reason_type=N'销售收款') ff
    WHERE ff.n<>1 OR ff.amount<>s.paid_amount
)
    THROW 51553, N'销售收款流水笔数或金额不一致。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.goods_return r
    OUTER APPLY (SELECT COUNT(*) AS n, SUM(amount) AS amount
                 FROM dbo.fund_flow f WHERE f.return_id=r.id) ff
    WHERE (r.refund_amount>0 AND (ff.n<>1 OR ff.amount<>r.refund_amount))
       OR (r.refund_amount=0 AND ff.n<>0)
)
    THROW 51554, N'退货退款流水笔数或金额不一致。', 1;
IF EXISTS (
    SELECT 1 FROM (SELECT fund_before,
        LAG(fund_after,1,CONVERT(decimal(12,2),0)) OVER (ORDER BY recorded_at,id) AS previous_after
        FROM dbo.fund_flow) x
    WHERE x.fund_before<>x.previous_after
)
    THROW 51555, N'资金流水前后余额不连续。', 1;

DECLARE @cash DECIMAL(12,2), @profit DECIMAL(12,2);
SELECT @cash=COALESCE(SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END),0),
       @profit=COALESCE(SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0
                                 WHEN direction=N'收' THEN amount ELSE -amount END),0)
FROM dbo.fund_flow;
IF @cash<>555.30 OR @profit<>-944.70
    THROW 51556, N'扩充后现金余额或经营盈亏不符合预期。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.stock_movement m
    JOIN dbo.employee e ON e.phone=m.changed_by
    WHERE e.role<>CASE WHEN m.change_type=N'卖出' THEN N'收银员' ELSE N'库管' END
)
 OR EXISTS (
    SELECT 1 FROM dbo.fund_flow f
    JOIN dbo.employee e ON e.phone=f.recorded_by
    WHERE e.role<>CASE WHEN f.reason_type IN (N'采购付款',N'注资',N'提现') THEN N'店长' ELSE N'收银员' END
)
    THROW 51557, N'新增样例的操作人角色不符合规则。', 1;

/* 6. 输出可保存到 db/results 的只读证据。 */
SELECT N'week-6-regression-readonly' AS check_name,
       DB_NAME() AS database_name,
       20 AS user_tables,
       49 AS foreign_keys,
       (SELECT COUNT_BIG(*) FROM dbo.goods) AS goods_count,
       (SELECT COUNT_BIG(*) FROM dbo.member) AS member_count,
       (SELECT COUNT_BIG(*) FROM dbo.purchase_request) AS purchase_request_count,
       (SELECT COUNT_BIG(*) FROM dbo.reservation) AS reservation_count,
       (SELECT COUNT_BIG(*) FROM dbo.sale) AS sale_count,
       (SELECT COUNT_BIG(*) FROM dbo.goods_return) AS return_count,
       (SELECT COUNT_BIG(*) FROM dbo.stock_movement) AS stock_movement_count,
       (SELECT COUNT_BIG(*) FROM dbo.point_movement) AS point_movement_count,
       (SELECT COUNT_BIG(*) FROM dbo.fund_flow) AS fund_flow_count,
       @legacy_cash AS legacy_cash_balance,
       @legacy_profit AS legacy_operating_result,
       @cash AS cash_balance,
       @profit AS operating_result;

SELECT N'employee' AS object_name, COUNT_BIG(*) AS row_count FROM dbo.employee
UNION ALL SELECT N'card_type', COUNT_BIG(*) FROM dbo.card_type
UNION ALL SELECT N'book', COUNT_BIG(*) FROM dbo.book
UNION ALL SELECT N'toy', COUNT_BIG(*) FROM dbo.toy
UNION ALL SELECT N'goods', COUNT_BIG(*) FROM dbo.goods
UNION ALL SELECT N'supplier', COUNT_BIG(*) FROM dbo.supplier
UNION ALL SELECT N'supplier_quote', COUNT_BIG(*) FROM dbo.supplier_quote
UNION ALL SELECT N'member', COUNT_BIG(*) FROM dbo.member
UNION ALL SELECT N'purchase_request', COUNT_BIG(*) FROM dbo.purchase_request
UNION ALL SELECT N'purchase_request_item', COUNT_BIG(*) FROM dbo.purchase_request_item
UNION ALL SELECT N'reservation', COUNT_BIG(*) FROM dbo.reservation
UNION ALL SELECT N'reservation_item', COUNT_BIG(*) FROM dbo.reservation_item
UNION ALL SELECT N'sale', COUNT_BIG(*) FROM dbo.sale
UNION ALL SELECT N'sale_item', COUNT_BIG(*) FROM dbo.sale_item
UNION ALL SELECT N'goods_return', COUNT_BIG(*) FROM dbo.goods_return
UNION ALL SELECT N'goods_return_item', COUNT_BIG(*) FROM dbo.goods_return_item
UNION ALL SELECT N'stock_movement', COUNT_BIG(*) FROM dbo.stock_movement
UNION ALL SELECT N'point_movement', COUNT_BIG(*) FROM dbo.point_movement
UNION ALL SELECT N'fund_flow', COUNT_BIG(*) FROM dbo.fund_flow
UNION ALL SELECT N'schema_migration', COUNT_BIG(*) FROM dbo.schema_migration
ORDER BY object_name;

PRINT N'regression.sql READONLY PASS: W6 sample snapshot, legacy preservation and cross-table reconciliation passed.';
