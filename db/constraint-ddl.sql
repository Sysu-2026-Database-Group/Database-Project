:On Error exit
-- 第六周跨行约束的“纯 DDL”安装脚本：只安装 R-17 的卡档顺序触发器，不含任何反例测试。
-- 与 db/constraint.sql 的关系：后者是“DDL + 回滚测试”混写的历史脚本，且已被第六周证据清单索引，
-- 因此不得修改；本文件只复制其 DDL 段，供从零建库的 runner 调用。
-- 建库顺序：schema.sql → sample-data.sql → checks/verify.sql → 本文件 → view.sql → migration.sql …

USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
GO

/* Cross-row rule R-17: tier configuration cannot be expressed by a row CHECK.
   触发器名称、判定逻辑与错误号 51025 与 db/constraint.sql 保持完全一致。 */
IF OBJECT_ID(N'dbo.tr_card_type_cross_row', N'TR') IS NULL
    EXEC(N'
CREATE TRIGGER dbo.tr_card_type_cross_row
ON dbo.card_type
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @silver nvarchar(10) = NCHAR(38134) + NCHAR(21345);
    DECLARE @gold nvarchar(10) = NCHAR(37329) + NCHAR(21345);
    IF EXISTS (
        SELECT 1
        FROM dbo.card_type AS s
        JOIN dbo.card_type AS g ON s.[level] = @silver AND g.[level] = @gold
        WHERE g.[card_fee] <= s.[card_fee]
           OR g.[discount_rate] > s.[discount_rate]
    )
        THROW 51025, ''Card tier relation is invalid.'', 1;
END');
GO

IF OBJECT_ID(N'dbo.tr_card_type_cross_row', N'TR') IS NULL
    THROW 52110, N'跨行约束触发器安装失败。', 1;
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'tr_card_type_cross_row' AND is_disabled = 1)
    THROW 52111, N'跨行约束触发器处于禁用状态。', 1;
GO

PRINT N'constraint-ddl.sql PASS: tr_card_type_cross_row installed';
GO
