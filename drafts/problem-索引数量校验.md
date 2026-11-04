# 问题记录：从零 setup 必然失败 —— 筛选唯一索引数量校验写死 6

- **状态**：已定位 / 有临时补丁（本地未提交）/ 待作者确认正式修法
- **记录日期**：2026-11-04
- **复现人**：组员（非本版作者）
- **影响版本**：`a3f8551`（2026-11-02，Web 交付提交）及之后
- **严重级别**：**阻断（新机器无法完成 setup）**
- **相关文件**：`scripts/project_runner.py` · `db/migration.sql` · `db/return-entry.sql`

---

## 1. 现象

在一台**从未建过本项目数据库**的机器上，按交接单执行：

```powershell
.\run.ps1 setup -Server localhost\SQLEXPRESS ^
  -DatabaseName ShiguangBookstoreWeek7Repro20261104 ^
  -LoginPrefix bookstore_repro
```

前 27 步全部 PASS（建库、样例、迁移、应用基线、权限、9 个 runtime schema、两个 check 均通过），**最后一步失败**：

```text
[objects-runtime] FAIL
筛选唯一索引数量不符（7/6）。请使用新的 -DatabaseName 重新 setup，不要复用旧运行库。
```

失败发生在 `provision`（生成 6 个服务登录与本机配置）**之前**，因此：

- `.runner/<run>/settings/` 为空 → 无 `settings.local.ps1`、无 `demo-credentials.local.json`；
- 数据库对象其实已经建齐，但环境不可用（拿不到服务连接）。

**证据**：`.runner/setup-20261104T023331Z8fb351/summary.json`
（`status: FAIL`，`steps[27].name = objects-runtime`，`error` 为上述文案）。

---

## 2. 复现要点（用于证明"不是旧库污染"）

1. 使用**全新库名** `ShiguangBookstoreWeek7Repro20261104`（事先不存在，已用 `sys.databases` 确认）；
2. 使用全新登录前缀 `bookstore_repro`；
3. 用的不是任何既有副本，仍稳定复现。

> 报错文案"请使用新的 `-DatabaseName`"在此场景下是**误导**：换名字也不会好。

---

## 3. 根因

`scripts/project_runner.py` 的 `check_objects()`（第 179 行起）把筛选唯一索引数量**写死为 6**：

```python
# 修复前
def check_objects(config, database):
    """…Week4 三个视图、六个筛选唯一索引。"""
    ...
    (SELECT COUNT(*) FROM sys.indexes WHERE is_unique=1 AND has_filter=1)
    ...
    if filtered != 6:                                     # ← 写死
        problems.append(f'筛选唯一索引数量不符（{filtered}/6）')
```

而运行库实际有 **7 个**筛选唯一索引（2026-11-04 实测）：

| # | 表 | 索引 | 引入来源 |
|---:|---|---|---|
| 1 | `dbo.goods` | `UX_goods_book_isbn` | 第 6 周 `migration.sql` |
| 2 | `dbo.goods` | `UX_goods_toy_code` | 第 6 周 `migration.sql` |
| 3 | `dbo.sale` | `UX_sale_reservation_id` | 第 6 周 `migration.sql` |
| 4 | `dbo.point_movement` | `UX_point_movement_earn` | 第 6 周 `migration.sql` |
| 5 | `dbo.point_movement` | `UX_point_movement_use` | 第 6 周 `migration.sql` |
| 6 | `dbo.point_movement` | `UX_point_movement_return` | 第 6 周 `migration.sql` |
| **7** | `dbo.stock_movement` | **`UX_stock_return_once`** | **第 7—9 周 `return-entry.sql`（P5 退货回库）** |

脚本数量也能对上：`db/migration.sql` 有 **6 处** `CREATE UNIQUE INDEX`，`db/return-entry.sql` 有 **1 处**。

---

## 4. 时间线（为什么会漏）

| 日期 | 提交 | 事件 |
|---|---|---|
| 2026-10-18 | `bfe5d6e` | 第 6 周迁移建 6 个筛选唯一索引 |
| 2026-10-23 | `c9a80cc` | `project_runner.py` 加入对象校验，写死 `filtered != 6` —— **当时正确**（库里只有 6 个） |
| 2026-11-02 | `a3f8551` | P5 退货新增 `UX_stock_return_once` → 运行库变 7 个，**校验未同步** |
| 2026-11-04 | 本次复现 | 从零 setup 必失败 |

**结论**：不是索引数量本身有误，而是**校验常量没有跟随结构演进**。作者开发机上是"先有库、后加索引"，所以未暴露。

---

## 5. 影响范围

