# 第六周验收记录

> **当前结论（2026-10-22）**：用户已明确允许 AI 自检。Codex 主代理按当前源文件在新隔离副本完成45步技术验收，全部符合预期；新增日期规则及反向变异检查通过。**梁宇聪于2026-10-22明确确认v1.4 ER图人工审查通过，本周声明范围内验收已完成**。未实现的应用入口按已接受的第7—9周边界登记，不属于本周待补技术项。

## 1. 验收口径与执行环境

允许 AI 自检、主代理复核及受委托子代理复跑，不另要求非作者组员重复执行。必须保留原始输出和真实执行归属；AI 通过不代表梁宇聪已经人工阅读或签收。该口径由用户本次明确调整，见[项目约定](../project-conventions.md)。

| 项目 | 本轮实际记录 |
|---|---|
| 委托人 | 梁宇聪 |
| 实际执行者 | Codex 主代理；本轮没有创建子代理 |
| 执行时刻 | `2026-10-21T22:09:24.4420684+08:00`，+08:00 |
| 终端与客户端 | PowerShell 7.6.5，SQLCMD 17.0.1000.7，Windows身份验证 |
| SQL Server | localhost，SQL Server 2025 Express 17.0.1000.7 |
| 来源库 | `ShiguangBookstoreWeek3`，只读快照、COPY_ONLY备份及必须失败的目标保护检查 |
| 新验收库 | `ShiguangBookstoreWeek6Final20261021220913` |
| 故障副本 | `ShiguangBookstoreWeek6Final20261021220913Failure` |
| 备份 | `C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Backup\ShiguangBookstoreWeek6Final20261021220913.bak` |
| 完整性 | COPY_ONLY、BACKUP CHECKSUM、RESTORE VERIFYONLY CHECKSUM通过；未取得操作系统备份文件长度或SHA-256 |

环境及元数据：[00-environment.txt](../../db/results/week-6/acceptance/final-check/00-environment.txt)、[39-backup-metadata.txt](../../db/results/week-6/acceptance/final-check/39-backup-metadata.txt)。副本和备份保留，未覆盖原有库。

## 2. 技术验收结果

