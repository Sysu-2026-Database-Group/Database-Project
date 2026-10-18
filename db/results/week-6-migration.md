# 第六周迁移执行记录

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 迁移脚本：[`db/migration.sql`](../../db/migration.sql)
- 执行方式：SSMS SQLCMD 模式；首次编译问题修订后重新执行
- 用户反馈：迁移结果符合预期

## 预期且已由用户确认的结果

| 项目 | 结果 |
|---|---:|
| 迁移后用户表 | 20 |
| 迁移后外码 | 49 |
| `schema_migration` 记录 | 1 |
| 旧供应商 NULL 留痕行 | 3 |

迁移脚本包含事务和失败回滚；旧 19 张业务表与旧业务记录原地保留。原始 `ShiguangBookstoreWeek3` 未执行迁移。

迁移后的独立只读核对已由用户在工作副本执行并反馈符合预期，记录见 [`db/results/week-6-migration-check.md`](./week-6-migration-check.md)。原始 SSMS 结果网格尚未复制到仓库；该反馈不替代后续非作者复核。
