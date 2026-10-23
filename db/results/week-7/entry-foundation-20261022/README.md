# 第七周第一步：登录与受控入口执行记录

执行日期：2026-10-22。由 AI 使用本机 `LZQ\18192` 管理身份执行技术验证，不记为人工独立复现。

后续状态：2026-10-23已在 `ShiguangBookstoreWeek7EntryYourRun` 完成独立服务登录、员工练习口令和实际HTTP验证，见[本机部署记录](../local-deployment-20261023/README.md)。本页其余内容保留2026-10-22原验收时的状态。

## 环境与执行范围

- SQL Server 默认实例 `localhost`，Windows 身份验证模式；ODBC Driver 17 for SQL Server。
- 来源：已完成第六周迁移及样例扩充的 `ShiguangBookstoreWeek6Work`。
- 新副本：`ShiguangBookstoreWeek7Entry20261022`，通过 COPY_ONLY/CHECKSUM 备份、校验及恢复建立，未覆盖来源或已有数据库。备份和副本保留。
- Python 3.12，Flask 3.1.3，pyodbc 5.3.0；依赖位于本地忽略的 `.venv`。
- 部署入口：[准备副本](../../../prepare-entry-test.sql)、[入口基础](../../../entry-foundation.sql)。

## 结果与证据

| 文件 | 实际结果 |
|---|---|
| [01-source-before.txt](01-source-before.txt) | 准备副本前19张业务表的旧列行数和SHA-256。 |
| [02-prepare-copy.txt](02-prepare-copy.txt) | 备份、VERIFYONLY、恢复到全新文件成功。 |
| [03-deploy-foundation.txt](03-deploy-foundation.txt) | 首次部署成功。 |
| [04-tests.txt](04-tests.txt) | 初次测试失败：23项，2 failures、18 errors；数据库游标未关闭，导致后续命令及 REVERT 被未消费结果阻塞。保留原始失败输出。 |
| [05-tests-after-cursor-fix.txt](05-tests-after-cursor-fix.txt) | 关闭游标后，23项测试全部通过。 |
| [06-repeat-deploy.txt](06-repeat-deploy.txt) | 增加迁移完成和模式所有者校验后，再次部署成功。 |
| [07-final-tests.txt](07-final-tests.txt) | 最终25项测试全部通过，0 failures、0 errors、0 skipped。 |
| [08-source-after.txt](08-source-after.txt)、[09-target-after.txt](09-target-after.txt) | 测试后来源和目标的旧列快照。 |
| [10-final-state.txt](10-final-state.txt) | 21张用户表、50个外码、4个应用角色及4个入口过程；凭据0行、测试用户0个；来源仍20表/49外码，19张业务表所有列数据与副本一致。 |
| [11-snapshot-comparison.json](11-snapshot-comparison.json) | 19项旧列快照的来源前后、来源与目标均一致。 |

最终测试包含11项 Flask 应用测试及14项真实 SQL Server 集成测试。覆盖四名既有员工的登录与本人身份查询、伪造角色/操作人、CSRF、账号停用、岗位变化、口令重置导致旧会话失效、初次凭据创建、拒绝管理员运行连接、拒绝多应用角色、拒绝直接读凭据/销售表或写业务表，以及认证与业务过程隔离。

集成测试中的临时数据库用户与随机口令哈希在同一管理连接事务内创建，以 `EXECUTE AS USER` 进入各真实数据库用户后执行 SQL，最后整笔回滚。测试替换的是 DAO 建立连接的步骤，过程和权限检查均由实际 SQL Server 执行。测试过程中预期出现的管理员连接拒绝日志，不是测试失败。

旧列快照复用历史 `legacy-snapshot.sql`，不含 `supplier.updated_by/updated_at`；[final-state.sql](final-state.sql) 另行包含这两列，比对来源与目标的全部19张业务表数据。没有改写第六周来源脚本、既有证据或其清单。

## 复现最终测试

在仓库根目录，使用已部署基础且尚无员工凭据的 Week7 副本：

```powershell
$env:BOOKSTORE_TEST_ADMIN_CONNECTION='DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=ShiguangBookstoreWeek7Entry20261022;Trusted_Connection=yes;TrustServerCertificate=yes;'
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
sqlcmd -S localhost -E -C -b -f 65001 -i db/results/week-7/entry-foundation-20261022/final-state.sql
```

快照比较可复用 `db/checks/legacy-snapshot.sql`，分别传入来源和目标 `DatabaseName`；按表名比较19行数据和指纹，忽略数据库上下文消息。

## 当前边界

本步没有配置四个独立服务器登录、持久员工口令或浏览器演示环境，也没有改变实例认证模式或重启服务。独立服务账号的真实连接验证仍待部署；不能用 `EXECUTE AS USER` 的测试结果代替这项验收。运行说明见 [应用 README](../../../../app/README.md)，身份信任边界见 [方案](../../../../docs/design/entry-permissions.md)。

当前仅实现登录、退出、本人身份查询及权限基础。销售、预订等写入入口、幂等、并发和自动过期仍在后续步骤。

## 追加：用户复现中的编码问题

2026-10-22，用户按应用 README 中原先缺少 `-f 65001` 的两条命令执行，准备步骤仅显示切换到 `master`，部署步骤报2760、`api`架构不存在。只读查询发现目标 `ShiguangBookstoreWeek7EntryYourRun` 并未创建，当前身份为sysadmin。UTF-8无BOM的中文注释探测脚本在默认编码下未输出查询结果，显式指定 `-f 65001` 后正常输出，定位为脚本读取编码问题。

已修正应用 README 和准备脚本中的命令示例，保留显式 UTF-8 参数；使用相同目标名重新执行，准备和部署均成功。证据为 [12-encoding-recovery-prepare.txt](12-encoding-recovery-prepare.txt)、[13-encoding-recovery-deploy.txt](13-encoding-recovery-deploy.txt)、[14-encoding-recovery-state.txt](14-encoding-recovery-state.txt)。该副本已具备api/auth架构、4个入口过程、21表/50外码，凭据仍为0行；没有配置服务登录或员工口令。此追加验证不替代前述25项测试，也不把原副本的测试结果记为在此新副本重跑。
