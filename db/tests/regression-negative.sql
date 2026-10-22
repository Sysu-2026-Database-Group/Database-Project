:On Error exit
-- SQLCMD 模式；DatabaseName 由调用者传入，目标须以 ShiguangBookstoreWeek6 开头。
-- 第六周已实现约束的反例回归
-- 每个反例都在独立事务中执行并回滚；本脚本不应留下任何业务数据变化。
-- 本脚本只测试 DDL / CHECK / 外码 / 唯一索引已经明确实现的拒绝边界。

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
SET XACT_ABORT ON;

IF (DB_NAME() <> N'$(DatabaseName)' OR DB_NAME() NOT LIKE N'ShiguangBookstoreWeek6%')
    THROW 51600, N'当前数据库不是 ShiguangBookstoreWeek6Work，停止反例回归。', 1;
IF @@TRANCOUNT <> 0
    THROW 51601, N'请在没有外层事务的新查询窗口执行反例回归。', 1;
IF NOT EXISTS (
    SELECT 1 FROM dbo.schema_migration
    WHERE migration_key='W6-NORMALIZATION-1.0'
      AND status=N'已完成'
)
    THROW 51602, N'第六周迁移标记不是已完成，停止反例回归。', 1;

DECLARE @before_goods BIGINT = (SELECT COUNT_BIG(*) FROM dbo.goods);
DECLARE @before_sale BIGINT = (SELECT COUNT_BIG(*) FROM dbo.sale);
DECLARE @before_point BIGINT = (SELECT COUNT_BIG(*) FROM dbo.point_movement);
DECLARE @before_fund BIGINT = (SELECT COUNT_BIG(*) FROM dbo.fund_flow);
DECLARE @before_cash DECIMAL(12,2), @before_profit DECIMAL(12,2);
SELECT @before_cash=SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END),
       @before_profit=SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0
                               WHEN direction=N'收' THEN amount ELSE -amount END)
FROM dbo.fund_flow;

/* expected_errors 允许 SQL Server 对 UNIQUE 约束 / 唯一索引返回 2627 或 2601。 */
DECLARE @cases TABLE (
    case_id INT IDENTITY(1,1) PRIMARY KEY,
    label NVARCHAR(120) NOT NULL,
    sql_text NVARCHAR(MAX) NOT NULL,
    expected_errors VARCHAR(50) NOT NULL
);
INSERT @cases(label,sql_text,expected_errors) VALUES
(N'主键重复：book.isbn',
 N'INSERT dbo.book(isbn,author,publisher,page_count)
   SELECT isbn,author,publisher,page_count FROM dbo.book WHERE isbn=''9787506365437''',
 '2627,2601'),
(N'业务唯一键重复：supplier.name',
 N'INSERT dbo.supplier(name,created_by)
   SELECT name,created_by FROM dbo.supplier WHERE id=1',
 '2627,2601'),
(N'外码不存在：supplier_quote.supplier_id',
 N'INSERT dbo.supplier_quote(supplier_id,goods_id,quote_amount,reported_by)
   VALUES(999999,1,10,''13800000002'')',
 '547'),
(N'非空约束：toy.spec',
 N'INSERT dbo.toy(inner_code,spec) VALUES(''W6-NEG-TOY'',NULL)',
 '515'),
(N'CHECK：商品价格必须为正数',
 N'UPDATE dbo.goods SET price=-1 WHERE id=1',
 '547'),
(N'CHECK：商品类别与细节必须匹配',
 N'UPDATE dbo.goods SET toy_code=''W6-NOT-A-BOOK'' WHERE id=1',
 '547'),
(N'CHECK：已订量不能超过在架量',
 N'UPDATE dbo.goods SET reserved_qty=stock_total+1 WHERE id=1',
 '547'),
(N'CHECK：损坏流水必须有原因',
 N'UPDATE dbo.stock_movement SET note=NULL WHERE id=12',
 '547'),
(N'CHECK：预订有效期必须为三天',
 N'UPDATE dbo.reservation SET expires_at=DATEADD(day,4,created_at) WHERE code=''517436''',
 '547'),
(N'CHECK：采购取消不能保留审批留痕',
 N'UPDATE dbo.purchase_request
   SET status=N''已取消'',cancelled_by=''13800000001'',cancelled_at=SYSDATETIME()
   WHERE no=''PR20260906-01''',
 '547'),
(N'CHECK：积分抵扣不得超过折后金额上限',
 N'UPDATE dbo.sale SET point_deduction_amount=19,paid_amount=73.15
   WHERE no=''S20260914-01''',
 '547'),
(N'CHECK：卡费必须大于零',
 N'UPDATE dbo.card_type SET card_fee=0 WHERE level=N''银卡''',
 '547'),
(N'CHECK：资金前后余额必须相等',
 N'UPDATE dbo.fund_flow SET fund_after=fund_after+1 WHERE id=1',
 '547'),
(N'CHECK：会员修改人和时刻成对',
 N'UPDATE dbo.member SET updated_at=NULL WHERE phone=''13900000001''',
 '547'),
(N'CHECK：员工手机号格式',
 N'INSERT dbo.employee(phone,name,role,created_by)
   VALUES(''123'',N''非法账号'',N''收银员'',''13800000001'')',
 '547'),
(N'CHECK：购入流水必须有采购单来源',
 N'UPDATE dbo.stock_movement SET request_id=NULL WHERE id=1',
 '547'),
