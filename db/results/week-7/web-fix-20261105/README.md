# Web 修复验收证据（2026-11-05）

- 分支/标签：`fix/web-20261105` / `web-baseline-20261105`
- 验证库：`ShiguangBookstoreWeek7Fix20261105`（全新库名、全新登录前缀）
- 原始输出：`migration-summary.txt`、`fix-verification.json`
- 截图：`drafts/assets/web-fix-20261105/`、`drafts/assets/web-audit-20261105/`

## 一、迁移前后关键查询

| 指标 | 迁移前（v0.2-w6） | 迁移后（v1.0） |
|---|---|---|
| 经营实体 | 19 | 21（+`member_service`、`member_contact_history`） |
| 外码 | 47 | 49 |
| 筛选唯一索引 | 6 | 7（+`UX_stock_return_once`） |
| 现金余额 | `1430.30` | `555.30` |
| 经营盈亏 | `−69.70` | `−944.70` |

迁移前后分别引用，不用新数据覆盖旧截面；结构与账目明细见 `migration-summary.txt`。

## 二、权限矩阵（实测）

| 主体 | 动作 | 期望 | 实际 | 证据 |
|---|---|---|---|---|
| 匿名 | 访问 `/workspace` | 401 | 401 | `web-repro-20261104/07-workspace-anon.png` |
| 收银员 | 访问 `/management/goods` | 403 | 403 | `16-cashier-forbidden-management.png` |
| 库管 | 访问 `/management/reports` | 403 | 403 | `26-inventory-forbidden-reports.png` |
| 店长 | 调用商品删除 | 403 | 403 | `web-fix-20261105/F08-manager-forbidden.png` |
| 库管 | 删除有库存商品 | 409 | 409 | `web-fix-20261105/F08-stock-reject.png` |
| 库管 | 删除在架商品 | 409 | 409 | `web-fix-20261105/F08-shelf-reject.png` |
| 库管 | 删除被引用商品 | 409 | 409 | `web-fix-20261105/F08-ref-reject.png` |
| 库管 | 删除三无商品 | 成功 | 成功 | `web-fix-20261105/F08-delete-ok.png` |

## 三、回归

| 项 | 结果 |
|---|---|
| 全量测试 | 119 项通过（失败 0 / 错误 0 / 跳过 0） |
| 修复项验证 | F-02/03/04/06/07/08/11 共 12 项，全部 PASS（`fix-verification.json`） |
| 生命周期 | 连续 3 次 start/stop 无残留进程 |
| 新库 setup | 全新库名一次通过，`objects-runtime` 按名称集合校验 |
