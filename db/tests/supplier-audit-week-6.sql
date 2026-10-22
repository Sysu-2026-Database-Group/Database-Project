:On Error exit
-- SQLCMD 模式；DatabaseName 由调用者传入，目标须以 ShiguangBookstoreWeek6 开头。
-- I-09：供应商合法改名、修改留痕成对及员工引用的小测试。
-- 在 SSMS 新查询窗口完整执行；SQLCMD 模式，DatabaseName 由调用者指定。
-- 每项均单独开启事务并回滚，不提交改名或修改留痕。
-- 执行期间不要在其他窗口修改本库；本脚本不实现受控改名入口。
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

IF (DB_NAME()<>N'$(DatabaseName)' OR DB_NAME() NOT LIKE N'ShiguangBookstoreWeek6%')
    THROW 51820, N'当前数据库错误，停止供应商留痕测试。', 1;
IF @@TRANCOUNT<>0
    THROW 51821, N'请在没有外层事务的新查询窗口执行。', 1;
IF COL_LENGTH(N'dbo.supplier',N'updated_by') IS NULL
 OR COL_LENGTH(N'dbo.supplier',N'updated_at') IS NULL
    THROW 51822, N'供应商留痕列缺失，请先核对第六周迁移。', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.supplier WHERE name=N'新阅供应链')
 OR NOT EXISTS (SELECT 1 FROM dbo.employee WHERE phone='13800000001' AND role=N'店长')
    THROW 51823, N'缺少新增供应商或店长样例。', 1;
IF EXISTS (SELECT 1 FROM dbo.supplier WHERE name=N'W6-I09-RENAME-TEST')
 OR EXISTS (SELECT 1 FROM dbo.employee WHERE phone='19999999999')
    THROW 51824, N'临时名称或不存在员工的测试值发生冲突，请先报告。', 1;

DROP TABLE IF EXISTS #w6_i09_supplier;
DROP TABLE IF EXISTS #w6_i09_quote;
DROP TABLE IF EXISTS #w6_i09_purchase;
SELECT * INTO #w6_i09_supplier FROM dbo.supplier;
SELECT * INTO #w6_i09_quote FROM dbo.supplier_quote;
SELECT * INTO #w6_i09_purchase FROM dbo.purchase_request;

DECLARE @cases TABLE (
    id INT PRIMARY KEY, label NVARCHAR(80), sql_text NVARCHAR(MAX),
    expected_error INT, expected_constraint NVARCHAR(128)
);
INSERT @cases VALUES
(1,N'合法改名，同时填写修改人与时刻',
 N'DECLARE @supplier_id BIGINT=(SELECT id FROM dbo.supplier WHERE name=N''新阅供应链'');
   UPDATE dbo.supplier SET name=N''W6-I09-RENAME-TEST'',
       updated_by=''13800000001'', updated_at=''2026-10-01T10:00:00''
   WHERE id=@supplier_id;
   IF NOT EXISTS (SELECT 1 FROM dbo.supplier WHERE id=@supplier_id
       AND name=N''W6-I09-RENAME-TEST'' AND updated_by=''13800000001''
       AND updated_at=CONVERT(DATETIME2,''2026-10-01T10:00:00''))
       THROW 51825,N''合法改名或留痕未实际写入。'',1;',0,NULL),
(2,N'只填修改人，不填修改时刻',
 N'UPDATE dbo.supplier SET updated_by=''13800000001'', updated_at=NULL
   WHERE name=N''新阅供应链'';',547,N'CK_supplier_updated_by_pair'),
(3,N'只填修改时刻，不填修改人',
 N'UPDATE dbo.supplier SET updated_by=NULL, updated_at=''2026-10-01T10:00:00''
   WHERE name=N''新阅供应链'';',547,N'CK_supplier_updated_by_pair'),
(4,N'成对填写，但修改人不存在',
 N'UPDATE dbo.supplier SET updated_by=''19999999999'', updated_at=''2026-10-01T10:00:00''
   WHERE name=N''新阅供应链'';',547,N'FK_supplier_updated_by');

DECLARE @results TABLE (
    case_id INT, test_case NVARCHAR(80), expected_error INT,
    actual_error INT, checked_constraint NVARCHAR(128), result VARCHAR(10)
);
DECLARE @id INT=1, @label NVARCHAR(80), @sql NVARCHAR(MAX), @expected INT,
        @constraint NVARCHAR(128), @actual INT, @message NVARCHAR(2048), @failure NVARCHAR(2048);
WHILE @id<=4
BEGIN
    SELECT @label=label, @sql=sql_text, @expected=expected_error,
           @constraint=expected_constraint FROM @cases WHERE id=@id;
    SET @actual=0;
    SET @message=NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC sys.sp_executesql @sql;
        -- 合法改名不应改写报价、采购的供应商编号或任何其他字段。
        IF EXISTS (SELECT * FROM dbo.supplier_quote EXCEPT SELECT * FROM #w6_i09_quote)
         OR EXISTS (SELECT * FROM #w6_i09_quote EXCEPT SELECT * FROM dbo.supplier_quote)
         OR EXISTS (SELECT * FROM dbo.purchase_request EXCEPT SELECT * FROM #w6_i09_purchase)
         OR EXISTS (SELECT * FROM #w6_i09_purchase EXCEPT SELECT * FROM dbo.purchase_request)
            THROW 51826, N'修改供应商时改写了报价或采购记录。', 1;
        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        SET @actual=ERROR_NUMBER();
        SET @message=ERROR_MESSAGE();
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    END CATCH;

    IF @actual<>@expected
       OR (@constraint IS NOT NULL AND CHARINDEX(@constraint,COALESCE(@message,N''))=0)
    BEGIN
        SET @failure=CONCAT(@label,N'：预期错误号 ',@expected,N'，实际 ',@actual,
                            N'；要求约束 ',COALESCE(@constraint,N'无'),N'；',@message);
        THROW 51827, @failure, 1;
    END;
    IF @@TRANCOUNT<>0
        THROW 51828, N'测试项结束后仍有未结束事务。', 1;
    IF EXISTS (SELECT * FROM dbo.supplier EXCEPT SELECT * FROM #w6_i09_supplier)
     OR EXISTS (SELECT * FROM #w6_i09_supplier EXCEPT SELECT * FROM dbo.supplier)
     OR EXISTS (SELECT * FROM dbo.supplier_quote EXCEPT SELECT * FROM #w6_i09_quote)
     OR EXISTS (SELECT * FROM #w6_i09_quote EXCEPT SELECT * FROM dbo.supplier_quote)
     OR EXISTS (SELECT * FROM dbo.purchase_request EXCEPT SELECT * FROM #w6_i09_purchase)
     OR EXISTS (SELECT * FROM #w6_i09_purchase EXCEPT SELECT * FROM dbo.purchase_request)
        THROW 51829, N'测试回滚后三张表与初始快照不一致。', 1;

    INSERT @results VALUES (@id,@label,@expected,@actual,@constraint,'PASS');
    SET @id+=1;
END;

SELECT * FROM @results ORDER BY case_id;
SELECT N'I09-RESTORED' AS check_name, @@TRANCOUNT AS open_transactions,
       COUNT_BIG(*) AS supplier_count,
       (SELECT COUNT_BIG(*) FROM dbo.supplier WHERE name=N'W6-I09-RENAME-TEST') AS temporary_name_count
FROM dbo.supplier;
DROP TABLE #w6_i09_supplier, #w6_i09_quote, #w6_i09_purchase;
PRINT N'supplier-audit-week-6.sql PASS: 4 audit cases checked; all test changes rolled back.';
