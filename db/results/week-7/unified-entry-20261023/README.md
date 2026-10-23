# 统一入口验收记录（2026-10-23）

用户要求完成供队友换电脑准备环境、启动和验收的统一入口。实现根目录 `run.ps1` 的 help、doctor、setup、start、test、verify；用法见[统一入口说明](../../../../docs/design/unified-entry.md)。

本次由AI实际执行，非队友换电脑或人工浏览器签收。验证环境为 Windows PowerShell 5.1、Python 3.12、SQL Server 2022（16.0.1000.6，默认实例localhost）及ODBC Driver 17。代码支持本机命名实例及驱动17/18选择，尚未在另一台电脑、命名实例或ODBC18上实测。实例认证及服务状态未修改。

## 1 结果

| 验证 | 结果 | 文件 |
|---|---|---|
| 仅应用与runner测试 | 26项，无失败/错误/跳过 | `unit-summary.json` |
| 从仓库脚本准备基线及两个测试库，完整测试 | 58项，无失败/错误/跳过 | `test-summary.json`、`tests.txt` |
| 两个测试库19张业务表数据恢复 | 每表指纹与本次基线一致 | `business-fingerprints.json` |
| 临时用户、凭据、请求和故障触发器清理 | PASS；4个本次临时服务器登录已删除 | `test-summary.json` |
| 第六周原始脚本与证据只读审计 | PASS | `artifact-audit.txt` |
| 独立配置下首次setup | 完整建库、迁移、部署、服务登录及练习口令生成PASS | `setup-summary.json` |
| 独立新环境start及实际HTTP验证 | 5057端口启动、四员工登录/退出及岗位边界PASS；验证进程已停止 | `fresh-verify.json` |
| 既有运行环境doctor及verify -Http | PASS；保留原配置 | `runtime-doctor.json`、`runtime-verify.json` |
| 重复setup、错误目标库、无测试配置、非法选项、端口占用 | 均正确返回1，原运行配置文件指纹不变 | `failure-validation.json` |

完整测试中新加10项runner安全/失败判定测试；原应用及数据库测试48项继续执行。故障注入52999及预期配置拒绝在日志中可能打印异常，断言和最终结果均通过。

首次从脚本构建测试环境时发现旧销售测试写死扩展商品ID，受历史自增值消耗影响。修正为按ISBN定位，不修改历史SQL样例或第六周证据。销售测试还改为显式传入专用连接、逐条核对实际库/实例/登录，取消对运行连接字符串的替换；会员有效期相对门店当日准备，清理后恢复。

## 2 留存与边界

详细本机执行日志保留于被Git忽略的 `.runner/`；本目录只复制本次最终报告、测试输出、指纹和审计结果，不包含账号密码、会话密钥或秘密连接串。`source-hashes.json`对应最终完整测试时的主要源码；不包括随后补充的说明文档。

首次setup验证使用独立配置 `.runner/setup-validation.local.json`、运行库 `ShiguangBookstoreWeek7RunnerSetup20261023`、服务登录前缀 `bookstore_runner_setup20261023`；4个验证环境服务登录保留，用于重新启动该环境。秘密设置仅保存在被忽略的独立目录，ACL为当前用户和SYSTEM，无继承授权。既有 `app/settings.local.ps1` 及练习口令未重写。

基线、运行/测试数据库及COPY_ONLY备份均按入口设计保留，资源名见报告；没有自动删库。测试期间的本机5057服务已停止，原5000服务未由本轮替换。未新增业务页面，未commit或push。
