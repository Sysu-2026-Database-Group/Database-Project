-- ============================
-- 采购申请主表 BuyRequest
-- ============================
DROP TABLE IF EXISTS BuyRequestItem;
DROP TABLE IF EXISTS BuyRequest;
GO

CREATE TABLE BuyRequest(
    id BIGINT NOT NULL PRIMARY KEY IDENTITY(1,1), -- 采购申请单号，唯一标识
    producer NVARCHAR(100) NOT NULL, -- 供应商名称（文本，不建实体表）
    is_accepted BIT, -- 是否通过：NULL=未审批，1=通过，0=驳回
    apply_time DATETIME NOT NULL DEFAULT GETDATE() -- 申请时刻，默认当前时间
);
GO

-- ============================
-- 采购申请明细表 BuyRequestItem
-- 一张采购申请单对应多条明细
-- 商品类型：Book(ISBN) / Toy(goods_code)，二选一填写
-- ============================
CREATE TABLE BuyRequestItem(
    item_id BIGINT NOT NULL PRIMARY KEY IDENTITY(1,1), -- 明细行主键
    request_id BIGINT NOT NULL, -- 外键，关联采购申请主表BuyRequest.id
    isbn VARCHAR(13), -- 图书：引用Book表isbn；如果是文创Toy则为NULL
    goods_code VARCHAR(50), -- 文创：引用Toy表goods_code；如果是Book则为NULL
    quantity INT NOT NULL CHECK (quantity > 0), -- 申请件数，必须大于0
    cost_price DECIMAL(10,2) NOT NULL CHECK (cost_price > 0), -- 进价

    -- 外键关联采购申请主表
    CONSTRAINT FK_BuyRequestItem_BuyRequest
        FOREIGN KEY(request_id) REFERENCES BuyRequest(id),
    
    -- 外键关联图书Book
    CONSTRAINT FK_BuyRequestItem_Book
        FOREIGN KEY(isbn) REFERENCES Book(isbn),
    
    -- 外键关联文创Toy
    CONSTRAINT FK_BuyRequestItem_Toy
        FOREIGN KEY(goods_code) REFERENCES Toy(goods_code),

    -- CHECK约束：isbn 和 goods_code 只能有一个不为NULL（商品二选一）
    CONSTRAINT CK_BuyRequestItem_GoodsType
        CHECK (
            (isbn IS NOT NULL AND goods_code IS NULL) 
            OR 
            (isbn IS NULL AND goods_code IS NOT NULL)
        )
);
GO

-- ============================
-- 插入测试样例数据
-- ============================
-- 1. 新建采购申请主单（未审批 NULL）
INSERT INTO BuyRequest(producer, is_accepted, apply_time)
VALUES
(N'机械工业出版社供货部', NULL, '2026-09-10 09:30:00'),
(N'中大文创供应商', NULL, '2026-09-11 14:20:00');
GO

-- 2. 插入明细
-- 第1张采购单：采购图书（Book，isbn）
INSERT INTO BuyRequestItem(request_id, isbn, goods_code, quantity, cost_price)
VALUES
(1, '9787111532644', NULL, 20, 80.00);

-- 第2张采购单：采购文创Toy（goods_code）
INSERT INTO BuyRequestItem(request_id, isbn, goods_code, quantity, cost_price)
VALUES
(2, NULL, 'TOY-001', 50, 15.00);
GO

-- ============================
-- 查询：联合查询采购申请 + 明细
-- ============================
SELECT
    br.id AS 申请单号,
    br.producer AS 供应商,
    CASE br.is_accepted
        WHEN 1 THEN N'已通过'
        WHEN 0 THEN N'已驳回'
        WHEN NULL THEN N'待审批'
    END AS 审批状态,
    br.apply_time AS 申请时间,
    bri.quantity AS 采购数量,
    bri.cost_price AS 进价,
    bri.isbn AS 图书ISBN,
    bri.goods_code AS 文创编码
FROM BuyRequest br
JOIN BuyRequestItem bri ON br.id = bri.request_id;
GO

-- ============================
-- 约束测试示例（实验报告可用）
-- ============================
/*
-- 测试1：同时填写isbn和goods_code，触发CK_BuyRequestItem_GoodsType报错
INSERT INTO BuyRequestItem(request_id, isbn, goods_code, quantity, cost_price)
VALUES
(1, '9787111532644', 'TOY-001', 10, 20);

-- 测试2：quantity=0，触发CHECK数量大于0报错
INSERT INTO BuyRequestItem(request_id, isbn, goods_code, quantity, cost_price)
VALUES
(1, '9787111532644', NULL, 0, 20);

-- 测试3：引用不存在的ISBN，外键报错
INSERT INTO BuyRequestItem(request_id, isbn, goods_code, quantity, cost_price)
VALUES
(1, '9999999999999', NULL, 10, 20);
*/
