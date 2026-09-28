:On Error exit
-- 使用 SQLCMD 模式；DatabaseName 由调用者指定，例：sqlcmd -v DatabaseName=ShiguangBookstoreWeek3
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51009, N'请在无外层事务的新查询窗口执行本脚本。', 1;
-- 2026-09-20 收盘截面。重复执行时，已存在的表须与样例完全一致，否则整批回滚。
-- 不按当前日期自动过期历史样例，也不删除或覆盖已有记录。
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @seed_employee TABLE ([phone] VARCHAR(11) NOT NULL, [name] NVARCHAR(20) NOT NULL, [role] NVARCHAR(10) NOT NULL, [created_by] VARCHAR(11) NOT NULL, [created_at] DATETIME2 NOT NULL, [updated_by] VARCHAR(11) NULL, [updated_at] DATETIME2 NULL);
    INSERT INTO @seed_employee ([phone], [name], [role], [created_by], [created_at], [updated_by], [updated_at]) VALUES
        (N'13800000001', N'林泽群', N'店长', N'13800000001', N'2026-09-01T09:00:00', NULL, NULL),
        (N'13800000002', N'黄智亮', N'库管', N'13800000001', N'2026-09-01T09:10:00', NULL, NULL),
        (N'13800000003', N'梁宇聪', N'收银员', N'13800000001', N'2026-09-01T09:20:00', NULL, NULL),
        (N'13800000004', N'陈思远', N'收银员', N'13800000001', N'2026-09-02T09:00:00', NULL, NULL);
    IF NOT EXISTS (SELECT 1 FROM dbo.[employee])
    BEGIN
        INSERT INTO dbo.[employee] ([phone], [name], [role], [created_by], [created_at], [updated_by], [updated_at]) SELECT [phone], [name], [role], [created_by], [created_at], [updated_by], [updated_at] FROM @seed_employee;
    END
    ELSE IF EXISTS (SELECT [phone], [name], [role], [created_by], [created_at], [updated_by], [updated_at] FROM dbo.[employee] EXCEPT SELECT [phone], [name], [role], [created_by], [created_at], [updated_by], [updated_at] FROM @seed_employee)
         OR EXISTS (SELECT [phone], [name], [role], [created_by], [created_at], [updated_by], [updated_at] FROM @seed_employee EXCEPT SELECT [phone], [name], [role], [created_by], [created_at], [updated_by], [updated_at] FROM dbo.[employee])
        THROW 51001, N'employee 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_book TABLE ([isbn] VARCHAR(17) NOT NULL, [author] NVARCHAR(100) NOT NULL, [publisher] NVARCHAR(100) NOT NULL, [page_count] INT NOT NULL);
    INSERT INTO @seed_book ([isbn], [author], [publisher], [page_count]) VALUES
        (N'9787506365437', N'余华', N'作家出版社', 191),
        (N'9787544253994', N'加西亚·马尔克斯', N'南海出版公司', 360);
    IF NOT EXISTS (SELECT 1 FROM dbo.[book])
    BEGIN
        INSERT INTO dbo.[book] ([isbn], [author], [publisher], [page_count]) SELECT [isbn], [author], [publisher], [page_count] FROM @seed_book;
    END
    ELSE IF EXISTS (SELECT [isbn], [author], [publisher], [page_count] FROM dbo.[book] EXCEPT SELECT [isbn], [author], [publisher], [page_count] FROM @seed_book)
         OR EXISTS (SELECT [isbn], [author], [publisher], [page_count] FROM @seed_book EXCEPT SELECT [isbn], [author], [publisher], [page_count] FROM dbo.[book])
        THROW 51001, N'book 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_toy TABLE ([inner_code] VARCHAR(20) NOT NULL, [spec] NVARCHAR(100) NOT NULL);
    INSERT INTO @seed_toy ([inner_code], [spec]) VALUES
        (N'SP-BAG-001', N'38×42cm 米白帆布'),
        (N'SP-MARK-002', N'5×15cm 黄铜');
    IF NOT EXISTS (SELECT 1 FROM dbo.[toy])
    BEGIN
        INSERT INTO dbo.[toy] ([inner_code], [spec]) SELECT [inner_code], [spec] FROM @seed_toy;
    END
    ELSE IF EXISTS (SELECT [inner_code], [spec] FROM dbo.[toy] EXCEPT SELECT [inner_code], [spec] FROM @seed_toy)
         OR EXISTS (SELECT [inner_code], [spec] FROM @seed_toy EXCEPT SELECT [inner_code], [spec] FROM dbo.[toy])
        THROW 51001, N'toy 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_supplier TABLE ([id] BIGINT NOT NULL, [name] NVARCHAR(100) NOT NULL, [created_by] VARCHAR(11) NOT NULL, [created_at] DATETIME2 NOT NULL);
    INSERT INTO @seed_supplier ([id], [name], [created_by], [created_at]) VALUES
        (1, N'博文图书批发', N'13800000002', N'2026-09-04T09:20:00'),
        (2, N'文创源', N'13800000002', N'2026-09-04T09:25:00'),
        (3, N'华南图书批发', N'13800000002', N'2026-09-04T09:30:00');
    IF NOT EXISTS (SELECT 1 FROM dbo.[supplier])
    BEGIN
        SET IDENTITY_INSERT dbo.[supplier] ON;
        INSERT INTO dbo.[supplier] ([id], [name], [created_by], [created_at]) SELECT [id], [name], [created_by], [created_at] FROM @seed_supplier;
        SET IDENTITY_INSERT dbo.[supplier] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [name], [created_by], [created_at] FROM dbo.[supplier] EXCEPT SELECT [id], [name], [created_by], [created_at] FROM @seed_supplier)
         OR EXISTS (SELECT [id], [name], [created_by], [created_at] FROM @seed_supplier EXCEPT SELECT [id], [name], [created_by], [created_at] FROM dbo.[supplier])
        THROW 51001, N'supplier 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_card_type TABLE ([level] NVARCHAR(10) NOT NULL, [card_fee] DECIMAL(10,2) NOT NULL, [discount_rate] DECIMAL(3,2) NOT NULL, [set_by] VARCHAR(11) NOT NULL, [set_at] DATETIME2 NOT NULL);
    INSERT INTO @seed_card_type ([level], [card_fee], [discount_rate], [set_by], [set_at]) VALUES
        (N'银卡', 20.00, 0.95, N'13800000001', N'2026-09-01T09:00:00'),
        (N'金卡', 50.00, 0.90, N'13800000001', N'2026-09-01T09:00:00');
    IF NOT EXISTS (SELECT 1 FROM dbo.[card_type])
    BEGIN
        INSERT INTO dbo.[card_type] ([level], [card_fee], [discount_rate], [set_by], [set_at]) SELECT [level], [card_fee], [discount_rate], [set_by], [set_at] FROM @seed_card_type;
    END
    ELSE IF EXISTS (SELECT [level], [card_fee], [discount_rate], [set_by], [set_at] FROM dbo.[card_type] EXCEPT SELECT [level], [card_fee], [discount_rate], [set_by], [set_at] FROM @seed_card_type)
         OR EXISTS (SELECT [level], [card_fee], [discount_rate], [set_by], [set_at] FROM @seed_card_type EXCEPT SELECT [level], [card_fee], [discount_rate], [set_by], [set_at] FROM dbo.[card_type])
        THROW 51001, N'card_type 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_goods TABLE ([id] BIGINT NOT NULL, [category] NVARCHAR(10) NOT NULL, [name] NVARCHAR(100) NOT NULL, [book_isbn] VARCHAR(17) NULL, [toy_code] VARCHAR(20) NULL, [on_shelf] BIT NOT NULL, [price] DECIMAL(10,2) NULL, [stock_total] INT NOT NULL, [reserved_qty] INT NOT NULL, [created_by] VARCHAR(11) NOT NULL, [created_at] DATETIME2 NOT NULL, [updated_by] VARCHAR(11) NULL, [updated_at] DATETIME2 NULL);
    INSERT INTO @seed_goods ([id], [category], [name], [book_isbn], [toy_code], [on_shelf], [price], [stock_total], [reserved_qty], [created_by], [created_at], [updated_by], [updated_at]) VALUES
        (1, N'图书', N'活着', N'9787506365437', NULL, 1, 39.00, 6, 6, N'13800000002', N'2026-09-04T09:00:00', N'13800000001', N'2026-09-05T09:20:00'),
        (2, N'图书', N'百年孤独', N'9787544253994', NULL, 1, 49.00, 0, 0, N'13800000002', N'2026-09-04T09:05:00', N'13800000001', N'2026-09-05T09:25:00'),
        (3, N'文创', N'拾光帆布袋', NULL, N'SP-BAG-001', 1, 19.00, 10, 0, N'13800000002', N'2026-09-04T09:10:00', N'13800000001', N'2026-09-05T09:30:00'),
        (4, N'文创', N'拾光书签', NULL, N'SP-MARK-002', 1, 6.00, 19, 0, N'13800000002', N'2026-09-04T09:15:00', N'13800000001', N'2026-09-05T09:35:00');
    IF NOT EXISTS (SELECT 1 FROM dbo.[goods])
    BEGIN
        SET IDENTITY_INSERT dbo.[goods] ON;
        INSERT INTO dbo.[goods] ([id], [category], [name], [book_isbn], [toy_code], [on_shelf], [price], [stock_total], [reserved_qty], [created_by], [created_at], [updated_by], [updated_at]) SELECT [id], [category], [name], [book_isbn], [toy_code], [on_shelf], [price], [stock_total], [reserved_qty], [created_by], [created_at], [updated_by], [updated_at] FROM @seed_goods;
        SET IDENTITY_INSERT dbo.[goods] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [category], [name], [book_isbn], [toy_code], [on_shelf], [price], [stock_total], [reserved_qty], [created_by], [created_at], [updated_by], [updated_at] FROM dbo.[goods] EXCEPT SELECT [id], [category], [name], [book_isbn], [toy_code], [on_shelf], [price], [stock_total], [reserved_qty], [created_by], [created_at], [updated_by], [updated_at] FROM @seed_goods)
         OR EXISTS (SELECT [id], [category], [name], [book_isbn], [toy_code], [on_shelf], [price], [stock_total], [reserved_qty], [created_by], [created_at], [updated_by], [updated_at] FROM @seed_goods EXCEPT SELECT [id], [category], [name], [book_isbn], [toy_code], [on_shelf], [price], [stock_total], [reserved_qty], [created_by], [created_at], [updated_by], [updated_at] FROM dbo.[goods])
        THROW 51001, N'goods 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_supplier_quote TABLE ([supplier_id] BIGINT NOT NULL, [goods_id] BIGINT NOT NULL, [quote_amount] DECIMAL(10,2) NOT NULL, [reported_by] VARCHAR(11) NOT NULL, [reported_at] DATETIME2 NOT NULL);
    INSERT INTO @seed_supplier_quote ([supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at]) VALUES
        (1, 1, 22.00, N'13800000002', N'2026-09-04T10:00:00'),
        (1, 2, 26.50, N'13800000002', N'2026-09-04T10:05:00'),
        (2, 3, 8.00, N'13800000002', N'2026-09-04T10:10:00'),
        (2, 4, 2.50, N'13800000002', N'2026-09-04T10:15:00'),
        (3, 1, 24.00, N'13800000002', N'2026-09-04T10:20:00');
    IF NOT EXISTS (SELECT 1 FROM dbo.[supplier_quote])
    BEGIN
        INSERT INTO dbo.[supplier_quote] ([supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at]) SELECT [supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at] FROM @seed_supplier_quote;
    END
    ELSE IF EXISTS (SELECT [supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at] FROM dbo.[supplier_quote] EXCEPT SELECT [supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at] FROM @seed_supplier_quote)
         OR EXISTS (SELECT [supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at] FROM @seed_supplier_quote EXCEPT SELECT [supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at] FROM dbo.[supplier_quote])
        THROW 51001, N'supplier_quote 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_member TABLE ([phone] VARCHAR(11) NOT NULL, [card_level] NVARCHAR(10) NOT NULL, [opened_by] VARCHAR(11) NOT NULL, [opened_at] DATETIME2 NOT NULL, [updated_by] VARCHAR(11) NULL, [updated_at] DATETIME2 NULL, [expires_at] DATE NOT NULL, [points_balance] INT NOT NULL);
    INSERT INTO @seed_member ([phone], [card_level], [opened_by], [opened_at], [updated_by], [updated_at], [expires_at], [points_balance]) VALUES
        (N'13900000001', N'金卡', N'13800000003', N'2026-09-08T10:40:00', N'13800000003', N'2026-09-19T10:00:00', N'2027-09-08', -26),
        (N'13900000002', N'金卡', N'13800000003', N'2026-09-09T11:00:00', NULL, NULL, N'2027-09-09', 0);
    IF NOT EXISTS (SELECT 1 FROM dbo.[member])
    BEGIN
        INSERT INTO dbo.[member] ([phone], [card_level], [opened_by], [opened_at], [updated_by], [updated_at], [expires_at], [points_balance]) SELECT [phone], [card_level], [opened_by], [opened_at], [updated_by], [updated_at], [expires_at], [points_balance] FROM @seed_member;
    END
    ELSE IF EXISTS (SELECT [phone], [card_level], [opened_by], [opened_at], [updated_by], [updated_at], [expires_at], [points_balance] FROM dbo.[member] EXCEPT SELECT [phone], [card_level], [opened_by], [opened_at], [updated_by], [updated_at], [expires_at], [points_balance] FROM @seed_member)
         OR EXISTS (SELECT [phone], [card_level], [opened_by], [opened_at], [updated_by], [updated_at], [expires_at], [points_balance] FROM @seed_member EXCEPT SELECT [phone], [card_level], [opened_by], [opened_at], [updated_by], [updated_at], [expires_at], [points_balance] FROM dbo.[member])
        THROW 51001, N'member 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_purchase_request TABLE ([id] BIGINT NOT NULL, [no] VARCHAR(20) NOT NULL, [supplier_id] BIGINT NOT NULL, [status] NVARCHAR(10) NOT NULL, [created_by] VARCHAR(11) NOT NULL, [created_at] DATETIME2 NOT NULL, [submitted_by] VARCHAR(11) NULL, [submitted_at] DATETIME2 NULL, [approved_by] VARCHAR(11) NULL, [approved_at] DATETIME2 NULL, [cancelled_by] VARCHAR(11) NULL, [cancelled_at] DATETIME2 NULL);
    INSERT INTO @seed_purchase_request ([id], [no], [supplier_id], [status], [created_by], [created_at], [submitted_by], [submitted_at], [approved_by], [approved_at], [cancelled_by], [cancelled_at]) VALUES
        (1, N'PR20260906-01', 1, N'已收货', N'13800000002', N'2026-09-06T09:50:00', N'13800000002', N'2026-09-06T10:00:00', N'13800000001', N'2026-09-06T11:00:00', NULL, NULL),
        (2, N'PR20260910-01', 1, N'已收货', N'13800000002', N'2026-09-10T08:50:00', N'13800000002', N'2026-09-10T09:00:00', N'13800000001', N'2026-09-10T09:30:00', NULL, NULL),
        (3, N'PR20260911-01', 2, N'已收货', N'13800000002', N'2026-09-11T08:50:00', N'13800000002', N'2026-09-11T09:00:00', N'13800000001', N'2026-09-11T09:20:00', NULL, NULL);
    IF NOT EXISTS (SELECT 1 FROM dbo.[purchase_request])
    BEGIN
        SET IDENTITY_INSERT dbo.[purchase_request] ON;
        INSERT INTO dbo.[purchase_request] ([id], [no], [supplier_id], [status], [created_by], [created_at], [submitted_by], [submitted_at], [approved_by], [approved_at], [cancelled_by], [cancelled_at]) SELECT [id], [no], [supplier_id], [status], [created_by], [created_at], [submitted_by], [submitted_at], [approved_by], [approved_at], [cancelled_by], [cancelled_at] FROM @seed_purchase_request;
        SET IDENTITY_INSERT dbo.[purchase_request] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [no], [supplier_id], [status], [created_by], [created_at], [submitted_by], [submitted_at], [approved_by], [approved_at], [cancelled_by], [cancelled_at] FROM dbo.[purchase_request] EXCEPT SELECT [id], [no], [supplier_id], [status], [created_by], [created_at], [submitted_by], [submitted_at], [approved_by], [approved_at], [cancelled_by], [cancelled_at] FROM @seed_purchase_request)
         OR EXISTS (SELECT [id], [no], [supplier_id], [status], [created_by], [created_at], [submitted_by], [submitted_at], [approved_by], [approved_at], [cancelled_by], [cancelled_at] FROM @seed_purchase_request EXCEPT SELECT [id], [no], [supplier_id], [status], [created_by], [created_at], [submitted_by], [submitted_at], [approved_by], [approved_at], [cancelled_by], [cancelled_at] FROM dbo.[purchase_request])
        THROW 51001, N'purchase_request 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_purchase_request_item TABLE ([id] BIGINT NOT NULL, [request_id] BIGINT NOT NULL, [goods_id] BIGINT NOT NULL, [request_qty] INT NOT NULL, [unit_cost] DECIMAL(10,2) NOT NULL);
    INSERT INTO @seed_purchase_request_item ([id], [request_id], [goods_id], [request_qty], [unit_cost]) VALUES
        (1, 1, 1, 5, 22.00),
        (2, 1, 2, 3, 26.50),
        (3, 2, 1, 3, 23.50),
        (4, 3, 3, 10, 8.00),
        (5, 3, 4, 20, 2.50);
    IF NOT EXISTS (SELECT 1 FROM dbo.[purchase_request_item])
    BEGIN
        SET IDENTITY_INSERT dbo.[purchase_request_item] ON;
        INSERT INTO dbo.[purchase_request_item] ([id], [request_id], [goods_id], [request_qty], [unit_cost]) SELECT [id], [request_id], [goods_id], [request_qty], [unit_cost] FROM @seed_purchase_request_item;
        SET IDENTITY_INSERT dbo.[purchase_request_item] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [request_id], [goods_id], [request_qty], [unit_cost] FROM dbo.[purchase_request_item] EXCEPT SELECT [id], [request_id], [goods_id], [request_qty], [unit_cost] FROM @seed_purchase_request_item)
         OR EXISTS (SELECT [id], [request_id], [goods_id], [request_qty], [unit_cost] FROM @seed_purchase_request_item EXCEPT SELECT [id], [request_id], [goods_id], [request_qty], [unit_cost] FROM dbo.[purchase_request_item])
        THROW 51001, N'purchase_request_item 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_reservation TABLE ([id] BIGINT NOT NULL, [code] VARCHAR(20) NOT NULL, [phone] VARCHAR(11) NOT NULL, [status] NVARCHAR(10) NOT NULL, [created_at] DATETIME2 NOT NULL, [expires_at] DATETIME2 NOT NULL, [cancelled_by_employee] VARCHAR(11) NULL, [cancelled_at] DATETIME2 NULL);
    INSERT INTO @seed_reservation ([id], [code], [phone], [status], [created_at], [expires_at], [cancelled_by_employee], [cancelled_at]) VALUES
        (1, N'483920', N'13700000009', N'已取', N'2026-09-12T09:15:00', N'2026-09-15T09:15:00', NULL, NULL),
        (2, N'517436', N'13900000001', N'有效', N'2026-09-18T10:00:00', N'2026-09-21T10:00:00', NULL, NULL);
    IF NOT EXISTS (SELECT 1 FROM dbo.[reservation])
    BEGIN
        SET IDENTITY_INSERT dbo.[reservation] ON;
        INSERT INTO dbo.[reservation] ([id], [code], [phone], [status], [created_at], [expires_at], [cancelled_by_employee], [cancelled_at]) SELECT [id], [code], [phone], [status], [created_at], [expires_at], [cancelled_by_employee], [cancelled_at] FROM @seed_reservation;
        SET IDENTITY_INSERT dbo.[reservation] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [code], [phone], [status], [created_at], [expires_at], [cancelled_by_employee], [cancelled_at] FROM dbo.[reservation] EXCEPT SELECT [id], [code], [phone], [status], [created_at], [expires_at], [cancelled_by_employee], [cancelled_at] FROM @seed_reservation)
         OR EXISTS (SELECT [id], [code], [phone], [status], [created_at], [expires_at], [cancelled_by_employee], [cancelled_at] FROM @seed_reservation EXCEPT SELECT [id], [code], [phone], [status], [created_at], [expires_at], [cancelled_by_employee], [cancelled_at] FROM dbo.[reservation])
        THROW 51001, N'reservation 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_reservation_item TABLE ([id] BIGINT NOT NULL, [reservation_id] BIGINT NOT NULL, [goods_id] BIGINT NOT NULL, [quantity] INT NOT NULL);
    INSERT INTO @seed_reservation_item ([id], [reservation_id], [goods_id], [quantity]) VALUES
        (1, 1, 2, 3),
        (2, 2, 1, 6);
    IF NOT EXISTS (SELECT 1 FROM dbo.[reservation_item])
    BEGIN
        SET IDENTITY_INSERT dbo.[reservation_item] ON;
        INSERT INTO dbo.[reservation_item] ([id], [reservation_id], [goods_id], [quantity]) SELECT [id], [reservation_id], [goods_id], [quantity] FROM @seed_reservation_item;
        SET IDENTITY_INSERT dbo.[reservation_item] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [reservation_id], [goods_id], [quantity] FROM dbo.[reservation_item] EXCEPT SELECT [id], [reservation_id], [goods_id], [quantity] FROM @seed_reservation_item)
         OR EXISTS (SELECT [id], [reservation_id], [goods_id], [quantity] FROM @seed_reservation_item EXCEPT SELECT [id], [reservation_id], [goods_id], [quantity] FROM dbo.[reservation_item])
        THROW 51001, N'reservation_item 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_sale TABLE ([id] BIGINT NOT NULL, [no] VARCHAR(20) NOT NULL, [status] NVARCHAR(10) NOT NULL, [cashier_by] VARCHAR(11) NOT NULL, [sold_at] DATETIME2 NOT NULL, [card_level] NVARCHAR(10) NULL, [member_phone] VARCHAR(11) NULL, [reservation_id] BIGINT NULL, [subtotal_amount] DECIMAL(10,2) NOT NULL, [discount_rate] DECIMAL(3,2) NOT NULL, [point_deduction_amount] DECIMAL(10,2) NOT NULL, [paid_amount] DECIMAL(10,2) NOT NULL);
    INSERT INTO @seed_sale ([id], [no], [status], [cashier_by], [sold_at], [card_level], [member_phone], [reservation_id], [subtotal_amount], [discount_rate], [point_deduction_amount], [paid_amount]) VALUES
        (1, N'S20260908-01', N'已全退', N'13800000003', N'2026-09-08T11:00:00', N'银卡', N'13900000001', NULL, 117.00, 0.95, 0.00, 111.15),
        (2, N'S20260914-01', N'部分退款', N'13800000003', N'2026-09-14T15:20:00', N'银卡', N'13900000001', NULL, 97.00, 0.95, 1.00, 91.15),
        (3, N'S20260913-01', N'已付', N'13800000003', N'2026-09-13T14:30:00', NULL, NULL, 1, 147.00, 1.00, 0.00, 147.00);
    IF NOT EXISTS (SELECT 1 FROM dbo.[sale])
    BEGIN
        SET IDENTITY_INSERT dbo.[sale] ON;
        INSERT INTO dbo.[sale] ([id], [no], [status], [cashier_by], [sold_at], [card_level], [member_phone], [reservation_id], [subtotal_amount], [discount_rate], [point_deduction_amount], [paid_amount]) SELECT [id], [no], [status], [cashier_by], [sold_at], [card_level], [member_phone], [reservation_id], [subtotal_amount], [discount_rate], [point_deduction_amount], [paid_amount] FROM @seed_sale;
        SET IDENTITY_INSERT dbo.[sale] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [no], [status], [cashier_by], [sold_at], [card_level], [member_phone], [reservation_id], [subtotal_amount], [discount_rate], [point_deduction_amount], [paid_amount] FROM dbo.[sale] EXCEPT SELECT [id], [no], [status], [cashier_by], [sold_at], [card_level], [member_phone], [reservation_id], [subtotal_amount], [discount_rate], [point_deduction_amount], [paid_amount] FROM @seed_sale)
         OR EXISTS (SELECT [id], [no], [status], [cashier_by], [sold_at], [card_level], [member_phone], [reservation_id], [subtotal_amount], [discount_rate], [point_deduction_amount], [paid_amount] FROM @seed_sale EXCEPT SELECT [id], [no], [status], [cashier_by], [sold_at], [card_level], [member_phone], [reservation_id], [subtotal_amount], [discount_rate], [point_deduction_amount], [paid_amount] FROM dbo.[sale])
        THROW 51001, N'sale 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_sale_item TABLE ([id] BIGINT NOT NULL, [sale_id] BIGINT NOT NULL, [goods_id] BIGINT NOT NULL, [quantity] INT NOT NULL, [unit_price] DECIMAL(10,2) NOT NULL);
    INSERT INTO @seed_sale_item ([id], [sale_id], [goods_id], [quantity], [unit_price]) VALUES
        (1, 1, 1, 3, 39.00),
        (2, 2, 1, 2, 39.00),
        (3, 2, 3, 1, 19.00),
        (4, 3, 2, 3, 49.00);
    IF NOT EXISTS (SELECT 1 FROM dbo.[sale_item])
    BEGIN
        SET IDENTITY_INSERT dbo.[sale_item] ON;
        INSERT INTO dbo.[sale_item] ([id], [sale_id], [goods_id], [quantity], [unit_price]) SELECT [id], [sale_id], [goods_id], [quantity], [unit_price] FROM @seed_sale_item;
        SET IDENTITY_INSERT dbo.[sale_item] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [sale_id], [goods_id], [quantity], [unit_price] FROM dbo.[sale_item] EXCEPT SELECT [id], [sale_id], [goods_id], [quantity], [unit_price] FROM @seed_sale_item)
         OR EXISTS (SELECT [id], [sale_id], [goods_id], [quantity], [unit_price] FROM @seed_sale_item EXCEPT SELECT [id], [sale_id], [goods_id], [quantity], [unit_price] FROM dbo.[sale_item])
        THROW 51001, N'sale_item 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_goods_return TABLE ([id] BIGINT NOT NULL, [no] VARCHAR(20) NOT NULL, [sale_id] BIGINT NOT NULL, [refund_amount] DECIMAL(10,2) NOT NULL, [handled_by] VARCHAR(11) NOT NULL, [handled_at] DATETIME2 NOT NULL);
    INSERT INTO @seed_goods_return ([id], [no], [sale_id], [refund_amount], [handled_by], [handled_at]) VALUES
        (1, N'RT20260915-01', 2, 17.85, N'13800000004', N'2026-09-15T11:00:00'),
        (2, N'RT20260916-01', 1, 111.15, N'13800000004', N'2026-09-16T11:00:00');
    IF NOT EXISTS (SELECT 1 FROM dbo.[goods_return])
    BEGIN
        SET IDENTITY_INSERT dbo.[goods_return] ON;
        INSERT INTO dbo.[goods_return] ([id], [no], [sale_id], [refund_amount], [handled_by], [handled_at]) SELECT [id], [no], [sale_id], [refund_amount], [handled_by], [handled_at] FROM @seed_goods_return;
        SET IDENTITY_INSERT dbo.[goods_return] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [no], [sale_id], [refund_amount], [handled_by], [handled_at] FROM dbo.[goods_return] EXCEPT SELECT [id], [no], [sale_id], [refund_amount], [handled_by], [handled_at] FROM @seed_goods_return)
         OR EXISTS (SELECT [id], [no], [sale_id], [refund_amount], [handled_by], [handled_at] FROM @seed_goods_return EXCEPT SELECT [id], [no], [sale_id], [refund_amount], [handled_by], [handled_at] FROM dbo.[goods_return])
        THROW 51001, N'goods_return 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_goods_return_item TABLE ([id] BIGINT NOT NULL, [return_id] BIGINT NOT NULL, [sale_item_id] BIGINT NOT NULL, [quantity] INT NOT NULL, [refund_amount] DECIMAL(10,2) NOT NULL);
    INSERT INTO @seed_goods_return_item ([id], [return_id], [sale_item_id], [quantity], [refund_amount]) VALUES
        (1, 1, 3, 1, 17.85),
        (2, 2, 1, 3, 111.15);
    IF NOT EXISTS (SELECT 1 FROM dbo.[goods_return_item])
    BEGIN
        SET IDENTITY_INSERT dbo.[goods_return_item] ON;
        INSERT INTO dbo.[goods_return_item] ([id], [return_id], [sale_item_id], [quantity], [refund_amount]) SELECT [id], [return_id], [sale_item_id], [quantity], [refund_amount] FROM @seed_goods_return_item;
        SET IDENTITY_INSERT dbo.[goods_return_item] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [return_id], [sale_item_id], [quantity], [refund_amount] FROM dbo.[goods_return_item] EXCEPT SELECT [id], [return_id], [sale_item_id], [quantity], [refund_amount] FROM @seed_goods_return_item)
         OR EXISTS (SELECT [id], [return_id], [sale_item_id], [quantity], [refund_amount] FROM @seed_goods_return_item EXCEPT SELECT [id], [return_id], [sale_item_id], [quantity], [refund_amount] FROM dbo.[goods_return_item])
        THROW 51001, N'goods_return_item 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_stock_movement TABLE ([id] BIGINT NOT NULL, [goods_id] BIGINT NOT NULL, [change_type] NVARCHAR(10) NOT NULL, [quantity] INT NOT NULL, [note] NVARCHAR(200) NULL, [changed_by] VARCHAR(11) NOT NULL, [changed_at] DATETIME2 NOT NULL, [request_id] BIGINT NULL, [sale_id] BIGINT NULL, [return_item_id] BIGINT NULL);
    INSERT INTO @seed_stock_movement ([id], [goods_id], [change_type], [quantity], [note], [changed_by], [changed_at], [request_id], [sale_id], [return_item_id]) VALUES
        (1, 1, N'购入', 5, NULL, N'13800000002', N'2026-09-07T10:30:00', 1, NULL, NULL),
        (2, 2, N'购入', 3, NULL, N'13800000002', N'2026-09-07T10:35:00', 1, NULL, NULL),
        (3, 1, N'卖出', -3, NULL, N'13800000003', N'2026-09-08T11:00:00', NULL, 1, NULL),
        (4, 1, N'购入', 3, NULL, N'13800000002', N'2026-09-10T10:00:00', 2, NULL, NULL),
        (5, 3, N'购入', 10, NULL, N'13800000002', N'2026-09-11T10:00:00', 3, NULL, NULL),
        (6, 4, N'购入', 20, NULL, N'13800000002', N'2026-09-11T10:05:00', 3, NULL, NULL),
        (7, 2, N'卖出', -3, NULL, N'13800000003', N'2026-09-13T14:30:00', NULL, 3, NULL),
        (8, 1, N'卖出', -2, NULL, N'13800000003', N'2026-09-14T15:20:00', NULL, 2, NULL),
        (9, 3, N'卖出', -1, NULL, N'13800000003', N'2026-09-14T15:20:00', NULL, 2, NULL),
        (10, 3, N'退货', 1, NULL, N'13800000002', N'2026-09-15T11:05:00', NULL, NULL, 1),
        (11, 1, N'退货', 3, NULL, N'13800000002', N'2026-09-16T11:05:00', NULL, NULL, 2),
        (12, 4, N'损坏', -1, N'运输中受挤压变形', N'13800000002', N'2026-09-17T16:00:00', NULL, NULL, NULL);
    IF NOT EXISTS (SELECT 1 FROM dbo.[stock_movement])
    BEGIN
        SET IDENTITY_INSERT dbo.[stock_movement] ON;
        INSERT INTO dbo.[stock_movement] ([id], [goods_id], [change_type], [quantity], [note], [changed_by], [changed_at], [request_id], [sale_id], [return_item_id]) SELECT [id], [goods_id], [change_type], [quantity], [note], [changed_by], [changed_at], [request_id], [sale_id], [return_item_id] FROM @seed_stock_movement;
        SET IDENTITY_INSERT dbo.[stock_movement] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [goods_id], [change_type], [quantity], [note], [changed_by], [changed_at], [request_id], [sale_id], [return_item_id] FROM dbo.[stock_movement] EXCEPT SELECT [id], [goods_id], [change_type], [quantity], [note], [changed_by], [changed_at], [request_id], [sale_id], [return_item_id] FROM @seed_stock_movement)
         OR EXISTS (SELECT [id], [goods_id], [change_type], [quantity], [note], [changed_by], [changed_at], [request_id], [sale_id], [return_item_id] FROM @seed_stock_movement EXCEPT SELECT [id], [goods_id], [change_type], [quantity], [note], [changed_by], [changed_at], [request_id], [sale_id], [return_item_id] FROM dbo.[stock_movement])
        THROW 51001, N'stock_movement 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_point_movement TABLE ([id] BIGINT NOT NULL, [member_phone] VARCHAR(11) NOT NULL, [change_type] NVARCHAR(10) NOT NULL, [points] INT NOT NULL, [sale_id] BIGINT NULL, [return_id] BIGINT NULL, [changed_by] VARCHAR(11) NOT NULL, [changed_at] DATETIME2 NOT NULL);
    INSERT INTO @seed_point_movement ([id], [member_phone], [change_type], [points], [sale_id], [return_id], [changed_by], [changed_at]) VALUES
        (1, N'13900000001', N'消费获得', 111, 1, NULL, N'13800000003', N'2026-09-08T11:00:00'),
        (2, N'13900000001', N'抵扣使用', -100, 2, NULL, N'13800000003', N'2026-09-14T15:20:00'),
        (3, N'13900000001', N'消费获得', 91, 2, NULL, N'13800000003', N'2026-09-14T15:20:00'),
        (4, N'13900000001', N'退货回滚', -17, 2, 1, N'13800000004', N'2026-09-15T11:00:00'),
        (5, N'13900000001', N'退货回滚', -111, 1, 2, N'13800000004', N'2026-09-16T11:00:00');
    IF NOT EXISTS (SELECT 1 FROM dbo.[point_movement])
    BEGIN
        SET IDENTITY_INSERT dbo.[point_movement] ON;
        INSERT INTO dbo.[point_movement] ([id], [member_phone], [change_type], [points], [sale_id], [return_id], [changed_by], [changed_at]) SELECT [id], [member_phone], [change_type], [points], [sale_id], [return_id], [changed_by], [changed_at] FROM @seed_point_movement;
        SET IDENTITY_INSERT dbo.[point_movement] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [member_phone], [change_type], [points], [sale_id], [return_id], [changed_by], [changed_at] FROM dbo.[point_movement] EXCEPT SELECT [id], [member_phone], [change_type], [points], [sale_id], [return_id], [changed_by], [changed_at] FROM @seed_point_movement)
         OR EXISTS (SELECT [id], [member_phone], [change_type], [points], [sale_id], [return_id], [changed_by], [changed_at] FROM @seed_point_movement EXCEPT SELECT [id], [member_phone], [change_type], [points], [sale_id], [return_id], [changed_by], [changed_at] FROM dbo.[point_movement])
        THROW 51001, N'point_movement 与样例基线不同，停止装载，不覆盖现有数据。', 1;

    DECLARE @seed_fund_flow TABLE ([id] BIGINT NOT NULL, [amount] DECIMAL(10,2) NOT NULL, [direction] NVARCHAR(2) NOT NULL, [reason_type] NVARCHAR(10) NOT NULL, [sale_id] BIGINT NULL, [return_id] BIGINT NULL, [request_id] BIGINT NULL, [member_phone] VARCHAR(11) NULL, [fund_before] DECIMAL(12,2) NOT NULL, [fund_after] DECIMAL(12,2) NOT NULL, [recorded_by] VARCHAR(11) NOT NULL, [recorded_at] DATETIME2 NOT NULL);
    INSERT INTO @seed_fund_flow ([id], [amount], [direction], [reason_type], [sale_id], [return_id], [request_id], [member_phone], [fund_before], [fund_after], [recorded_by], [recorded_at]) VALUES
        (1, 2000.00, N'收', N'注资', NULL, NULL, NULL, NULL, 0.00, 2000.00, N'13800000001', N'2026-09-01T09:05:00'),
        (2, 189.50, N'付', N'采购付款', NULL, NULL, 1, NULL, 2000.00, 1810.50, N'13800000001', N'2026-09-07T10:00:00'),
        (3, 20.00, N'收', N'办卡费', NULL, NULL, NULL, N'13900000001', 1810.50, 1830.50, N'13800000003', N'2026-09-08T10:40:00'),
        (4, 111.15, N'收', N'销售收款', 1, NULL, NULL, NULL, 1830.50, 1941.65, N'13800000003', N'2026-09-08T11:00:00'),
        (5, 50.00, N'收', N'办卡费', NULL, NULL, NULL, N'13900000002', 1941.65, 1991.65, N'13800000003', N'2026-09-09T11:00:00'),
        (6, 70.50, N'付', N'采购付款', NULL, NULL, 2, NULL, 1991.65, 1921.15, N'13800000001', N'2026-09-10T09:40:00'),
        (7, 130.00, N'付', N'采购付款', NULL, NULL, 3, NULL, 1921.15, 1791.15, N'13800000001', N'2026-09-11T09:30:00'),
        (8, 147.00, N'收', N'销售收款', 3, NULL, NULL, NULL, 1791.15, 1938.15, N'13800000003', N'2026-09-13T14:30:00'),
        (9, 91.15, N'收', N'销售收款', 2, NULL, NULL, NULL, 1938.15, 2029.30, N'13800000003', N'2026-09-14T15:20:00'),
        (10, 17.85, N'付', N'退货退款', 2, 1, NULL, NULL, 2029.30, 2011.45, N'13800000004', N'2026-09-15T11:00:00'),
        (11, 111.15, N'付', N'退货退款', 1, 2, NULL, NULL, 2011.45, 1900.30, N'13800000004', N'2026-09-16T11:00:00'),
        (12, 30.00, N'收', N'办卡费', NULL, NULL, NULL, N'13900000001', 1900.30, 1930.30, N'13800000003', N'2026-09-19T10:00:00'),
        (13, 500.00, N'付', N'提现', NULL, NULL, NULL, NULL, 1930.30, 1430.30, N'13800000001', N'2026-09-20T16:00:00');
    IF NOT EXISTS (SELECT 1 FROM dbo.[fund_flow])
    BEGIN
        SET IDENTITY_INSERT dbo.[fund_flow] ON;
        INSERT INTO dbo.[fund_flow] ([id], [amount], [direction], [reason_type], [sale_id], [return_id], [request_id], [member_phone], [fund_before], [fund_after], [recorded_by], [recorded_at]) SELECT [id], [amount], [direction], [reason_type], [sale_id], [return_id], [request_id], [member_phone], [fund_before], [fund_after], [recorded_by], [recorded_at] FROM @seed_fund_flow;
        SET IDENTITY_INSERT dbo.[fund_flow] OFF;
    END
    ELSE IF EXISTS (SELECT [id], [amount], [direction], [reason_type], [sale_id], [return_id], [request_id], [member_phone], [fund_before], [fund_after], [recorded_by], [recorded_at] FROM dbo.[fund_flow] EXCEPT SELECT [id], [amount], [direction], [reason_type], [sale_id], [return_id], [request_id], [member_phone], [fund_before], [fund_after], [recorded_by], [recorded_at] FROM @seed_fund_flow)
         OR EXISTS (SELECT [id], [amount], [direction], [reason_type], [sale_id], [return_id], [request_id], [member_phone], [fund_before], [fund_after], [recorded_by], [recorded_at] FROM @seed_fund_flow EXCEPT SELECT [id], [amount], [direction], [reason_type], [sale_id], [return_id], [request_id], [member_phone], [fund_before], [fund_after], [recorded_by], [recorded_at] FROM dbo.[fund_flow])
        THROW 51001, N'fund_flow 与样例基线不同，停止装载，不覆盖现有数据。', 1;
    COMMIT;
    PRINT N'sample-data.sql PASS: baseline loaded or unchanged (77 rows).';
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    SET IDENTITY_INSERT dbo.[supplier] OFF;
    SET IDENTITY_INSERT dbo.[goods] OFF;
    SET IDENTITY_INSERT dbo.[purchase_request] OFF;
    SET IDENTITY_INSERT dbo.[purchase_request_item] OFF;
    SET IDENTITY_INSERT dbo.[reservation] OFF;
    SET IDENTITY_INSERT dbo.[reservation_item] OFF;
    SET IDENTITY_INSERT dbo.[sale] OFF;
    SET IDENTITY_INSERT dbo.[sale_item] OFF;
    SET IDENTITY_INSERT dbo.[goods_return] OFF;
    SET IDENTITY_INSERT dbo.[goods_return_item] OFF;
    SET IDENTITY_INSERT dbo.[stock_movement] OFF;
    SET IDENTITY_INSERT dbo.[point_movement] OFF;
    SET IDENTITY_INSERT dbo.[fund_flow] OFF;
    THROW;
END CATCH;
