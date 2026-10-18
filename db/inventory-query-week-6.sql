-- 第六周库存查询证据：普通 T-SQL，无需 SQLCMD 模式。
-- 只读业务表；中间结果仅保存在会话表变量中。
-- 核对已装载的固定样例截面，不用于任意历史时刻的状态重建。
USE [ShiguangBookstoreWeek6Work];
GO
SET NOCOUNT ON;

IF DB_NAME()<>N'ShiguangBookstoreWeek6Work'
    THROW 51920, N'目标数据库错误，停止库存查询。', 1;
IF @@TRANCOUNT<>0
    THROW 51921, N'请使用没有未结束事务的新查询窗口。', 1;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NULL
    THROW 51922, N'缺少第六周迁移表，请先核对工作库。', 1;

DECLARE @as_of DATETIME2='2026-09-29T18:00:00';
DECLARE @legacy_as_of DATETIME2='2026-09-20T12:00:00';
IF EXISTS (SELECT 1 FROM dbo.stock_movement WHERE changed_at>@as_of)
 OR EXISTS (SELECT 1 FROM dbo.reservation WHERE created_at>@as_of)
 OR EXISTS (SELECT 1 FROM dbo.goods WHERE created_at>@as_of)
    THROW 51923, N'存在截面之后的新数据，请勿把当前快照作为固定截面结果。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.stock_movement)<>31
    THROW 51924, N'本脚本要求扩充后 31 条库存流水的样例基线。', 1;

DECLARE @inventory TABLE (
    goods_ref VARCHAR(20), goods_name NVARCHAR(100), stock_total INT,
    movement_total BIGINT, reserved_qty INT, status_reserved_qty BIGINT,
    available_qty INT, time_valid_reserved_qty BIGINT, expired_pending_qty BIGINT
);

-- 流水、预订各自汇总，避免两侧多行连接造成数量重复。
-- 状态口径包含所有“有效”预订；时间口径另看是否到期，不实际释放占用。
INSERT @inventory
SELECT COALESCE(g.book_isbn,g.toy_code),g.name,g.stock_total,
       COALESCE(m.total_qty,0),g.reserved_qty,COALESCE(r.status_qty,0),
       g.stock_total-g.reserved_qty,COALESCE(r.time_qty,0),COALESCE(r.expired_qty,0)
FROM dbo.goods g
OUTER APPLY (
    SELECT SUM(CONVERT(bigint,quantity)) AS total_qty
    FROM dbo.stock_movement WHERE goods_id=g.id AND changed_at<=@as_of
) m
OUTER APPLY (
    SELECT SUM(CONVERT(bigint,ri.quantity)) AS status_qty,
           SUM(CASE WHEN rh.expires_at>@as_of THEN CONVERT(bigint,ri.quantity) ELSE 0 END) AS time_qty,
           SUM(CASE WHEN rh.expires_at<=@as_of THEN CONVERT(bigint,ri.quantity) ELSE 0 END) AS expired_qty
    FROM dbo.reservation_item ri
    JOIN dbo.reservation rh ON rh.id=ri.reservation_id
    WHERE ri.goods_id=g.id AND rh.status=N'有效' AND rh.created_at<=@as_of
) r;

DECLARE @expected TABLE (
    goods_ref VARCHAR(20),stock_total INT,reserved_qty INT,available_qty INT,
    time_valid_reserved_qty BIGINT,expired_pending_qty BIGINT
);
INSERT @expected VALUES
('9787506365437',6,6,0,0,6),('9787544253994',0,0,0,0,0),
('SP-BAG-001',10,0,10,0,0),('SP-MARK-002',19,0,19,0,0),
('9787300000001',0,0,0,0,0),('SP-NOTE-003',0,0,0,0,0),
('9787111000002',10,3,7,3,0),('SP-CUP-004',5,0,5,0,0),
('9787040000003',5,0,5,0,0),('SP-KEY-005',18,0,18,0,0);

