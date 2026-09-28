# Week 3 数据库执行与复现说明

已实现并在本机 SQL Server 2025 Express（17.0.1000.7）验证。本周脚本创建 19 张表、47 个外键，装载数据字典中的 77 行样例，演示商品、库存和销售单 CRUD，并进行基础约束及对账检查。实际输出见 [第三周执行记录](results/week-3.md)。

## 1. 执行顺序

| 顺序 | 文件 | 内容与预期 |
|---|---|---|
| 1 | `schema.sql` | 创建专用数据库及 19 张表，设置主键、9 个业务唯一约束、47 个外键、非空、默认值和单行检查约束；字段含义写入 `MS_Description`。输出 `schema.sql PASS` |
| 2 | `sample-data.sql` | 按外键依赖装载 77 行样例，保留原主键。输出 `sample-data.sql PASS` |
| 3 | `verify.sql` | 检查结构、样例行数、来源关联、采购时序、库存、积分和资金；运行默认值正例、16 个基础约束反例。输出 `verify.sql PASS` |
| 4 | `crud.sql` | 新建演示商品，完成采购入库、非会员销售及全退，输出新增、查询、修改、删除的前后结果；最终回滚。输出 `crud.sql PASS` |
| 5 | `verify.sql` | 再次检查回滚后样例基线不变 |

每一步必须成功后再执行下一步。示例库名为 `ShiguangBookstoreWeek3`；重新从空库复现时使用新的名称，例如 `ShiguangBookstoreWeek3Replay`，不需要删除已有数据库。

## 2. 命令行执行

在仓库根目录打开 PowerShell。使用已有的 SQL Server 实例和 Windows 身份验证；本机默认实例可填写 `localhost`。

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek3 -i db/schema.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek3 -i db/sample-data.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek3 -i db/verify.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek3 -i db/crud.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek3 -i db/verify.sql
```

- `-S` 指定实例；如果安装的是命名实例，替换为实际实例名，例如 `localhost\SQLEXPRESS`。
- `-E` 使用 Windows 身份验证；`-C` 为本机练习实例信任服务器证书；`-b` 遇错返回非零退出码；`-f 65001` 保证中文按 UTF-8 读取。
- `DatabaseName` 是 SQLCMD 变量，五步必须一致。库名使用英文字母、数字和下划线，不能省略变量。
- 保存输出时，可在单条命令后加 `-W -s "|" -w 2000 -o "输出文件路径"`。先检查 `$LASTEXITCODE` 为 0，再继续。
- 建库需要实例上的创建数据库权限。不要把账号密码或连接凭据写入脚本与记录。

## 3. 在 SSMS 中执行

连接实例，新建查询窗口，启用 **查询 → SQLCMD 模式**。例如执行建库步骤：

```sql
:setvar DatabaseName "ShiguangBookstoreWeek3"
:r "D:\000MyWorkSpace\001ActiveProjects\Database-Project\db\schema.sql"
```

运行成功后，将第二行的文件名依次换成 `sample-data.sql`、`verify.sql`、`crud.sql`、`verify.sql`，逐步执行并查看“结果”和“消息”。如仓库不在示例位置，替换完整路径。也可直接打开单个脚本，在开头添加同一条 `:setvar` 后运行。

这些脚本使用 `GO`、`:On Error exit` 和 `$(DatabaseName)`，需要 SQLCMD 模式或 `sqlcmd`，不能直接作为一条普通 SQL 发给数据库驱动。请使用没有外层事务的新查询窗口。

## 4. 样例与重复运行

样例对应 **2026-09-20 收盘**，有效预订按该历史截面解释，不按今天的日期自动过期。

- `schema.sql` 只创建不存在的库或在没有用户表的空库中建表。已有表时返回错误 51000，不覆盖、不重建。
- `sample-data.sql` 对空表插入样例；已有内容与样例完全一致时不重复插入；不一致时返回错误 51001，并回滚本次装载，不覆盖经营数据。标识列通过 `IDENTITY_INSERT` 保持字典中的 id。
- `crud.sql` 只修改和删除本事务中新建、从未提交的演示数据，不删除或改写原样例历史。库存计数随演示流水同步；销售 UPDATE 使用全退状态迁移。脚本的 DELETE 用于课程演示，不能作为实际营业中的删单功能。
- 演示和约束测试回滚后，IDENTITY 自增值可能留下间隙。验收比较行内容、关联及对账结果，不要求下次演示 id 相同。
- 任何执行错误都应先查看消息。日期时间字面量使用完整的 `YYYY-MM-DDTHH:MM:SS`，会员到期日使用 `YYYY-MM-DD`。

复现关键结果：19 表、77 行；库存依次为 6、0、10、19；有效已订量为商品 1 的 6 件；会员 13900000001 积分 −26；现金余额 1430.30，经营盈亏 −69.70。

## 5. 本周验证与后续边界

`verify.sql` 明确检查结构和当前基线的跨表关系；这些验证查询不会自动维护以后的业务数据。基础 CHECK 能拒绝非法枚举、数量、金额、来源空值组合等；跨表的角色权限、积分余额上限、累计退货、档位间费率关系、完整状态迁移、自动过期、并发和重复请求处理仍需 Week 4 的事务、授权或业务逻辑落实，不能声称 26 条业务规则已全部实现。

Week 4 再补 `query.sql`、`view.sql`、`constraint.sql`、`role.sql`，不要重复创建本周已有约束。本周已完成 AI 操作的两次独立空库执行；**非作者组员独立复现和现场说明仍待完成**。执行者应在 `results/week-3.md` 补记自己的环境、步骤、实际结果与问题，不能把本次机器验证代替人工验收。
