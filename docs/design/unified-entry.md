# 统一入口与跨电脑复现

统一入口为根目录 `run.ps1`，编排代码在 `scripts/project_runner.py`。目前验收范围是员工登录、受限服务身份和门店销售；采购、预订、退款等尚未实现的业务不计入本轮验收。

## 1 首次准备

面向 Windows 本机 SQL Server，支持默认实例和本机命名实例，例如 `localhost\SQLEXPRESS`。先安装：

- Python 3.10 或更新版本（本次实测3.12）。
- SQL Server，Windows 登录需能创建练习数据库、备份恢复及管理服务登录。使用项目已验证的 SQL Server 版本，不承诺任意旧版本兼容。
- Microsoft ODBC Driver 17 或18 for SQL Server。
- `sqlcmd`，并加入 PATH。
- Windows PowerShell 5.1 或更新版本；第六周历史验收脚本仍单独要求 PowerShell 7。

本应用采用四个受限 SQL 登录，实例需要 Windows + SQL Server 混合身份验证。若尚未启用，由管理员另行配置并重启实例。统一入口只检查，不自动修改认证模式、注册表或重启服务。

在仓库根目录执行：

```powershell
# 默认实例；未指定驱动时优先检测18，其次17。
.\run.ps1 setup

# 命名实例示例（二选一，按实际环境填写）。
.\run.ps1 setup -Server 'localhost\SQLEXPRESS' -Driver 'ODBC Driver 18 for SQL Server'
```

如果 Windows 阻止执行脚本，可以只对本次进程放行，不修改整机执行策略：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 setup
```

其余命令也可以使用同样前缀。网络受限时先配置好 pip；依赖安装失败会停止，不继续创建数据库。

`setup` 依次完成：

1. 建立 `.venv` 并安装 `requirements.txt`。
2. 检查依赖、实例与认证方式，拒绝覆盖既有本地凭据、目标数据库或同名前缀的登录。
3. 从仓库建库、基础样例、第六周迁移及扩展样例脚本建立新的 `ShiguangBookstoreWeek6Runner...` 基线库，并检查结构和数据。
4. 通过 COPY_ONLY / CHECKSUM 备份、校验、恢复建立 Week7 运行库，部署登录基础及销售入口。
5. 生成四个受限服务登录、已有员工的独立随机练习口令，以及本机配置；口令不打印到终端。

不要求队友预先拥有其他电脑的 `Week6Work` 数据库，也不需要复制他人的备份或密码。

## 2 配置与已有环境

`run.example.json` 是无秘密示例；成功 setup 后参数保存为被 Git 忽略的 `run.local.json`：

| 字段 | 用途 |
|---|---|
| `server` | 本机实例名 |
| `driver` | ODBC驱动名称；首次未指定时自动检测 |
| `database` | Week7专用运行库 |
| `login_prefix` | 四个服务登录的共同前缀 |
| `port` | 本机HTTP端口，默认5000 |
| `settings_directory` | 设置及练习口令所在目录，默认 `app` |

setup 可用 `-Server`、`-Driver`、`-DatabaseName`、`-LoginPrefix`、`-Port` 覆盖参数并保存。也可以先复制示例为 `run.local.json` 后编辑。`-ConfigFile` 可选择仓库内另一份本地配置；第二套环境应使用独立运行库、登录前缀、端口和 `settings_directory`。

其他命令的参数只对本次调用生效；例如 start 临时指定端口时，verify -Http 也应指定同一端口。

含秘密的文件为所选目录内的 `settings.local.ps1`、`demo-credentials.local.json`，均被 Git 忽略。新建文件在 Windows 上仅授权当前用户和 SYSTEM。`doctor/start/verify` 加载所选设置；`test` 不加载运行设置。

此前已配置的默认 `YourRun` 环境可直接执行 doctor/start/verify，无需重新 setup，也不重写员工口令。旧配置若使用其他库名或登录前缀，请先填写对应的 `run.local.json`。

setup 遇到既有本地配置会停止。中途失败时报告列出已准备或计划创建的资源，数据库和备份保留供检查。如果库已创建而配置尚未完成，不能直接覆盖重跑；先检查失败步骤，或为新尝试选择独立库名和登录前缀。入口不提供隐式删库重建。

## 3 日常命令

```powershell
.\run.ps1                         # 用法
.\run.ps1 doctor                  # 环境、实际连接、目标库、岗位、必要过程和应用配置
.\run.ps1 test -Unit              # 仅应用与runner测试，不连接SQL Server
.\run.ps1 test                    # 从源码准备独立测试库，完整验收
.\run.ps1 start                   # 前台运行；Ctrl+C停止
# 保持 start 的终端开启，在另一终端执行：
.\run.ps1 verify -Http            # 部署验证及本机实际HTTP验证
```

doctor 在首次 setup 前可能报告尚未配置运行环境；完成准备后再检查。verify 不带 `-Http` 时使用真实服务连接和 Flask 测试客户端，无需启动监听；带 `-Http` 时要求配置端口上已有本应用。

start 核对四条实际服务连接的目标库、登录和岗位，检查必要过程及应用密钥，移除管理与测试连接后启动 Flask，仅监听 `127.0.0.1`。启动失败返回非零退出码。旧 `app/start-local.ps1` 委托该入口。

部署验证只检查身份与读取，包括匿名拒绝、四名练习员工登录/退出及销售页面岗位边界，不确认销售。它使用本机练习口令；若主动重置员工口令，需要同步维护本机演示凭据。

## 4 隔离验收与结果

完整 test 不依赖运行库和运行账号。每次创建独立基线库、认证测试库、销售测试库和四个随机前缀的临时 SQL 登录，只向测试子进程传递本次专用连接。

销售测试在写入凭据及业务数据前，逐条实际连接，核对数据库、实例、真实登录和受限角色。不通过字符串替换改写运行连接，也不回退到运行配置。DAO 可显式绑定预期数据库，连错库时阻止业务调用。

完整验收要求登录和销售两组数据库测试都被发现，且没有失败、错误或跳过；缺少数据库配置不能当作通过。`-Unit` 单独执行不依赖数据库的测试，报告标记为 unit。

会员测试有效期相对于门店当前日期准备，清理时恢复；扩展商品按业务键查找，不依赖历史执行造成的自增ID。结束后核对两个测试库的19张业务表指纹与基线一致，检查凭据、请求、测试用户和故障触发器已清理，并删除本次临时服务器登录。

测试库、基线库及备份保留供复查；反复验收会增加磁盘占用，由数据库维护者按报告清单管理。

进入 Python 编排阶段后，命令结果保存在被 Git 忽略的 `.runner/<命令>-<UTC时间及随机编号>/`。更早的 PowerShell 参数、虚拟环境或 pip 安装失败直接在终端报告：

- `summary.json`：状态、无秘密配置、资源、步骤及退出码；完整测试还含测试计数。
- 各步骤 `.log`：SQLCMD / Python输出。
- `unittest-results.json`：测试计数。
- `business-fingerprints.json`：完整验收的数据恢复判据。
- `source-hashes.json`：本次主要源码指纹。

成功返回0，失败返回非零，主动中断记录 STOPPED。预期的权限拒绝及故障注入可能在测试日志中打印异常，以断言、状态检查和最终报告为准。

第六周历史脚本和证据不重写；完整验收另调用只读 `audit-week-6-artifacts.py`。这不等于重新执行第六周45步验收，需要时仍单独使用原 `db/accept-week-6.ps1`。
