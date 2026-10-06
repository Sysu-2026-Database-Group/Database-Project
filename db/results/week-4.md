# Week 4 execution record

The four Week 4 scripts were added for the existing SQL Server schema. Run them after the
Week 3 scripts in this order: `query.sql`, `view.sql`, `constraint.sql`, `role.sql`.

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/schema.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/sample-data.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/query.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/view.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/constraint.sql
sqlcmd -S localhost -E -C -b -f 65001 -v DatabaseName=ShiguangBookstoreWeek4 -i db/role.sql
```

Expected markers are `query.sql PASS`, `view.sql PASS`, `constraint.sql PASS`, and
`role.sql PASS`. The Week 3 baseline remains 19 tables, 77 sample rows, cash balance 1430.30,
and operating result -69.70. The query/view scripts are read-only. Constraint negative cases
run in transactions and roll back. The role script grants no `db_owner`, `CONTROL`, or `ALTER`
permissions; customers remain a business-layer identity rather than a database role.

## 完整性约束补充：会员卡档位关系

数据字典 §3.1（R-17）规定：银卡初始办卡费为 20.00、折扣率为 0.95，金卡初始办卡费为 50.00、折扣率为 0.90；金卡办卡费必须严格高于银卡，金卡折扣率不得高于银卡。

该规则跨越 `card_type` 的两行，不能由单行 `CHECK` 约束表达。Week 4 的 `constraint.sql` 创建 `dbo.tr_card_type_cross_row`，在 `INSERT` 或 `UPDATE` 后检查两档关系。违反规则时触发错误码 `51025`，当前事务回滚。

实际证据：

- 合法正例：金卡办卡费增加 1.00；关系检查通过，事务回滚；输出 `PASS|valid card tier update accepted and rolled back`。
- 非法反例：把金卡办卡费改为银卡办卡费；触发器返回 `51025` 和 `Card tier relation is invalid.`，事务回滚。
- 回滚后基线仍为：银卡 `20.00 / 0.95`，金卡 `50.00 / 0.90`。


## 查询与视图的可复算预期结果

以下结果在 `ShiguangBookstoreWeek4Replay` 上通过只读查询复核，基于 Week 3 的 77 行样例数据。

| 编号 | 业务问题 | 预期结果 |
|---|---|---|
| Q1 | 查询每张销售单的商品明细、会员归属和成交快照 | 4 行销售明细 |
| Q2 | 查询所有商品的销售数量和原始销售金额，并保留无销售商品 | 4 行；商品 1 销量 5、金额 195.00；商品 4 销量 0、金额 0.00 |
| Q3 | 查询库存、已订数量和可售数量 | 4 行；商品 1 可售数量为 0，商品 3 为 10，商品 4 为 19 |
| Q4 | 查询销量至少为 2 件的商品 | 2 行；商品 1 和商品 2 |
| Q5 | 查询消费金额高于会员平均消费的会员 | 结果为空；当前样例只有一个会员有销售记录，没有会员高于会员平均值 |
| Q6 | 查询采购单、供应商、采购明细和供应商报价 | 5 行采购明细 |
| Q7 | 查询销售明细的累计退货数量和剩余可退数量 | 4 行销售明细；存在 2 条退货明细 |

视图预期结果：

| 视图 | 业务含义 | 预期结果 |
|---|---|---|
| `v_sale_detail` | 销售单及其明细 | 4 行 |
| `v_goods_sales_summary` | 所有商品的销量和销售额 | 4 行；包含商品 4 的 0 销售记录 |
| `v_inventory_status` | 商品库存、已订数量和可售数量 | 4 行；商品 1 可售数量 0，商品 3 为 10，商品 4 为 19 |

独立复核结果保存在：

```text
db/results/week-4-expected.txt


## 角色权限矩阵

本矩阵与 `db/role.sql` 的实际 GRANT 和 EXECUTE AS 测试对应。

| 角色 | 能看 | 能改 |
|---|---|---|
| 店长 | 员工、商品、会员卡参数、销售单、销售明细、预订单、预订单明细、会员、采购申请、采购明细、资金流水、库存流水、积分流水 | `goods.price`、`goods.on_shelf`、`card_type.card_fee`、`card_type.discount_rate` |
| 收银员 | 商品、会员、预订单、预订单明细、销售单、销售明细、退货单、退货明细 | 新增会员、新增预订单及明细、新增销售单及明细、新增退货单及明细 |
| 库存管理员 | 商品、图书、文创、供应商、供应商报价、采购申请、采购明细、库存流水 | 新增商品、新增供应商报价、新增采购申请及明细、新增库存流水 |
| 顾客 | 业务层中属于自己的商品公开信息、预订单和单据 | 通过业务层创建自己的预订单；不能直接写数据库表 |

