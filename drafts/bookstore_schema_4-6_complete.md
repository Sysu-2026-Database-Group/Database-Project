# 书店数据库：功能 4–6 完整模式文档

说明：本文件覆盖功能 4（商品线下退货）、5（商品线上预定）、6（会员积分与评定管理）的完整数据库设计。每张表包含字段、类型、是否可空、索引、默认值、额外属性与注释，并附 MySQL 建表（DDL）示例。

目录

- 商品线下退货（offline_returns）
  - offline_returns
  - offline_return_items
  - return_reasons
  - refund_transactions
- 商品线上预定（reservations）
  - reservations
  - reservation_items
  - reservation_inventory_logs
- 会员积分与等级（members & tiers）
  - member_tiers
  - members
  - member_points_transactions
  - member_tier_changes

---

注意：下表中 `key` 列使用 `PRI` 表示主键、`UNI` 表示唯一索引、`MUL` 表示普通索引。类型与默认值以 MySQL 为参考；如需 PostgreSQL 版本可另行转换。


**商品线下退货 / Offline Returns**

### 表：`offline_returns`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 退货主键ID |
| return_no | VARCHAR(64) | NO | UNI | NULL |  | 退货单号（平台唯一） |
| sale_id | BIGINT UNSIGNED | YES | MUL | NULL |  | 关联的销售单ID |
| customer_id | BIGINT UNSIGNED | YES | MUL | NULL |  | 顾客ID（若为会员） |
| cashier_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 操作收银员ID |
| store_id | INT UNSIGNED | NO | MUL | NULL |  | 门店ID |
| return_time | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 退货时间 |
| total_refund | DECIMAL(10,2) | NO |  | 0.00 |  | 本次退货退款总额 |
| refund_method | ENUM('cash','card','store_credit','online') | NO |  | 'cash' |  | 退款方式 |
| status | ENUM('pending','approved','completed','rejected') | NO |  | 'pending' |  | 退货流程状态 |
| reason_text | TEXT | YES |  | NULL |  | 退货原因备注 |
| processed_by_manager_id | BIGINT UNSIGNED | YES | MUL | NULL |  | 审批者ID（若有） |
| created_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 创建时间 |
| updated_at | DATETIME | NO |  | CURRENT_TIMESTAMP | ON UPDATE CURRENT_TIMESTAMP | 最后更新时间 |


### 表：`offline_return_items`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 退货明细ID |
| return_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 关联 `offline_returns.id` |
| sale_item_id | BIGINT UNSIGNED | YES | MUL | NULL |  | 原销售明细ID |
| product_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 商品ID |
| sku | VARCHAR(64) | YES |  | NULL |  | 商品条码或SKU |
| quantity | INT UNSIGNED | NO |  | 1 |  | 退货数量 |
| unit_price | DECIMAL(10,2) | NO |  | 0.00 |  | 单价（退款依据） |
| refund_amount | DECIMAL(10,2) | NO |  | 0.00 |  | 本行退款金额 |
| condition | ENUM('new','like_new','used','damaged') | NO |  | 'like_new' |  | 商品状态 |
| reason_id | INT UNSIGNED | YES | MUL | NULL |  | 参考 `return_reasons.id` |
| created_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 创建时间 |


### 表：`return_reasons`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | INT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 原因字典ID |
| code | VARCHAR(32) | NO | UNI | NULL |  | 原因代码 |
| description | VARCHAR(255) | NO |  | NULL |  | 原因描述 |


### 表：`refund_transactions`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 退款流水ID |
| return_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 关联 `offline_returns.id` |
| amount | DECIMAL(10,2) | NO |  | 0.00 |  | 退款金额 |
| payment_method | ENUM('cash','card','store_credit','online') | NO |  | 'cash' |  | 实际退款方式 |
| transaction_time | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 退款时间 |
| processed_by | BIGINT UNSIGNED | YES | MUL | NULL |  | 经手人ID |
| external_txn_no | VARCHAR(128) | YES |  | NULL |  | 支付平台流水号 |
| note | VARCHAR(255) | YES |  | NULL |  | 备注 |


---

**商品线上预定 / Online Reservations**

