# 文档与课程交付索引

## 当前使用入口

| 想了解什么 | 维护位置 |
|---|---|
| 课程交付的设计、实现与实验结论 | [第 5—9 周实验报告](reports/report-web-v1.0.md) |
| 首次建库、启动、四角色操作及排障 | [全角色手册](design/web-operation-manual.md) · [统一入口参数](design/unified-entry.md) |
| Web 实际数据模型、角色与事务边界 | [Web 增量模型与事务设计](design/web-model-extension.md)，基础经营规则仍由 [specs](specs/) 维护 |
| 最新技术验证、遗留边界与个人签收 | [实施台账](tasks/task-web-development.md) · [分工与签收](reports/team-division-v1.0.md) |
| 队友接手、凭据和证据交接 | [项目交接单](team-handoff.md) |

## 历史设计与证据

[Web 开发规划](design/plan-web-development.md)保存获准实施的范围和当时的设计候选。[早期实施指南](design/next-steps-guide.md)保存从登录与销售基线继续开发的顺序。[P2 采购与资金设计](design/p2-operations.md)及 [P3 公开目录设计](design/p3-public-catalog.md)保存各自阶段的实现依据，涉及后续变化时使用上表的当前设计入口。[过程材料索引](../drafts/README.md)保留审查、修复和交接批次。

课程原始要求以 [homework](../homework/) 内 DOCX 为准。第7—9周第二阶段作业要求保留第5—6周全部成果，不能只交应用。

第 5—6 周历史 ER：[v1.4 用户调整修订图](../ER/er-diagram-v1.4.drawio)、[PNG](../ER/er-diagram-v1.4.drawio.png)、[逐表审查与检查](../ER/review-v1.4.md)。保持原整体布局及19实体尺寸，4框微调对齐，单页展示137个业务属性；此前v1.4/v1.5重排稿已撤下，当前v1.4沿用用户调整的布局。人工验收已于2026-10-22由梁宇聪确认通过，Web v1.0 使用独立的[图源](../ER/er-diagram-web-v1.0.drawio)和[PNG](../ER/er-diagram-web-v1.0.png)，历史签收范围为 v1.4。

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
| 第6周：六项迁移、旧表保留、重复/冲突检查、备份与失败恢复；旧场景回归及前后差异 | [migration.sql](../db/migration.sql)、[regression.sql](../db/regression.sql)、[归档入口](../db/accept-week-6.ps1)、[最新独立审核](reviews/review-week-6.md)、[原始输出](../db/results/week-6/acceptance/) | 正式入口和所用测试全部保留；**第六周两脚本为归档入口（仅 PS7 + 默认实例）**，跨机复现改用根目录 `run.ps1`；报告已合并为[第六周报告](reports/report-week-6.md) |
| 第二阶段 v1.0（第 5—9 周） | [课程原件](../homework/第7-9周任务讲解.docx)、[实验报告](reports/report-web-v1.0.md)、[全角色手册](design/web-operation-manual.md)、[复验证据](../db/results/week-7/stage-report-20261107/README.md)、[AI 记录](ai-usage-log.md)、[分工表](reports/team-division-v1.0.md) | 四角色流程已实现，完整 119 项与本轮 Edge 16 节点通过。组内个人签收 2/3，部分分工、逐页人工记录及另机原始输出待补 |

## 整理范围

第3—6周保留24份 SQL：根目录9份课程交付与装载脚本，`checks/` 3份辅助核对，`tests/` 12份演示、反例及专项测试。第7周另增练习副本准备、登录基础、运行身份配置及销售入口脚本，执行证据保存于 `db/results/week-7/`。`migration.sql` 虽按版本执行一次，仍是必交成果，不能删。删除的3份 `i04-*` 是早期探测脚本，历史发现及证据限制留在规范化说明 §23。

第六周工作报告合并入正式周报告，剩余事项合并入问题清单。结果按 Week3、Week4、Week6 保存，第六周 `records/` 为逐项反馈，`acceptance/` 为唯一最新独立审核；原始输出、历史命令、课程原件、ER 图源和截图不改写。
