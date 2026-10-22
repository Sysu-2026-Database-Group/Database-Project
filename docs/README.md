# 文档与课程交付索引

课程原始要求以 [homework](../homework/) 内 DOCX 为准。第7—9周第二阶段作业要求保留第5—6周全部成果，不能只交应用。

当前 ER 使用：[v1.4 用户调整修订图](../ER/er-diagram-v1.4.drawio)、[PNG](../ER/er-diagram-v1.4.drawio.png)、[逐表审查与检查](../ER/review-v1.4.md)。保持原整体布局及19实体尺寸，4框微调对齐，单页展示137个业务属性；此前v1.4/v1.5重排稿已撤下，当前v1.4沿用用户调整的布局。人工验收已于2026-10-22由梁宇聪确认通过，旧阶段签收不沿用到本修订稿。

| 目录 | 内容 |
|---|---|
| [specs](specs/) | 场景、角色、业务、数据边界、数据字典 |
| [design](design/) | ER 映射、设计比较、依赖与规范化、问题清单、新样例规划 |
| [tasks](tasks/) | 第1—6周任务及第一阶段任务 |
| [reviews](reviews/) | 各周验收，Week6 只保留最新结论 |
| [reports](reports/) | 阶段报告、证据索引和组内分工 |
| [AI 使用记录](ai-usage-log.md) | 按实际工作周次记录 AI 协助、人工决定与验证范围 |
| [项目规范](project-conventions.md) | 目录、命名、协作和证据维护约定 |

## 作业要求与保留材料

| 作业要求 | 当前材料 | 状态与限制 |
|---|---|---|
| 第1周：场景、业务流程、角色、数据边界及理由 | [业务口径](specs/)、[验收](reviews/review-week-1.md) | 保留 |
| 第2周：表、字段域、码、关系与样例元组 | [数据字典](specs/spec-data-dictionary.md)、[验收](reviews/review-week-2.md) | 保留；旧记录引用的独立 `week-2-samples.md` 未在仓库找到，严格每表2—3行提交材料待核实，不能用整理代替补齐 |
| 第3周：建库、建表、样例、CRUD 与执行结果 | [schema.sql](../db/schema.sql)、[sample-data.sql](../db/sample-data.sql)、[crud.sql](../db/tests/crud.sql)、[结果](../db/results/week-3/) | 全部保留，空库复现顺序见 [db/README](../db/README.md) |
| 第4周及 v0.1：查询、视图、约束、角色授权与拒绝、正确/错误结果及截图 | [query.sql](../db/query.sql)、[view.sql](../db/view.sql)、[constraint.sql](../db/constraint.sql)、[role.sql](../db/role.sql)、[结果及截图](../db/results/week-4/)、[证据索引](reports/evidence-v0.1.md) | 全部保留，包括前几周成果、[阶段报告](reports/report-v0.1.md)、[分工](reports/team-division-v0.1.md)与 AI 记录 |
| 第5周：可编辑 ER 与清晰导出、基数/参与/条件/FK/实现映射、问题证据和取舍、三组设计比较 | [ER 图源](../ER/er-diagram-v1.0.drawio)、[PNG](../ER/er-diagram-v1.0.png)、[映射](design/er-mapping-v1.0.md)、[问题清单](design/issues-v0.1.md)、[设计说明](design/design-notes-v1.0.md) | 保留完整19表与规则；ER 全图人工验收已于2026-10-22由梁宇聪确认通过 |
| 第6周：逐表码/FD/三类异常/范式；分解、无损与依赖保持、冗余理由和维护 | [规范化说明](design/design-normalization-v1.0.md)、[数据字典增量](specs/spec-data-dictionary.md)、[ER](../ER/) | 保留完整分析；四张表明确保留非3NF冗余，有限样例通过不等于一般性无损证明 |
| 第6周：六项迁移、旧表保留、重复/冲突检查、备份与失败恢复；旧场景回归及前后差异 | [migration.sql](../db/migration.sql)、[regression.sql](../db/regression.sql)、[验收入口](../db/accept-week-6.ps1)、[最新独立审核](reviews/review-week-6.md)、[原始输出](../db/results/week-6/acceptance/) | 正式入口和所用测试全部保留；报告已合并为[第六周报告](reports/report-week-6.md) |
| 第7—9周 v1.0：包含第5—6周成果，并交应用、操作手册、分层/参数SQL/事务/后端权限/统一错误、多角色完整流程及正确/错误测试、阶段报告和分工 | [课程原件](../homework/第7-9周任务讲解.docx)、[当前业务待办](design/issues-v0.1.md) | 应用及其手册和测试尚未实现；现有 Week6 验收不能替代这些交付 |

## 整理范围

保留24份 SQL：根目录9份课程交付与装载脚本，`checks/` 3份辅助核对，`tests/` 12份演示、反例及专项测试。`migration.sql` 虽按版本执行一次，仍是必交成果，不能删。删除的3份 `i04-*` 是早期探测脚本，历史发现及证据限制留在规范化说明 §23。

第六周工作报告合并入正式周报告，剩余事项合并入问题清单。结果按 Week3、Week4、Week6 保存，第六周 `records/` 为逐项反馈，`acceptance/` 为唯一最新独立审核；原始输出、历史命令、课程原件、ER 图源和截图不改写。
