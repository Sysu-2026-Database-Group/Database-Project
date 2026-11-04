# P3 公开商品查询与配置升级

2026-11-02。P3按工作单元逐步实现；本轮仅公开商品查询和独立顾客身份，不宣称预订、取货或到期任务已经完成。

页面为 `/shop`、`/shop/goods/<id>`；API为 `/api/shop/goods` 及详情。匿名首页跳转公开列表，员工登录后保留工作台。名称搜索按字面子串匹配，分类限图书/文创，分页默认20、最大100；列表保留筛选。只有已上架且已定价商品可见，库存为零仍显示“暂时无货”。接口只输出公开属性、两位十进制售价字符串和有货布尔值，不暴露精确库存、已订量、采购价、供应商和员工资料。

数据库增量 `shop-entry.sql` 创建 `bookstore_app_guest` 角色，拒绝dbo/auth/api表访问，只精确授权 `api.usp_shop_catalog`。应用复核该连接只能属于一个应用角色、不能为dbo/sysadmin/db_owner且目标库匹配。员工身份不能调用公开过程，顾客不能调用员工/采购过程。新增读取不在GET中写库，不偷偷清理过期预订。

新库由runner部署shop脚本，setup创建5个独立服务登录。完整验收创建5个临时登录并清理。既有运行配置缺顾客连接时doctor/start/verify明确失败，不冒充升级完成。

## 既有运行副本的增量升级

先完成完整隔离验收，再对明确指定的Week7运行副本安装 `operations-entry.sql`（如尚未安装）及 `shop-entry.sql`，使用UTF-8 SQLCMD。不要重跑setup或覆盖已有settings和员工口令。

示例（库名/登录前缀须与本机现有配置一致）：

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -i db/shop-entry.sql -v DatabaseName=ShiguangBookstoreWeek7EntryYourRun
.\.venv\Scripts\python.exe -m app.upgrade_guest --database ShiguangBookstoreWeek7EntryYourRun --login-prefix bookstore_w7_yourrun --directory app
```

工具只新增guest登录及用户，并创建独立 `settings.guest.local.ps1`，不会改settings.local.ps1或员工凭据；若登录、用户或补充配置已存在则拒绝覆盖。限制配置文件ACL失败会回滚SQL并移除本次文件。原配置与补充配置由run.ps1在启动/诊断时加载。补充配置含秘密，已加入gitignore。直接使用Python启动时须先手动点源加载两个配置。

本轮未实际升级既有运行副本；升级工具仅经隔离测试/单元验证的范围须以台账为准，不把编写工具当作已部署。

## 后续预订规则及依赖

原数据库已有 `expires_at = DATEADD(day,3,created_at)` 约束。后续沿用创建时刻加3天的精确到期时刻，并以数据库可信时间 `now >= expires_at` 判断；不可由浏览器指定当前时间。下架不自动取消已有预订，保留已订量及原到期时间，取货仍按R-1检查上架；顾客可整单取消或等待在有效期内重新上架。该行为沿用规划推荐并兼容既定R-1，不允许下架后暗中绕过销售限制。

预订写入前还须实现专用顾客凭证和请求去重、随机预定码、预订/取消/到期竞争锁、库存边界；取货须原子消费本单已订量并复用销售结算；到期由独立任务身份执行，任务不伪造员工。当前没有这些过程或可操作按钮，不把它们写成已完成。
