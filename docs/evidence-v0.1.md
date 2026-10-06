# v0.1 结果与截图证据索引

本索引把 `docs/task-v0.1.md` 要求的八类结果对应到可重跑脚本和实际文件。文本输出是主要可复核证据，截图是辅助证据，不能替代 SQL。

| 官方八类 | 产生脚本 | 现有文本结果 | 现有 SSMS 截图 | 状态 |
|---|---|---|---|---|
| 成功建库 | `schema.sql`、`sample-data.sql` | `week-4-verify2-schema.txt`、`week-4-verify2-sample-data.txt` | `week-4-verify2-ssms-结构核对.png` | 已有 |
| 正常用例 | `crud.sql`、`constraint.sql` | `week-4-verify2-crud.txt`、`week-4-verify2-constraint.txt` | `week-4-verify2-ssms-正常用例.png` | **截图已有**（2026-10-06） |
| 非法数据 | `verify.sql`、`constraint.sql` | `week-4-verify2-verify-before.txt`、`week-4-verify2-constraint.txt` | `week-4-verify2-ssms-非法数据.png` | **截图已有**（2026-10-06） |
| 越权访问 | `role.sql` | `week-4-verify2-role.txt` | `week-4-verify2-ssms-越权访问.png` | **截图已有**（2026-10-06） |
| 关键查询 | `query.sql` | `week-4-verify2-query.txt` | `week-4-verify2-ssms-关键查询-1.png`（Q1）· `-2.png`（Q4）· `-3.png`（Q5，0 行）· `-4.png`（Q5 说明版） | **截图已有**（2026-10-06） |
| CRUD | `crud.sql` | `week-4-verify2-crud.txt` | `week-4-verify2-ssms-CRUD.png` | **截图已有**（2026-10-06） |
| 统计视图 | `view.sql` | `week-4-verify2-view.txt`、`week-4-view-compare.txt` | `week-4-verify2-ssms-统计视图-1.png`（明细）· `-2.png`（汇总）· `-3.png`（视图 ↔ 基表对照） | **截图已有**（2026-10-06） |
| 不同角色权限 | `role.sql` | `week-4-verify2-role.txt`、`week-4-role.txt` | `week-4-verify2-ssms-角色权限-1.png`（允许的操作成功）· `-2.png`（授权清单） | **截图已有**（2026-10-06） |

## 1. 总览与对账类截图（八类之外，原有）

- `week-4-verify2-ssms-结构核对.png`：19 张表、47 个外键、主键、唯一约束、CHECK、视图、触发器、列说明、角色和测试用户；
- `week-4-verify2-ssms-对账-行数.png`：19 张表逐表行数及总行数 77；
- `week-4-verify2-ssms-对账-三本账.png`：库存、积分和资金链；
- `week-4-verify2-ssms-对账-已订量-修正.png`：修正后的有效已订量。

## 2. 八类截图的补拍要点（2026-10-06 已全部完成）

在 SSMS 连接 `ShiguangBookstoreVerify2` 后，用查询窗口执行对应脚本或结果查询；
**截图只放结果**（Results 网格或 Messages 标签），**SQL 语句不截进图** —— 语句与预期值统一记在 §3：

1. 正常用例：`crud.sql` 中商品插入、更新、查询和回滚前后的结果；
2. 非法数据：`constraint.sql` 中 `51025`、`547`、`2627` 错误及事务回滚消息；
3. 越权访问：`role.sql` 中三个角色的正常操作和 `229` 越权失败；
4. 关键查询：`query.sql` 的 Q1—Q7 结果，至少覆盖连接、`LEFT JOIN`、聚合、`HAVING` 和子查询；
5. CRUD：显示事务中 INSERT、SELECT、UPDATE、DELETE 的前后结果；
6. 统计视图：三个 `CREATE VIEW` 后的 `SELECT` 结果，并与基表对照；
7. 不同角色权限：分别显示 `EXECUTE AS USER` 下的成功与失败结果。

