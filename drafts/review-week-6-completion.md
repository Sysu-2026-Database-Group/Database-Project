# 第六周复核（Reviewer B）· 2026-10-22

> **对象**：`169c697`（Reviewer A 验收提交）+ 本轮修复（未提交）
> **已关闭不再列出**：首轮 7 项已逐条验证关闭（`audit-week-6-artifacts.py` PASS、21/21 记录状态行、原漂移 7 处已登记、4 处文本已改、死分支已删）；独立复现 46 项通过。证据见 `db/results/week-6/acceptance-b-20261022/` 与 `docs/reviews/review-week-6.md` §6。
> **本文只保留未关闭的 13 项**：9 项产品/操作边界（第 7—9 周；含 1 项展示口径）+ 4 项验收链与工具问题。

---

## A. 产品与操作边界（9，第 7—9 周实现；不得写成"已具备"）

### A1. 重复请求无幂等 🟡

**Location:** `db/results/week-6/acceptance-b-20261022/26-duplicate-cancel-boundary-check.txt#L4`、`db/schema.sql`

**现状与影响:** 实测 `DIRECT_DML_ACCEPTED_NO_IDEMPOTENCY_GUARD`：同一取消再执行一次会更新 1 行。同一收货 / 取货 / 退款 / 取消被重试时，库存、资金、积分会重复变化；库里没有任何请求识别手段，事后无法区分"重试"与"新请求"。

**最小实现:**

```sql
// FILEPATH: e:\CodeBuddy\Database-Project\db\schema.sql

// ------ ORIGINAL CODE ------
-- （库内无任何请求识别结构；新增对象位置由第 7 周决定）
// --------------------------
// ------ NEW CODE ----------
CREATE TABLE dbo.request_log (
    request_key VARCHAR(64)  NOT NULL CONSTRAINT PK_request_log PRIMARY KEY,
    action      NVARCHAR(30) NOT NULL,
    result_ref  BIGINT       NULL,
    created_at  DATETIME2    NOT NULL CONSTRAINT DF_request_log_created_at DEFAULT (SYSDATETIME())
);
-- 入口：INSERT dbo.request_log(...)；若 2627，则按 request_key 回读 result_ref 返回原结果，不再改库存/资金/积分
// --------------------------
```

**验收用例:** 同一取消键提交两次，第二次返回原结果，`reservation` / `stock_movement` / `fund_flow` 行数不变。

### A2. 预订没有自动过期与已订量释放 🟡

**Location:** `db/results/week-6/acceptance-b-20261022/27-auto-expiry-boundary-check.txt#L4`

**现状与影响:** 固定 `2026-10-01 12:00` 时仍有 **2 条**过期但状态为"有效"的预订（`517436`、`W6R-2105`），输出 `AUTO_EXPIRY_NOT_APPLIED`。过期不释放已订量 → 可售量被长期占用，货在架上却显示无货。

**最小实现:**

```sql
// FILEPATH: e:\CodeBuddy\Database-Project\db\schema.sql

// ------ ORIGINAL CODE ------
-- （库内无定时作业、无过期过程）
// --------------------------
// ------ NEW CODE ----------
CREATE PROCEDURE dbo.usp_expire_reservations @as_of DATETIME2
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    UPDATE r SET r.status = N'已过期'
    FROM dbo.reservation r
    WHERE r.status = N'有效' AND r.expires_at < @as_of;
    -- 同一事务内按有效预订明细重算，避免加减漂移
    UPDATE g SET g.reserved_qty = COALESCE(x.qty, 0)
    FROM dbo.goods g
    OUTER APPLY (SELECT SUM(i.quantity) qty FROM dbo.reservation_item i
                 JOIN dbo.reservation r ON r.id = i.reservation_id
                 WHERE i.goods_id = g.id AND r.status = N'有效') x;
    COMMIT;
END;
// --------------------------
```

**验收用例:** 同一 `@as_of` 连跑两次，第一次过期 2 条、第二次 0 条（幂等）；`reserved_qty` 对应减少，不产生资金 / 积分流水。

### A3. 无并发控制（超卖） 🟡

**Location:** `db/*.sql`（`UPDLOCK` / `HOLDLOCK` / `SERIALIZABLE` / `sp_getapplock` 命中 0）

