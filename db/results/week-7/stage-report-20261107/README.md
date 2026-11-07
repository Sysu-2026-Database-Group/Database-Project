# 第二阶段报告运行证据

2026-11-07。执行者为 Codex，基线为本地 HEAD 481ee1a 与工作区的 .gitattributes 换行修复。使用独立演示库 ShiguangBookstoreWeek7WebDemoReport20261107、ODBC Driver 17 和端口 5098。数据库、凭据和原始运行日志留在本机。

- [运行摘要](runtime-results.json)摘录 setup、doctor、test、start 和 verify 的实际步骤和状态，包含 119 项测试、三种 Git 换行设置的历史审计、503 注入和停止状态。
- [业务对账](database-checks.json)来自演示结束后的只读 SQL 查询，按采购单、销售单、退款明细及库存流水来源核对数量和金额。
- [浏览器结果](browser-results.json)记录 Edge 实际通过的 16 个节点，号码、会员凭证和预定码已遮盖。401、403、404 为预期响应。

| 图证 | 角色与结果 |
| --- | --- |
| [注资](01-injection.png) · [提现](10-withdrawal.png) · [报表](11-reports.png) | 店长办理资金并查询经营数据 |
| [采购收货](02-purchase-received.png) | 店长审批付款后库管收货，商品 3 入库 2 件 |
| [会员开卡](03-member-card.png) · [会员自助](08-member-self.png) | 收银员开卡直接发凭证，顾客凭同一凭证查历史 |
| [预订](04-reservation.png) · [取货](05-pickup-sale.png) · [取消](09-cancellation.png) | 顾客预订、收银员核验结算及独立订单取消 |
| [退款](06-refund.png) · [回收](07-recovery.png) | 收银员退款 ¥18.05，库管另行回收 1 件 |
| [404](12-not-found.png) · [401](13-login-required.png) · [403](14-forbidden.png) | 不存在页面、匿名访问及收银员越权 |
| [删除资格](15-goods-delete-eligibility.png) · [删除结果](16-goods-deleted.png) | 仅新增的三无档案显示删除入口，确认后列表与数据库均查不到该样品 |

原始运行 ID 见运行摘要，可在本机 .runner 追溯。历史第六周结果及 11 月 2 日浏览器验收另有独立归档。 [第 5—9 周实验报告](../../../../docs/reports/report-web-v1.0.md)
