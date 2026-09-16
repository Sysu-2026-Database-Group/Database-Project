-- ============================
-- 文创商品表 Toy
-- ============================
DROP TABLE IF EXISTS Toy;
GO

CREATE TABLE Toy(
    toy_id BIGINT NOT NULL PRIMARY KEY IDENTITY(1,1), -- 主键，自增ID，内部记录ID
    goods_code VARCHAR(50) NOT NULL UNIQUE, -- 内部编码，本次新增，商品编码，全局唯一
    name NVARCHAR(255) NOT NULL, -- 商品名
    brand NVARCHAR(100) NOT NULL, -- 品牌
    produce_time DATE NOT NULL, -- 生产日期
    style NVARCHAR(255), -- 款式（选做，允许为空）
    sn_code VARCHAR(64) UNIQUE, -- SN码编码，一物一码（选做，唯一约束，可NULL）
    price DECIMAL(10,2), -- 售价，可选拓展字段
    stock INT DEFAULT 0, -- 库存数量，可选拓展字段
    remark NVARCHAR(MAX) -- 备注信息
);
GO

-- ============================
-- 插入测试样例数据
-- ============================
INSERT INTO Toy(goods_code, name, brand, produce_time, style, sn_code, price, stock, remark)
VALUES
(
    'TOY-001',
    N'中山大学校徽钥匙扣',
    N'中大文创',
    '2025-03-10',
    N'金属款',
    N'SN20250310001',
    29.90,
    100,
    N'校园文创，金属烤漆校徽挂件'
),
(
    'TOY-002',
    N'中大猫笔记本',
    N'中大文创',
    '2025-05-20',
    N'平装A5',
    N'SN20250520001',
    35.00,
    200,
    N'校园猫咪主题记事本'
),
(
    'TOY-003',
    N'岭南建筑书签套装',
    N'岭南文创',
    '2025-01-15',
    N'黄铜套装',
    N'SN20250115001',
    49.90,
    50,
    N'岭南古建筑黄铜书签四件套'
);
GO

-- ============================
-- 查询验证
-- ============================
SELECT * FROM Toy;
GO

-- ============================
-- 约束测试示例（可选，用于实验报告）
-- ============================
-- 测试1：重复goods_code，触发UNIQUE报错
/*
INSERT INTO Toy(goods_code, name, brand, produce_time, style, sn_code)
VALUES
(
    'TOY-001', -- 和上面goods_code重复
    N'测试商品',
    N'测试品牌',
    '2025-01-01',
    N'测试款式',
    N'SN999999'
);
*/

-- 测试2：重复sn_code，触发UNIQUE报错
/*
INSERT INTO Toy(goods_code, name, brand, produce_time, style, sn_code)
VALUES
(
    'TOY-999',
    N'测试商品',
    N'测试品牌',
    '2025-01-01',
    N'测试款式',
    N'SN20250310001' -- SN码重复
);
*/