**现状与影响:** 库存判定与扣减是两条独立语句，中间无行锁。两名收银员同时卖最后 1 件，双方都可能读到"可售 1"，最终卖出 2 件或计数为负（`CK_goods_stock` 只能挡负值，挡不住"先读后写"）。

**最小实现:**

```sql
// FILEPATH: e:\CodeBuddy\Database-Project\db\schema.sql

// ------ ORIGINAL CODE ------
-- （现有写入路径为普通 UPDATE，无锁提示）
// --------------------------
// ------ NEW CODE ----------
BEGIN TRANSACTION;
SELECT @stock = stock_total, @reserved = reserved_qty
FROM dbo.goods WITH (UPDLOCK, HOLDLOCK) WHERE id = @goods_id;
IF @stock - @reserved < @qty THROW 51600, N'可售量不足', 1;
-- 同事务内写 sale / sale_item / stock_movement 并更新 goods 计数
COMMIT;
// --------------------------
```

**验收用例:** 两个会话各卖最后 1 件，只有一个成功，另一个得到 51600；`stock_total` 不小于 0。

### A4. 没有统一的业务入口 🟡

**Location:** `db/constraint.sql#L11`（全库唯一触发器）、`db/*.sql`（`CREATE PROCEDURE` 命中 0）

**现状与影响:** 采购、销售、取货、退货、办卡都是多条散装 SQL，没有过程封装；库存计数、流水、单据状态靠调用者自行保证顺序与事务。A1—A3 只能在入口层解决，所以这是它们的前置条件。

**最小实现:** 每个动作一个过程（`usp_sale_create` / `usp_reservation_pickup` / `usp_purchase_receive` / `usp_return_create`），内部完成"单头 + 明细 + 流水 + 计数"；随后收回业务角色对底表的写权限，只授 `EXECUTE`。

**验收用例:** `INSERT dbo.sale` 直接写被拒（错误 229），通过过程成功；中途失败整笔回滚且四项计数不变。

---

### A5. 积分可超额抵扣（R-7） 🟡

**Location:** `db/schema.sql` 的 `CK_sale_amount`、`db/checks/verify.sql` 的 `51211`

**现状与影响:** CHECK 只限制抵扣 ≤ 折后金额的 20%，`51211` 只校验"余额 = 流水和"。余额 0 的会员用 100 分 → 生成 −100 抵扣流水、余额变 −100，`51211` 与回归 `51551` 全部通过。规则允许"退货导致负余额"，不等于"消费时可超扣"，目前两者无法区分。

**建议:** 入口内先读 `member.points_balance` 并加 `WITH (UPDLOCK)`，`IF @used*100 > MAX(@balance,0) THROW`；余额判定与写流水同事务。

**验收用例:** 余额 0 的会员尝试抵扣 1 分被拒；负余额会员（退货导致）新消费可正常获取积分但不能抵扣。

### A6. 单据状态机不受控（R-5 / R-10 / R-12） 🟡

**Location:** `db/schema.sql` 的 `CK_purchase_request_stage`、`CK_reservation_cancel`

**现状与影响:** 两个 CHECK 只校验"当前状态 + 留痕组合"，**不比较修改前的状态**。可写入的非法跃迁：已审批 → 已取消（同时清空审批人/时刻）、已取 → 已取消（补取消留痕）、已收货 → 已审批。销售侧仅靠 `51214` 用累计退款反推状态，属事后校验。与 A1 不同：A1 管同一请求重提，本条管"换一个请求做不允许的跃迁"。

**建议:** 入口内 `SELECT status FROM … WITH (UPDLOCK)` 取旧值，按允许的迁移表判定；或在触发器里比较 `inserted`/`deleted` 的 status。

**验收用例:** 已审批单取消被拒；已取预订改为已取消被拒；终态重复操作被拒且不产生流水。

### A7. 会员业务无入口、办卡收费无快照（R-17 / R-18 / R-24） 🟡

**Location:** `db/schema.sql`（无过程）、`fund_flow` 表结构

**现状与影响:** 办卡、续费、升级、到期恢复都没有对象；`fund_flow` 只存金额与会员手机号，**没有存办理时的档位与应收费用**，事后无法复核收费是否符合当时参数（I-20 未闭环）。`member.expires_at` 只受日期关系 CHECK，不受"按 R-18/R-24 算出"的约束。