权限边界说明：

- 店长不能直接更新销售单内容；
- 收银员不能修改商品价格；
- 库存管理员不能插入销售单；
- 店长、收银员和库存管理员均未授予 `db_owner`、`CONTROL` 或 `ALTER`；
- 顾客不创建员工式数据库角色，因为顾客是外部主体，不属于店内经营角色；
- 顾客查询通过手机号与预订码等业务凭证验证归属，手机号本身不能单独作为授权凭证。

实际权限证据位于：

```text
db/results/week-4-role.txt
db/results/week-4-replay-role.txt
```

---

## 非作者组员独立复现（2026-10-05）

| 项 | 内容 |
|---|---|
| 执行者 | 组员（**非脚本作者**） |
| 环境 | SQL Server 2025 (RTM) 17.0.1000.7 (X64) · Express Edition · Windows 10 Home China 10.0（Build 26200）· 实例 `localhost\SQLEXPRESS` · Windows 身份验证 · `sqlcmd` 17.0.1000.7 + ODBC Driver 18（本机需 `-C`） |
| 库 | `ShiguangBookstoreVerify2`（本次新建；该实例此前**没有本项目任何数据库** → 属另一环境的独立复现） |
| 输出 | `db/results/week-4-verify2-*.txt`（9 份，见下） |

**实际执行的命令**（仓库根目录，PowerShell；等价于 `db/README.md` §2 的九步，仅换了实例名、库名与输出名）：

```powershell
$Srv='localhost\SQLEXPRESS'; $db='ShiguangBookstoreVerify2'
$steps=@(
 @{f='db\schema.sql';        o='db\results\week-4-verify2-schema.txt'},
 @{f='db\sample-data.sql';   o='db\results\week-4-verify2-sample-data.txt'},
 @{f='db\verify.sql';        o='db\results\week-4-verify2-verify-before.txt'},
 @{f='db\crud.sql';          o='db\results\week-4-verify2-crud.txt'},
 @{f='db\verify.sql';        o='db\results\week-4-verify2-verify-after.txt'},
 @{f='db\query.sql';         o='db\results\week-4-verify2-query.txt'},
 @{f='db\view.sql';          o='db\results\week-4-verify2-view.txt'},
 @{f='db\constraint.sql';    o='db\results\week-4-verify2-constraint.txt'},
 @{f='db\role.sql';          o='db\results\week-4-verify2-role.txt'}
)
foreach($st in $steps){
  sqlcmd -S $Srv -E -C -b -f 65001 -W -s "|" -v DatabaseName=$db -i $st.f -o $st.o
  "{0,-24} exit={1}" -f $st.f, $LASTEXITCODE
  if($LASTEXITCODE -ne 0){ 'STOP'; break }
}
```

**结果：九步退出码全部为 `0`**，各脚本的标志行与实际输出一致：

| 步 | 脚本 | 退出码 | 标志行 |
|---|---|---|---|
| ① | `schema.sql` | 0 | `schema.sql PASS: 19 tables, 47 foreign keys.` |
| ② | `sample-data.sql` | 0 | `sample-data.sql PASS: baseline loaded or unchanged (77 rows).` |
| ③ | `verify.sql`（前） | 0 | `verify.sql PASS: metadata, baseline reconciliation, defaults and 16 negative cases.` |
| ④ | `crud.sql` | 0 | `crud.sql PASS: goods / inventory / sale CRUD completed and rolled back.` |
| ⑤ | `verify.sql`（后） | 0 | 同 ③ |
| ⑥ | `query.sql` | 0 | `query.sql PASS` |
| ⑦ | `view.sql` | 0 | `view.sql PASS` |
| ⑧ | `constraint.sql` | 0 | 7 条 `PASS`（触发器 `51025` · `547` × 5 · `2627`） |
| ⑨ | `role.sql` | 0 | 6 条 `ROLE TEST` 全 `PASS`（越权 `229` × 3） |

**核验（不只看 PASS）**：

- 基线行 `baseline|19|47|77|1430.30|-69.70`，与本文档预期一致；
- `verify-before` 与 `verify-after` **逐字节相同** → CRUD 演示回滚干净，基线未被改动；
- 反例与越权确实被拒：`51025`（卡档位跨行）· `547` × 5 · `2627` · `229` × 3；
- `Q1`–`Q7` 与三个视图的结果与本文件前方的**预期表逐条一致**（含"商品 4 销量 0"、`Q5` 返回空）。

**遇到的问题与处理**：

