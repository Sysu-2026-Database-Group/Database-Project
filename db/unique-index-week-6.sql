-- 第六周唯一索引补测：文创细节重复引用（I-07）、重复积分抵扣（I-18）。
-- 在 SSMS 新查询窗口完整执行；普通 T-SQL，无需 SQLCMD 模式。
-- 使用已有新增样例做临时 UPDATE，各项独立事务，成功或异常均回滚。
-- 执行期间不要在其他窗口修改本库。
USE [ShiguangBookstoreWeek6Work];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME()<>N'ShiguangBookstoreWeek6Work'
    THROW 51840, N'目标数据库错误，停止唯一索引补测。', 1;
IF @@TRANCOUNT<>0
    THROW 51841, N'请在没有外层事务的新查询窗口执行。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.goods WHERE toy_code='SP-NOTE-003')<>1
 OR (SELECT COUNT_BIG(*) FROM dbo.goods WHERE toy_code='SP-KEY-005')<>1
    THROW 51842, N'缺少两件新增文创样例，或引用计数异常。', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.point_movement p JOIN dbo.sale s ON s.id=p.sale_id
    WHERE s.no='S20260927-W609' AND p.change_type=N'消费获得'
      AND p.points=210 AND p.return_id IS NULL)<>1
 OR (SELECT COUNT_BIG(*) FROM dbo.point_movement p JOIN dbo.sale s ON s.id=p.sale_id
     WHERE s.no='S20260927-W609' AND p.change_type=N'抵扣使用'
       AND p.points=-10 AND p.return_id IS NULL)<>1
    THROW 51843, N'新销售单 S09 的获得 / 抵扣积分夹具与扩充样例不符。', 1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.goods')
               AND name=N'UX_goods_toy_code' AND is_unique=1 AND is_disabled=0)
 OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.point_movement')
                AND name=N'UX_point_movement_use' AND is_unique=1 AND is_disabled=0)
    THROW 51844, N'目标唯一索引缺失或未启用，请先核对迁移。', 1;

DROP TABLE IF EXISTS #w6_unique_goods;
DROP TABLE IF EXISTS #w6_unique_point;
SELECT * INTO #w6_unique_goods FROM dbo.goods;
SELECT * INTO #w6_unique_point FROM dbo.point_movement;

DECLARE @cases TABLE (id INT PRIMARY KEY, label NVARCHAR(80),
                      sql_text NVARCHAR(MAX), index_name NVARCHAR(128));
INSERT @cases VALUES
(1,N'同一文创细节不能被两件商品引用',
 N'UPDATE dbo.goods SET toy_code=''SP-NOTE-003'' WHERE toy_code=''SP-KEY-005'';',
 N'UX_goods_toy_code'),
(2,N'同一销售单不能重复抵扣积分',
 N'UPDATE p SET change_type=N''抵扣使用'', points=-1
   FROM dbo.point_movement p JOIN dbo.sale s ON s.id=p.sale_id
   WHERE s.no=''S20260927-W609'' AND p.change_type=N''消费获得'' AND p.return_id IS NULL;',
 N'UX_point_movement_use');

DECLARE @results TABLE (case_id INT, test_case NVARCHAR(80),
    expected_errors VARCHAR(20), actual_error INT,
    checked_index NVARCHAR(128), result VARCHAR(10));
DECLARE @id INT=1, @label NVARCHAR(80), @sql NVARCHAR(MAX), @index NVARCHAR(128),
        @actual INT, @message NVARCHAR(2048), @failure NVARCHAR(2048);
WHILE @id<=2
BEGIN
    SELECT @label=label, @sql=sql_text, @index=index_name FROM @cases WHERE id=@id;
    SET @actual=0;
    SET @message=NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC sys.sp_executesql @sql;
        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        SET @actual=ERROR_NUMBER();
        SET @message=ERROR_MESSAGE();
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    END CATCH;

    -- 错误号与目标索引名均须匹配，避免因其他 CHECK / 外码错误误判通过。
    IF @actual NOT IN (2601,2627)
       OR CHARINDEX(@index,COALESCE(@message,N''))=0
    BEGIN
        SET @failure=CONCAT(@label,N'：预期 2601/2627 且包含索引 ',@index,
                            N'，实际错误 ',@actual,N'；',@message);
        THROW 51845, @failure, 1;
    END;
    IF @@TRANCOUNT<>0
        THROW 51846, N'测试后仍有未结束事务。', 1;
    IF EXISTS (SELECT * FROM dbo.goods EXCEPT SELECT * FROM #w6_unique_goods)
     OR EXISTS (SELECT * FROM #w6_unique_goods EXCEPT SELECT * FROM dbo.goods)
     OR EXISTS (SELECT * FROM dbo.point_movement EXCEPT SELECT * FROM #w6_unique_point)
     OR EXISTS (SELECT * FROM #w6_unique_point EXCEPT SELECT * FROM dbo.point_movement)
        THROW 51847, N'回滚后商品或积分流水与初始快照不一致。', 1;

    INSERT @results VALUES (@id,@label,'2601,2627',@actual,@index,'PASS');
    SET @id+=1;
END;

SELECT * FROM @results ORDER BY case_id;
SELECT N'UNIQUE-RESTORED' AS check_name, @@TRANCOUNT AS open_transactions,
       (SELECT COUNT_BIG(*) FROM dbo.goods) AS goods_count,
       (SELECT COUNT_BIG(*) FROM dbo.point_movement) AS point_movement_count;
DROP TABLE #w6_unique_goods, #w6_unique_point;
PRINT N'unique-index-week-6.sql PASS: toy reference and point deduction duplicates rejected; changes rolled back.';