| 入口 | 是否受影响 | 说明 |
|---|---|---|
| `run.ps1 setup` | **是** | `objects-runtime` 步骤失败，环境不可用 |
| `run.ps1 doctor` | **是** | `objects` 步骤同样调用该函数 |
| `run.ps1 verify` | 可能 | 同样会检查对象（视步骤而定） |
| `run.ps1 test` | 否 | 走独立测试库路径，未触发该断言 |
| 交接文档"新环境可复现" | **冲突** | 与 `docs/team-handoff.md` §2/§4 的声明矛盾 |

附带问题：失败时步骤日志 `27-objects-runtime.log` 为 **0 字节**，错误只写在 `summary.json`，排查体验差。

---

## 6. 临时处理（已做，仅本地，未提交）

```diff
-def check_objects(config, database):
+def check_objects(config, database, expected_filtered=6):

-            if filtered != 6:
-                problems.append(f'筛选唯一索引数量不符（{filtered}/6）')
+            if filtered != expected_filtered:
+                problems.append(f'筛选唯一索引数量不符（{filtered}/{expected_filtered}）')

-    report.action('objects-runtime', lambda: check_objects(config, config['database']))
+    report.action('objects-runtime', lambda: check_objects(config, config['database'], expected_filtered=7))

-            report.action('objects', lambda: check_objects(config, config['database']))
+            report.action('objects', lambda: check_objects(config, config['database'], expected_filtered=7))
```

**为什么不能只把常量改成 7**：`check_objects()` 同时用于两处，两处数量不同——

| 调用点 | 检查对象 | 真实数量 |
|---|---|---:|
| 第 233 行 `objects-baseline` | 第 6 周基线副本（`ShiguangBookstoreWeek6Runner*`） | **6** |
| 第 342 行 `objects-runtime` | 运行库 | **7** |
| 第 520 行（doctor）`objects` | 运行库 | **7** |

基线副本由 `prepare_source()` 从 `schema.sql` 起逐步重放 `migration.sql` 得到，**设计上就停在 v0.2-w6**，不含 `return-entry.sql`，所以它应当是 6。

**补丁后实测**（新库 `...Repro20261104B`）：

```text
setup           PASS（28 步，objects-runtime 7/7）
doctor          PASS
test -Unit      49 通过
test（全量）    119 通过，失败 0 / 错误 0 / 跳过 0
start + verify -Http  PASS
```

---

## 7. 建议的正式修法（作者选一）

| 方案 | 做法 | 评价 |
|---|---|---|
| **A 参数化（最小）** | 同临时补丁：基线传 6、运行库/doctor 传 7 | 改动 3 处，风险最低；缺点是"两个数字"仍在 |
| **B 名字集合（推荐）** | 不数数量，校验**索引名集合**：6 个基线索引必须存在；运行库额外要求 `UX_stock_return_once` | 以后再加筛选唯一索引不会重演；报错可直接说"缺少 X 索引" |
| C 基线升到 v1.0 | 在 `prepare_source()` 里也装 `return-entry` 等，基线/运行库都变 7 | **不推荐**：会失去"第 6 周基线可独立重建"的验证意义，且需同步 week6 证据口径 |

同时建议：

1. 修正报错文案（"请使用新的 `-DatabaseName`"→"对象校验失败：缺少 X / 多余 Y"）；
2. 失败时把 `problems` 写入步骤日志，避免日志 0 字节；
3. 同步文档表述："第 6 周基线 6 个，运行库含退货回库索引后 7 个"（涉及 `scripts/project_runner.py` docstring、`db/README.md`）。

---

## 8. 验收标准（修好后应能验证）

1. 全新库名 + 全新前缀，`setup` **一次跑通**，`.runner/<run>/settings/` 生成完整配置文件；
2. `doctor`、`test`（119）、`verify -Http` 全部 PASS；
3. 人为删掉 `UX_stock_return_once` 后，运行库校验**明确报出缺少该索引**（而不是数量不符）；
4. 人为在基线上新增一个筛选唯一索引，`objects-baseline` 仍能按预期判定。

---

## 9. 关联

- 代码：`scripts/project_runner.py`（`check_objects` L179、调用点 L233 / L342 / L520）
- 结构：`db/migration.sql`（6 个索引）、`db/return-entry.sql`（`UX_stock_return_once`）
- 文档：`docs/team-handoff.md` §2/§4（"新环境可复现"声明与此冲突）
- 证据：`.runner/setup-20261104T023331Z8fb351/summary.json`、`.runner/doctor-*`、`.runner/test-*`、`.runner/verify-*`
- 相关提交：`bfe5d6e`（10-18）· `c9a80cc`（10-23）· `a3f8551`（11-02）