1. **实例是命名实例** —— `-S localhost` 连不上，改用 `localhost\SQLEXPRESS`（`db/README.md` §0 已补"实例名以本地为准"）；
2. **ODBC Driver 18 默认强制加密** —— 命令需加 `-C`（`db/README.md` §2 已补）；
3. **沿用已有库名会被挡下** —— 该库已存在且含表时，`schema.sql` 按设计报 `51000` 停止（防呆，不覆盖数据），换新库名即通过（`db/README.md` §2 已补说明）；
4. 输出中金额 `0.00` 显示为 `.00` —— 是 `sqlcmd -W` 的显示习惯，**不是数据问题**；
5. 复现脚本自身的一个坑：**PowerShell 变量名不区分大小写**，循环变量 `s` 覆盖了实例名变量（报错为"与 System.Collections.Hashtable 建立连接"）—— 与项目脚本无关，改名即解决。

**结论**：`docs/task-week-4.md` 第 12 条（非作者组员从空库复现）**已达成**。

八类 SSMS 截图已于 2026-10-06 逐张补齐（清单、对应语句与预期见 `docs/evidence-v0.1.md`）。

### SSMS 人工核对（同日）

在 sqlcmd 复现出的库 `ShiguangBookstoreVerify2` 上，用 SSMS（对象资源管理器 + 查询）**人工**核对对象与权限，结果与脚本自检一致：

| 核对项 | 实测 | 预期 |
|---|---|---|
| 表 | **19** | 19 |
| 外键 | **47** | 47 |
| 主键 | **19** | 19 |
| 唯一约束 | **9** | 9 |
| `CHECK` 约束 | **95** | 95 |
| 视图 | **3** | 3 |
| 触发器 | **1** | 1 |
| 列注释（`MS_Description`） | **135** | = 字段总数 135 —— **每列一条，全覆盖**（表级未单独写注释） |
| 角色 / 测试用户 | **3 个角色 + 3 个 `SQL_USER`**（`WITHOUT LOGIN`，越权测试用） | 3 + 3 |

截图留档：`db/results/week-4-verify2-ssms-结构核对.png`
（上半为对象计数，下半为角色与测试用户清单）。

核对方式：SSMS 连接 `localhost\SQLEXPRESS` → 查询 `sys.tables` / `sys.foreign_keys` / `sys.key_constraints` /
`sys.check_constraints` / `sys.views` / `sys.triggers` / `sys.extended_properties` / `sys.database_principals`。

**数据与对账核对（同一库，SSMS 查询）**：

- **行数**：19 张表逐表计数，**合计 77 行** ✓
  （`fund_flow` 13 · `stock_movement` 12 · `purchase_request_item` / `point_movement` / `supplier_quote` 各 5 ·
  `employee` / `goods` / `sale_item` 各 4 · `purchase_request` / `sale` / `supplier` 各 3 · 其余 8 张各 2；**每张 ≥ 2 行**）
  —— 截图：`db/results/week-4-verify2-ssms-对账-行数.png`
- **样例总行数 / 在架总量 / 积分 / 资金链**（四段结果同屏）
  —— 截图：`db/results/week-4-verify2-ssms-对账-三本账.png`
  - 总行数 **77** ✓；
  - **在架总量 = 变动累加**：商品 1 / 2 / 3 / 4 → **6 / 0 / 10 / 19**，两列逐行相等 ✓；
  - **积分余额 = 流水之和**：`13900000001` → **−26 / −26** ✓；
  - **资金链**：**13 笔**流水，末笔 `fund_before` 1930.30 → `fund_after` **1430.30** ✓。
  - ⚠️ 该图**最后一段（有效已订量）是修正前**的查询结果，见下条：已由修正版取代。
- **八类验收截图**（2026-10-06 补拍，13 张）：正常用例 · 非法数据 · 越权访问 · 关键查询 1–4 · CRUD ·
  统计视图 1–3 · 角色权限 1–2 —— 清单、对应语句与预期值见 `docs/evidence-v0.1.md`。
- **有效已订量**（人工复核，修正后）：商品 1 → **6 / 6**，商品 2 / 3 / 4 → **0 / 0** ✓
  —— 截图：`db/results/week-4-verify2-ssms-对账-已订量-修正.png`；
  与 `query.sql` 的 Q3（`reservation_detail_qty` = 6 / 0 / 0 / 0）及 `verify.sql` 一致。
  **经营盈亏 −69.70** 由 `verify.sql` 的基线行佐证。
- ⚠️ **人工手写对账查询的一处写法坑**：有效预订的过滤条件必须写进 **`WHERE`**（或 `SUM(CASE WHEN … )`），
  写进 `LEFT JOIN … ON r.status = N'有效'` **不会**排除"已取 / 已取消 / 已过期"的行 ——
  `ON` 里的是"匹配条件"，不是过滤器（右表不匹配时那行**仍在结果里**，只是右表列为 NULL）。
  仓库里的 Q3 与 `v_inventory_status` 用的就是 `CASE` 写法，故结果正确。