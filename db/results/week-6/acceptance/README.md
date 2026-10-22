# 第六周验收证据

当前结论以[正式验收记录](../../../../docs/reviews/review-week-6.md)为准。用户于2026-10-21允许AI自检，梁宇聪已于2026-10-22确认ER最终人工验收通过。

- `final-check/`：本轮修正后主代理完整45步、11个日期规则示例、两个错误算法变异及产物复查。`summary.json`/`steps.json`和编号文本保留实际执行归属。
- 本目录原00—44、原 `summary.json`/`steps.json`、`source-manifest.json`、`source-layout-manifest.json`及子代理交接：此前运行的历史证据，保持原实际归属；旧结论中的“会员日期边界”按当时脚本解释，不能冒充本轮规则测试。
- **2026-10-22 Reviewer B 登记**：`00-environment.txt` 与 `final-check/00-environment.txt` 的库清单包含步骤 00 之后才创建的库，按 `accept-week-6.ps1` 的步骤顺序不可能是当时输出，判定为事后重新查询覆盖；`reviewer-findings.md` 亦在索引后被修订。三份文件的旧哈希与新哈希已逐条写入 `final-check/metadata-updates.json`，两个清单按当前字节重算并在同表注明原因，SQL 结果未重跑、未改写。当前审核以 Reviewer B 的独立复现目录 `../acceptance-b-20261022/` 为准。
- `source-current-manifest.json`：本轮实际执行后源码指纹，不覆盖历史指纹。
- `manifest.json`：当前所有证据文件索引及哈希（不索引自身和可重建的artifact-checks.json）。
- `er-consistency.json`：当前v1.4检查及旧记录实际适用的v1.0文件。

只读复查：`./db/results/week-6/acceptance/independent-audit.ps1`。重跑数据库使用 `db/accept-week-6.ps1`，必须指定全新库名和结果目录。旧库、备份和原始文本没有删除/覆盖。

2026-10-22补录的人工通过记录绑定当前v1.4文件指纹；`final-check/summary.json`中的pending是2026-10-21运行时状态，保留原样，不覆盖为事后人工结果。当前人工状态以 `er-consistency.json` 和正式验收§5为准。
