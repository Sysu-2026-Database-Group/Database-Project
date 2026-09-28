:On Error exit
-- 使用 SQLCMD 模式；DatabaseName 由调用者指定，例：sqlcmd -v DatabaseName=ShiguangBookstoreWeek3
USE [master];
GO
-- 只创建不存在的专用练习库；不 DROP，不覆盖已有表。
IF DB_ID(N'$(DatabaseName)') IS NULL
    EXEC(N'CREATE DATABASE [$(DatabaseName)]');
GO
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51009, N'请在无外层事务的新查询窗口执行本脚本。', 1;
IF EXISTS (SELECT 1 FROM sys.tables WHERE is_ms_shipped=0)
    THROW 51000, N'目标数据库已有表，停止建表。请使用新的专用空库。', 1;
BEGIN TRY
    BEGIN TRANSACTION;

    -- employee：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[employee] (
        [phone] VARCHAR(11) NOT NULL,
        [name] NVARCHAR(20) NOT NULL,
        [role] NVARCHAR(10) NOT NULL,
        [created_by] VARCHAR(11) NOT NULL,
        [created_at] DATETIME2 NOT NULL CONSTRAINT [DF_employee_created_at] DEFAULT (SYSDATETIME()),
        [updated_by] VARCHAR(11) NULL,
        [updated_at] DATETIME2 NULL,
        CONSTRAINT [PK_employee] PRIMARY KEY ([phone]),
        CONSTRAINT [CK_employee_role] CHECK ([role] IN (N'库管',N'收银员',N'店长')),
        CONSTRAINT [CK_employee_phone_text] CHECK (LEN(LTRIM(RTRIM([phone]))) > 0),
        CONSTRAINT [CK_employee_phone_phone] CHECK ([phone] IS NULL OR (LEN([phone])=11 AND [phone] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_employee_name_text] CHECK (LEN(LTRIM(RTRIM([name]))) > 0),
        CONSTRAINT [CK_employee_created_by_text] CHECK (LEN(LTRIM(RTRIM([created_by]))) > 0),
        CONSTRAINT [CK_employee_created_by_phone] CHECK ([created_by] IS NULL OR (LEN([created_by])=11 AND [created_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_employee_updated_by_phone] CHECK ([updated_by] IS NULL OR (LEN([updated_by])=11 AND [updated_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_employee_updated_by_pair] CHECK (([updated_by] IS NULL AND [updated_at] IS NULL) OR ([updated_by] IS NOT NULL AND [updated_at] IS NOT NULL))
    );

    -- book：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[book] (
        [isbn] VARCHAR(17) NOT NULL,
        [author] NVARCHAR(100) NOT NULL,
        [publisher] NVARCHAR(100) NOT NULL,
        [page_count] INT NOT NULL,
        CONSTRAINT [PK_book] PRIMARY KEY ([isbn]),
        CONSTRAINT [CK_book_isbn] CHECK (LEN(isbn) BETWEEN 10 AND 17),
        CONSTRAINT [CK_book_pages] CHECK (page_count > 0),
        CONSTRAINT [CK_book_isbn_text] CHECK (LEN(LTRIM(RTRIM([isbn]))) > 0),
        CONSTRAINT [CK_book_author_text] CHECK (LEN(LTRIM(RTRIM([author]))) > 0),
        CONSTRAINT [CK_book_publisher_text] CHECK (LEN(LTRIM(RTRIM([publisher]))) > 0)
    );

    -- toy：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[toy] (
        [inner_code] VARCHAR(20) NOT NULL,
        [spec] NVARCHAR(100) NOT NULL,
        CONSTRAINT [PK_toy] PRIMARY KEY ([inner_code]),
        CONSTRAINT [CK_toy_inner_code_text] CHECK (LEN(LTRIM(RTRIM([inner_code]))) > 0),
        CONSTRAINT [CK_toy_spec_text] CHECK (LEN(LTRIM(RTRIM([spec]))) > 0)
    );

    -- supplier：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[supplier] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [name] NVARCHAR(100) NOT NULL,
        [created_by] VARCHAR(11) NOT NULL,
        [created_at] DATETIME2 NOT NULL CONSTRAINT [DF_supplier_created_at] DEFAULT (SYSDATETIME()),
        CONSTRAINT [PK_supplier] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_supplier_name] UNIQUE ([name]),
        CONSTRAINT [CK_supplier_name_text] CHECK (LEN(LTRIM(RTRIM([name]))) > 0),
        CONSTRAINT [CK_supplier_created_by_text] CHECK (LEN(LTRIM(RTRIM([created_by]))) > 0),
        CONSTRAINT [CK_supplier_created_by_phone] CHECK ([created_by] IS NULL OR (LEN([created_by])=11 AND [created_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );

    -- card_type：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[card_type] (
        [level] NVARCHAR(10) NOT NULL,
        [card_fee] DECIMAL(10,2) NOT NULL,
        [discount_rate] DECIMAL(3,2) NOT NULL,
        [set_by] VARCHAR(11) NOT NULL,
        [set_at] DATETIME2 NOT NULL CONSTRAINT [DF_card_type_set_at] DEFAULT (SYSDATETIME()),
        CONSTRAINT [PK_card_type] PRIMARY KEY ([level]),
        CONSTRAINT [CK_card_type_level] CHECK ([level] IN (N'银卡',N'金卡')),
        CONSTRAINT [CK_card_type_fee] CHECK (card_fee > 0),
        CONSTRAINT [CK_card_type_rate] CHECK (discount_rate > 0 AND discount_rate <= 1),
        CONSTRAINT [CK_card_type_set_by_text] CHECK (LEN(LTRIM(RTRIM([set_by]))) > 0),
        CONSTRAINT [CK_card_type_set_by_phone] CHECK ([set_by] IS NULL OR (LEN([set_by])=11 AND [set_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );

    -- goods：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[goods] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [category] NVARCHAR(10) NOT NULL,
        [name] NVARCHAR(100) NOT NULL,
        [book_isbn] VARCHAR(17) NULL,
        [toy_code] VARCHAR(20) NULL,
        [on_shelf] BIT NOT NULL CONSTRAINT [DF_goods_on_shelf] DEFAULT (0),
        [price] DECIMAL(10,2) NULL,
        [stock_total] INT NOT NULL CONSTRAINT [DF_goods_stock_total] DEFAULT (0),
        [reserved_qty] INT NOT NULL CONSTRAINT [DF_goods_reserved_qty] DEFAULT (0),
        [created_by] VARCHAR(11) NOT NULL,
        [created_at] DATETIME2 NOT NULL CONSTRAINT [DF_goods_created_at] DEFAULT (SYSDATETIME()),
        [updated_by] VARCHAR(11) NULL,
        [updated_at] DATETIME2 NULL,
        CONSTRAINT [PK_goods] PRIMARY KEY ([id]),
        CONSTRAINT [CK_goods_category] CHECK (([category]=N'图书' AND book_isbn IS NOT NULL AND toy_code IS NULL) OR ([category]=N'文创' AND toy_code IS NOT NULL AND book_isbn IS NULL)),
        CONSTRAINT [CK_goods_price] CHECK (price IS NULL OR price > 0),
        CONSTRAINT [CK_goods_listing] CHECK (on_shelf=0 OR price IS NOT NULL),
        CONSTRAINT [CK_goods_stock] CHECK (stock_total >= 0 AND reserved_qty >= 0 AND reserved_qty <= stock_total),
        CONSTRAINT [CK_goods_name_text] CHECK (LEN(LTRIM(RTRIM([name]))) > 0),
        CONSTRAINT [CK_goods_created_by_text] CHECK (LEN(LTRIM(RTRIM([created_by]))) > 0),
        CONSTRAINT [CK_goods_created_by_phone] CHECK ([created_by] IS NULL OR (LEN([created_by])=11 AND [created_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_goods_updated_by_phone] CHECK ([updated_by] IS NULL OR (LEN([updated_by])=11 AND [updated_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_goods_updated_by_pair] CHECK (([updated_by] IS NULL AND [updated_at] IS NULL) OR ([updated_by] IS NOT NULL AND [updated_at] IS NOT NULL))
    );

    -- supplier_quote：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[supplier_quote] (
        [supplier_id] BIGINT NOT NULL,
        [goods_id] BIGINT NOT NULL,
        [quote_amount] DECIMAL(10,2) NOT NULL,
        [reported_by] VARCHAR(11) NOT NULL,
        [reported_at] DATETIME2 NOT NULL CONSTRAINT [DF_supplier_quote_reported_at] DEFAULT (SYSDATETIME()),
        CONSTRAINT [PK_supplier_quote] PRIMARY KEY ([supplier_id], [goods_id]),
        CONSTRAINT [CK_supplier_quote_amount] CHECK (quote_amount > 0),
        CONSTRAINT [CK_supplier_quote_reported_by_text] CHECK (LEN(LTRIM(RTRIM([reported_by]))) > 0),
        CONSTRAINT [CK_supplier_quote_reported_by_phone] CHECK ([reported_by] IS NULL OR (LEN([reported_by])=11 AND [reported_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );

    -- member：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[member] (
        [phone] VARCHAR(11) NOT NULL,
        [card_level] NVARCHAR(10) NOT NULL,
        [opened_by] VARCHAR(11) NOT NULL,
        [opened_at] DATETIME2 NOT NULL CONSTRAINT [DF_member_opened_at] DEFAULT (SYSDATETIME()),
        [updated_by] VARCHAR(11) NULL,
        [updated_at] DATETIME2 NULL,
        [expires_at] DATE NOT NULL,
        [points_balance] INT NOT NULL CONSTRAINT [DF_member_points_balance] DEFAULT (0),
        CONSTRAINT [PK_member] PRIMARY KEY ([phone]),
        CONSTRAINT [CK_member_expiry] CHECK (expires_at > CAST(opened_at AS date)),
        CONSTRAINT [CK_member_phone_text] CHECK (LEN(LTRIM(RTRIM([phone]))) > 0),
        CONSTRAINT [CK_member_phone_phone] CHECK ([phone] IS NULL OR (LEN([phone])=11 AND [phone] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_member_card_level_text] CHECK (LEN(LTRIM(RTRIM([card_level]))) > 0),
        CONSTRAINT [CK_member_opened_by_text] CHECK (LEN(LTRIM(RTRIM([opened_by]))) > 0),
        CONSTRAINT [CK_member_opened_by_phone] CHECK ([opened_by] IS NULL OR (LEN([opened_by])=11 AND [opened_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_member_updated_by_phone] CHECK ([updated_by] IS NULL OR (LEN([updated_by])=11 AND [updated_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_member_updated_by_pair] CHECK (([updated_by] IS NULL AND [updated_at] IS NULL) OR ([updated_by] IS NOT NULL AND [updated_at] IS NOT NULL))
    );

    -- purchase_request：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[purchase_request] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [no] VARCHAR(20) NOT NULL,
        [supplier_id] BIGINT NOT NULL,
        [status] NVARCHAR(10) NOT NULL CONSTRAINT [DF_purchase_request_status] DEFAULT (N'草稿'),
        [created_by] VARCHAR(11) NOT NULL,
        [created_at] DATETIME2 NOT NULL CONSTRAINT [DF_purchase_request_created_at] DEFAULT (SYSDATETIME()),
        [submitted_by] VARCHAR(11) NULL,
        [submitted_at] DATETIME2 NULL,
        [approved_by] VARCHAR(11) NULL,
        [approved_at] DATETIME2 NULL,
        [cancelled_by] VARCHAR(11) NULL,
        [cancelled_at] DATETIME2 NULL,
        CONSTRAINT [PK_purchase_request] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_purchase_request_no] UNIQUE ([no]),
        CONSTRAINT [CK_purchase_request_status] CHECK ([status] IN (N'草稿',N'已提交',N'已审批',N'已收货',N'已取消')),
        CONSTRAINT [CK_purchase_request_stage] CHECK (([status]=N'草稿' AND submitted_by IS NULL AND approved_by IS NULL AND cancelled_by IS NULL) OR ([status]=N'已提交' AND submitted_by IS NOT NULL AND approved_by IS NULL AND cancelled_by IS NULL) OR ([status] IN (N'已审批',N'已收货') AND submitted_by IS NOT NULL AND approved_by IS NOT NULL AND cancelled_by IS NULL) OR ([status]=N'已取消' AND cancelled_by IS NOT NULL AND approved_by IS NULL)),
        CONSTRAINT [CK_purchase_request_times] CHECK ((submitted_at IS NULL OR submitted_at >= created_at) AND (approved_at IS NULL OR approved_at >= submitted_at) AND (cancelled_at IS NULL OR cancelled_at >= created_at)),
        CONSTRAINT [CK_purchase_request_no_text] CHECK (LEN(LTRIM(RTRIM([no]))) > 0),
        CONSTRAINT [CK_purchase_request_created_by_text] CHECK (LEN(LTRIM(RTRIM([created_by]))) > 0),
        CONSTRAINT [CK_purchase_request_created_by_phone] CHECK ([created_by] IS NULL OR (LEN([created_by])=11 AND [created_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_purchase_request_submitted_by_phone] CHECK ([submitted_by] IS NULL OR (LEN([submitted_by])=11 AND [submitted_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_purchase_request_submitted_by_pair] CHECK (([submitted_by] IS NULL AND [submitted_at] IS NULL) OR ([submitted_by] IS NOT NULL AND [submitted_at] IS NOT NULL)),
        CONSTRAINT [CK_purchase_request_approved_by_phone] CHECK ([approved_by] IS NULL OR (LEN([approved_by])=11 AND [approved_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_purchase_request_approved_by_pair] CHECK (([approved_by] IS NULL AND [approved_at] IS NULL) OR ([approved_by] IS NOT NULL AND [approved_at] IS NOT NULL)),
        CONSTRAINT [CK_purchase_request_cancelled_by_phone] CHECK ([cancelled_by] IS NULL OR (LEN([cancelled_by])=11 AND [cancelled_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_purchase_request_cancelled_by_pair] CHECK (([cancelled_by] IS NULL AND [cancelled_at] IS NULL) OR ([cancelled_by] IS NOT NULL AND [cancelled_at] IS NOT NULL))
    );

    -- purchase_request_item：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[purchase_request_item] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [request_id] BIGINT NOT NULL,
        [goods_id] BIGINT NOT NULL,
        [request_qty] INT NOT NULL,
        [unit_cost] DECIMAL(10,2) NOT NULL,
        CONSTRAINT [PK_purchase_request_item] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_purchase_request_item_request_id_goods_id] UNIQUE ([request_id], [goods_id]),
        CONSTRAINT [CK_purchase_request_item_quantity] CHECK (request_qty > 0),
        CONSTRAINT [CK_purchase_request_item_cost] CHECK (unit_cost > 0)
    );

    -- reservation：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[reservation] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [code] VARCHAR(20) NOT NULL,
        [phone] VARCHAR(11) NOT NULL,
        [status] NVARCHAR(10) NOT NULL CONSTRAINT [DF_reservation_status] DEFAULT (N'有效'),
        [created_at] DATETIME2 NOT NULL CONSTRAINT [DF_reservation_created_at] DEFAULT (SYSDATETIME()),
        [expires_at] DATETIME2 NOT NULL,
        [cancelled_by_employee] VARCHAR(11) NULL,
        [cancelled_at] DATETIME2 NULL,
        CONSTRAINT [PK_reservation] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_reservation_code] UNIQUE ([code]),
        CONSTRAINT [CK_reservation_status] CHECK ([status] IN (N'有效',N'已取',N'已过期',N'已取消')),
        CONSTRAINT [CK_reservation_expiry] CHECK (expires_at = DATEADD(day,3,created_at)),
        CONSTRAINT [CK_reservation_cancel] CHECK (([status]=N'已取消' AND cancelled_at IS NOT NULL AND cancelled_at >= created_at) OR ([status]<>N'已取消' AND cancelled_at IS NULL AND cancelled_by_employee IS NULL)),
        CONSTRAINT [CK_reservation_code_text] CHECK (LEN(LTRIM(RTRIM([code]))) > 0),
        CONSTRAINT [CK_reservation_phone_text] CHECK (LEN(LTRIM(RTRIM([phone]))) > 0),
        CONSTRAINT [CK_reservation_phone_phone] CHECK ([phone] IS NULL OR (LEN([phone])=11 AND [phone] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_reservation_cancelled_by_employee_phone] CHECK ([cancelled_by_employee] IS NULL OR (LEN([cancelled_by_employee])=11 AND [cancelled_by_employee] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );

    -- reservation_item：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[reservation_item] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [reservation_id] BIGINT NOT NULL,
        [goods_id] BIGINT NOT NULL,
        [quantity] INT NOT NULL,
        CONSTRAINT [PK_reservation_item] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_reservation_item_reservation_id_goods_id] UNIQUE ([reservation_id], [goods_id]),
        CONSTRAINT [CK_reservation_item_quantity] CHECK (quantity > 0)
    );

    -- sale：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[sale] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [no] VARCHAR(20) NOT NULL,
        [status] NVARCHAR(10) NOT NULL CONSTRAINT [DF_sale_status] DEFAULT (N'已付'),
        [cashier_by] VARCHAR(11) NOT NULL,
        [sold_at] DATETIME2 NOT NULL CONSTRAINT [DF_sale_sold_at] DEFAULT (SYSDATETIME()),
        [card_level] NVARCHAR(10) NULL,
        [member_phone] VARCHAR(11) NULL,
        [reservation_id] BIGINT NULL,
        [subtotal_amount] DECIMAL(10,2) NOT NULL,
        [discount_rate] DECIMAL(3,2) NOT NULL CONSTRAINT [DF_sale_discount_rate] DEFAULT (1.00),
        [point_deduction_amount] DECIMAL(10,2) NOT NULL CONSTRAINT [DF_sale_point_deduction_amount] DEFAULT (0),
        [paid_amount] DECIMAL(10,2) NOT NULL,
        CONSTRAINT [PK_sale] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_sale_no] UNIQUE ([no]),
        CONSTRAINT [CK_sale_status] CHECK ([status] IN (N'已付',N'部分退款',N'已全退')),
        CONSTRAINT [CK_sale_card] CHECK ((card_level IS NULL AND discount_rate=1 AND point_deduction_amount=0) OR (card_level IS NOT NULL AND card_level IN (N'银卡',N'金卡') AND member_phone IS NOT NULL)),
        CONSTRAINT [CK_sale_rate] CHECK (discount_rate > 0 AND discount_rate <= 1),
        CONSTRAINT [CK_sale_amount] CHECK (subtotal_amount >= 0 AND point_deduction_amount >= 0 AND paid_amount >= 0 AND point_deduction_amount <= FLOOR(ROUND(subtotal_amount*discount_rate,2)*0.20*100)/100.0 AND paid_amount = ROUND(subtotal_amount*discount_rate,2)-point_deduction_amount),
        CONSTRAINT [CK_sale_no_text] CHECK (LEN(LTRIM(RTRIM([no]))) > 0),
        CONSTRAINT [CK_sale_cashier_by_text] CHECK (LEN(LTRIM(RTRIM([cashier_by]))) > 0),
        CONSTRAINT [CK_sale_cashier_by_phone] CHECK ([cashier_by] IS NULL OR (LEN([cashier_by])=11 AND [cashier_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_sale_member_phone_phone] CHECK ([member_phone] IS NULL OR (LEN([member_phone])=11 AND [member_phone] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );

    -- sale_item：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[sale_item] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [sale_id] BIGINT NOT NULL,
        [goods_id] BIGINT NOT NULL,
        [quantity] INT NOT NULL,
        [unit_price] DECIMAL(10,2) NOT NULL,
        CONSTRAINT [PK_sale_item] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_sale_item_sale_id_goods_id] UNIQUE ([sale_id], [goods_id]),
        CONSTRAINT [CK_sale_item_quantity] CHECK (quantity > 0),
        CONSTRAINT [CK_sale_item_price] CHECK (unit_price >= 0)
    );

    -- goods_return：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[goods_return] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [no] VARCHAR(20) NOT NULL,
        [sale_id] BIGINT NOT NULL,
        [refund_amount] DECIMAL(10,2) NOT NULL,
        [handled_by] VARCHAR(11) NOT NULL,
        [handled_at] DATETIME2 NOT NULL CONSTRAINT [DF_goods_return_handled_at] DEFAULT (SYSDATETIME()),
        CONSTRAINT [PK_goods_return] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_goods_return_no] UNIQUE ([no]),
        CONSTRAINT [CK_goods_return_amount] CHECK (refund_amount >= 0),
        CONSTRAINT [CK_goods_return_no_text] CHECK (LEN(LTRIM(RTRIM([no]))) > 0),
        CONSTRAINT [CK_goods_return_handled_by_text] CHECK (LEN(LTRIM(RTRIM([handled_by]))) > 0),
        CONSTRAINT [CK_goods_return_handled_by_phone] CHECK ([handled_by] IS NULL OR (LEN([handled_by])=11 AND [handled_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );

    -- goods_return_item：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[goods_return_item] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [return_id] BIGINT NOT NULL,
        [sale_item_id] BIGINT NOT NULL,
        [quantity] INT NOT NULL,
        [refund_amount] DECIMAL(10,2) NOT NULL,
        CONSTRAINT [PK_goods_return_item] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_goods_return_item_return_id_sale_item_id] UNIQUE ([return_id], [sale_item_id]),
        CONSTRAINT [CK_goods_return_item_quantity] CHECK (quantity > 0),
        CONSTRAINT [CK_goods_return_item_amount] CHECK (refund_amount >= 0)
    );

    -- stock_movement：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[stock_movement] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [goods_id] BIGINT NOT NULL,
        [change_type] NVARCHAR(10) NOT NULL,
        [quantity] INT NOT NULL,
        [note] NVARCHAR(200) NULL,
        [changed_by] VARCHAR(11) NOT NULL,
        [changed_at] DATETIME2 NOT NULL CONSTRAINT [DF_stock_movement_changed_at] DEFAULT (SYSDATETIME()),
        [request_id] BIGINT NULL,
        [sale_id] BIGINT NULL,
        [return_item_id] BIGINT NULL,
        CONSTRAINT [PK_stock_movement] PRIMARY KEY ([id]),
        CONSTRAINT [CK_stock_movement_source] CHECK ((change_type=N'购入' AND quantity>0 AND request_id IS NOT NULL AND sale_id IS NULL AND return_item_id IS NULL) OR (change_type=N'卖出' AND quantity<0 AND sale_id IS NOT NULL AND request_id IS NULL AND return_item_id IS NULL) OR (change_type=N'退货' AND quantity>0 AND return_item_id IS NOT NULL AND request_id IS NULL AND sale_id IS NULL) OR (change_type=N'损坏' AND quantity<0 AND request_id IS NULL AND sale_id IS NULL AND return_item_id IS NULL AND note IS NOT NULL AND LEN(LTRIM(RTRIM(note)))>0)),
        CONSTRAINT [CK_stock_movement_changed_by_text] CHECK (LEN(LTRIM(RTRIM([changed_by]))) > 0),
        CONSTRAINT [CK_stock_movement_changed_by_phone] CHECK ([changed_by] IS NULL OR (LEN([changed_by])=11 AND [changed_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );

    -- point_movement：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[point_movement] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [member_phone] VARCHAR(11) NOT NULL,
        [change_type] NVARCHAR(10) NOT NULL,
        [points] INT NOT NULL,
        [sale_id] BIGINT NULL,
        [return_id] BIGINT NULL,
        [changed_by] VARCHAR(11) NOT NULL,
        [changed_at] DATETIME2 NOT NULL CONSTRAINT [DF_point_movement_changed_at] DEFAULT (SYSDATETIME()),
        CONSTRAINT [PK_point_movement] PRIMARY KEY ([id]),
        CONSTRAINT [CK_point_movement_kind] CHECK ((change_type=N'消费获得' AND points>0 AND return_id IS NULL) OR (change_type=N'抵扣使用' AND points<0 AND return_id IS NULL) OR (change_type=N'退货回滚' AND points<0 AND return_id IS NOT NULL)),
        CONSTRAINT [CK_point_movement_member_phone_text] CHECK (LEN(LTRIM(RTRIM([member_phone]))) > 0),
        CONSTRAINT [CK_point_movement_member_phone_phone] CHECK ([member_phone] IS NULL OR (LEN([member_phone])=11 AND [member_phone] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_point_movement_changed_by_text] CHECK (LEN(LTRIM(RTRIM([changed_by]))) > 0),
        CONSTRAINT [CK_point_movement_changed_by_phone] CHECK ([changed_by] IS NULL OR (LEN([changed_by])=11 AND [changed_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );

    -- fund_flow：字段含义保存在 MS_Description 扩展属性中。
    CREATE TABLE dbo.[fund_flow] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [amount] DECIMAL(10,2) NOT NULL,
        [direction] NVARCHAR(2) NOT NULL,
        [reason_type] NVARCHAR(10) NOT NULL,
        [sale_id] BIGINT NULL,
        [return_id] BIGINT NULL,
        [request_id] BIGINT NULL,
        [member_phone] VARCHAR(11) NULL,
        [fund_before] DECIMAL(12,2) NOT NULL,
        [fund_after] DECIMAL(12,2) NOT NULL,
        [recorded_by] VARCHAR(11) NOT NULL,
        [recorded_at] DATETIME2 NOT NULL CONSTRAINT [DF_fund_flow_recorded_at] DEFAULT (SYSDATETIME()),
        CONSTRAINT [PK_fund_flow] PRIMARY KEY ([id]),
        CONSTRAINT [CK_fund_flow_amount] CHECK (amount > 0 AND fund_before >= 0),
        CONSTRAINT [CK_fund_flow_balance] CHECK ((direction=N'收' AND fund_after=fund_before+amount) OR (direction=N'付' AND fund_after=fund_before-amount)),
        CONSTRAINT [CK_fund_flow_source] CHECK ((reason_type=N'销售收款' AND direction=N'收' AND sale_id IS NOT NULL AND return_id IS NULL AND request_id IS NULL AND member_phone IS NULL) OR (reason_type=N'采购付款' AND direction=N'付' AND request_id IS NOT NULL AND sale_id IS NULL AND return_id IS NULL AND member_phone IS NULL) OR (reason_type=N'退货退款' AND direction=N'付' AND sale_id IS NOT NULL AND return_id IS NOT NULL AND request_id IS NULL AND member_phone IS NULL) OR (reason_type=N'办卡费' AND direction=N'收' AND member_phone IS NOT NULL AND sale_id IS NULL AND return_id IS NULL AND request_id IS NULL) OR (reason_type IN (N'注资',N'提现') AND sale_id IS NULL AND return_id IS NULL AND request_id IS NULL AND member_phone IS NULL AND ((reason_type=N'注资' AND direction=N'收') OR (reason_type=N'提现' AND direction=N'付')))),
        CONSTRAINT [CK_fund_flow_member_phone_phone] CHECK ([member_phone] IS NULL OR (LEN([member_phone])=11 AND [member_phone] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%')),
        CONSTRAINT [CK_fund_flow_recorded_by_text] CHECK (LEN(LTRIM(RTRIM([recorded_by]))) > 0),
        CONSTRAINT [CK_fund_flow_recorded_by_phone] CHECK ([recorded_by] IS NULL OR (LEN([recorded_by])=11 AND [recorded_by] COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^0-9]%'))
    );
    ALTER TABLE dbo.[employee] ADD CONSTRAINT [FK_employee_created_by] FOREIGN KEY ([created_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[employee] ADD CONSTRAINT [FK_employee_updated_by] FOREIGN KEY ([updated_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[supplier] ADD CONSTRAINT [FK_supplier_created_by] FOREIGN KEY ([created_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[card_type] ADD CONSTRAINT [FK_card_type_set_by] FOREIGN KEY ([set_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[goods] ADD CONSTRAINT [FK_goods_book_isbn] FOREIGN KEY ([book_isbn]) REFERENCES dbo.[book] ([isbn]);
    ALTER TABLE dbo.[goods] ADD CONSTRAINT [FK_goods_toy_code] FOREIGN KEY ([toy_code]) REFERENCES dbo.[toy] ([inner_code]);
    ALTER TABLE dbo.[goods] ADD CONSTRAINT [FK_goods_created_by] FOREIGN KEY ([created_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[goods] ADD CONSTRAINT [FK_goods_updated_by] FOREIGN KEY ([updated_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[supplier_quote] ADD CONSTRAINT [FK_supplier_quote_supplier_id] FOREIGN KEY ([supplier_id]) REFERENCES dbo.[supplier] ([id]);
    ALTER TABLE dbo.[supplier_quote] ADD CONSTRAINT [FK_supplier_quote_goods_id] FOREIGN KEY ([goods_id]) REFERENCES dbo.[goods] ([id]);
    ALTER TABLE dbo.[supplier_quote] ADD CONSTRAINT [FK_supplier_quote_reported_by] FOREIGN KEY ([reported_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[member] ADD CONSTRAINT [FK_member_card_level] FOREIGN KEY ([card_level]) REFERENCES dbo.[card_type] ([level]);
    ALTER TABLE dbo.[member] ADD CONSTRAINT [FK_member_opened_by] FOREIGN KEY ([opened_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[member] ADD CONSTRAINT [FK_member_updated_by] FOREIGN KEY ([updated_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[purchase_request] ADD CONSTRAINT [FK_purchase_request_supplier_id] FOREIGN KEY ([supplier_id]) REFERENCES dbo.[supplier] ([id]);
    ALTER TABLE dbo.[purchase_request] ADD CONSTRAINT [FK_purchase_request_created_by] FOREIGN KEY ([created_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[purchase_request] ADD CONSTRAINT [FK_purchase_request_submitted_by] FOREIGN KEY ([submitted_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[purchase_request] ADD CONSTRAINT [FK_purchase_request_approved_by] FOREIGN KEY ([approved_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[purchase_request] ADD CONSTRAINT [FK_purchase_request_cancelled_by] FOREIGN KEY ([cancelled_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[purchase_request_item] ADD CONSTRAINT [FK_purchase_request_item_request_id] FOREIGN KEY ([request_id]) REFERENCES dbo.[purchase_request] ([id]);
    ALTER TABLE dbo.[purchase_request_item] ADD CONSTRAINT [FK_purchase_request_item_goods_id] FOREIGN KEY ([goods_id]) REFERENCES dbo.[goods] ([id]);
    ALTER TABLE dbo.[reservation] ADD CONSTRAINT [FK_reservation_cancelled_by_employee] FOREIGN KEY ([cancelled_by_employee]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[reservation_item] ADD CONSTRAINT [FK_reservation_item_reservation_id] FOREIGN KEY ([reservation_id]) REFERENCES dbo.[reservation] ([id]);
    ALTER TABLE dbo.[reservation_item] ADD CONSTRAINT [FK_reservation_item_goods_id] FOREIGN KEY ([goods_id]) REFERENCES dbo.[goods] ([id]);
    ALTER TABLE dbo.[sale] ADD CONSTRAINT [FK_sale_cashier_by] FOREIGN KEY ([cashier_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[sale] ADD CONSTRAINT [FK_sale_member_phone] FOREIGN KEY ([member_phone]) REFERENCES dbo.[member] ([phone]);
    ALTER TABLE dbo.[sale] ADD CONSTRAINT [FK_sale_reservation_id] FOREIGN KEY ([reservation_id]) REFERENCES dbo.[reservation] ([id]);
    ALTER TABLE dbo.[sale_item] ADD CONSTRAINT [FK_sale_item_sale_id] FOREIGN KEY ([sale_id]) REFERENCES dbo.[sale] ([id]);
    ALTER TABLE dbo.[sale_item] ADD CONSTRAINT [FK_sale_item_goods_id] FOREIGN KEY ([goods_id]) REFERENCES dbo.[goods] ([id]);
    ALTER TABLE dbo.[goods_return] ADD CONSTRAINT [FK_goods_return_sale_id] FOREIGN KEY ([sale_id]) REFERENCES dbo.[sale] ([id]);
    ALTER TABLE dbo.[goods_return] ADD CONSTRAINT [FK_goods_return_handled_by] FOREIGN KEY ([handled_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[goods_return_item] ADD CONSTRAINT [FK_goods_return_item_return_id] FOREIGN KEY ([return_id]) REFERENCES dbo.[goods_return] ([id]);
    ALTER TABLE dbo.[goods_return_item] ADD CONSTRAINT [FK_goods_return_item_sale_item_id] FOREIGN KEY ([sale_item_id]) REFERENCES dbo.[sale_item] ([id]);
    ALTER TABLE dbo.[stock_movement] ADD CONSTRAINT [FK_stock_movement_goods_id] FOREIGN KEY ([goods_id]) REFERENCES dbo.[goods] ([id]);
    ALTER TABLE dbo.[stock_movement] ADD CONSTRAINT [FK_stock_movement_changed_by] FOREIGN KEY ([changed_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[stock_movement] ADD CONSTRAINT [FK_stock_movement_request_id] FOREIGN KEY ([request_id]) REFERENCES dbo.[purchase_request] ([id]);
    ALTER TABLE dbo.[stock_movement] ADD CONSTRAINT [FK_stock_movement_sale_id] FOREIGN KEY ([sale_id]) REFERENCES dbo.[sale] ([id]);
    ALTER TABLE dbo.[stock_movement] ADD CONSTRAINT [FK_stock_movement_return_item_id] FOREIGN KEY ([return_item_id]) REFERENCES dbo.[goods_return_item] ([id]);
    ALTER TABLE dbo.[point_movement] ADD CONSTRAINT [FK_point_movement_member_phone] FOREIGN KEY ([member_phone]) REFERENCES dbo.[member] ([phone]);
    ALTER TABLE dbo.[point_movement] ADD CONSTRAINT [FK_point_movement_sale_id] FOREIGN KEY ([sale_id]) REFERENCES dbo.[sale] ([id]);
    ALTER TABLE dbo.[point_movement] ADD CONSTRAINT [FK_point_movement_return_id] FOREIGN KEY ([return_id]) REFERENCES dbo.[goods_return] ([id]);
    ALTER TABLE dbo.[point_movement] ADD CONSTRAINT [FK_point_movement_changed_by] FOREIGN KEY ([changed_by]) REFERENCES dbo.[employee] ([phone]);
    ALTER TABLE dbo.[fund_flow] ADD CONSTRAINT [FK_fund_flow_sale_id] FOREIGN KEY ([sale_id]) REFERENCES dbo.[sale] ([id]);
    ALTER TABLE dbo.[fund_flow] ADD CONSTRAINT [FK_fund_flow_return_id] FOREIGN KEY ([return_id]) REFERENCES dbo.[goods_return] ([id]);
    ALTER TABLE dbo.[fund_flow] ADD CONSTRAINT [FK_fund_flow_request_id] FOREIGN KEY ([request_id]) REFERENCES dbo.[purchase_request] ([id]);
    ALTER TABLE dbo.[fund_flow] ADD CONSTRAINT [FK_fund_flow_member_phone] FOREIGN KEY ([member_phone]) REFERENCES dbo.[member] ([phone]);
    ALTER TABLE dbo.[fund_flow] ADD CONSTRAINT [FK_fund_flow_recorded_by] FOREIGN KEY ([recorded_by]) REFERENCES dbo.[employee] ([phone]);

    -- 字段含义来自正式数据字典。
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'手机号 —— 同时就是登录账号（A18），所有留痕都指向它', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'employee', @level2type=N'COLUMN', @level2name=N'phone';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'姓名', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'employee', @level2type=N'COLUMN', @level2name=N'name';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'岗位', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'employee', @level2type=N'COLUMN', @level2name=N'role';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'账号维护人（R-22 §4「发账号要有出处」）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'employee', @level2type=N'COLUMN', @level2name=N'created_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'创建时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'employee', @level2type=N'COLUMN', @level2name=N'created_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次修改岗位或账号信息的店长', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'employee', @level2type=N'COLUMN', @level2name=N'updated_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次修改时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'employee', @level2type=N'COLUMN', @level2name=N'updated_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ISBN —— 图书的标识（A1），也是认书 / 查书的入口', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'book', @level2type=N'COLUMN', @level2name=N'isbn';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'作者（A2）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'book', @level2type=N'COLUMN', @level2name=N'author';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'出版社（存文本，不单独建表）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'book', @level2type=N'COLUMN', @level2name=N'publisher';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'页数（A2）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'book', @level2type=N'COLUMN', @level2name=N'page_count';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'内部编码 —— 文创的标识（A1），也是认货 / 查货的入口', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'toy', @level2type=N'COLUMN', @level2name=N'inner_code';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'规格 / 款式（A2）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'toy', @level2type=N'COLUMN', @level2name=N'spec';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'供应商标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'供应商名称 —— 只要一个名字（A7）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier', @level2type=N'COLUMN', @level2name=N'name';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'建立供应商档案的库管', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier', @level2type=N'COLUMN', @level2name=N'created_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'建档时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier', @level2type=N'COLUMN', @level2name=N'created_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'当前档位名（A16、R-17）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'card_type', @level2type=N'COLUMN', @level2name=N'level';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'办卡、换卡时的当前收费基准', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'card_type', @level2type=N'COLUMN', @level2name=N'card_fee';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'结算时的当前折扣率，成交时复制到 sale', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'card_type', @level2type=N'COLUMN', @level2name=N'discount_rate';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次设定人（R-22）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'card_type', @level2type=N'COLUMN', @level2name=N'set_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次设定时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'card_type', @level2type=N'COLUMN', @level2name=N'set_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'商品标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'商品类别（A1）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'category';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'商品名称（书名 / 文创名）（A2）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'name';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'指到图书细节（A1 / A2）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'book_isbn';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'指到文创细节（A1 / A2）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'toy_code';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'店长的上架决定（R-1）；未上架商品不对顾客展示', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'on_shelf';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'当前售价（A4、R-1）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'price';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'在架总量（含已订未取）（A5、R-21）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'stock_total';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'已订量（A5、R-23）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'reserved_qty';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'建档的库管（R-22）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'created_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'建档时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'created_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次定价、调价或上下架的店长', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'updated_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次基础信息变更时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods', @level2type=N'COLUMN', @level2name=N'updated_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'哪一家报的（A7）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier_quote', @level2type=N'COLUMN', @level2name=N'supplier_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'报的是哪个商品（A7）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier_quote', @level2type=N'COLUMN', @level2name=N'goods_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'当前报价（新报价覆盖旧报价，不留历史）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier_quote', @level2type=N'COLUMN', @level2name=N'quote_amount';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'上报人（A7）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier_quote', @level2type=N'COLUMN', @level2name=N'reported_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'上报时刻（定价时要判断这个价还新不新）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'supplier_quote', @level2type=N'COLUMN', @level2name=N'reported_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'手机号 —— 会员记录的唯一标识（A13）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'member', @level2type=N'COLUMN', @level2name=N'phone';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'当前持有的卡档位（R-17 / R-24）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'member', @level2type=N'COLUMN', @level2name=N'card_level';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'开卡人（R-22）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'member', @level2type=N'COLUMN', @level2name=N'opened_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'开卡时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'member', @level2type=N'COLUMN', @level2name=N'opened_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次换卡的收银员；积分变动另见流水', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'member', @level2type=N'COLUMN', @level2name=N'updated_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最近一次换卡时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'member', @level2type=N'COLUMN', @level2name=N'updated_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'权益到期日，含当天；年限、续期与闰日按 R-18、R-24', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'member', @level2type=N'COLUMN', @level2name=N'expires_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'积分余额', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'member', @level2type=N'COLUMN', @level2name=N'points_balance';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'单据标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'单号（A8、R-19）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'no';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'向哪一家买（一张单只对应一家，R-6）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'supplier_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'推进到哪一步', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'status';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'建立草稿的库管', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'created_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'草稿建立时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'created_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'提交人（库管）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'submitted_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'提交时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'submitted_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'审批人（店长）（R-22 §4）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'approved_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'审批时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'approved_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'取消申请的员工', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'cancelled_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'取消时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request', @level2type=N'COLUMN', @level2name=N'cancelled_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'行标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request_item', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'属于哪张单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request_item', @level2type=N'COLUMN', @level2name=N'request_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'申请的是哪个商品', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request_item', @level2type=N'COLUMN', @level2name=N'goods_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'申请数量，也是一次正常入库数量（R-26）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request_item', @level2type=N'COLUMN', @level2name=N'request_qty';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'该批进价（进价随批次不同，所以按批记，A8）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'purchase_request_item', @level2type=N'COLUMN', @level2name=N'unit_cost';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'预订标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'预定码 —— 取货唯一凭证；它同时就是这张单的单号（R-19）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation', @level2type=N'COLUMN', @level2name=N'code';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'下单手机号（可与会员手机号不同：订的人不一定是会员，A10）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation', @level2type=N'COLUMN', @level2name=N'phone';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'预订状态（过期由系统自动置）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation', @level2type=N'COLUMN', @level2name=N'status';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'下单时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation', @level2type=N'COLUMN', @level2name=N'created_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'有效期', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation', @level2type=N'COLUMN', @level2name=N'expires_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'代取消的收银员', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation', @level2type=N'COLUMN', @level2name=N'cancelled_by_employee';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'取消时刻；若无代取消员工，则由下单手机号持有人自行取消', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation', @level2type=N'COLUMN', @level2name=N'cancelled_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'行标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation_item', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'属于哪张预订', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation_item', @level2type=N'COLUMN', @level2name=N'reservation_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'订了哪个商品', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation_item', @level2type=N'COLUMN', @level2name=N'goods_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'数量（有效预订的行数量之和 = 商品的 reserved_qty，R-23）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'reservation_item', @level2type=N'COLUMN', @level2name=N'quantity';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'单据标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'单号（A9、R-19）—— 顾客凭它认单（R-20）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'no';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'单据状态', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'status';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'收银员（R-22 §4）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'cashier_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'成交时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'sold_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'成交时的会员卡档位快照（R-8）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'card_level';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'这单是谁买的：挂会员（A9）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'member_phone';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'这单是谁买的：挂预订（取货销售，A9）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'reservation_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'原始总额（折扣前小计 S，成交快照）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'subtotal_amount';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'成交时从 card_type 读取并保存的折扣率快照（R-8、R-17）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'discount_rate';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'积分抵扣金额（D）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'point_deduction_amount';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'成交金额（实付）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale', @level2type=N'COLUMN', @level2name=N'paid_amount';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'行标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale_item', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'属于哪张单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale_item', @level2type=N'COLUMN', @level2name=N'sale_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'卖了哪个商品', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale_item', @level2type=N'COLUMN', @level2name=N'goods_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'数量', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale_item', @level2type=N'COLUMN', @level2name=N'quantity';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'成交价（快照 —— 事后再调价也改不动它）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'sale_item', @level2type=N'COLUMN', @level2name=N'unit_price';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'退货标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'退货单号，供退款与核对使用', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return', @level2type=N'COLUMN', @level2name=N'no';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'退的是哪一单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return', @level2type=N'COLUMN', @level2name=N'sale_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'本次退款总额', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return', @level2type=N'COLUMN', @level2name=N'refund_amount';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'受理人（R-22 §4）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return', @level2type=N'COLUMN', @level2name=N'handled_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'受理时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return', @level2type=N'COLUMN', @level2name=N'handled_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'退货明细标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return_item', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'所属退货单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return_item', @level2type=N'COLUMN', @level2name=N'return_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'原销售明细；必须属于退货单所指销售单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return_item', @level2type=N'COLUMN', @level2name=N'sale_item_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'本次退回数量', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return_item', @level2type=N'COLUMN', @level2name=N'quantity';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'该行退款额', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'goods_return_item', @level2type=N'COLUMN', @level2name=N'refund_amount';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'变动标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'变动的是哪件商品', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'goods_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'这次变动属于哪一类', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'change_type';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'变了多少', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'quantity';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'为什么变（R-3 报损必填文字原因）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'note';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'操作人 —— 做这次变动的那个人（收货 / 报损 / 卖出 / 退货回收 的经办人）（R-22）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'changed_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'变动时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'changed_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'这次入库是那张采购单收的货', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'request_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'这次出库是那张销售单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'sale_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'这次回收入库对应哪条退货明细', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'stock_movement', @level2type=N'COLUMN', @level2name=N'return_item_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'变动标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'point_movement', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'记在谁头上', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'point_movement', @level2type=N'COLUMN', @level2name=N'member_phone';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'为什么变', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'point_movement', @level2type=N'COLUMN', @level2name=N'change_type';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'变了多少分', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'point_movement', @level2type=N'COLUMN', @level2name=N'points';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'引起它的那张销售单（退货回滚要能指回原单，R-25）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'point_movement', @level2type=N'COLUMN', @level2name=N'sale_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'本次积分回滚对应的退货单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'point_movement', @level2type=N'COLUMN', @level2name=N'return_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'操作人 —— 做这件事的人（退货回滚记该次退货的受理人）（R-22）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'point_movement', @level2type=N'COLUMN', @level2name=N'changed_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'变动时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'point_movement', @level2type=N'COLUMN', @level2name=N'changed_at';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'流水标识', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'这笔钱的金额', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'amount';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'钱进来还是出去（R-15 靠它区分收支）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'direction';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'事由类别（A17）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'reason_type';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'收款的销售单；退款时为退货单指向的原销售单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'sale_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'本次退款所对应的退货单', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'return_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'挂在哪张采购单上', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'request_id';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'办的是哪位会员的卡（B8）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'member_phone';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'收付前的资金总额', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'fund_before';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'收付后的资金总额（= 店内资金总额，A17、R-15）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'fund_after';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'登记人 —— 做这笔业务的人（R-22 §4）', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'recorded_by';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'收付时刻', @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'fund_flow', @level2type=N'COLUMN', @level2name=N'recorded_at';
    COMMIT;
    PRINT N'schema.sql PASS: 19 tables, 47 foreign keys.';
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