| 核对项目 | 预期 | 实际与证据 |
|---|---|---|
| 旧基线 | 19表、47外码、77行，现金1430.30、经营盈亏-69.70 | [步骤05](../../db/results/week-6/acceptance/final-check/05-baseline.txt)全部匹配 |
| 迁移及旧语义 | 20表、49外码、77旧业务行，1条迁移记录；完整旧列与查询不变 | 步骤08—11及快照比对一致 |
| 重复数据 | 六项重复分组均为0 | [步骤08](../../db/results/week-6/acceptance/final-check/08-migration.txt)逐项输出0 |
| 新样例及四类账 | 商品10、会员6、采购10、销售9、预订8、退货5；现金555.30、盈亏-944.70 | 步骤13、14、29逐项断言通过；198业务行+1技术行 |
| 正反例与权限 | 22个反例，3个越权均229 | 步骤16/17明细匹配 |
| 中途失败与恢复 | 非法明细547整笔回滚；故障迁移1913回滚DDL | 步骤18、34—36符合预期 |
| 重跑及目标防护 | 迁移/样例重复运行不重复写入；原始库迁移被51040拒绝 | 步骤12、28、40符合预期 |
| 权限判据故障测试 | 非权限异常51039和错授权51030均使测试失败 | 步骤37、42符合预期，注入权限已撤销 |
| 多个合法NULL | 两个商品筛选唯一索引各允许5行NULL | [步骤21](../../db/results/week-6/acceptance/final-check/21-unique-index-week-6.txt)实际各5行 |
| 固定输入日期规则 | 5个有效性示例+6个首次/重买/闰日示例，预期与实际分列 | [步骤25](../../db/results/week-6/acceptance/final-check/25-member-validity-week-6.txt)11例匹配 |
| 日期测试反向验证 | 排除到期当天应51966；错误闰日应51967 | [变异结果](../../db/results/week-6/acceptance/final-check/date-mutations.json)2项均按预期失败 |
| ER技术一致性及人工确认 | 当前页签/标题v1.4、PNG内嵌源相同，19表137业务字段均展示，端点存在 | [ER一致性](../../db/results/week-6/acceptance/er-consistency.json)及[产物检查](../../db/results/week-6/acceptance/final-check/artifact-checks.json)通过；人工验收于2026-10-22由用户明确确认通过，见§5 |
| 理论与文档 | 逐表依赖/范式/异常、无损与依赖保持、报告总结和README一致 | [设计§25](../design/design-normalization-v1.0.md#25-19-表范式结论索引)、[报告](../reports/report-week-6.md)；四表严格非3NF的冗余取舍保留 |

六组快照每组19表均相同：来源/还原、还原/迁移、来源/步骤38、来源/最终、专项测试前/后、故障回滚前/后。迁移前后 `query.sql` 输出逐字节相同；没有用行数相同代替内容比较。

### 2.1 测试与后续应用边界

- `regression.sql` 是第六周固定装载快照验收，绝对行数、余额和旧商品当前值断言有意固定。第7—9周应用合法写入后，应运行相应业务测试，不复用本快照当通用健康检查。
- 日期专项的11个用例是独立固定输入的**规则示例**；6名会员标为 `STATIC_DATA_ONLY`，不再将从自身日期反推的结果当业务测试。重买起算日与闰日公式已验证，收费、续费/重买、权益恢复、正负积分保持的业务入口仍未实现；这些是后续阶段责任，不是当前功能通过。
- 重复取消直接UPDATE可被接受，事务回滚；固定时点仍有2张到期但有效的预订，输出 `AUTO_EXPIRY_NOT_APPLIED`。当前没有通用幂等、自动过期/占用释放、并发库存或完整统一事务入口。已如实记录范围，不以边界观测PASS宣称功能实现。
- 关系映射通过旧列快照、业务键、外码、来源归属及跨表对账验证；权限实际执行在 `role.sql`，由统一入口编排。没有以“脚本是否含映射二字”或“实体表存在”代替业务映射验收。

## 3. 原始执行索引

本轮输出在同一验收目录的 `final-check/`，是修改后的完整重跑证据；原上级00—44输出保留为此前子代理运行，不改写为本轮结果。正式验收结论仅为本文件。

| 步骤 | 预期退出 | 实际退出 | 原始输出 |
|---|---|---|---|
| 00-environment | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/00-environment.txt) |
| 01-source-before | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/01-source-before.txt) |
| 02-backup | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/02-backup.txt) |
| 03-restore | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/03-restore.txt) |
| 04-restored-snapshot | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/04-restored-snapshot.txt) |
| 05-baseline | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/05-baseline.txt) |
| 06-query-before | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/06-query-before.txt) |
| 07-constraint | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/07-constraint.txt) |
| 08-migration | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/08-migration.txt) |
| 09-migration-check | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/09-migration-check.txt) |
| 10-migrated-snapshot | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/10-migrated-snapshot.txt) |
| 11-query-after | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/11-query-after.txt) |
| 12-migration-repeat | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/12-migration-repeat.txt) |
| 13-sample | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/13-sample.txt) |
| 14-regression | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/14-regression.txt) |
| 15-expanded-before-tests | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/15-expanded-before-tests.txt) |
| 16-regression-negative | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/16-regression-negative.txt) |
| 17-role | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/17-role.txt) |
| 18-transaction-week-6 | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/18-transaction-week-6.txt) |
| 19-price-snapshot-week-6 | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/19-price-snapshot-week-6.txt) |
| 20-supplier-audit-week-6 | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/20-supplier-audit-week-6.txt) |
| 21-unique-index-week-6 | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/21-unique-index-week-6.txt) |
| 22-sales-statistics-week-6 | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/22-sales-statistics-week-6.txt) |
| 23-inventory-query-week-6 | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/23-inventory-query-week-6.txt) |
| 24-supplier-cost-week-6 | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/24-supplier-cost-week-6.txt) |
| 25-member-validity-week-6 | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/25-member-validity-week-6.txt) |
| 26-duplicate-cancel-boundary-check | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/26-duplicate-cancel-boundary-check.txt) |
| 27-auto-expiry-boundary-check | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/27-auto-expiry-boundary-check.txt) |
| 28-sample-repeat | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/28-sample-repeat.txt) |
| 29-final-regression | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/29-final-regression.txt) |
| 30-expanded-after-tests | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/30-expanded-after-tests.txt) |
| 31-failure-restore | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/31-failure-restore.txt) |
| 32-failure-snapshot-before | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/32-failure-snapshot-before.txt) |
| 33-inject-index-conflict | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/33-inject-index-conflict.txt) |
| 34-migration-rollback | 非0，错误1913 | 1 | [txt](../../db/results/week-6/acceptance/final-check/34-migration-rollback.txt) |
| 35-rollback-assertions | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/35-rollback-assertions.txt) |
| 36-failure-snapshot-after | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/36-failure-snapshot-after.txt) |
| 37-role-rejects-unexpected-error | 非0，错误51039 | 1 | [txt](../../db/results/week-6/acceptance/final-check/37-role-rejects-unexpected-error.txt) |
| 38-source-after | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/38-source-after.txt) |
| 39-backup-metadata | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/39-backup-metadata.txt) |
| 40-original-target-rejected | 非0，错误51040 | 1 | [txt](../../db/results/week-6/acceptance/final-check/40-original-target-rejected.txt) |
| 41-inject-permission-leak | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/41-inject-permission-leak.txt) |
| 42-role-rejects-permission-leak | 非0，错误51030 | 1 | [txt](../../db/results/week-6/acceptance/final-check/42-role-rejects-permission-leak.txt) |
| 43-remove-injected-permission | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/43-remove-injected-permission.txt) |
| 44-source-final | 0 | 0 | [txt](../../db/results/week-6/acceptance/final-check/44-source-final.txt) |

