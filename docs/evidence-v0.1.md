# v0.1 结果与截图证据索引

本索引把 `docs/task-v0.1.md` 要求的八类结果对应到可重跑脚本和实际文件。文本输出是主要可复核证据，截图是辅助证据，不能替代 SQL。

| 官方八类 | 产生脚本 | 现有文本结果 | 现有 SSMS 截图 | 状态 |
|---|---|---|---|---|
| 成功建库 | `schema.sql`、`sample-data.sql` | `week-4-verify2-schema.txt`、`week-4-verify2-sample-data.txt` | `week-4-verify2-ssms-结构核对.png` | 已有 |
| 正常用例 | `crud.sql`、`constraint.sql` | `week-4-verify2-crud.txt`、`week-4-verify2-constraint.txt` | 当前没有单独的 SSMS 正常用例图 | 文本已有，截图待补 |
| 非法数据 | `verify.sql`、`constraint.sql` | `week-4-verify2-verify-before.txt`、`week-4-verify2-constraint.txt` | 当前没有单独的 SSMS 非法数据图 | 文本已有，截图待补 |
| 越权访问 | `role.sql` | `week-4-verify2-role.txt` | 当前没有单独的 SSMS 越权图 | 文本已有，截图待补 |
| 关键查询 | `query.sql` | `week-4-verify2-query.txt` | 当前没有单独的 SSMS 查询图 | 文本已有，截图待补 |
| CRUD | `crud.sql` | `week-4-verify2-crud.txt` | 当前没有单独的 SSMS CRUD 图 | 文本已有，截图待补 |
| 统计视图 | `view.sql` | `week-4-verify2-view.txt`、`week-4-view-compare.txt` | 当前没有单独的 SSMS 视图图 | 文本已有，截图待补 |
| 不同角色权限 | `role.sql` | `week-4-verify2-role.txt`、`week-4-role.txt` | `week-4-verify2-ssms-结构核对.png` 含角色和测试用户清单，但不含完整操作过程 | 角色对象图已有，操作截图待补 |

## 1. 已有 SSMS 截图

- `week-4-verify2-ssms-结构核对.png`：19 张表、47 个外键、主键、唯一约束、CHECK、视图、触发器、列说明、角色和测试用户；
- `week-4-verify2-ssms-对账-行数.png`：19 张表逐表行数及总行数 77；
- `week-4-verify2-ssms-对账-三本账.png`：库存、积分和资金链；
- `week-4-verify2-ssms-对账-已订量-修正.png`：修正后的有效已订量。

## 2. 建议补拍的 SSMS 截图

在 SSMS 连接 `ShiguangBookstoreVerify2` 后，使用查询窗口执行对应脚本或结果查询，并让截图同时包含查询语句、数据库名、结果或错误消息：

1. 正常用例：`crud.sql` 中商品插入、更新、查询和回滚前后的结果；
2. 非法数据：`constraint.sql` 中 `51025`、`547`、`2627` 错误及事务回滚消息；
3. 越权访问：`role.sql` 中三个角色的正常操作和 `229` 越权失败；
4. 关键查询：`query.sql` 的 Q1—Q7 结果，至少覆盖连接、`LEFT JOIN`、聚合、`HAVING` 和子查询；
5. CRUD：显示事务中 INSERT、SELECT、UPDATE、DELETE 的前后结果；
6. 统计视图：三个 `CREATE VIEW` 后的 `SELECT` 结果，并与基表对照；
7. 不同角色权限：分别显示 `EXECUTE AS USER` 下的成功与失败结果。

截图文件应使用 `week-4-verify2-ssms-<类别>.png` 命名，放入 `db/results/`，并在本表补充路径和拍摄日期。没有实际在 SSMS 中执行和截图前，不把“待补”改为“已有”。
