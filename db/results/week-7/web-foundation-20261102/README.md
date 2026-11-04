# Web基础开发验证记录 · 2026-11-02

执行者：AI。范围：P0基线和P1公共应用源码开发，尚未达到里程碑验收条件。状态及剩余工作见 [唯一实施台账](../../../../docs/tasks/task-web-development.md)。

| 实际操作 | 实际结果 |
|---|---|
| Python3.12.4 环境检查 | Python可用，Flask/pyodbc缺失 |
| `python -m venv .venv` | 创建项目内虚拟环境 |
| `.venv/Scripts/python.exe -m pip install -r requirements.txt` | FAIL：受限网络WinError10013；未安装依赖 |
| 提权安装相同requirements | 未执行：自动审批服务404 / model not found，审批无法完成 |
| 用户明确允许安装后，重试相同提权安装 | 仍未执行：自动审批服务再次返回404 / model not found；无需重复用户授权 |
| `Get-Service MSSQLSERVER` | Running |
| `python db/checks/audit-week-6-artifacts.py`（续作） | PASS：历史两组45步材料、11个日期样例、2个拒绝变异、19表/137 ER字段审计；不代表新增应用通过 |
| 只读 `sqlcmd -S localhost -E -C -l 5 -b -Q ...` | FAIL：Encryption not supported / SSL Provider凭据错误，未建立SQL连接 |
| `.venv/Scripts/python.exe scripts/project_runner.py test --unit` | FAIL：依赖检查报告缺少flask、pyodbc，测试尚未开始 |

Python语法及仓库空白检查原始输出见同目录 `static-checks.txt`。语法通过不代表模板渲染、HTTP、SQL规则、权限、事务、并发及浏览器视觉通过。未使用mock结果替代真实库验收，未对既有运行库做写入。
