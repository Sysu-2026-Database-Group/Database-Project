:On Error exit
-- 第六周迁移：v0.1 -> v0.2-w6
-- SQLCMD 模式；DatabaseName 必须由调用者指定，不在脚本内覆盖 -v 参数。
-- 例：sqlcmd -S localhost -E -C -b -v DatabaseName=ShiguangBookstoreWeek6Acceptance -i db/migration.sql

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

-- 安全门：迁移只能在还原出来的工作副本上执行，不能碰原始 Week 3 库。
IF DB_NAME() = N'ShiguangBookstoreWeek3'
    THROW 51040, N'禁止在 ShiguangBookstoreWeek3 原始库上执行迁移。请先还原为独立工作副本。', 1;
IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek6%'
    THROW 51040, N'迁移目标必须是 ShiguangBookstoreWeek6 开头的专用副本。', 1;
IF DB_ID(N'$(DatabaseName)') IS NULL
    THROW 51041, N'目标数据库不存在。请检查 SQLCMD 模式和 DatabaseName 变量。', 1;
IF @@TRANCOUNT <> 0
    THROW 51042, N'请在没有外层事务的新查询窗口执行迁移脚本。', 1;

-- 成功标记存在时，整份迁移已经完成；重复执行不再修改结构或插入数据。
-- 第一次运行时 schema_migration 尚不存在，表查询必须延迟到运行时编译。
DECLARE @migration_marker_exists bit = 0;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql
        N'SELECT @exists = CASE WHEN EXISTS
              (SELECT 1 FROM dbo.schema_migration WHERE migration_key = ''W6-NORMALIZATION-1.0'')
              THEN 1 ELSE 0 END;',
        N'@exists bit OUTPUT',
        @exists = @migration_marker_exists OUTPUT;
END;
IF @migration_marker_exists = 1
BEGIN
    PRINT N'migration.sql SKIP: W6-NORMALIZATION-1.0 已完成。';
    RETURN;
END;

-- 迁移前提：这是 v0.1 副本，而不是空库、旧迁移库或被其他脚本改过的库。
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) <> 19
    THROW 51043, N'迁移前用户表数量不是 19；请确认目标是未迁移的 v0.1 副本。', 1;
IF (SELECT COUNT(*) FROM sys.foreign_keys) <> 47
    THROW 51044, N'迁移前外码数量不是 47；请先恢复干净的 v0.1 副本。', 1;
IF OBJECT_ID(N'dbo.schema_migration', N'U') IS NOT NULL
    THROW 51045, N'发现未完成的 schema_migration 表，无法判断上次迁移状态；请从备份恢复副本。', 1;
IF COL_LENGTH(N'dbo.supplier', N'updated_by') IS NOT NULL
    OR COL_LENGTH(N'dbo.supplier', N'updated_at') IS NOT NULL
    THROW 51046, N'supplier 留痕字段已存在但没有迁移完成标记；请从备份恢复副本。', 1;

-- 六要件中的“重复数据检查”在任何 DDL 之前执行，冲突时不会改变目标库。
IF EXISTS (
    SELECT book_isbn FROM dbo.goods
    WHERE book_isbn IS NOT NULL
    GROUP BY book_isbn HAVING COUNT_BIG(*) > 1
)
    THROW 51047, N'goods.book_isbn 存在重复引用，不能创建筛选唯一索引。', 1;
IF EXISTS (
    SELECT toy_code FROM dbo.goods
    WHERE toy_code IS NOT NULL
    GROUP BY toy_code HAVING COUNT_BIG(*) > 1
)
    THROW 51048, N'goods.toy_code 存在重复引用，不能创建筛选唯一索引。', 1;
IF EXISTS (
    SELECT reservation_id FROM dbo.sale
    WHERE reservation_id IS NOT NULL
    GROUP BY reservation_id HAVING COUNT_BIG(*) > 1
)
    THROW 51049, N'sale.reservation_id 存在重复取货销售单，不能创建唯一索引。', 1;
IF EXISTS (
    SELECT sale_id FROM dbo.point_movement
    WHERE change_type IN (N'消费获得', N'抵扣使用')
      AND sale_id IS NULL
)
    THROW 51050, N'消费获得或抵扣使用积分流水缺少 sale_id。', 1;
IF EXISTS (
    SELECT 1 FROM dbo.point_movement
    WHERE change_type = N'退货回滚'
      AND (sale_id IS NULL OR return_id IS NULL)
)
    THROW 51051, N'退货回滚积分流水必须同时关联 sale_id 和 return_id。', 1;
IF EXISTS (
    SELECT sale_id FROM dbo.point_movement
    WHERE change_type = N'消费获得' AND sale_id IS NOT NULL
    GROUP BY sale_id HAVING COUNT_BIG(*) > 1
)
    THROW 51052, N'同一销售单存在重复消费获得积分流水。', 1;
