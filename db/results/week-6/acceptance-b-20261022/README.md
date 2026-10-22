# Reviewer B 独立复现（2026-10-22）

> **性质**：第二名复核人（Reviewer B）在本机对第六周交付做的**独立复跑**，不是对 `../acceptance/` 的转抄。
> **结论**：46 项检查（40 步主流程 + 6 项补测）全部符合预期，旧基线、迁移前后语义、扩充截面与四类账目均与本机重算一致；本轮未发现新的执行阻塞。
> **入口**：`./db/results/week-6/acceptance-b-20261022/run-b.ps1`（本目录内，见下"与官方入口的差异"）。

## 1. 环境与对象

| 项目 | 本轮实际 |
|---|---|
| 执行者 | Reviewer B（AI 复核，用户授权 AI 自检口径） |
| 时间 | 2026-10-22，见 `steps.json` 与 `00-environment.txt` |
| 终端 | Windows PowerShell 5.1 |
| SQL Server | `.\SQLEXPRESS`，SQL Server 2025 Express 17.0.1000.7 |
| 来源库（只读） | `ShiguangBookstoreVerify2`（v0.1 干净基线：19 表 / 47 外码 / 77 行 / 1430.30 / -69.70） |
| 验收库 | `ShiguangBookstoreWeek6B20261022R3` |
| 故障副本 | `ShiguangBookstoreWeek6B20261022R3Failure` |
| 备份 | `COPY_ONLY` + `BACKUP CHECKSUM` + `RESTORE VERIFYONLY CHECKSUM`；未采集文件 SHA-256 |

来源库不是作者使用的 `ShiguangBookstoreWeek3`：本机没有该库，改用同一份 v0.1 结构与本机已存在的干净基线库，进入迁移前先用 `checks/verify.sql` 复核为 `19/47/77/1430.30/-69.70` 且 16 个反例全 PASS，确认与文档基线等价后才继续。

## 2. 与官方入口 `db/accept-week-6.ps1` 的差异

1. **PowerShell 版本**：官方入口 `#requires -Version 7.0`，本机只有 5.1，故使用本目录的 `run-b.ps1`（同序、同断言，去掉了 7.0 要求）。
2. **实例名**：官方入口的路径检查只接受 `localhost` / `.` / 主机名，本机是命名实例 `.\SQLEXPRESS`；`run-b.ps1` 支持 `host\instance`。
3. **官方 45 步内容已全覆盖**：第一轮缺的 37（权限变异·非权限异常）、39（备份元数据）、41—43（越权注入与撤销）由 `run-b-supplement.ps1` 补测，并额外增加一次撤销后复跑（44）。官方 40（原库拒绝）由本轮 `38-original-target-rejected` 承担。因此主流程 40 步 + 补测 6 项 = **46 项**，编号与官方不完全对齐。
4. 其余步骤顺序、断言与预期错误码与官方一致（34→1913、38→51040）。

## 3. 实测结果

| 项目 | 预期 | 本轮实际 |
|---|---|---|
| 旧基线 | 19 表 / 47 外码 / 77 行 / 1430.30 / -69.70 | `05-baseline.txt` 全部匹配 |
| 备份与还原 | 完整旧列快照一致 | `01 = 04`（19 表 SHA-256 全等） |
| 迁移结构 | 20 表 / 49 外码 / 77 旧行 / 1 记录 | `09-migration-check.txt` 逐项匹配 |
| 迁移语义 | 关键查询输出不变 | `06-query-before.txt` 与 `11-query-after.txt` 逐字节相同 |
| 重复数据检查 | 6 项均为 0 | `08-migration.txt` 六行全 0 |
| 重复执行 | 迁移 / 样例均 SKIP | `12`、`28` 未重复写入 |
| 扩充截面 | 198 业务行 + 1 技术行 | `14`、`29` 回归通过；现金 555.30、盈亏 -944.70 |
| 结构反例 | 22 项拒绝并回滚 | `16` 实际 22 行 PASS |
| 权限 | 3 次越权均 229 | `17` 实际 3 行 |
| 事务 | 547 整笔回滚 | `18` 销售/明细行数不变 |
| 专项 | 调价快照、供应商留痕、唯一索引、销售统计、库存、供应商成本、会员日期规则 | `19`—`25` 全 PASS；会员 11 个规则示例 |
| 边界 | 重复取消、自动过期 | `26`、`27` 按未实现记录，不记通过 |
| 测试污染 | 19 表快照不变 | `15 = 30` |
| 故障恢复 | 1913 回滚，DDL 无残留 | `34`—`36` 通过，`32 = 36` |
| 原库保护 | 51040 且原库不变 | `38` 退出 1、错误 51040；`01 = 37 = 39` |
| 权限判据抗误判 | 非权限异常必须上抛；越权授权必须被发现 | `supplement-37` 命中 51039、`supplement-42` 命中 51030；`43` 撤销并断言无残留，`44` 复跑通过 |
| 备份元数据 | COPY_ONLY + 校验位 | `supplement-39` 查 `msdb.backupset` 匹配本次备份 |

## 4. 本机副作用

- 新建并保留：`ShiguangBookstoreWeek6B20261022`、`ShiguangBookstoreWeek6B20261022R2` 及各自 `Failure` 副本。
- 新建备份：`<实例默认备份目录>\ShiguangBookstoreWeek6B20261022*.bak`。
- 来源库 `ShiguangBookstoreVerify2` 未被写入：`01`、`37`、`39` 三次快照与 `38` 的原库拒绝共同证明。
- 未删除、未覆盖任何既有数据库、备份或结果目录。

## 5. 复查方式

```powershell
# 只读复查：核对原始输出、退出码、快照与清单哈希（不连数据库）
python db/checks/audit-week-6-artifacts.py   # 针对作者证据目录
# 本目录的证据可用 manifest.json 逐文件核对：
Get-Content db/results/week-6/acceptance-b-20261022/manifest.json | ConvertFrom-Json |
    ForEach-Object { (Get-FileHash $_.file -Algorithm SHA256).Hash.ToLower() -eq $_.sha256 }
```

## 6. 已知范围

- 本轮仍**不覆盖**：重复请求幂等、自动过期与已订量释放、并发库存控制、完整业务事务入口——与本项目已声明的后续阶段边界一致，不作为本周通过项。
- 权限变异注入已由 `run-b-supplement.ps1` 补测（37 / 41—43），"判据不会误判 PASS"这条防线本轮已有独立证据；它仍属于测试判据的验证，不等于业务权限已实现。