**建议:** 增加 `usp_member_card_open / usp_member_upgrade`，写入 `fund_flow` 时同时记录 `card_level` 与应收费用（或新增 `member_card_log`），并与 `expires_at` 计算同事务。

**验收用例:** 银卡升级金卡按当时差价收费、到期日不变；过期后重买从办理日起算；差额与 `fund_flow` 逐笔可对。

### A8. 岗位与动作匹配只覆盖两处（R-22 / spec-roles） 🟡

**Location:** `db/checks/verify.sql` 的 `51221`

**现状与影响:** 只检查 `stock_movement.changed_by` 与 `fund_flow.recorded_by` 的岗位。未覆盖：`sale.cashier_by`、`purchase_request.approved_by`、`supplier_quote.reported_by`、`member.opened_by/updated_by`、`card_type.set_by`。这些列只受外码约束（员工存在即可），填成别的岗位也不会报错；当前主要靠 GRANT 的表级权限间接限制，而权限按表不按动作语义。

**建议:** 把 `51221` 扩为逐列映射表（列 → 允许岗位），或下沉到各业务过程内校验。

**验收用例:** 库管被记为采购审批人时被拒；收银员被记为调价人时被拒。

### A9. 顾客侧展示无库内落点（R-2，展示口径，非操作） 🟡

**Location:** `db/view.sql#L40-L54`

**现状与影响:** `v_inventory_status` 输出 `on_shelf` 但**不过滤**，也没有仅含上架商品的顾客视图。"顾客只看到已上架商品"目前只是应用层约定，任何直连查询都能看到未上架商品与成本侧字段。

**建议:** 增加 `v_customer_goods`（`WHERE on_shelf = 1` 且只暴露可售量、名称、价格），顾客端只授该视图。

**验收用例:** 用顾客身份查询未上架商品返回 0 行。

---

## B. 验收链与工具（4）

### B1. 官方两个入口在本机无法执行，Reviewer B 用的是自写 runner 🟡

**Location:** `db/accept-week-6.ps1#L1`、`db/results/week-6/acceptance/independent-audit.ps1#L1`、`db/accept-week-6.ps1#L29`

#### 环境差异（造成无法验收官方脚本的直接原因）

| 项目 | 作者（Reviewer A） | Reviewer B（本轮） | 后果 |
| --- | --- | --- | --- |
| 主机 / 账户 | `DESKTOP-IJTRRN8\lyclyc_NSP` | `MOONY\38499` | 非同一台机器 |
| PowerShell | 7.6.5 | **5.1.26100.9711**（`pwsh` 不存在） | 两个脚本的 `#requires -Version 7.0` 直接拒绝执行 |
| SQL Server 实例 | `localhost`（默认实例 MSSQLSERVER） | `Moony\SQLEXPRESS`（命名实例） | `accept-week-6.ps1#L29` 的 `$Server -notin @('localhost','.', $env:COMPUTERNAME)` 只认默认实例 |
| 引擎版本 | 2025 Express 17.0.1000.7 | 2025 Express 17.0.1000.7 | 相同 |
| 源库 | `ShiguangBookstoreWeek3` | `ShiguangBookstoreVerify2`（迁移前 `verify.sql` 已证 19/47/77/1430.30/−69.70 与作者快照哈希逐表相同） | 内容等价，名字不同 |
| sqlcmd | 17.0.1000.7 | 同（ODBC 180 Tools） | — |

实测报错（两个脚本相同）：

```text
The script 'accept-week-6.ps1' cannot be run because it contained a "#requires"
statement for Windows PowerShell 7.0. The version of Windows PowerShell that is
required by the script does not match the currently running version of
Windows PowerShell 5.1.26100.9711.
```

**因此：官方两个 `.ps1` 入口一次都没有执行。** `.ps1` 外壳里的断言（读 `steps.json`、比对 19 表快照、比对清单哈希）我只做了等价重实现，不等于原样跑通；作者证据目录的实质校验由纯 Python 的 `db/checks/audit-week-6-artifacts.py` 完成（该脚本与本机 PS 版本无关，实测 `PASS`）。

#### 本轮实际使用的验收脚本

