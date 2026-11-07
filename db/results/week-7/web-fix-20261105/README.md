# Web 修复验收证据（2026-11-05）

- 分支/标签：`fix/web-20261105` / `web-baseline-20261105`
- 验证库：`ShiguangBookstoreWeek7Fix20261105`（全新库名、全新登录前缀）
- 原始输出：[结构与经营汇总](migration-summary.txt)、[修复验证](fix-verification.json)、[补充验收](supplement-accept.json)。JSON 中的旧截图路径保留为历史记录，原图未归档。
- 2026-11-07 使用新隔离库补拍了开卡、错误页和商品删除。见[本轮图证与数据库对账](../stage-report-20261107/README.md)。

## 一、历史迁移截面与 Web 验证库

| 截面 | 结构口径 | 资金口径 |
|---|---|---|
| 第六周迁移前的 v0.1 | 19 张用户表、47 个外码 | 旧场景现金 ¥1,430.30，经营盈亏 −¥69.70 |
| 第六周迁移后并扩充样例 | 20 张用户表、49 个外码 | 旧截面保持一致，扩充截面现金 ¥555.30，经营盈亏 −¥944.70 |
| 11 月 5 日 Web v1.0 验证库 | 21 个经营实体。该次实测 `dbo` 表 22 张、全库 63 个外码及 7 个筛选唯一索引 | 实测现金 ¥693.30。该库已有验证操作，数值对应当时的运行截面 |

第六周以[回归原始输出](../../week-6/acceptance/final-check/14-regression.txt)为准。Web 结构与账目明细见[当次运行输出](migration-summary.txt)和[增量模型](../../../../docs/design/web-model-extension.md)。

## 二、权限矩阵（实测）

| 主体 | 动作 | 期望 | 实际 | 证据 |
|---|---|---|---|---|
| 匿名 | 访问 `/workspace` | 401 | 401 | [11 月 7 日复验截图](../stage-report-20261107/13-login-required.png) |
| 收银员 | 访问 `/management/goods` | 403 | 403 | [11 月 7 日复验截图](../stage-report-20261107/14-forbidden.png) |
| 库管 | 访问 `/management/reports` | 403 | 403 | [11 月 4 日复现报告](../../../../drafts/Web复现报告-20261104.md)，原图未归档 |
| 店长 | 调用商品删除 | 403 | 403 | [修复验证 F-08e](fix-verification.json) |
| 库管 | 删除有库存商品 | 409 | 409 | [修复验证 F-08b](fix-verification.json) |
| 库管 | 删除在架商品 | 409 | 409 | [修复验证 F-08c](fix-verification.json) |
| 库管 | 删除被引用商品 | 409 | 409 | [修复验证 F-08d](fix-verification.json) |
| 库管 | 删除三无商品 | 成功 | 成功 | [修复验证 F-08a](fix-verification.json)及[11 月 7 日复验截图](../stage-report-20261107/16-goods-deleted.png) |
| 库管 | 删除后同编码重建 | 成功 | 历史记录为成功 | 11 月 5 日报告记录 `recreated same code`，原始脚本及输出未归档。11 月 7 日复验核对了[删除后的数据库记录](../stage-report-20261107/database-checks.json) |

## 三、回归

| 项 | 结果 |
|---|---|
| 全量测试 | 119 项通过（失败 0 / 错误 0 / 跳过 0） |
| 修复项验证 | F-02/03/04/06/07/08/11 共 12 项，全部 PASS（`fix-verification.json`） |
| 生命周期 | 连续 3 次 start/stop 无残留进程 |
| 新库 setup | 全新库名一次通过，`objects-runtime` 按名称集合校验 |