复查入口（只读数据库证据及当前源文件，重建JSON需显式传 `--output`）：

```powershell
./db/results/week-6/acceptance/independent-audit.ps1
```

重跑数据库需使用 `db/accept-week-6.ps1` 并传入全新库名及不存在的结果目录；不得覆盖本轮证据。

## 4. 原审核15项处理对照

| 原Issue | 处理结果 |
|---|---|
| 1 输出/索引 | 真实原始输出和本文件步骤索引已归档，旧SSMS反馈与新运行分开 |
| 2 状态列 | task-week-6 §3 已补状态/证据；第13/14项涉及的ER人工签收已于2026-10-22补录 |
| 3 ER版本 | 当前v1.4页签/标题/内嵌源/指纹统一，旧版本原样保留 |
| 4 无损与依赖保持 | 设计§25.1逐表记录恒等投影、依赖保持及四表非3NF取舍 |
| 5 会员测试 | 消除自证式业务通过判据，新增11个独立固定输入规则示例和2个拒绝错误算法的变异；应用动作按范围边界登记 |
| 6 权限分工 | 统一入口执行真实权限正反例，分工明确，不以角色存在代替权限执行 |
| 7 固定截面 | regression文件头明确固定样例验收用途，不改成不完整的时间过滤 |
| 8 README | 当前目录导航与第六周验收入口同步 |
| 9 冗余目标判断 | 已由调用者传参和Week6副本/原始库保护代替，步骤40实际验证 |
| 10 ER新属性 | 当前供应商含新增审计属性，19表137字段逐表核对 |
| 11 关系映射 | 原审核的关键字判断不适用；实际映射及来源关联回归通过 |
| 12 重复检查展示 | 六项计数输出均为0；展示多个NULL合法性 |
| 13 实验总结 | 补入成果、范式取舍、约束责任与经验，未采用19表均3NF的错误建议 |
| 14 同源基准 | 同一还原副本迁移前/后查询逐字节一致，完整旧列哈希一致 |
| 15 方法边界 | 本轮是真实数据库AI执行+源码/产物检查；人工确认与AI检查分别留痕，不宣称未实现入口通过 |

## 5. ER 图最终人工验收（已通过）

梁宇聪于2026-10-22在本对话明确反馈：“我已审查通过1.4版本的ER图”，并授权AI代为填写。本节据该人工确认补录，不表示AI代替本人完成审查，也不扩大到未实现的应用功能。用户未另行提供逐项检查意见，以下仅登记整体通过结论。

| 项目 | 人工确认记录 |
|---|---|
| 审核人 | 梁宇聪 |
| 确认日期 | 2026-10-22（本对话确认日期；未另行提供实际审查时刻） |
| 审查对象 | 当前 [v1.4 PNG](../../ER/er-diagram-v1.4.drawio.png)及[图源](../../ER/er-diagram-v1.4.drawio)，不指已撤销的同名重排稿 |
| 全图、联系基数、标签与连线检查结论 | 用户确认v1.4 ER图总体审查通过；未另行提供各子项意见 |
| 发现的问题及处理意见 | 本次确认未提出待整改项 |
| 最终验收结果 | 通过 |
| 记录方式 | 用户人工审查并确认，Codex按授权补录 |

当前第六周技术自检及ER人工验收均已完成。收费/续费、权益恢复、自动过期、幂等、并发等后续应用入口仍按§2.1的实际边界保留，不因ER通过而视为实现。当前指纹及确认来源另见 `db/results/week-6/acceptance/er-consistency.json`。