截图文件命名 `week-4-verify2-ssms-<类别>.png`（同类多张加 `-1` / `-2` 后缀），放入 `db/results/`，
并在上表补充文件名与拍摄日期（**13 张已于 2026-10-06 全部完成**；补拍期间遵循一条纪律：没有实际在 SSMS 中执行并截图前，不把占位状态改成已完成）。没有实际在 SSMS 中执行和截图前，不把"待补"改为"已有"。

## 3. 各截图的 SQL 与预期结果

> 截图只放结果，**语句与预期值集中记在这里** —— 复核时按本节重跑即可对上截图。

### 3.1 正常用例 —— `week-4-verify2-ssms-正常用例.png`（2026-10-06）

摘自 `db/crud.sql` 的商品 CRUD 部分，改为单批自包含写法（末尾回滚，不留数据）：

```sql
USE [ShiguangBookstoreVerify2];
GO
SELECT DB_NAME() AS 当前数据库;
BEGIN TRAN;
INSERT dbo.toy (inner_code, spec) VALUES (N'SSMS-SHOT-001', N'截图用文创');
INSERT dbo.goods (category, name, toy_code, created_by) VALUES (N'文创', N'截图演示书签', N'SSMS-SHOT-001', N'13800000002');
SELECT N'① 插入后' AS 步骤, id, name, price, on_shelf, stock_total FROM dbo.goods WHERE toy_code = N'SSMS-SHOT-001';
UPDATE dbo.goods SET price = 10.00, on_shelf = 1, updated_by = N'13800000001', updated_at = SYSDATETIME() WHERE toy_code = N'SSMS-SHOT-001';
SELECT N'② 更新后' AS 步骤, id, name, price, on_shelf, updated_by FROM dbo.goods WHERE toy_code = N'SSMS-SHOT-001';
ROLLBACK;
SELECT N'③ 回滚后' AS 步骤, COUNT(*) AS 残留行数 FROM dbo.goods WHERE toy_code = N'SSMS-SHOT-001';
```

**截图里的四行结果与预期**：

| 结果 | 预期 |
|---|---|
| `当前数据库` | `ShiguangBookstoreVerify2` |
| `① 插入后` | `price` 空 · `on_shelf = 0` · `stock_total = 0` |
| `② 更新后` | `price = 10.00` · `on_shelf = 1` · `updated_by = 13800000001` |
| `③ 回滚后` | `残留行数 = 0` |

整批在一个显式事务里执行并回滚，**运行前后库内容一致**（第 3 周样例基线不受影响）。

### 3.2 非法数据 —— `week-4-verify2-ssms-非法数据.png`（2026-10-06 已拍，实测与 `week-4-verify2-constraint.txt` 逐行一致）

语句取自 `db/constraint.sql` 的 `ILLEGAL TEST 0`–`ILLEGAL TEST 5`，改写为**单批、单结果集**（便于一张图拍完）：