### 表：`reservations`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 预定主键ID |
| reservation_no | VARCHAR(64) | NO | UNI | NULL |  | 预定单号 |
| customer_id | BIGINT UNSIGNED | YES | MUL | NULL |  | 会员ID |
| customer_name | VARCHAR(128) | YES |  | NULL |  | 顾客姓名 |
| customer_mobile | VARCHAR(32) | YES |  | NULL |  | 手机号 |
| store_id | INT UNSIGNED | NO | MUL | NULL |  | 取货门店ID |
| status | ENUM('frozen','confirmed','cancelled','collected','expired') | NO |  | 'frozen' |  | 预定状态 |
| total_amount | DECIMAL(10,2) | NO |  | 0.00 |  | 预定总价 |
| payment_status | ENUM('unpaid','partial','paid','refunded') | NO |  | 'unpaid' |  | 支付状态 |
| reserved_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 预定时间 |
| expire_at | DATETIME | YES |  | NULL |  | 过期时间 |
| frozen_by_job | TINYINT(1) | NO |  | 0 |  | 是否系统冻结 |
| note | VARCHAR(255) | YES |  | NULL |  | 备注 |
| created_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 创建时间 |
| updated_at | DATETIME | NO |  | CURRENT_TIMESTAMP | ON UPDATE CURRENT_TIMESTAMP | 最后更新时间 |


### 表：`reservation_items`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 预定明细ID |
| reservation_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 关联 `reservations.id` |
| product_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 商品ID |
| sku | VARCHAR(64) | YES |  | NULL |  | SKU |
| quantity | INT UNSIGNED | NO |  | 1 |  | 预定数量 |
| unit_price | DECIMAL(10,2) | NO |  | 0.00 |  | 单价 |
| reserved_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 创建时间 |


### 表：`reservation_inventory_logs`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 日志ID |
| reservation_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 关联 `reservations.id` |
| product_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 商品ID |
| sku | VARCHAR(64) | YES |  | NULL |  | SKU |
| change_qty | INT | NO |  | 0 |  | 正数=冻结，负数=释放 |
| action | ENUM('freeze','release','expire','collect') | NO |  | 'freeze' |  | 操作类型 |
| operator_id | BIGINT UNSIGNED | YES | MUL | NULL |  | 操作人ID |
| created_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 记录时间 |


---

**会员积分和评定管理 / Member Points & Tiers**

### 表：`member_tiers`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | INT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 会员等级ID |
| name | VARCHAR(64) | NO | UNI | NULL |  | 等级名称 |
| min_points | INT UNSIGNED | NO |  | 0 |  | 升级所需最低积分 |
| discount_rate | DECIMAL(5,2) | NO |  | 0.00 |  | 等级折扣 (%) |
| benefits | TEXT | YES |  | NULL |  | 等级特权 |
| created_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 创建时间 |


### 表：`members`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 会员ID |
| member_no | VARCHAR(64) | NO | UNI | NULL |  | 会员卡号 |
| name | VARCHAR(128) | YES |  | NULL |  | 会员姓名 |
| mobile | VARCHAR(32) | YES | MUL | NULL |  | 手机号 |
| email | VARCHAR(128) | YES | UNI | NULL |  | 邮箱 |
| tier_id | INT UNSIGNED | NO | MUL | NULL |  | 当前等级 |
| points_balance | INT | NO |  | 0 |  | 当前积分余额 |
| total_earned_points | BIGINT | NO |  | 0 |  | 累计获得积分 |
| total_spent_amount | DECIMAL(12,2) | NO |  | 0.00 |  | 累计消费金额 |
| status | ENUM('active','inactive','banned') | NO |  | 'active' |  | 状态 |
| joined_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 注册时间 |
| last_active_at | DATETIME | YES |  | NULL |  | 最后活跃时间 |
| notes | VARCHAR(255) | YES |  | NULL |  | 备注 |


