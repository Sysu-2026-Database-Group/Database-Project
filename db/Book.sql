-- ======================
-- 1. 创建出版社表 publisher
-- ======================
CREATE TABLE publisher(
	publisher_id bigint NOT NULL PRIMARY KEY, --出版社编号
	publisher_name nvarchar(100) NOT NULL, --出版社名称
	address nvarchar(255), --出版社地址
	contact nvarchar(50) --联系方式
);
GO

-- ======================
-- 2. 创建图书表 book
-- ======================
CREATE TABLE book(
	book_id bigint NOT NULL PRIMARY KEY, --书店内部标记
	isbn varchar(13) NOT NULL UNIQUE, --书的isbn码
	title nvarchar(255) NOT NULL, --书名，unicode支持中文
	publisher_id bigint NOT NULL, --出版社编号（外键）
	publisher_date date NOT NULL, --出版日期
	list_price decimal(10,2) NOT NULL, --生产商建议售价
	book_format varchar(50) NOT NULL, --书的形式：paperback平装,hardcover精装,audiobook有声书
	page_count int NOT NULL, --书的页数
	summary nvarchar(max), --书的简介，替换老旧text类型
	
	-- 外键约束：关联出版社表
	CONSTRAINT FK_book_publisher 
	FOREIGN KEY (publisher_id) REFERENCES publisher(publisher_id),
	
	-- CHECK约束：限制book_format只能是指定3个值
	CONSTRAINT CK_book_format 
	CHECK (book_format IN ('paperback','hardcover','audiobook'))
);
GO

-- ======================
-- 3. 插入测试数据
-- ======================
-- 先插入出版社
INSERT INTO publisher(publisher_id, publisher_name, address, contact)
VALUES
(1, N'机械工业出版社', N'北京市西城区百万庄大街22号', N'010-68326294'),
(2, N'人民邮电出版社', N'北京市丰台区成寿寺路11号', N'010-81055256');

-- 再插入图书
INSERT INTO book(
	book_id, isbn, title, publisher_id, publisher_date, list_price, book_format, page_count, summary
)
VALUES
(
	1,
	'9787111532644',
	N'深入理解计算机系统',
	1,
	'2016-01-01',
	129.00,
	'hardcover',
	700,
	N'本书从程序员的视角详细描述计算机系统的本质，包括程序是如何映射到系统上，程序是如何执行的。'
),
(
	2,
	'9787115546081',
	N'Python编程：从入门到实践',
	2,
	'2020-05-01',
	89.00,
	'paperback',
	520,
	N'一本针对所有层次Python读者而作的入门书，讲解基础语法与项目实战。'
);
GO

-- ======================
-- 4. 查询验证
-- ======================
-- 查询所有图书信息，关联出版社名称
SELECT 
	b.book_id,
	b.isbn,
	b.title,
	p.publisher_name,
	b.publisher_date,
	b.list_price,
	b.book_format,
	b.page_count,
	b.summary
FROM book b
JOIN publisher p ON b.publisher_id = p.publisher_id;
GO
