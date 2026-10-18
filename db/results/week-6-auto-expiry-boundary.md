# 第六周自动过期边界记录

- 日期：2026-10-18
- 目标数据库：`ShiguangBookstoreWeek6Work`
- 检查脚本：[`db/auto-expiry-boundary-check.sql`](../../db/auto-expiry-boundary-check.sql)
- 固定测试时刻：`2026-10-01 12:00:00`
- 用户反馈：符合预期

## 核对结果

固定时刻下，查询发现 **2** 条预订单的 `expires_at` 已到但 `status` 仍为“有效”：

| 预定码 | 来源 | 到期时间 | 当前状态 |
|---|---|---|---|
| `517436` | 旧场景 | 2026-09-21 10:00 | 有效 |
| `W6R-2105` | 第六周新增场景 W6-S02 / W6-S06 | 2026-09-30 09:00 | 有效 |

脚本输出：

```text
effective_reservations_past_expiry = 2
observed_behavior = AUTO_EXPIRY_NOT_APPLIED
```

这说明当前数据库没有自动把到期预订单改为“已过期”的作业、触发器或其他自动处理入口。脚本只读，没有更新预订单，也没有改变已订量、库存、资金或积分。自动过期仍属于后续流程实现项；不能把静态“已过期”样例 `W6R-2104` 当成自动处理已经通过。