IF EXISTS (
    SELECT goods_ref,stock_total,reserved_qty,available_qty,time_valid_reserved_qty,expired_pending_qty
    FROM @inventory EXCEPT SELECT * FROM @expected
) OR EXISTS (
    SELECT * FROM @expected EXCEPT
    SELECT goods_ref,stock_total,reserved_qty,available_qty,time_valid_reserved_qty,expired_pending_qty
    FROM @inventory
)
    THROW 51925, N'逐商品库存或预订占用与样例截面预期不一致。', 1;
IF EXISTS (
    SELECT 1 FROM @inventory
    WHERE stock_total<>movement_total OR reserved_qty<>status_reserved_qty
       OR status_reserved_qty<>time_valid_reserved_qty+expired_pending_qty
)
    THROW 51926, N'库存与流水、已订与有效状态预订汇总不一致。', 1;

-- 旧商品的旧时点库存流水单独核对，不重建预订历史状态。
IF EXISTS (
    SELECT 1 FROM @expected e
    JOIN dbo.goods g ON COALESCE(g.book_isbn,g.toy_code)=e.goods_ref
    OUTER APPLY (
        SELECT SUM(CONVERT(bigint,quantity)) AS qty FROM dbo.stock_movement
        WHERE goods_id=g.id AND changed_at<=@legacy_as_of
    ) m
    WHERE e.goods_ref IN ('9787506365437','9787544253994','SP-BAG-001','SP-MARK-002')
      AND COALESCE(m.qty,0)<>e.stock_total
)
    THROW 51927, N'旧商品在旧截面的库存流水与 v0.1 预期不一致。', 1;

DECLARE @expired_effective BIGINT;
SELECT @expired_effective=COUNT_BIG(*) FROM dbo.reservation
WHERE status=N'有效' AND created_at<=@as_of AND expires_at<=@as_of;
IF @expired_effective<>1
    THROW 51928, N'固定截面预期恰有一张已到期但仍有效的预订。', 1;

-- 结果 1：10 件商品的库存、来源和预订占用。
SELECT *, N'PASS' AS reconciliation_result FROM @inventory ORDER BY goods_ref;

-- 结果 2：当前仍为有效的两张预订，各一条明细。
SELECT rh.code,COALESCE(g.book_isbn,g.toy_code) AS goods_ref,
       ri.quantity,rh.status,rh.expires_at,
       CASE WHEN rh.expires_at<=@as_of THEN N'已到期但未释放' ELSE N'截面时尚未到期' END AS expiry_observation
FROM dbo.reservation rh
JOIN dbo.reservation_item ri ON ri.reservation_id=rh.id
JOIN dbo.goods g ON g.id=ri.goods_id
WHERE rh.status=N'有效' AND rh.created_at<=@as_of
ORDER BY rh.expires_at,rh.code;

-- 结果 3：对账通过与自动过期缺口分别展示。
SELECT @as_of AS fixed_as_of,(SELECT COUNT(*) FROM @inventory) AS goods_count,
       (SELECT COUNT_BIG(*) FROM dbo.stock_movement) AS movement_count,
       (SELECT COUNT(*) FROM @inventory
        WHERE stock_total<>movement_total OR reserved_qty<>status_reserved_qty) AS mismatch_count,
       (SELECT SUM(stock_total) FROM @inventory) AS total_stock,
       (SELECT SUM(reserved_qty) FROM @inventory) AS total_reserved,
       (SELECT SUM(available_qty) FROM @inventory) AS total_available,
       @expired_effective AS effective_reservations_past_expiry,
       N'AUTO_EXPIRY_NOT_APPLIED' AS observed_behavior,N'PASS' AS reconciliation_result;

PRINT N'inventory-query-week-6.sql PASS: inventory and reservation totals match baseline; expiry gap reported separately.';
-- 未更新状态或释放库存；对账通过不表示自动过期功能已实现。