```sql
USE [ShiguangBookstoreVerify2];
GO
SET NOCOUNT ON;
DECLARE @r TABLE (序号 INT, 用例 NVARCHAR(30), 错误码 INT, 消息 NVARCHAR(400));

-- 0 金卡办卡费低于银卡（档位关系触发器）
BEGIN TRY
    BEGIN TRAN;
    UPDATE dbo.card_type SET [card_fee] = (SELECT [card_fee] FROM dbo.card_type WHERE [level] = N'银卡')
    WHERE [level] = N'金卡';
    ROLLBACK; INSERT @r VALUES (0, N'金卡费<银卡', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @r VALUES (0, N'金卡费<银卡', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

-- 1 已订量超过在架
BEGIN TRY
    BEGIN TRAN;
    UPDATE dbo.goods SET reserved_qty = stock_total + 1 WHERE id = 1;
    ROLLBACK; INSERT @r VALUES (1, N'已订量>在架', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @r VALUES (1, N'已订量>在架', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

-- 2 销售行数量 = 0
BEGIN TRY
    BEGIN TRAN;
    INSERT dbo.sale_item (sale_id, goods_id, quantity, unit_price) VALUES (1, 4, 0, 6.00);
    ROLLBACK; INSERT @r VALUES (2, N'数量=0', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @r VALUES (2, N'数量=0', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

-- 3 外键指向不存在的商品
BEGIN TRY
    BEGIN TRAN;
    INSERT dbo.sale_item (sale_id, goods_id, quantity, unit_price) VALUES (1, 999999, 1, 1.00);
    ROLLBACK; INSERT @r VALUES (3, N'外键不存在', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @r VALUES (3, N'外键不存在', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

-- 4 单号重复
BEGIN TRY
    BEGIN TRAN;
    INSERT dbo.sale (no, status, cashier_by, sold_at, subtotal_amount, discount_rate, point_deduction_amount, paid_amount)
    VALUES (N'S20260908-01', N'已付', N'13800000003', '2026-09-20T12:00:00', 0.00, 1.00, 0.00, 0.00);
    ROLLBACK; INSERT @r VALUES (4, N'单号重复', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @r VALUES (4, N'单号重复', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

-- 5 资金前后余额不自洽
BEGIN TRY
    BEGIN TRAN;
    INSERT dbo.fund_flow (amount, direction, reason_type, fund_before, fund_after, recorded_by, recorded_at)
    VALUES (10.00, N'收', N'注资', 100.00, 100.00, N'13800000001', '2026-09-20T12:00:00');
    ROLLBACK; INSERT @r VALUES (5, N'资金余额不自洽', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @r VALUES (5, N'资金余额不自洽', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

SELECT 序号, 用例, 错误码, 消息 FROM @r ORDER BY 序号;
GO
```

**截图里应出现的 6 行结果**（均为被拒绝，取值与 `db/results/week-4-verify2-constraint.txt` 一致）：

| 用例 | 错误码 | 被触发的约束 / 触发器 |
|---|---|---|
| 0 金卡办卡费低于银卡 | **51025** | 档位关系触发器 |
| 1 已订量超过在架 | **547** | `CK_goods_stock` |
| 2 销售行数量 = 0 | **547** | `CK_sale_item_quantity` |
| 3 外键指向不存在的商品 | **547** | `FK_sale_item_goods_id` |
| 4 单号重复 | **2627** | `UQ_sale_no` |
| 5 资金前后余额不自洽 | **547** | `CK_fund_flow_balance` |

这 6 条都是 `TRY/CATCH` 包住的**故意失败**，每条失败后 `ROLLBACK` —— **库内数据不变**。

### 3.3 越权访问 —— `week-4-verify2-ssms-越权访问.png`（2026-10-06 已拍，3 行错误码均为 `229`）

语句取自 `db/role.sql` 的三段 `ROLE TEST`（收银员改售价 · 库管开销售单 · 店长改已成交单），
同样改写为**单批、单结果集**：