### 表：`member_points_transactions`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 积分变动记录ID |
| member_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 关联 `members.id` |
| change | INT | NO |  | 0 |  | 积分变动（正/负） |
| reason | ENUM('purchase','return','adjustment','bonus','expire') | NO |  | 'purchase' |  | 变动理由 |
| reference_id | BIGINT UNSIGNED | YES | MUL | NULL |  | 关联业务单据ID |
| operator_id | BIGINT UNSIGNED | YES | MUL | NULL |  | 操作人ID |
| created_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 记录时间 |
| note | VARCHAR(255) | YES |  | NULL |  | 备注 |


### 表：`member_tier_changes`

| field | type | null | key | default | extra | comment |
|---|---|---:|:---:|---|---|---|
| id | BIGINT UNSIGNED | NO | PRI | NULL | AUTO_INCREMENT | 等级变更记录ID |
| member_id | BIGINT UNSIGNED | NO | MUL | NULL |  | 关联 `members.id` |
| old_tier_id | INT UNSIGNED | YES | MUL | NULL |  | 变更前等级 |
| new_tier_id | INT UNSIGNED | NO | MUL | NULL |  | 变更后等级 |
| change_reason | VARCHAR(128) | YES |  | NULL |  | 变更原因 |
| changed_by | BIGINT UNSIGNED | YES | MUL | NULL |  | 执行者ID |
| changed_at | DATETIME | NO |  | CURRENT_TIMESTAMP |  | 变更时间 |


---

## MySQL 建表（DDL）示例

下面为每张表给出 MySQL 的 CREATE TABLE 示例。实际部署前请根据你的 MySQL 版本与字符集（如 utf8mb4）调整 `CHARSET` 与 `COLLATE`，并根据业务需要增加外键约束或分区策略。

-- offline_returns
CREATE TABLE `offline_returns` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `return_no` VARCHAR(64) NOT NULL,
  `sale_id` BIGINT UNSIGNED DEFAULT NULL,
  `customer_id` BIGINT UNSIGNED DEFAULT NULL,
  `cashier_id` BIGINT UNSIGNED NOT NULL,
  `store_id` INT UNSIGNED NOT NULL,
  `return_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `total_refund` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `refund_method` ENUM('cash','card','store_credit','online') NOT NULL DEFAULT 'cash',
  `status` ENUM('pending','approved','completed','rejected') NOT NULL DEFAULT 'pending',
  `reason_text` TEXT,
  `processed_by_manager_id` BIGINT UNSIGNED DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_offline_returns_return_no` (`return_no`),
  KEY `idx_offline_returns_sale_id` (`sale_id`),
  KEY `idx_offline_returns_customer_id` (`customer_id`),
  KEY `idx_offline_returns_cashier_id` (`cashier_id`),
  KEY `idx_offline_returns_store_id` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- offline_return_items
