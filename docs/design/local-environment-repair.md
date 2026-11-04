# 本机开发环境修复

当前诊断日期：2026-11-02。用户已授权安装项目依赖。此处处理依赖、执行审批和SQL连接，项目进度仍以 [Web开发台账](../tasks/task-web-development.md) 为准。

## 1. 在自己的 PowerShell 中安装和诊断

请在Windows终端或IDE的普通PowerShell终端运行，不是在AI工具调用中运行。通常不需要管理员权限。

```powershell
Set-Location -LiteralPath 'C:\Users\18192\Desktop\Database-Project'
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair-local-environment.ps1
```

这里的 `-ExecutionPolicy Bypass` 仅允许本次PowerShell进程运行仓库脚本，不会修改系统执行策略，也不改变Codex审批或沙箱策略。

脚本仅在项目内创建虚拟环境、安装 `requirements.txt` 的依赖、运行单元测试，以及用Windows身份执行SQL只读诊断。它不执行setup、不创建数据库、不改实例认证、不重启服务、不重置口令。测试结果在 `.runner/test-*`。

安装成功后重复诊断可跳过安装；命名实例需填写实际实例名：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair-local-environment.ps1 -SkipInstall
# 仅在实际使用命名实例时：
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair-local-environment.ps1 -SkipInstall -Server 'localhost\SQLEXPRESS'
```

如果pip仍报WinError10013、代理或TLS错误，先检查当前终端是否可以访问PyPI：

```powershell
Test-NetConnection pypi.org -Port 443
.\.venv\Scripts\python.exe -m pip --version
```

443失败时检查本机网络、组织代理和终端进程的防火墙权限，按所在网络的要求配置代理。不要关闭TLS验证或整机防火墙。能联网的另一台Windows机器也可用相同Python版本下载离线依赖：

```powershell
# 在能联网的Windows机器上，使用与本机相同的Python版本和架构：
python -m pip download -r requirements.txt -d wheelhouse
# 将wheelhouse目录拷贝到本项目根目录，在本机运行：
.\.venv\Scripts\python.exe -m pip install --no-index --find-links .\wheelhouse -r requirements.txt
```

## 2. 修复 Codex 自动审批服务

已读取到的非秘密配置：`C:\Users\18192\.codex\config.toml` 当前 `model_provider="rightcode"`、`model="gpt-6.1-sol"`；provider地址为 `https://rightapi.ai/codex/v1`，协议为 `responses`。自动审批请求在此地址返回HTTP404、`model not found`，所以安装命令未执行。用户许可本身没有缺失。

该错误只能证明审批链路的模型请求无法路由，不能据此断言普通对话模型也不可用，也不能确定审批内部具体使用哪个模型。项目代码和requirements无法修复提供方的模型映射。

1. 在IDE/Codex中确认当前选择的服务提供方、模型及客户端版本。向该第三方服务商反馈“普通对话可用，但auto_review审批请求返回404/model not found”，请其核查审批请求实际模型ID、Responses兼容性和账号模型权限。不要在反馈中附API密钥或auth.json。
2. 如服务商给出正确模型ID/地址，先备份 `config.toml`，再按照其说明修正实际使用的provider或model设置，避免猜测替换模型名。如果设置由客户端界面或托管策略注入，应在对应界面或由管理员修正，修改项目文件不会生效。
3. 如改用OpenAI官方提供方，先确认自己的账号可用并通过客户端正常登录，再在客户端中切换并选择该账号实际可用的模型。不要把第三方密钥直接用于官方地址。
4. 保存后重启IDE/Codex或开始新的会话，重新尝试安装依赖。当前会话中的托管审批策略不一定会随磁盘配置变化。

不建议通过关闭审批、配置 `never` 或解除沙箱来掩盖该问题。当前AI无法修改项目外的用户配置，也不能修复第三方服务器；因此没有自动改写 `.codex/config.toml`。

本轮尝试访问OpenAI官方配置文档，但当前网络无法获取页面，以下仅提供查阅入口，不将其记作本轮已核实的文档内容：<https://developers.openai.com/codex/config-reference/>。

## 3. 判断 SQL 故障是否来自沙箱

MSSQLSERVER服务已确认Running，注册表确认默认实例ID为 `MSSQL16.MSSQLSERVER`，SQLCMD使用ODBC17。AI执行环境中报 `Encryption not supported on the client`、`SSL Provider: 安全包中没有可用的凭证`。这还不能确定是驱动损坏、沙箱限制还是实例问题。

先在自己的普通终端单独运行：

```powershell
sqlcmd -S localhost -E -C -l 5 -t 15 -b -Q "SELECT @@SERVERNAME AS server_name, CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')) AS version;"
```

- **普通终端成功、AI内失败**：说明应优先检查Codex执行隔离环境；不要修改SQL实例或重新安装数据库。可先在自己的终端安装依赖、运行测试，将报告供AI分析；恢复审批后再比较AI执行结果。
- **普通终端也报相同SSL/凭据错误**：在SSMS中以同一Windows身份连接 `localhost`。如果SSMS可连，优先修复或更新Microsoft ODBC17/18与SQLCMD客户端；如果SSMS也失败，按错误检查Windows凭据、系统事件、SQL错误日志和实例网络/证书设置。不要因为SSL错误直接切换混合认证、关闭加密或重启实例。
- **出现18456 / 登录失败**：连接已到达SQL Server；需数据库管理员核查该Windows账号的实例访问权限。不要在聊天中提供sa口令。
- **找不到实例 / 超时**：核对SQL Server配置管理器中的实例名和服务状态；命名实例使用实际的 `主机\实例`，不要将默认实例自动替换成SQLEXPRESS。

## 4. 恢复后的验收顺序

```powershell
Set-Location -LiteralPath 'C:\Users\18192\Desktop\Database-Project'
.\run.ps1 test -Unit
# 单元测试及SQL连接均正常后：
.\run.ps1 test
```

完整test会按项目既有机制创建独立基线/验收库和临时服务登录，测试后清理临时登录并保留测试库/备份。它不会替代既有运行副本升级。

请提供这几个结果即可继续定位：依赖安装是否成功、单元测试最新 `.runner/test-*/summary.json` 的状态、普通终端的SQL错误编号/文字。不要提供 `auth.json`、`settings.local.ps1`、Cookie或数据库连接口令。