```sql
USE [ShiguangBookstoreVerify2];
GO
SET NOCOUNT ON;
DECLARE @r TABLE (序号 INT, 角色 NVARCHAR(20), 越权尝试 NVARCHAR(40), 错误码 INT, 消息 NVARCHAR(300));

-- 1 收银员：未获授权，不能修改商品售价
EXECUTE AS USER = N'week4_cashier_user';
BEGIN TRY
    BEGIN TRAN;
    UPDATE dbo.goods SET [price] = [price] WHERE id = 1;
    IF @@TRANCOUNT > 0 ROLLBACK;
    REVERT;
    INSERT @r VALUES (1, N'收银员', N'修改商品售价', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF USER_NAME() = N'week4_cashier_user' REVERT;
    INSERT @r VALUES (1, N'收银员', N'修改商品售价', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

-- 2 库管：未获授权，不能开销售单
EXECUTE AS USER = N'week4_inventory_user';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.[sale] ([no], [cashier_by], [subtotal_amount], [paid_amount])
    VALUES (N'W4-UNAUTHORIZED', N'13800000002', 0.00, 0.00);
    IF @@TRANCOUNT > 0 ROLLBACK;
    REVERT;
    INSERT @r VALUES (2, N'库管', N'开销售单', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF USER_NAME() = N'week4_inventory_user' REVERT;
    INSERT @r VALUES (2, N'库管', N'开销售单', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

-- 3 店长：未获授权，不能修改已成交的销售单
EXECUTE AS USER = N'week4_manager_user';
BEGIN TRY
    BEGIN TRAN;
    UPDATE dbo.[sale] SET [paid_amount] = [paid_amount] WHERE id = 1;
    IF @@TRANCOUNT > 0 ROLLBACK;
    REVERT;
    INSERT @r VALUES (3, N'店长', N'改已成交销售单', 0, N'未被拒绝（异常）');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF USER_NAME() = N'week4_manager_user' REVERT;
    INSERT @r VALUES (3, N'店长', N'改已成交销售单', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH

SELECT 序号, 角色, 越权尝试, 错误码, 消息 FROM @r ORDER BY 序号;
GO
```

**截图里应出现的 3 行结果**（均为 `REVERT` 后记录，错误码 = `229` 拒绝访问，取值与 `db/results/week-4-verify2-role.txt` 一致）：

| 序号 | 角色 | 越权尝试 | 错误码 |
|---|---|---|---|
| 1 | 收银员 | 修改商品售价 | **229** |
| 2 | 库管 | 开销售单 | **229** |
| 3 | 店长 | 改已成交销售单 | **229** |

三段都是 `EXECUTE AS USER` 后**故意越权**，失败信息里会写到"拒绝了对对象 … 的 … 权限"；每次失败后 `ROLLBACK` + `REVERT` —— **库内数据不变、身份已还原**。

### 3.4 关键查询（Q1 / Q4 / Q5）—— `week-4-verify2-ssms-关键查询-1/2/3.png`（2026-10-06 已拍）

语句取自 `db/query.sql`（Q1 · Q4 · Q5 三段；执行前把该文件第 4 行的 `USE [$(DatabaseName)];` 改为 `USE [ShiguangBookstoreVerify2];`）：

| 截图 | 段落 | 覆盖的技术 | 实测（2026-10-06，与 `week-4-verify2-query.txt` 逐行一致） |
|---|---|---|---|
| `week-4-verify2-ssms-关键查询-1.png` | 第 10–26 行（Q1） | **多表连接 + `LEFT JOIN`** | 4 行；第 2 行 `member_phone = NON_MEMBER` —— 非会员的单没有被丢掉 |
| `week-4-verify2-ssms-关键查询-2.png` | 第 65–76 行（Q4） | **`GROUP BY` + `HAVING`** | 2 行：`活着 5 / 195.00` · `百年孤独 3 / 147.00`（售出 < 2 件的商品不在结果里） |
| `week-4-verify2-ssms-关键查询-3.png` | 第 78–98 行（Q5） | **CTE + 标量子查询** | **0 行（预期如此）**，原因见 §3.5 |

### 3.5 Q5 为什么是 0 行 —— 说明版（`week-4-verify2-ssms-关键查询-4.png`，2026-10-06 已拍）

实测 1 行：会员 `13900000001`（金卡）`paid_amount = 202.30`、`sale_count = 2`，**全体平均 `202.300000`** —— 与他自己相等，故 Q5 的 `>` 不成立，返回 0 行。

Q5 的判据是"消费额**严格大于**全体会员平均值"。样例里只有一位会员有成交，**平均值就等于他自己的消费额**，
`>` 不成立 → **0 行**；`db/results/week-4-verify2-query.txt` 第 24–25 行同样只记录了表头，**两者一致**
（不是漏拍、也不是查询坏了）。

补一张**把平均值一并显示出来**的说明版（仍然覆盖标量子查询），命名 `week-4-verify2-ssms-关键查询-4.png`：

