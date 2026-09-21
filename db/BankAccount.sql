-- ============================
-- 资金账户主表 BankAccount
-- ============================
DROP TABLE IF EXISTS BankAccountLog;
DROP TABLE IF EXISTS BankAccount;
GO

CREATE TABLE BankAccount(
    account_id BIGINT NOT NULL PRIMARY KEY IDENTITY(1,1), -- 账户唯一ID
    account_name NVARCHAR(100) NOT NULL, -- 账户名称（如门店对公账户）
    money_count DECIMAL(12,2) NOT NULL DEFAULT 0.00, -- 当前余额
    create_time DATETIME NOT NULL DEFAULT GETDATE() -- 账户创建时间
);
GO

-- ============================
-- 资金变动流水表 BankAccountLog
-- 逐笔留痕：金额变动、原因、时间、变动前后金额快照
-- ============================
CREATE TABLE BankAccountLog(
    log_id BIGINT NOT NULL PRIMARY KEY IDENTITY(1,1), -- 流水记录ID
    account_id BIGINT NOT NULL, -- 关联资金账户ID
    delta_money DECIMAL(12,2) NOT NULL, -- 金额变动：+收款，-付款
    reason NVARCHAR(20) NOT NULL, -- 变动原因枚举：采购付款 / 销售收款 / 会员卡费
    operate_time DATETIME NOT NULL DEFAULT GETDATE(), -- 变动时刻
    before_money DECIMAL(12,2) NOT NULL, -- 变动前余额（快照冗余）
    after_money DECIMAL(12,2) NOT NULL, -- 变动后余额（快照冗余）

    -- 外键关联资金账户主表
    CONSTRAINT FK_BankAccountLog_BankAccount
        FOREIGN KEY(account_id) REFERENCES BankAccount(account_id),

    -- CHECK约束：限制reason只能是指定三个枚举值
    CONSTRAINT CK_BankAccountLog_Reason
        CHECK (reason IN (N'采购付款', N'销售收款', N'会员卡费')),

    -- CHECK校验快照：after_money必须等于 before_money + delta_money，用于校验数据一致性
    CONSTRAINT CK_BankAccountLog_BalanceCheck
        CHECK (after_money = before_money + delta_money)
);
GO

-- ============================
-- 测试样例数据插入
-- ============================
-- 新建资金账户，初始余额0
INSERT INTO BankAccount(account_name, money_count)
VALUES(N'书店对公资金账户', 0.00);
GO

-- 流水1：收到销售收款 +2000，余额从0→2000
INSERT INTO BankAccountLog(account_id, delta_money, reason, operate_time, before_money, after_money)
VALUES
(1, 2000.00, N'销售收款', '2026-09-10 10:00:00', 0.00, 2000.00);

-- 流水2：支付采购货款 -800，余额从2000→1200
INSERT INTO BankAccountLog(account_id, delta_money, reason, operate_time, before_money, after_money)
VALUES
(1, -800.00, N'采购付款', '2026-09-11 14:30:00', 2000.00, 1200.00);

-- 流水3：收到会员卡费 +500，余额从1200→1700
INSERT INTO BankAccountLog(account_id, delta_money, reason, operate_time, before_money, after_money)
VALUES
(1, 500.00, N'会员卡费', '2026-09-12 09:15:00', 1200.00, 1700.00);

-- 更新主账户当前余额（业务逻辑：每次记账同步更新BankAccount.money_count）
UPDATE BankAccount SET money_count = 1700.00 WHERE account_id = 1;
GO

-- ============================
-- 查询：账户信息 + 所有资金流水
-- ============================
SELECT
    ba.account_id AS 账户ID,
    ba.account_name AS 账户名称,
    ba.money_count AS 当前账户余额,
    bal.log_id AS 流水号,
    bal.delta_money AS 变动金额,
    bal.reason AS 变动原因,
    bal.operate_time AS 变动时间,
    bal.before_money AS 变动前余额,
    bal.after_money AS 变动后余额
FROM BankAccount ba
JOIN BankAccountLog bal ON ba.account_id = bal.account_id;
GO

-- ============================
-- 约束报错测试代码（实验报告用）
-- ============================
/*
-- 测试1：reason填非法值，触发CK_BankAccountLog_Reason报错
INSERT INTO BankAccountLog(account_id, delta_money, reason, operate_time, before_money, after_money)
VALUES
(1, 100, N'退款', '2026-09-13 10:00:00', 1700, 1800);

-- 测试2：前后余额不满足等式，触发CK_BankAccountLog_BalanceCheck校验失败
INSERT INTO BankAccountLog(account_id, delta_money, reason, operate_time, before_money, after_money)
VALUES
(1, 100, N'销售收款', '2026-09-13 10:00:00', 1700, 1900);
*/