| 脚本 | 路径（仓库相对） | 版本要求 | 步数 | 与官方入口的差异 |
| --- | --- | --- | --- | --- |
| `run-b.ps1` | `db/results/week-6/acceptance-b-20261022/run-b.ps1` | PowerShell 5.1 | 40（00—39） | 与官方 45 步同序同断言；支持 `host\instance`；未实现官方 37/39/41—43；每步用 `sqlcmd -v DatabaseName=…` 原样调用同一批 `.sql` |
| `run-b-supplement.ps1` | `db/results/week-6/acceptance-b-20261022/run-b-supplement.ps1` | PowerShell 5.1 | 6 | 补官方 37（非权限异常 51039）、39（`msdb.backupset`）、41—43（越权注入 → 51030 → 撤销），另加一次撤销后复跑 |

产出与证据同目录：`db/results/week-6/acceptance-b-20261022/`（`steps.json` 46 条、`summary.json`、`manifest.json`、`source-manifest.json`、46 份步骤输出 `.txt`、`README.md`）。

**建议:** `#requires` 降到 5.1 或提供兼容分支；`$Server` 允许 `host\instance`；并在 README 写明"入口需要什么环境才可复跑"，避免下一位复核人重复踩。

### B2. 审计脚本把自己写进自己校验的清单 🟡

`db/results/week-6/acceptance/source-current-manifest.json` 含 `db/checks/audit-week-6-artifacts.py` 自身，改校验器一行就必然自证失败。

**建议:** 清单排除校验器自身，或单列 `checker_sha256` 只展示不断言。

### B3. 权限变异测试在官方脚本与我们脚本里各一份（即"两份脚本不一致"） 🟡

**Location:** `db/accept-week-6.ps1#L104-L120`、`db/results/week-6/acceptance-b-20261022/run-b-supplement.ps1`

**现状与影响:** 是，这一条本质就是"我们自己写的脚本和官方脚本各实现了一遍"。同一组判据（37 非权限异常、41—43 越权注入/撤销）在两处各写一份，实测差异有三：

| 项 | 官方 `accept-week-6.ps1` | 本轮 `run-b-supplement.ps1` |
| --- | --- | --- |
| 执行库 | **Failure 副本**（迁移已回滚的 v0.1） | **验收库**（已迁移并含角色） |
| 43 撤销 | 只 `REVOKE` | `REVOKE` + 查 `sys.database_permissions` 断言无残留 |
| 43 之后 | 无复跑 | 追加 44：再跑 `role.sql` 期望 0 |

两份都 PASS，但断言强弱与执行对象不同；任一侧后续改动都不会自动同步到另一侧，容易出现"两边都绿、实际不一致"。

**建议:** 抽成独立脚本 `tests/role-mutation-week-6.sql`（含注入、期望错误码、撤销与断言），官方 runner 与复核 runner 都调用它，保证同一份判据。

### B4. 视图不在验收链里，结构一致性依赖源库 🟡

**Location:** `db/accept-week-6.ps1`（无 `view.sql` 调用）、`db/results/week-6/acceptance-b-20261022/run-b.ps1`

**现状与影响:** 两个 runner 都不执行 `db/view.sql`。本轮验收库 `…R3` 里的 3 个视图（`v_sale_detail` / `v_goods_sales_summary` / `v_inventory_status`）是**随源库备份带过来的**，不是验收过程创建的。结构断言只校验表（19 / 20）与外码（47 / 49），不校验视图。后果：换一个没有视图的源库（例如只跑 `schema.sql` + `sample-data.sql` 的库）同样能"验收通过"，但两个验收库的实际结构并不相同。

**建议:** 把 `db/view.sql` 纳入验收链（迁移前后各执行一次），并在 `migration-check.sql` 中断言 3 个视图存在且可查询。

---

## 范围与副作用

业务语义零改动（`schema.sql`、`migration.sql` 主体、`regression.sql`、`role.sql` 均未触碰）；唯一 SQL 改动是删除 `sample-data-week-6.sql` 中不可达分支，改后已重跑 46 项。本机新增并保留 6 个库 `…B20261022 / …R2 / …R3` 及各自 `Failure` 与对应 `.bak`，未删除或覆盖任何既有库、备份、结果目录。