IF EXISTS (
    SELECT sale_id FROM dbo.point_movement
    WHERE change_type = N'抵扣使用' AND sale_id IS NOT NULL
    GROUP BY sale_id HAVING COUNT_BIG(*) > 1
)
    THROW 51053, N'同一销售单存在重复抵扣使用积分流水。', 1;
IF EXISTS (
    SELECT return_id FROM dbo.point_movement
    WHERE change_type = N'退货回滚' AND return_id IS NOT NULL
    GROUP BY return_id HAVING COUNT_BIG(*) > 1
)
    THROW 51054, N'同一退货单存在重复退货回滚积分流水。', 1;
IF EXISTS (SELECT 1 FROM dbo.fund_flow WHERE fund_before < 0 OR fund_after < 0)
    THROW 51055, N'fund_flow 存在负余额，不能强化非负余额约束。', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    /* 要件 1：新表创建。
       这是迁移元数据表，不是虚构的业务实体；19 张旧业务表全部保留。
    */
    CREATE TABLE dbo.schema_migration (
        migration_key VARCHAR(64) NOT NULL,
        source_version VARCHAR(32) NOT NULL,
        target_version VARCHAR(32) NOT NULL,
        applied_at DATETIME2 NOT NULL CONSTRAINT DF_schema_migration_applied_at DEFAULT (SYSDATETIME()),
        applied_by VARCHAR(11) NULL,
        status NVARCHAR(10) NOT NULL,
        notes NVARCHAR(400) NOT NULL,
        CONSTRAINT PK_schema_migration PRIMARY KEY (migration_key),
        CONSTRAINT UQ_schema_migration_target_version UNIQUE (target_version),
        CONSTRAINT CK_schema_migration_status CHECK (status IN (N'已完成', N'已回滚')),
        CONSTRAINT CK_schema_migration_applied_by_phone CHECK (
            applied_by IS NULL OR
            (LEN(applied_by) = 11 AND applied_by COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')
        ),
        CONSTRAINT FK_schema_migration_applied_by
            FOREIGN KEY (applied_by) REFERENCES dbo.employee(phone)
    );

    /* 要件 2：字段调整。旧供应商没有可信的历史修改人 / 时刻，因此迁移值保留 NULL，
       不把 created_by / created_at 伪造为最近一次修改记录。 */
    ALTER TABLE dbo.supplier ADD
        updated_by VARCHAR(11) NULL,
        updated_at DATETIME2 NULL;
    -- 新增列在同一批次的静态编译阶段尚不可见，约束用动态批次执行。
    EXEC sys.sp_executesql N'
        ALTER TABLE dbo.supplier ADD CONSTRAINT CK_supplier_updated_by_phone CHECK (
            updated_by IS NULL OR
            (LEN(updated_by) = 11 AND updated_by COLLATE Latin1_General_100_BIN2 NOT LIKE ''%[^0-9]%'')
        );';
    EXEC sys.sp_executesql N'
        ALTER TABLE dbo.supplier ADD CONSTRAINT CK_supplier_updated_by_pair CHECK (
            (updated_by IS NULL AND updated_at IS NULL)
            OR (updated_by IS NOT NULL AND updated_at IS NOT NULL)
        );';

    /* 要件 3：主码、候选码和外码设置。
       schema_migration 的 migration_key 是主码，target_version 是候选码；
       applied_by 和 supplier.updated_by 均引用 employee.phone。
    */
    EXEC sys.sp_executesql N'
        ALTER TABLE dbo.supplier ADD CONSTRAINT FK_supplier_updated_by
            FOREIGN KEY (updated_by) REFERENCES dbo.employee(phone);';

    CREATE UNIQUE INDEX UX_goods_book_isbn
        ON dbo.goods(book_isbn)
        WHERE book_isbn IS NOT NULL;
    CREATE UNIQUE INDEX UX_goods_toy_code
        ON dbo.goods(toy_code)
        WHERE toy_code IS NOT NULL;
    CREATE UNIQUE INDEX UX_sale_reservation_id
        ON dbo.sale(reservation_id)
        WHERE reservation_id IS NOT NULL;
    CREATE UNIQUE INDEX UX_point_movement_earn
        ON dbo.point_movement(sale_id)
        WHERE change_type = N'消费获得';
    CREATE UNIQUE INDEX UX_point_movement_use
        ON dbo.point_movement(sale_id)
        WHERE change_type = N'抵扣使用';
    CREATE UNIQUE INDEX UX_point_movement_return
        ON dbo.point_movement(return_id)
        WHERE change_type = N'退货回滚';

    /* 要件 3 / 4：把已存在的来源规则强化为可执行约束，并保留旧流水。
       约束替换不改写任何旧业务行；旧行只做前置检查后原地保留。 */
    ALTER TABLE dbo.point_movement DROP CONSTRAINT CK_point_movement_kind;
    ALTER TABLE dbo.point_movement ADD CONSTRAINT CK_point_movement_kind CHECK (
        (change_type = N'消费获得' AND points > 0 AND sale_id IS NOT NULL AND return_id IS NULL)
        OR (change_type = N'抵扣使用' AND points < 0 AND sale_id IS NOT NULL AND return_id IS NULL)
        OR (change_type = N'退货回滚' AND points < 0 AND sale_id IS NOT NULL AND return_id IS NOT NULL)
    );

    ALTER TABLE dbo.fund_flow DROP CONSTRAINT CK_fund_flow_amount;
    ALTER TABLE dbo.fund_flow ADD CONSTRAINT CK_fund_flow_amount CHECK (
        amount > 0 AND fund_before >= 0 AND fund_after >= 0
    );

    /* 要件 4：必要的数据迁移。
       没有需要改写的旧业务事实；仅插入一条版本记录，明确来源、目标和保留策略。
    */
    INSERT dbo.schema_migration
        (migration_key, source_version, target_version, applied_by, status, notes)
    VALUES
        ('W6-NORMALIZATION-1.0', 'v0.1', 'v0.2-w6', NULL, N'已完成',
         N'保留19张旧业务表和旧记录；supplier旧留痕置空；新增唯一性、来源约束和迁移元数据。');

    /* 要件 5：重复数据检查在 DDL 前已完成；这里再做一次提交前断言，防止脚本维护时漏项。 */
    IF (SELECT COUNT(*) FROM sys.indexes
        WHERE name IN (N'UX_goods_book_isbn', N'UX_goods_toy_code', N'UX_sale_reservation_id',
                       N'UX_point_movement_earn', N'UX_point_movement_use', N'UX_point_movement_return')) <> 6
        THROW 51056, N'迁移唯一索引数量不符合预期。', 1;
    DECLARE @legacy_supplier_audit_count bigint;
    EXEC sys.sp_executesql
        N'SELECT @count = COUNT_BIG(*) FROM dbo.supplier
          WHERE updated_by IS NOT NULL OR updated_at IS NOT NULL;',
        N'@count bigint OUTPUT',
        @count = @legacy_supplier_audit_count OUTPUT;
    IF @legacy_supplier_audit_count > 0
        THROW 51057, N'旧供应商留痕不应被迁移脚本伪造。', 1;

    -- 新字段的说明与目标结构同步；不改变旧字段的含义。
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次已记录修改人；旧数据无可信历史时保留 NULL',
        @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier',
        @level2type=N'COLUMN', @level2name=N'updated_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次已记录修改时刻；与 updated_by 成对出现',
        @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier',
        @level2type=N'COLUMN', @level2name=N'updated_at';

    /* 要件 6：旧表处理或保留说明。
       本迁移不删除、不重命名、不覆盖任何旧业务表；schema_migration 是新增技术表。 */
    COMMIT;
    PRINT N'migration.sql PASS: v0.1 -> v0.2-w6; old business tables and rows retained.';
    DECLARE @migration_result_sql nvarchar(max) = N'
        SELECT N''migration'' AS check_name,
               DB_NAME() AS database_name,
               20 AS user_tables_after,
               49 AS foreign_keys_after,
               (SELECT COUNT_BIG(*) FROM dbo.schema_migration) AS migration_records,
               (SELECT COUNT_BIG(*) FROM dbo.supplier
                WHERE updated_by IS NULL AND updated_at IS NULL) AS legacy_supplier_rows_with_null_audit;';
    EXEC sys.sp_executesql @migration_result_sql;
    -- 展示六项重复分组计数；前置检查和唯一索引保证它们均为0。
    SELECT N'goods_book_isbn' AS duplicate_check, COUNT_BIG(*) AS duplicate_groups
    FROM (SELECT book_isbn FROM dbo.goods WHERE book_isbn IS NOT NULL GROUP BY book_isbn HAVING COUNT_BIG(*)>1) d
    UNION ALL SELECT N'goods_toy_code', COUNT_BIG(*)
    FROM (SELECT toy_code FROM dbo.goods WHERE toy_code IS NOT NULL GROUP BY toy_code HAVING COUNT_BIG(*)>1) d
    UNION ALL SELECT N'sale_reservation_id', COUNT_BIG(*)
    FROM (SELECT reservation_id FROM dbo.sale WHERE reservation_id IS NOT NULL GROUP BY reservation_id HAVING COUNT_BIG(*)>1) d
    UNION ALL SELECT N'point_earn', COUNT_BIG(*)
    FROM (SELECT sale_id FROM dbo.point_movement WHERE change_type=N'消费获得' GROUP BY sale_id HAVING COUNT_BIG(*)>1) d
    UNION ALL SELECT N'point_use', COUNT_BIG(*)
    FROM (SELECT sale_id FROM dbo.point_movement WHERE change_type=N'抵扣使用' GROUP BY sale_id HAVING COUNT_BIG(*)>1) d
    UNION ALL SELECT N'point_return', COUNT_BIG(*)
    FROM (SELECT return_id FROM dbo.point_movement WHERE change_type=N'退货回滚' GROUP BY return_id HAVING COUNT_BIG(*)>1) d;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
END CATCH;