```sql
USE [ShiguangBookstoreVerify2];
GO
WITH member_spend AS (
    SELECT
        m.[phone],
        m.[card_level],
        SUM(s.[paid_amount]) AS paid_amount,
        COUNT_BIG(*) AS sale_count
    FROM dbo.[member] AS m
    JOIN dbo.[sale] AS s ON s.[member_phone] = m.[phone]
    GROUP BY m.[phone], m.[card_level]
)
SELECT
    ms.[phone] AS member_phone,
    ms.[card_level],
    ms.[paid_amount],
    ms.[sale_count],
    (SELECT AVG(CAST([paid_amount] AS DECIMAL(12,2))) FROM member_spend) AS 全体平均
FROM member_spend AS ms
ORDER BY ms.[paid_amount] DESC;
GO
```

**预期**：每个有成交的会员一行，且其 `paid_amount` 与「全体平均」**相等** —— 这正是 Q5 返回 0 行的原因。

> 可选再补：Q2（`LEFT JOIN` 把"没卖过的商品"保留为 **0 行**）、Q6 / Q7（连到报价与退货）—— 非必需，§3.4 三项已覆盖要求的技术。

### 3.6 CRUD —— `week-4-verify2-ssms-CRUD.png`（2026-10-06 已拍）

实测 5 行：`① 插入后` 售价 `NULL`、上架 `0` → `③ 更新后` 售价 `10.00`、上架 `1`、改动人 `13800000001` → `④ 删除前` 仍可查到 → `⑤ 删除后剩余 0 行`。

取自 `db/crud.sql` 的商品线思路（插入 / 查询 / 更新 / 删除），改写为**单批、单结果集**：把四类操作的前后结果记进一张表，
整个演示在**事务内**执行、**结束即回滚**，库里不留数据。

```sql
USE [ShiguangBookstoreVerify2];
GO
SET NOCOUNT ON;
DECLARE @log TABLE (序 INT, 操作 NVARCHAR(10), 步骤 NVARCHAR(28), 内容 NVARCHAR(200));
BEGIN TRAN;

-- INSERT：新建一件演示文创（未上架、无售价）
INSERT dbo.toy (inner_code, spec) VALUES (N'SSMS-CRUD-001', N'CRUD 截图演示');
INSERT dbo.goods (category, name, toy_code, created_by) VALUES (N'文创', N'CRUD 演示书签', N'SSMS-CRUD-001', N'13800000002');
DECLARE @id BIGINT = SCOPE_IDENTITY();
INSERT @log VALUES (1, N'INSERT', N'① 插入后',
    (SELECT CONCAT(N'id=', id, N'，名称=', name, N'，售价=', ISNULL(CAST(price AS NVARCHAR(12)), N'NULL'), N'，上架=', on_shelf) FROM dbo.goods WHERE id = @id));

-- SELECT：用条件确认刚写入的行
INSERT @log VALUES (2, N'SELECT', N'② 按 id 查到',
    (SELECT CONCAT(N'id=', id, N'，名称=', name, N'，售价=', ISNULL(CAST(price AS NVARCHAR(12)), N'NULL'), N'，上架=', on_shelf) FROM dbo.goods WHERE id = @id));

-- UPDATE：店长定价并上架
UPDATE dbo.goods SET price = 10.00, on_shelf = 1, updated_by = N'13800000001', updated_at = SYSDATETIME() WHERE id = @id;
INSERT @log VALUES (3, N'UPDATE', N'③ 更新后',
    (SELECT CONCAT(N'售价=', price, N'，上架=', on_shelf, N'，改动人=', updated_by) FROM dbo.goods WHERE id = @id));

-- DELETE：先 SELECT 确认目标，再删除
INSERT @log VALUES (4, N'DELETE', N'④ 删除前（确认目标）',
    (SELECT CONCAT(N'id=', id, N'，名称=', name) FROM dbo.goods WHERE id = @id));
DELETE dbo.goods WHERE id = @id;
INSERT @log VALUES (5, N'DELETE', N'⑤ 删除后剩余行数',
    (SELECT CONCAT(N'剩余 ', COUNT(*), N' 行') FROM dbo.goods WHERE id = @id));

ROLLBACK;
SELECT 序, 操作, 步骤, 内容 FROM @log ORDER BY 序;
GO
```

