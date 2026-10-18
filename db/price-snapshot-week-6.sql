-- W6-S08：修改当前售价 / 卡参数后，历史成交快照不变。
-- 请在 SSMS 新查询窗口完整执行；普通 T-SQL，无需 SQLCMD 模式。
-- 仅对工作副本临时 UPDATE，成功或异常均回滚，不提交修改。
-- 执行期间请勿在其他窗口修改本库；本测试不验证新结算入口或并发。
USE [ShiguangBookstoreWeek6Work];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'ShiguangBookstoreWeek6Work'
    THROW 51800, N'目标库错误，停止快照测试。', 1;
IF @@TRANCOUNT <> 0
    THROW 51801, N'请在没有外层事务的新查询窗口执行。', 1;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NULL
    THROW 51802, N'未找到第六周迁移表，请先检查工作副本。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.schema_migration
               WHERE migration_key='W6-NORMALIZATION-1.0'
                 AND target_version='v0.2-w6' AND status=N'已完成')
    THROW 51803, N'第六周迁移尚未完成。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.employee WHERE phone='13800000001' AND role=N'店长')
    THROW 51804, N'缺少测试所用店长记录。', 1;

DECLARE @goods_id BIGINT = (SELECT id FROM dbo.goods WHERE book_isbn='9787111000002');
IF @goods_id IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.goods WHERE id=@goods_id AND price=75.00)
    THROW 51805, N'新增商品 G07 缺失，或当前售价不是扩充基线 75.00；请先核对，不要手工改价凑结果。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.sale s
    JOIN dbo.sale_item si ON si.sale_id=s.id
    JOIN dbo.reservation r ON r.id=s.reservation_id
    WHERE s.no='S20260925-W607' AND r.code='W6R-2107'
      AND si.goods_id=@goods_id AND si.quantity=1 AND si.unit_price=72.00
      AND s.card_level=N'银卡' AND s.discount_rate=0.95 AND s.paid_amount=68.40
)
    THROW 51806, N'S07 / R07 成交快照不符，停止测试。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.card_type WHERE [level]=N'金卡' AND card_fee=50.00 AND discount_rate=0.90)
 OR NOT EXISTS (SELECT 1 FROM dbo.card_type WHERE [level]=N'银卡' AND card_fee=20.00 AND discount_rate=0.95)
    THROW 51807, N'当前卡参数不是扩充基线，停止测试。', 1;

-- 临时快照在事务前建立，回滚后仍可用于逐列、双向比较。
DROP TABLE IF EXISTS #w6_s08_goods;
DROP TABLE IF EXISTS #w6_s08_card;
DROP TABLE IF EXISTS #w6_s08_sale;
DROP TABLE IF EXISTS #w6_s08_item;
SELECT * INTO #w6_s08_goods FROM dbo.goods;
SELECT * INTO #w6_s08_card FROM dbo.card_type;
SELECT * INTO #w6_s08_sale FROM dbo.sale;
SELECT * INTO #w6_s08_item FROM dbo.sale_item;

