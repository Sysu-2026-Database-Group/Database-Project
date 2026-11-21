:On Error exit
-- 库存流水增加调整前后数量：stock_before / stock_after
-- SQLCMD 模式；DatabaseName 必须由调用者指定，不在脚本内覆盖 -v 参数。
-- 例：sqlcmd -S localhost -E -C -b -v DatabaseName=ShiguangBookstoreWeek7Accept -i db/migration-stock-before-after.sql

USE [$(DatabaseName)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- 安全门：只允许项目工作副本；不要碰原始 Week3 库。
IF DB_NAME() = N'ShiguangBookstoreWeek3'
    THROW 51100, N'禁止在 ShiguangBookstoreWeek3 原始库上执行迁移。', 1;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek6%'
   AND DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7%'
    THROW 51100, N'迁移目标必须是 ShiguangBookstoreWeek6/Week7 开头的专用副本。', 1;
IF DB_ID(N'$(DatabaseName)') IS NULL
    THROW 51101, N'目标数据库不存在。请检查 SQLCMD 模式和 DatabaseName 变量。', 1;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NULL
    THROW 51102, N'缺少 dbo.schema_migration；请先执行 Week6 migration.sql。', 1;
IF @@TRANCOUNT <> 0
    THROW 51103, N'请在没有外层事务的新查询窗口执行迁移脚本。', 1;

DECLARE @migration_key varchar(64) = N'W7-STOCK-BEFORE-AFTER';
IF EXISTS (SELECT 1 FROM dbo.schema_migration WHERE migration_key = @migration_key)
BEGIN
    PRINT N'migration-stock-before-after.sql SKIP: W7-STOCK-BEFORE-AFTER 已完成。';
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(N'dbo.stock_movement', N'stock_before') IS NULL
       AND COL_LENGTH(N'dbo.stock_movement', N'stock_after') IS NULL
    BEGIN
        ALTER TABLE dbo.stock_movement ADD
            stock_before INT NULL,
            stock_after INT NULL;

        -- 新增列在同一批次的静态编译阶段不可见，回填和约束必须用动态批次。
        EXEC sys.sp_executesql N'
            ;WITH ordered AS (
                SELECT m.id, m.goods_id, m.quantity,
                       SUM(m.quantity) OVER (
                           PARTITION BY m.goods_id
                           ORDER BY m.changed_at DESC, m.id DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                       ) AS qty_from_latest
                FROM dbo.stock_movement m
            )
            UPDATE m
               SET stock_before = g.stock_total - o.qty_from_latest,
                   stock_after  = g.stock_total - (o.qty_from_latest - m.quantity)
              FROM dbo.stock_movement m
              JOIN ordered o ON o.id = m.id
              JOIN dbo.goods g ON g.id = m.goods_id;';

        EXEC sys.sp_executesql N'
            IF EXISTS (
                SELECT 1 FROM dbo.stock_movement
                WHERE stock_before IS NULL OR stock_after IS NULL
                   OR stock_before < 0 OR stock_after < 0
                   OR quantity <> stock_after - stock_before
            )
                THROW 51105, N''旧库存流水无法回填出合法的 stock_before/stock_after；请检查 goods.stock_total 与流水是否一致。'', 1;';

        EXEC sys.sp_executesql N'
            ALTER TABLE dbo.stock_movement ALTER COLUMN stock_before INT NOT NULL;
            ALTER TABLE dbo.stock_movement ALTER COLUMN stock_after INT NOT NULL;
            IF OBJECT_ID(N''dbo.CK_stock_movement_bounds'', N''C'') IS NOT NULL
                ALTER TABLE dbo.stock_movement DROP CONSTRAINT CK_stock_movement_bounds;
            IF OBJECT_ID(N''dbo.CK_stock_movement_delta'', N''C'') IS NOT NULL
                ALTER TABLE dbo.stock_movement DROP CONSTRAINT CK_stock_movement_delta;
            IF OBJECT_ID(N''dbo.CK_stock_movement_source'', N''C'') IS NOT NULL
                ALTER TABLE dbo.stock_movement DROP CONSTRAINT CK_stock_movement_source;
            ALTER TABLE dbo.stock_movement ADD
                CONSTRAINT CK_stock_movement_bounds CHECK (stock_before >= 0 AND stock_after >= 0),
                CONSTRAINT CK_stock_movement_delta CHECK (quantity = stock_after - stock_before),
                CONSTRAINT CK_stock_movement_source CHECK (
                    (change_type=N''购入'' AND stock_after > stock_before AND request_id IS NOT NULL AND sale_id IS NULL AND return_item_id IS NULL)
                    OR (change_type=N''卖出'' AND stock_after < stock_before AND sale_id IS NOT NULL AND request_id IS NULL AND return_item_id IS NULL)
                    OR (change_type=N''退货'' AND stock_after > stock_before AND return_item_id IS NOT NULL AND request_id IS NULL AND sale_id IS NULL)
                    OR (change_type=N''损坏'' AND stock_after < stock_before AND stock_before - stock_after BETWEEN 1 AND 1000
                        AND request_id IS NULL AND sale_id IS NULL AND return_item_id IS NULL
                        AND note IS NOT NULL AND LEN(LTRIM(RTRIM(note))) > 0)
                );';
    END
    ELSE
    BEGIN
        IF COL_LENGTH(N'dbo.stock_movement', N'stock_before') IS NULL
           OR COL_LENGTH(N'dbo.stock_movement', N'stock_after') IS NULL
            THROW 51104, N'stock_movement 只存在一个前后数量列，结构不完整；请检查数据库状态。', 1;
        EXEC sys.sp_executesql N'
            IF EXISTS (
                SELECT 1 FROM dbo.stock_movement
                WHERE stock_before IS NULL OR stock_after IS NULL
                   OR stock_before < 0 OR stock_after < 0
                   OR quantity <> stock_after - stock_before
            )
                THROW 51105, N''stock_movement 现有前后数量不合法；请检查 goods.stock_total 与流水是否一致。'', 1;';
        PRINT N'stock_movement 已包含 stock_before/stock_after，跳过结构回填。';
    END

    INSERT dbo.schema_migration
        (migration_key, source_version, target_version, applied_by, status, notes)
    VALUES
        (@migration_key, N'v0.2-w6', N'v1.1-stock-before-after', NULL, N'已完成',
         N'stock_movement 增加 stock_before/stock_after；quantity 保留并与差值一致');

    COMMIT;
    PRINT N'migration-stock-before-after.sql PASS: stock_before/stock_after added and backfilled.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
END CATCH;
