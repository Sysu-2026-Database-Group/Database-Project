# v0.1 阶段组内分工

本文记录第一阶段的实际分工，按周次和产出说明负责人。它是阶段过程材料，不改变正式业务、表结构或权限口径；正式口径以 `docs/spec-*.md` 为准。

## 1. 按周次分工

| 周次 | 负责人 | 主要工作 | 交付或证据 |
|---|---|---|---|
| Week 1 | 黄智亮 | 场景范围、经营角色、业务流程、数据边界的初稿与讨论；根据课程要求整理第一周方案 | `docs/spec-scenario.md`、`docs/spec-roles.md`、`docs/spec-businesses.md`、`docs/spec-data-boundary.md`；过程稿 `drafts/plan-week-1.md` |
| Week 2 | 黄智亮 | 19 张表、字段域、主键 / 候选码 / 外键和样例元组的数据字典方案 | `docs/spec-data-dictionary.md`；过程稿 `drafts/plan-week-2.md` |
| Week 3 | 梁宇聪 | SQL Server 建库建表、样例装载、结构与对账校验、CRUD 演示、空库复现 | `db/schema.sql`、`db/sample-data.sql`、`db/verify.sql`、`db/crud.sql`、`db/results/week-3*`、`drafts/plan-week-3.md` |
| Week 4 | 林泽群 | 多表查询、统计视图、跨行完整性约束、最小权限角色、复现结果和 SSMS 核对整理 | `db/query.sql`、`db/view.sql`、`db/constraint.sql`、`db/role.sql`、`db/results/week-4*`、`drafts/plan-week-4.md` |

## 2. 阶段性统稿与共同核对

林泽群负责 v0.1 阶段材料的统一编排、README 与执行顺序的整合、结果索引和阶段报告；黄智亮复核 Week 1—2 的业务、边界、字典与样例是否和数据库一致；梁宇聪复核 Week 3 脚本、对账和复现记录；三人共同确认最终提交内容。

“共同核对”只表示复核，不替代上表中各周的实际负责人。AI 参与起草和自查的范围、人工裁定和验证结论见 `docs/ai-usage-log.md`。

## 3. 验收责任分离

脚本负责人不独立完成自己的最终验收。v0.1 的空库复现、反例检查和证据核对应由非脚本作者组员执行并补录姓名、环境、命令和结果；本表只记录实现分工，不把当前执行者的机器运行自动写成全组验收。