DECLARE @during_price DECIMAL(10,2), @during_fee DECIMAL(10,2), @during_rate DECIMAL(3,2);
BEGIN TRY
    BEGIN TRANSACTION;

    -- 已有取货成交为 72.00，当前价为 75.00；本次再实际调为 80.00。
    UPDATE dbo.goods
    SET price=80.00, updated_by='13800000001', updated_at='2026-10-01T09:00:00'
    WHERE id=@goods_id;
    SELECT @during_price=price FROM dbo.goods WHERE id=@goods_id;
    IF @during_price IS NULL OR @during_price<>80.00
        THROW 51808, N'测试售价未实际改为 80.00。', 1;
    IF EXISTS (SELECT * FROM dbo.sale EXCEPT SELECT * FROM #w6_s08_sale)
     OR EXISTS (SELECT * FROM #w6_s08_sale EXCEPT SELECT * FROM dbo.sale)
     OR EXISTS (SELECT * FROM dbo.sale_item EXCEPT SELECT * FROM #w6_s08_item)
     OR EXISTS (SELECT * FROM #w6_s08_item EXCEPT SELECT * FROM dbo.sale_item)
        THROW 51809, N'当前售价变化导致历史销售单或明细变化。', 1;

    -- 金卡费 50 -> 55，折扣率 0.90 -> 0.88，仍满足两档之间的约束。
    UPDATE dbo.card_type
    SET card_fee=55.00, discount_rate=0.88,
        set_by='13800000001', set_at='2026-10-01T09:01:00'
    WHERE [level]=N'金卡';
    SELECT @during_fee=card_fee, @during_rate=discount_rate
    FROM dbo.card_type WHERE [level]=N'金卡';
    IF @during_fee IS NULL OR @during_rate IS NULL OR @during_fee<>55.00 OR @during_rate<>0.88
        THROW 51810, N'测试卡参数未实际变化。', 1;
    IF EXISTS (SELECT * FROM dbo.sale EXCEPT SELECT * FROM #w6_s08_sale)
     OR EXISTS (SELECT * FROM #w6_s08_sale EXCEPT SELECT * FROM dbo.sale)
     OR EXISTS (SELECT * FROM dbo.sale_item EXCEPT SELECT * FROM #w6_s08_item)
     OR EXISTS (SELECT * FROM #w6_s08_item EXCEPT SELECT * FROM dbo.sale_item)
        THROW 51811, N'当前卡参数变化导致历史成交档位、折扣、金额或明细变化。', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

IF @@TRANCOUNT<>0
    THROW 51812, N'测试后事务未结束。', 1;
IF EXISTS (SELECT * FROM dbo.goods EXCEPT SELECT * FROM #w6_s08_goods)
 OR EXISTS (SELECT * FROM #w6_s08_goods EXCEPT SELECT * FROM dbo.goods)
 OR EXISTS (SELECT * FROM dbo.card_type EXCEPT SELECT * FROM #w6_s08_card)
 OR EXISTS (SELECT * FROM #w6_s08_card EXCEPT SELECT * FROM dbo.card_type)
 OR EXISTS (SELECT * FROM dbo.sale EXCEPT SELECT * FROM #w6_s08_sale)
 OR EXISTS (SELECT * FROM #w6_s08_sale EXCEPT SELECT * FROM dbo.sale)
 OR EXISTS (SELECT * FROM dbo.sale_item EXCEPT SELECT * FROM #w6_s08_item)
 OR EXISTS (SELECT * FROM #w6_s08_item EXCEPT SELECT * FROM dbo.sale_item)
    THROW 51813, N'回滚后商品、卡档位或销售数据与测试前不一致。', 1;

SELECT N'W6-S08' AS scenario,
       @during_price AS price_during_test,
       (SELECT price FROM dbo.goods WHERE id=@goods_id) AS price_after_rollback,
       @during_fee AS gold_fee_during_test,
       (SELECT card_fee FROM dbo.card_type WHERE [level]=N'金卡') AS gold_fee_after_rollback,
       @during_rate AS gold_rate_during_test,
       (SELECT discount_rate FROM dbo.card_type WHERE [level]=N'金卡') AS gold_rate_after_rollback,
       @@TRANCOUNT AS open_transactions;
SELECT check_name, observed_result
FROM (VALUES
    (N'S08-PRICE', N'PASS: current price changed; all historical sale rows unchanged'),
    (N'S08-CARD', N'PASS: card parameters changed; all historical sale rows unchanged'),
    (N'S08-ROLLBACK', N'PASS: goods, card_type, sale and sale_item fully restored')
) v(check_name, observed_result);

DROP TABLE #w6_s08_goods, #w6_s08_card, #w6_s08_sale, #w6_s08_item;
PRINT N'price-snapshot-week-6.sql PASS: price/card changes preserve historical sales; all test changes rolled back.';