(N'迁移唯一索引：同一图书只能有一件商品',
 N'INSERT dbo.goods(category,name,book_isbn,created_by)
   VALUES(N''图书'',N''重复图书'', ''9787300000001'',''13800000002'')',
 '2601,2627'),
(N'迁移唯一索引：同一预订不能重复取货',
 N'INSERT dbo.sale(no,status,cashier_by,card_level,member_phone,reservation_id,
                  subtotal_amount,discount_rate,point_deduction_amount,paid_amount)
   VALUES(''W6-NEG-RES-SALE'',N''已付'',''13800000003'',N''银卡'',''13900000003'',
          (SELECT id FROM dbo.reservation WHERE code=''W6R-2106''),0,0.95,0,0)',
 '2601,2627'),
(N'迁移唯一索引：同一销售不能重复发放积分',
 N'INSERT dbo.point_movement(member_phone,change_type,points,sale_id,changed_by)
   VALUES(''13900000003'',N''消费获得'',1,
          (SELECT id FROM dbo.sale WHERE no=''S20260922-W604''),''13800000003'')',
 '2601,2627'),
(N'迁移CHECK：消费获得必须指向销售单',
 N'INSERT dbo.point_movement(member_phone,change_type,points,changed_by)
   VALUES(''13900000003'',N''消费获得'',1,''13800000003'')',
 '547'),
(N'迁移唯一索引：同一退货不能重复回滚积分',
 N'INSERT dbo.point_movement(member_phone,change_type,points,sale_id,return_id,changed_by)
   VALUES(''13900000003'',N''退货回滚'',-1,
          (SELECT s.id FROM dbo.sale s WHERE s.no=''S20260927-W609''),
          (SELECT r.id FROM dbo.goods_return r WHERE r.no=''RT20260928-W604''),
          ''13800000004'')',
 '2601,2627'),
(N'迁移CHECK：资金余额不能为负数',
 N'INSERT dbo.fund_flow(amount,direction,reason_type,fund_before,fund_after,recorded_by,recorded_at)
   VALUES(1,N''付'',N''提现'',0,-1,''13800000001'',''2026-10-01T12:00:00'')',
 '547');

DECLARE @id INT=1, @label NVARCHAR(120), @sql NVARCHAR(MAX), @expected VARCHAR(50);
DECLARE @actual INT, @message NVARCHAR(2048), @expected_message NVARCHAR(2048);
DECLARE @results TABLE (
    case_id INT NOT NULL,
    label NVARCHAR(120) NOT NULL,
    expected_errors VARCHAR(50) NOT NULL,
    actual_error INT NOT NULL,
    result VARCHAR(10) NOT NULL,
    error_message NVARCHAR(2048) NULL
);

WHILE @id <= (SELECT COUNT(*) FROM @cases)
BEGIN
    SELECT @label=label, @sql=sql_text, @expected=expected_errors
    FROM @cases WHERE case_id=@id;
    SET @actual=0;
    SET @message=NULL;

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC sys.sp_executesql @sql;
        IF XACT_STATE()<>0 ROLLBACK;
    END TRY
    BEGIN CATCH
        SET @actual=ERROR_NUMBER();
        SET @message=ERROR_MESSAGE();
        IF XACT_STATE()<>0 ROLLBACK;
    END CATCH;

    IF @actual=0
    BEGIN
        SET @expected_message=CONCAT(@label,N' 未产生错误；预期错误号为 ',@expected,N'。');
        THROW 51690, @expected_message, 1;
    END;
    IF CHARINDEX(','+CONVERT(VARCHAR(10),@actual)+',', ','+@expected+',')=0
    BEGIN
        SET @expected_message=CONCAT(@label,N' 预期错误 ',@expected,N'，实际错误 ',@actual,N'：',@message);
        THROW 51691, @expected_message, 1;
    END;

    INSERT @results(case_id,label,expected_errors,actual_error,result,error_message)
    VALUES(@id,@label,@expected,@actual,'PASS',@message);
    SET @id+=1;
END;

/* 所有反例都必须回滚；四个关键行数和账面数应与测试前完全相同。 */
IF (SELECT COUNT_BIG(*) FROM dbo.goods)<>@before_goods
   OR (SELECT COUNT_BIG(*) FROM dbo.sale)<>@before_sale
   OR (SELECT COUNT_BIG(*) FROM dbo.point_movement)<>@before_point
   OR (SELECT COUNT_BIG(*) FROM dbo.fund_flow)<>@before_fund
    THROW 51692, N'反例回归后发现业务行数变化，存在未回滚写入。', 1;
DECLARE @after_cash DECIMAL(12,2), @after_profit DECIMAL(12,2);
SELECT @after_cash=SUM(CASE direction WHEN N'收' THEN amount ELSE -amount END),
       @after_profit=SUM(CASE WHEN reason_type IN (N'注资',N'提现') THEN 0
                              WHEN direction=N'收' THEN amount ELSE -amount END)
FROM dbo.fund_flow;
IF @after_cash<>@before_cash OR @after_profit<>@before_profit
    THROW 51693, N'反例回归后现金或经营盈亏发生变化。', 1;

SELECT * FROM @results ORDER BY case_id;
PRINT N'regression-negative.sql PASS: 22 implemented constraint cases rejected and rolled back.';
