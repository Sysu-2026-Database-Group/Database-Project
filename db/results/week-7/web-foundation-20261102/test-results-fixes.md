# 用户验收结果及修复

用户原始输出为仓库 `tests/results.txt`，本机完整报告 `.runner/test-20261102T122200Z575f38/`。用户运行：依赖安装成功、普通终端SQL连接成功；完整75项，失败0、错误2、跳过0。

- `test_list_is_restricted_to_own_sales`：JSON缺records字段。`workspace-entry.sql` 对嵌套查询显式COALESCE为空数组，确保空结果仍含records；另增真实库空页回归用例。此SQL修复待重新部署到新测试库验证。
- `test_round_to_zero_creates_sale_without_zero_amount_ledgers`：销售本身成功，tearDown恢复卡参数时逐行UPDATE违反跨行规则。改为OPENJSON参数绑定后一次UPDATE恢复两档，不禁用触发器，不改变经营规则。

AI重跑单元验收39项，失败0、错误0、跳过0，报告 `.runner/test-20261102T122703Z214211/summary.json`。完整验收提权请求被自动审批服务404/model not found阻止，未执行。需普通终端重跑 `run.ps1 test`；P0/P1尚未最终验收，P2—P6未完成。
