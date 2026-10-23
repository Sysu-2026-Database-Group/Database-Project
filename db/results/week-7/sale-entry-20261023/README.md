# 门店销售入口验收

日期：2026-10-23（UTC+8）。按用户“继续”的指示，在员工认证与受限连接基础上实现门店销售。本次由AI执行技术测试，未记为人工浏览器验收。

## 环境与数据库

- 来源：`ShiguangBookstoreWeek6Work`，沿用已迁移的第六周业务样例。
- 新建专用销售测试副本：`ShiguangBookstoreWeek7SaleTests20261023`，COPY_ONLY/CHECKSUM备份、验证、恢复；不覆盖已有库或文件。
- 运行副本：`ShiguangBookstoreWeek7EntryYourRun`，部署销售DDL并重启本机Flask加载页面；运行副本只做读取和结算预览，没有提交测试销售。
- 登录基础可回滚测试：仍使用空凭据副本 `ShiguangBookstoreWeek7Entry20261022`。
- SQL Server默认实例，ODBC Driver17，Python3.12。销售测试通过四个既有受限SQL登录在专用测试副本中的临时数据库用户独立连接，未模拟DAO或以管理员代替运行连接。

## 证据与结果

| 文件 | 结果 |
|---|---|
| [01-prepare-tests.txt](01-prepare-tests.txt) | 新测试副本备份、校验、恢复成功。 |
| [02-entry-foundation.txt](02-entry-foundation.txt) | 部署登录基础成功。 |
| [03-sale-deploy.txt](03-sale-deploy.txt) | 首次部署销售过程成功。 |
| [04-sales-tests-initial.txt](04-sales-tests-initial.txt) | 首轮20项销售测试通过。 |
| [05-repeat-sale-deploy.txt](05-repeat-sale-deploy.txt) | 补全零额舍入处理后重复部署成功。 |
| [06-all-tests.txt](06-all-tests.txt) | 47项登录及销售测试通过。 |
| [07-final-tests.txt](07-final-tests.txt) | 增加真实HTTP表单确认测试后，最终48项全部通过，0失败、0错误、0跳过。 |
| [08-runtime-before.txt](08-runtime-before.txt)、[09-runtime-deploy.txt](09-runtime-deploy.txt) | 运行副本部署前旧列快照和部署成功输出。 |
| [10-runtime-preview.txt](10-runtime-preview.txt) | 实际5000端口服务：两名收银员可读取商品、打开表单及预览，两名其他岗位被拒绝；没有提交销售。源码：[runtime-preview-check.py](runtime-preview-check.py)。 |
| [11-final-state.txt](11-final-state.txt) | 测试库与运行库均22表/52外码/10个api过程；测试凭据、临时用户、故障触发器及测试销售已清理；运行4名员工凭据保留，无测试销售。源码：[final-state.sql](final-state.sql)。 |
| [12-runtime-after.txt](12-runtime-after.txt)、[13-tests-after.txt](13-tests-after.txt)、[14-source-after.txt](14-source-after.txt) | 部署及测试后的19张旧业务表快照。 |
| [15-snapshot-comparison.json](15-snapshot-comparison.json) | 四组各19项快照均与第一步保存的原始来源一致。 |

最终48项包含原登录25项，加销售23项（5项单元测试、18项真实数据库集成测试）。可执行代码见[tests/test_sales.py](../../../../tests/test_sales.py)。

销售覆盖：非会员、有效会员、到期当天、已过期、负积分、先折后扣、按分舍入、积分上限、零额不生成流水、库存与积分对账、保留已订量、下架与缺货、结算条件变化、同请求返回原结果、请求内容冲突、后段故障全回滚、本人凭证过滤及数据库权限隔离。多连接测试覆盖相同请求同时提交、最后一件可售库存竞争、同会员积分竞争、不同商品销售的资金余额衔接。

真实HTTP测试在专用库上启动临时本机HTTP服务，经过完整表单登录、选商品、预览、确认、303转到凭证页，并重复同一确认得到同一单；完成后停止临时服务并恢复数据。最终运行副本的HTTP验证仅预览，未生成测试交易。

故障测试故意通过测试库专属触发器抛出52999，在库存及积分写入后阻止资金入账，预期返回503并整笔回滚；控制台的异常日志属于该断言。管理员运行连接拒绝日志也属于预期测试。全部测试通过，非遗漏异常。

## 清理及快照范围

每项销售测试清理自己的销售、明细、库存/积分/资金流水和请求记录，恢复原商品、会员、卡参数，并比较相关表的完整JSON与测试前一致。测试类结束后删除临时数据库用户及测试员工凭据，故障触发器已删除。仅保留测试数据库、备份和过程部署；序列及IDENTITY允许存在空号。

最终跨库对照复用 `legacy-snapshot.sql`，旧列范围不包含`supplier.updated_by/updated_at`；19表旧列数据、来源前后及运行部署前后全部一致。此结论不声称数据库物理文件或技术元数据未变化。第六周历史交付审计另行通过。

## 复现

完整配置与命令见[应用README第8节](../../../../app/README.md#8-销售验收复现)。测试所需的两个副本须保持空测试凭据；服务连接从被忽略的本地配置加载。不要对运行副本运行清理式销售测试。

运行服务的只读预览检查：

```powershell
.\.venv\Scripts\python.exe db/results/week-7/sale-entry-20261023/runtime-preview-check.py
```

`final-state.sql` 保存的是部署验收时“尚未写入正式销售”的断言；用户开始办理真实练习销售后，不再要求运行副本请求记录为0。

设计见[门店销售入口](../../../../docs/design/sale-entry.md)。当前没有外部支付网关，页面由收银员确认现场已收款；预订取货、退款等仍待后续接入。