**截图应出现的 5 行**：

| 序 | 操作 | 步骤 | 内容要点 |
|---|---|---|---|
| 1 | INSERT | ① 插入后 | `售价=NULL，上架=0`（新品未定价、未上架） |
| 2 | SELECT | ② 按 id 查到 | 与第 1 行相同 |
| 3 | UPDATE | ③ 更新后 | `售价=10.00，上架=1，改动人=13800000001` |
| 4 | DELETE | ④ 删除前 | 能查到该行（先确认目标再删） |
| 5 | DELETE | ⑤ 删除后剩余行数 | `剩余 0 行` |

末尾 `ROLLBACK` 让演示**不留任何数据**（`toy` 行一并回滚），与 `db/crud.sql`「DELETE 只针对本事务新建的实验数据」的口径一致。

### 3.7 统计视图 —— `week-4-verify2-ssms-统计视图-1/2/3.png`（2026-10-06 已拍）

实测与 `db/results/week-4-verify2-view.txt` 逐行一致：明细视图 4 行（含 `member_phone` 为 `NULL` 的非会员单）、汇总视图 4 行（`拾光书签` 为 0）、对照图里 `视图_在架 / 视图_已订` 与 `基表_在架 / 基表_已订` **每行相同**（在架 6 / 0 / 10 / 19 = 第 3 周基线）。

三个视图已由 `db/view.sql` 建好（`CREATE OR ALTER VIEW`，第 8–55 行）—— **不用重建，直接查询**；
每段单独执行（各出一个结果集），执行前照例先 `USE [ShiguangBookstoreVerify2];`。

| 截图 | 查询 | 说明 |
|---|---|---|
| `week-4-verify2-ssms-统计视图-1.png` | `SELECT TOP (20) * FROM dbo.[v_sale_detail] ORDER BY sale_id, sale_item_id;` | 销售明细：单 + 行 + 商品 + 行金额 |
| `week-4-verify2-ssms-统计视图-2.png` | `SELECT TOP (20) * FROM dbo.[v_goods_sales_summary] ORDER BY goods_id;` | 商品销售汇总：口径应与 Q4 的聚合一致（未卖出的商品为 0） |
| `week-4-verify2-ssms-统计视图-3.png` | 见下方「与基表对照」查询 | **同一批数字并排：视图 vs 基表** |

**第三张（视图 ↔ 基表对照）**：

```sql
USE [ShiguangBookstoreVerify2];
GO
SELECT
    v.[goods_id],
    v.[goods_name],
    v.[stock_total]   AS 视图_在架,
    g.[stock_total]   AS 基表_在架,
    v.[reserved_qty]  AS 视图_已订,
    g.[reserved_qty]  AS 基表_已订,
    v.[available_qty] AS 视图_可售,
    v.[is_sellable]   AS 视图_可卖
FROM dbo.[v_inventory_status] AS v
JOIN dbo.[goods] AS g ON g.[id] = v.[goods_id]
ORDER BY v.[goods_id];
GO
```

**预期**：三张结果与 `db/results/week-4-verify2-view.txt` 一致；第三张里 `视图_在架 ／ 视图_已订` 与 `基表_在架 ／ 基表_已订`
**逐行相同** —— 视图不独立存数据，它只是基表的派生口径。

### 3.8 不同角色权限 —— `week-4-verify2-ssms-角色权限-1/2.png`（2026-10-06 已拍）

实测：图 1 四行全部通过（`可见 4 件` · `已插入并回滚` · `可见 13 行` · `已更新并回滚`）；
图 2 只有 `SELECT` / `INSERT` / `UPDATE` 三类、状态均为 `GRANT` —— 其中 manager 的 `UPDATE` 对象数为 **4 = 列级 4 列**
（`goods.price` · `goods.on_shelf` · `card_type.card_fee` · `card_type.discount_rate`），**没有 `CONTROL` / `db_owner`**。

