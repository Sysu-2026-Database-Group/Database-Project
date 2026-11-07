# 拾光书店项目队友交接单

始于 2026-11-02，当前入口已同步至 2026-11-07 的复验。仓库：[Sysu-2026-Database-Group/Database-Project](https://github.com/Sysu-2026-Database-Group/Database-Project)，日常分支为 `main`。本文件用于队友接手、换电脑运行、演示与最后交付检查；实时开发状态仍以[任务台账](tasks/task-web-development.md)为准。

## 1. 接手时先核对

当前交付包含 Web 应用和第 5—6 周历史材料。完整业务链、设计取舍及截图见[实验报告](reports/report-web-v1.0.md)。当前数据模型和权限见[增量设计](design/web-model-extension.md)，验收与未关闭事项见[实施台账](tasks/task-web-development.md)。

## 2. 在本机复现

在独立库按[全角色手册](design/web-operation-manual.md)执行首次准备、运行和课堂演示。已有配置先运行 doctor。旧库缺过程或身份时采用手册中的增量安装。每条命令使用同一配置，实例、库名、端口或配置路径不确定时查[统一入口说明](design/unified-entry.md)。

## 3. 账号、配置和数据如何交接

| 文件或资源 | 用途与交接方式 |
|---|---|
| `run.example.json` | 无秘密示例。setup 成功后将生效配置写入所选 `-ConfigFile`，缺省文件名为 `run.local.json` |
| `app/settings.local.ps1` | 默认配置目录的服务连接和应用密钥；各电脑由setup自行生成，不复制他人连接，不提交Git |
| `app/demo-credentials.local.json` | 本机练习员工账号及随机口令；在本机打开查看，用于员工登录；不发到仓库或截图报告 |
| `settings.guest.local.ps1` / `settings.task.local.ps1` | 旧环境增量补身份时生成；新setup已在主配置内生成六种连接 |
| `.runner/` | 本地运行报告、备份相关清单及演示配置；默认不提交。需交付的脱敏证据已经归档到 `db/results/week-7/` |
| SQL Server 数据库和备份 | 不随Git传输；各电脑从脚本复现。测试库和备份保留会占磁盘，由数据库负责人按报告核对后管理 |

员工入口 `/auth/login`，根据本机凭据文件选择店长、库管或收银员。顾客不需要员工账号。会员自助凭证由收银员现场核验后发放/重置，不能仅凭手机号申领。预订凭证是手机号加预定码。

## 4. 验收证据

最新结果和历史批次均由[实施台账](tasks/task-web-development.md#最新证据)索引。反馈失败时附运行 ID、失败步骤、错误码和复现操作。

## 5. 课堂演示

按[手册的演示顺序](design/web-operation-manual.md#演示顺序)操作，使用新演示副本。可选浏览器脚本位于 scripts/browser_acceptance.py 与 scripts/browser_workflows.py，依赖 Playwright 和本机 Edge。写流程脚本会产生演示交易，仅允许用于独立 WebDemo 副本。

## 6. 还需要队友接手的事情

| 待办 | 需要保留的实际结果 |
|---|---|
| 另机复现证据归档 | 复现已有用户确认。待补执行人、日期、软件版本和 setup/doctor/test/start/verify-Http 原始输出 |
| 人工页面及业务签收 | 顾客/收银/库管/店长全流程操作，360px/桌面可读性、金额和来源对账，记录审阅人及具体问题 |
| 当前ER与课程材料核对 | [21实体drawio](../ER/er-diagram-web-v1.0.drawio)及[PNG](../ER/er-diagram-web-v1.0.png)人工核对；原第六周图和指纹保护材料保留 |
| 第二阶段真实分工 | 根据各成员实际工作补录，不能把第一阶段负责人复制成本阶段实现者；本轮AI实现/运行范围已在AI记录说明 |
| 技术遗留项 | 见[实施台账的交付边界](tasks/task-web-development.md#当前交付边界) |
| 正式交付打包 | 对照 `homework/` 原始要求核对应用、说明、阶段报告、分工、第5—6周成果；处理差距后再标记最终完成 |

人员分工由小组按实际安排确认，本文件不虚构新的负责人或签收记录。当前为核心实现及上述技术验收通过的阶段交付，不能据此直接声明所有课程要求已经签收。

## 7. 文件入口与协作约定

优先阅读：[全角色手册](design/web-operation-manual.md) → [实时台账](tasks/task-web-development.md) → [第 5—9 周实验报告](reports/report-web-v1.0.md)。模型见[Web增量说明](design/web-model-extension.md)，业务规则以 `docs/specs/` 为准。

源码主要在 `app/`，安装和业务过程在 `db/`，统一入口在 `run.ps1` / `scripts/project_runner.py`，测试在 `tests/`。不要修改历史证据的manifest来消除审计失败；新扩展写独立文档和迁移。不要提交 `.venv`、本机配置、口令、数据库文件或 `.runner`。

开始工作前先 `git pull --ff-only`（有未提交改动时先妥善保存）；建议新建功能分支，说明变更和验证再合入main，避免强制推送覆盖队友。排障反馈提供对应报告目录、失败步骤、错误码和复现操作，隐去连接串、口令、Cookie与凭证。
