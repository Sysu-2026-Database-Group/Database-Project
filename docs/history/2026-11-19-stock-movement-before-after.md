# 2026-11-19 库存流水增加调整前后数量

## 变更摘要

`dbo.stock_movement` 增加：

```text
stock_before INT NOT NULL   调整前物理库存（goods.stock_total）
stock_after  INT NOT NULL   调整后物理库存（goods.stock_total）
```

`quantity` **保留为普通列**，用于兼容既有查询、测试与对账；它不是唯一来源，必须满足：

```sql
quantity = stock_after - stock_before
```

## 为什么保留 quantity

按本次确认，库存口径为 `goods.stock_total`，不是可售量 `stock_total - reserved_qty`。保留 `quantity` 可以：

- 兼容现有 `SUM(quantity)` 对账、报表和测试；
- 让库存变化方向仍可直接读取；
- 通过 `CK_stock_movement_delta` 防止三列不一致。

代价是保留一列冗余；如果后续决定彻底删除，需要重写所有读取路径。

## 约束变化

新增：

```text
CK_stock_movement_bounds  stock_before >= 0 AND stock_after >= 0
CK_stock_movement_delta   quantity = stock_after - stock_before
```

重写 `CK_stock_movement_source`：

```text
购入 / 退货：stock_after > stock_before，且来源字段匹配
卖出 / 损坏：stock_after < stock_before，且来源字段匹配
损坏：stock_before - stock_after 在 1..1000，note 非空
```

主键、外码、`changed_by` 文本/手机号约束、`changed_at` 默认值和 `UX_stock_return_once` 均保留。

## 写入变化

`api.usp_adjust_stock` 在更新 `goods.stock_total` 后插入：

```text
stock_before = 调整前 @stock
stock_after  = 调整后 @new_stock
quantity     = @delta
```

`goods` 与 `stock_movement` 仍在同一事务中；失败一起回滚。

## 迁移

新增 `db/migration-stock-before-after.sql`，迁移键：

```text
W7-STOCK-BEFORE-AFTER
```

旧库回填方式：

1. 增加可空列；
2. 以当前 `goods.stock_total` 为最后一条流水的 `stock_after`；
3. 按 `changed_at DESC, id DESC` 反向累计 `quantity`，推导每行 `stock_before/stock_after`；
4. 校验非负、差值一致后改为 NOT NULL；
5. 重建约束并写入迁移标记。

迁移脚本幂等；新装库已有三列时只校验并记录标记。负库存或流水与当前库存不一致时中止，不留下半成品。

## 受影响的核心位置

```text
db/schema.sql
db/procedure.sql
db/sample-data.sql
db/sample-data-week-6.sql
db/tests/crud.sql
db/tests/week-10-objects.sql
db/checks/verify.sql
db/regression.sql
app/templates/operations.html
tests/test_sales.py
tests/test_operations.py
tests/test_returns.py
```

当前数据字典、Web ER、对象契约已同步；以往历史报告、旧 ER、旧设计文档不逐个修改，以本文件记录差异。

## 兼容性说明

- 旧查询仍可读取 `quantity`；
- 新查询应优先使用 `stock_before/stock_after`，尤其是历史截面；
- 若旧库迁移前 `goods.stock_total` 与流水累计不一致，迁移会报 `51105` 并回滚；
- `stock_movement` 直插的应用权限仍由 `bookstore_app_*` 的 `DENY` 约束，迁移不改变权限模型。

## 验证记录

- 全新库 `setup`：通过，31 条样例流水均满足 `quantity = stock_after - stock_before`；
- 旧结构库执行迁移：回填成功，重复执行显示 `SKIP`；
- 约束反例：前后数量与来源/方向不一致的直插被 `547` 拒绝；
- 完整测试：**123 通过，失败 0、错误 0、跳过 0**；
- Week6 历史 artifact audit：通过（19 表 / 137 字段，忽略本次 Week11 扩展列）。