与 §3.3（越权失败 `229`）配对：本节拍**同一批角色"被允许的操作成功"** 与**授权清单**，合成"能看能改 vs 越权被拒"的正反例。

**第 1 张（允许的操作成功）—— `week-4-verify2-ssms-角色权限-1.png`**：

```sql
USE [ShiguangBookstoreVerify2];
GO
SET NOCOUNT ON;
DECLARE @r TABLE (角色 NVARCHAR(10), 允许的操作 NVARCHAR(30), 结果 NVARCHAR(80));

-- 收银员：查商品（只读）
EXECUTE AS USER = N'week4_cashier_user';
INSERT @r SELECT N'收银员', N'查询商品（读）', CONCAT(N'通过：可见 ', COUNT(*), N' 件') FROM dbo.[goods];
REVERT;

-- 库管：上报供应商报价（写，插入后回滚）
EXECUTE AS USER = N'week4_inventory_user';
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.[supplier_quote] ([supplier_id], [goods_id], [quote_amount], [reported_by], [reported_at])
    VALUES (3, 4, 2.75, N'13800000002', '2026-09-20T12:00:00');
    ROLLBACK;
    REVERT;
    INSERT @r VALUES (N'库管', N'上报供应商报价（写）', N'通过：已插入并回滚');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF USER_NAME() = N'week4_inventory_user' REVERT;
    INSERT @r VALUES (N'库管', N'上报供应商报价（写）', CONCAT(N'失败 ', ERROR_NUMBER()));
END CATCH

-- 店长：读资金流水（只读）
EXECUTE AS USER = N'week4_manager_user';
INSERT @r SELECT N'店长', N'读取资金流水（读）', CONCAT(N'通过：可见 ', COUNT(*), N' 行') FROM dbo.[fund_flow];
REVERT;

-- 店长：改商品售价（列级写权限，更新后回滚）
EXECUTE AS USER = N'week4_manager_user';
BEGIN TRY
    BEGIN TRAN;
    UPDATE dbo.[goods] SET [price] = 99.00 WHERE id = 1;
    ROLLBACK;
    REVERT;
    INSERT @r VALUES (N'店长', N'改商品售价（写）', N'通过：已更新并回滚');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF USER_NAME() = N'week4_manager_user' REVERT;
    INSERT @r VALUES (N'店长', N'改商品售价（写）', CONCAT(N'失败 ', ERROR_NUMBER()));
END CATCH

SELECT 角色, 允许的操作, 结果 FROM @r;
GO
```

**预期 4 行**：收银员 `通过：可见 4 件` · 库管 `通过：已插入并回滚` · 店长 `通过：可见 13 行` · 店长 `通过：已更新并回滚`
（与 `db/results/week-4-verify2-role.txt` 中的 `PASS|4`、`PASS|13` 一致）。

**第 2 张（授权清单）—— `week-4-verify2-ssms-角色权限-2.png`**：

```sql
USE [ShiguangBookstoreVerify2];
GO
SELECT dp.[name] AS 角色,
       p.[permission_name] AS 权限,
       p.[state_desc] AS 状态,
       COUNT(*) AS 对象数
FROM sys.[database_permissions] AS p
JOIN sys.[database_principals] AS dp ON dp.[principal_id] = p.[grantee_principal_id]
WHERE dp.[name] IN (N'bookstore_manager', N'bookstore_cashier', N'bookstore_inventory')
GROUP BY dp.[name], p.[permission_name], p.[state_desc]
ORDER BY dp.[name], p.[permission_name];
GO
```

**看什么**：三个角色只有 **`SELECT` / `INSERT` / `UPDATE`（列级）** 三类权限，**没有 `CONTROL` / `db_owner`** ——
最小权限落到了对象与列一级。