CREATE TABLE `offline_return_items` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `return_id` BIGINT UNSIGNED NOT NULL,
  `sale_item_id` BIGINT UNSIGNED DEFAULT NULL,
  `product_id` BIGINT UNSIGNED NOT NULL,
  `sku` VARCHAR(64) DEFAULT NULL,
  `quantity` INT UNSIGNED NOT NULL DEFAULT 1,
  `unit_price` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `refund_amount` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `condition` ENUM('new','like_new','used','damaged') NOT NULL DEFAULT 'like_new',
  `reason_id` INT UNSIGNED DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_offline_return_items_return_id` (`return_id`),
  KEY `idx_offline_return_items_product_id` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- return_reasons
CREATE TABLE `return_reasons` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `code` VARCHAR(32) NOT NULL,
  `description` VARCHAR(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_return_reasons_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- refund_transactions
CREATE TABLE `refund_transactions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `return_id` BIGINT UNSIGNED NOT NULL,
  `amount` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `payment_method` ENUM('cash','card','store_credit','online') NOT NULL DEFAULT 'cash',
  `transaction_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processed_by` BIGINT UNSIGNED DEFAULT NULL,
  `external_txn_no` VARCHAR(128) DEFAULT NULL,
  `note` VARCHAR(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_refund_transactions_return_id` (`return_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- reservations
CREATE TABLE `reservations` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reservation_no` VARCHAR(64) NOT NULL,
  `customer_id` BIGINT UNSIGNED DEFAULT NULL,
  `customer_name` VARCHAR(128) DEFAULT NULL,
  `customer_mobile` VARCHAR(32) DEFAULT NULL,
  `store_id` INT UNSIGNED NOT NULL,
  `status` ENUM('frozen','confirmed','cancelled','collected','expired') NOT NULL DEFAULT 'frozen',
  `total_amount` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `payment_status` ENUM('unpaid','partial','paid','refunded') NOT NULL DEFAULT 'unpaid',
  `reserved_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expire_at` DATETIME DEFAULT NULL,
  `frozen_by_job` TINYINT(1) NOT NULL DEFAULT 0,
  `note` VARCHAR(255) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_reservations_no` (`reservation_no`),
  KEY `idx_reservations_customer_id` (`customer_id`),
  KEY `idx_reservations_store_id` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- reservation_items
CREATE TABLE `reservation_items` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reservation_id` BIGINT UNSIGNED NOT NULL,
  `product_id` BIGINT UNSIGNED NOT NULL,
  `sku` VARCHAR(64) DEFAULT NULL,
  `quantity` INT UNSIGNED NOT NULL DEFAULT 1,
  `unit_price` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `reserved_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_reservation_items_reservation_id` (`reservation_id`),
  KEY `idx_reservation_items_product_id` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- reservation_inventory_logs
CREATE TABLE `reservation_inventory_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reservation_id` BIGINT UNSIGNED NOT NULL,
  `product_id` BIGINT UNSIGNED NOT NULL,
  `sku` VARCHAR(64) DEFAULT NULL,
  `change_qty` INT NOT NULL DEFAULT 0,
  `action` ENUM('freeze','release','expire','collect') NOT NULL DEFAULT 'freeze',
  `operator_id` BIGINT UNSIGNED DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_reservation_inventory_logs_reservation_id` (`reservation_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- member_tiers
CREATE TABLE `member_tiers` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(64) NOT NULL,
  `min_points` INT UNSIGNED NOT NULL DEFAULT 0,
  `discount_rate` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  `benefits` TEXT,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_member_tiers_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- members
CREATE TABLE `members` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `member_no` VARCHAR(64) NOT NULL,
  `name` VARCHAR(128) DEFAULT NULL,
  `mobile` VARCHAR(32) DEFAULT NULL,
  `email` VARCHAR(128) DEFAULT NULL,
  `tier_id` INT UNSIGNED NOT NULL,
  `points_balance` INT NOT NULL DEFAULT 0,
  `total_earned_points` BIGINT NOT NULL DEFAULT 0,
  `total_spent_amount` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  `status` ENUM('active','inactive','banned') NOT NULL DEFAULT 'active',
  `joined_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_active_at` DATETIME DEFAULT NULL,
  `notes` VARCHAR(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_members_member_no` (`member_no`),
  UNIQUE KEY `uk_members_email` (`email`),
  KEY `idx_members_mobile` (`mobile`),
  KEY `idx_members_tier_id` (`tier_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- member_points_transactions
CREATE TABLE `member_points_transactions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `member_id` BIGINT UNSIGNED NOT NULL,
  `change` INT NOT NULL DEFAULT 0,
  `reason` ENUM('purchase','return','adjustment','bonus','expire') NOT NULL DEFAULT 'purchase',
  `reference_id` BIGINT UNSIGNED DEFAULT NULL,
  `operator_id` BIGINT UNSIGNED DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `note` VARCHAR(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_member_points_transactions_member_id` (`member_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- member_tier_changes
CREATE TABLE `member_tier_changes` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `member_id` BIGINT UNSIGNED NOT NULL,
  `old_tier_id` INT UNSIGNED DEFAULT NULL,
  `new_tier_id` INT UNSIGNED NOT NULL,
  `change_reason` VARCHAR(128) DEFAULT NULL,
  `changed_by` BIGINT UNSIGNED DEFAULT NULL,
  `changed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_member_tier_changes_member_id` (`member_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


---

如需：
- 转为 PostgreSQL DDL、
- 增加外键约束与级联策略、
- 按业务补充字段（如退货审核流程字段、退款分期等）、
- 或导出为 ER 图（PNG / Mermaid），
告诉我你偏好的目标数据库和任何额外要求，我会继续完善。
