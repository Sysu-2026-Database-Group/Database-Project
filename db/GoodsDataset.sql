-- ============================
-- GoodsDataset 商品信息数据库（统一库存）
-- ============================
DROP TABLE IF EXISTS GoodsDataset;
GO

CREATE TABLE GoodsDataset(
    dataset_id BIGINT NOT NULL PRIMARY KEY IDENTITY(1,1), --本表内部主键
    goods_type VARCHAR(10) NOT NULL, --商品类型标记：Book / Toy
    isbn VARCHAR(13), --图书：Book类型时填写ISBN；Toy类型为NULL
    goods_code VARCHAR(50), --文创：Toy类型填写内部编码goods_code；Book类型为NULL

    stock_total INT NOT NULL DEFAULT 0, --在架总量：含已被订走、还没取走的货
    reserved_count INT NOT NULL DEFAULT 0, --预定数量：已被订走、待自提
    current_sale_price DECIMAL(10,2) NOT NULL, --当前售价，成交计价依据

    -- 外键关联Book表（仅goods_type='Book'生效）
    CONSTRAINT FK_GoodsDataset_Book
        FOREIGN KEY(isbn) REFERENCES Book(isbn),
    -- 外键关联Toy表（仅goods_type='Toy'生效）
    CONSTRAINT FK_GoodsDataset_Toy
        FOREIGN KEY(goods_code) REFERENCES Toy(goods_code),

    --约束1：goods_type只能为Book或者Toy
    CONSTRAINT CK_GoodsDataset_Type
        CHECK(goods_type IN ('Book','Toy')),

    --约束2：类型与编码匹配校验
    --Book → isbn非空、goods_code为空
    --Toy → goods_code非空、isbn为空
    CONSTRAINT CK_GoodsDataset_CodeMatch
        CHECK(
            (goods_type='Book' AND isbn IS NOT NULL AND goods_code IS NULL)
            OR
            (goods_type='Toy' AND goods_code IS NOT NULL AND isbn IS NULL)
        ),

    --约束3：库存、预定数量不能小于0
    CONSTRAINT CK_GoodsDataset_NonNegative
        CHECK(stock_total >=0 AND reserved_count >=0),

    --约束4：同一个商品（类型+编码）只能存在一条记录
    CONSTRAINT UQ_GoodsDataset_UniqueGoods
        UNIQUE(goods_type, isbn, goods_code)
);
GO

-- ============================
-- 插入测试样例数据
-- 依赖已经建好Book表、Toy表
-- ============================
INSERT INTO GoodsDataset(goods_type,isbn,goods_code,stock_total,reserved_count,current_sale_price)
VALUES
--图书商品：深入理解计算机系统
('Book','9787111532644',NULL,80,10,129.00),
--文创商品：中山大学校徽钥匙扣
('Toy',NULL,'TOY-001',200,30,29.90);
GO

-- ============================
-- 查询示例：派生计算【可售量 = 在库数量 − 预定数量】
-- 可售量不存列，查询实时计算
-- ============================
SELECT
    dataset_id,
    goods_type AS 商品类型,
    isbn AS ISBN,
    goods_code AS 内部编码,
    stock_total AS 在库数量,
    reserved_count AS 预定数量,
    (stock_total - reserved_count) AS 可售量, --派生字段
    current_sale_price AS 当前售价
FROM GoodsDataset;
GO

-- ============================
-- 约束测试代码（实验报告使用，注释状态）
-- ============================
/*
--测试1：goods_type填非法值，触发CK_GoodsDataset_Type报错
INSERT INTO GoodsDataset(goods_type,isbn,goods_code,stock_total,reserved_count,current_sale_price)
VALUES('Phone','9787111532644',NULL,50,0,99);

--测试2：类型Book但是isbn为NULL，编码不匹配CK_GoodsDataset_CodeMatch报错
INSERT INTO GoodsDataset(goods_type,isbn,goods_code,stock_total,reserved_count,current_sale_price)
VALUES('Book',NULL,'TOY-001',50,0,99);

--测试3：库存负数，触发CK_GoodsDataset_NonNegative报错
INSERT INTO GoodsDataset(goods_type,isbn,goods_code,stock_total,reserved_count,current_sale_price)
VALUES('Book','9787111532644',NULL,-5,0,129);

--测试4：重复插入同一个商品（类型+编码），触发UQ_GoodsDataset_UniqueGoods唯一约束报错
INSERT INTO GoodsDataset(goods_type,isbn,goods_code,stock_total,reserved_count,current_sale_price)
VALUES('Book','9787111532644',NULL,100,0,129);
*/
