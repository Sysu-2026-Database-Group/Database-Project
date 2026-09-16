-- ============================
-- 预定系统：预定主表 Reservation
-- ============================
DROP TABLE IF EXISTS ReservationItem;
DROP TABLE IF EXISTS Reservation;
GO

CREATE TABLE Reservation(
    lock_id BIGINT NOT NULL PRIMARY KEY IDENTITY(1,1), -- 预定码，唯一预定标识
    phone_number VARCHAR(20) NOT NULL, -- 手机号，身份核对
    member_name NVARCHAR(100) NOT NULL, -- 客户姓名快照
    lock_ddl DATETIME NOT NULL, -- 预定有效期，到期失效
    status NVARCHAR(10) NOT NULL, -- 状态枚举：有效 / 已取 / 已过期 / 已取消

    -- CHECK约束：限定状态只能取文档指定4个值
    CONSTRAINT CK_Reservation_Status
        CHECK (status IN (N'有效', N'已取', N'已过期', N'已取消'))
);
GO

-- ============================
-- 预定系统：预定明细 ReservationItem
-- 一张预定单对应多条商品记录；预定不记录金额
-- 商品二选一：Book填isbn，Toy填goods_code，不可同时填写
-- ============================
CREATE TABLE ReservationItem(
    item_id BIGINT NOT NULL PRIMARY KEY IDENTITY(1,1), -- 明细行主键
    lock_id BIGINT NOT NULL, -- 外键，关联预定主表lock_id
    isbn VARCHAR(13), -- 图书：引用Book.isbn；文创Toy则为NULL
    goods_code VARCHAR(50), -- 文创：引用Toy.goods_code；图书Book则为NULL
    quantity INT NOT NULL CHECK(quantity > 0), -- 预占件数，必须大于0

    -- 外键关联预定单主表
    CONSTRAINT FK_ReservationItem_Reservation
        FOREIGN KEY(lock_id) REFERENCES Reservation(lock_id),
    -- 外键关联图书
    CONSTRAINT FK_ReservationItem_Book
        FOREIGN KEY(isbn) REFERENCES Book(isbn),
    -- 外键关联文创
    CONSTRAINT FK_ReservationItem_Toy
        FOREIGN KEY(goods_code) REFERENCES Toy(goods_code),

    -- CHECK约束：只能是图书 或 文创其中一类商品，二选一
    CONSTRAINT CK_ReservationItem_GoodsType
        CHECK (
            (isbn IS NOT NULL AND goods_code IS NULL)
            OR
            (isbn IS NULL AND goods_code IS NOT NULL)
        )
);
GO

-- ============================
-- 测试样例数据插入
-- 依赖：Book、Toy表已建好
-- ============================
-- 插入预定主单：有效预定，有效期到2026-10-01
INSERT INTO Reservation(phone_number, member_name, lock_ddl, status)
VALUES
('13800138000', N'张三', '2026-10-01 23:59:59', N'有效'),
('13900139000', N'李四', '2026-09-15 23:59:59', N'已过期');
GO

-- 插入预定明细
-- 预定单1：预定图书《深入理解计算机系统》2本
INSERT INTO ReservationItem(lock_id, isbn, goods_code, quantity)
VALUES
(1, '9787111532644', NULL, 2);

-- 预定单1：预定文创 校徽钥匙扣5个
INSERT INTO ReservationItem(lock_id, isbn, goods_code, quantity)
VALUES
(1, NULL, 'TOY-001', 5);
GO

-- ============================
-- 查询示例：预定单 + 明细联合查询
-- ============================
SELECT
    r.lock_id AS 预定码,
    r.phone_number AS 手机号,
    r.member_name AS 客户姓名,
    r.lock_ddl AS 预定有效期,
    r.status AS 预定状态,
    ri.isbn AS 图书ISBN,
    ri.goods_code AS 文创编码,
    ri.quantity AS 预占件数
FROM Reservation r
JOIN ReservationItem ri ON r.lock_id = ri.lock_id;
GO

-- ============================
-- 约束测试代码（实验报告，注释）
-- ============================
/*
-- 测试1：非法状态，触发CK_Reservation_Status报错
INSERT INTO Reservation(phone_number, member_name, lock_ddl, status)
VALUES('13800138000', N'测试', '2026-10-01', N'已退款');

-- 测试2：明细同时填写isbn和goods_code，触发CK_ReservationItem_GoodsType报错
INSERT INTO ReservationItem(lock_id, isbn, goods_code, quantity)
VALUES(1, '9787111532644', 'TOY-001', 1);

-- 测试3：数量<=0，触发CHECK(quantity>0)报错
INSERT INTO ReservationItem(lock_id, isbn, goods_code, quantity)
VALUES(1, '9787111532644', NULL, 0);
*/
