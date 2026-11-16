:On Error exit
-- 在统一运行器新建的 AuthTests 副本执行。测试写入和模拟角色统一回滚。
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

IF DB_NAME() NOT LIKE N'ShiguangBookstoreWeek7AuthTests%' OR @@TRANCOUNT<>0
   OR EXISTS(SELECT 1 FROM auth.employee_credential)
   OR EXISTS(SELECT 1 FROM dbo.sale WHERE sold_at>='2098-06-01')
    THROW 53010,N'请使用统一运行器新建、无员工凭据的 AuthTests 副本。',1;

DECLARE @manager varchar(11)=(SELECT MIN(phone) FROM dbo.employee WHERE role=N'店长'),
        @inventory varchar(11)=(SELECT MIN(phone) FROM dbo.employee WHERE role=N'库管'),
        @cashier varchar(11)=(SELECT MIN(phone) FROM dbo.employee WHERE role=N'收银员'),
        @silver varchar(11)=(SELECT MIN(phone) FROM dbo.member WHERE card_level=N'银卡' AND expires_at>=CONVERT(date,SYSUTCDATETIME())),
        @gold varchar(11)=(SELECT MIN(phone) FROM dbo.member WHERE card_level=N'金卡' AND expires_at>=CONVERT(date,SYSUTCDATETIME()));
DECLARE @stock_before int=(SELECT stock_total FROM dbo.goods WHERE id=3),
        @reserved_before int=(SELECT reserved_qty FROM dbo.goods WHERE id=3),
        @movement_before bigint=(SELECT COUNT_BIG(*) FROM dbo.stock_movement),
        @purchases_before bigint=(SELECT COUNT_BIG(*) FROM dbo.purchase_request),
        @sale_before bigint=(SELECT COUNT_BIG(*) FROM dbo.sale);

BEGIN TRANSACTION;
CREATE USER week10_check_manager WITHOUT LOGIN;
CREATE USER week10_check_inventory WITHOUT LOGIN;
ALTER ROLE bookstore_app_manager ADD MEMBER week10_check_manager;
ALTER ROLE bookstore_app_inventory ADD MEMBER week10_check_inventory;
INSERT auth.employee_credential(employee_phone,password_hash)
SELECT phone,REPLICATE('x',24) FROM dbo.employee WHERE phone IN (@manager,@inventory);

-- 左边界有一笔双商品单，右边界有一笔商品 3 的订单，次日订单应被排除。
INSERT dbo.sale(no,cashier_by,sold_at,subtotal_amount,paid_amount)
VALUES ('W10-CHECK-OPEN',@cashier,'2098-06-01T00:00:00',35,35),
       ('W10-CHECK-CLOSE',@cashier,'2098-06-02T23:59:59.9999999',10,10),
       ('W10-CHECK-OUT',@cashier,'2098-06-03T00:00:00',999,999);
UPDATE dbo.sale SET member_phone=(SELECT MIN(phone) FROM dbo.member),card_level=N'银卡',
    discount_rate=0.95,point_deduction_amount=1,paid_amount=32.25 WHERE no='W10-CHECK-OPEN';
INSERT dbo.sale_item(sale_id,goods_id,quantity,unit_price)
SELECT s.id,x.goods_id,x.quantity,x.unit_price FROM dbo.sale s
JOIN (VALUES ('W10-CHECK-OPEN',3,2,10),('W10-CHECK-OPEN',4,1,15),
             ('W10-CHECK-CLOSE',3,1,10),('W10-CHECK-OUT',3,1,999)) x(no,goods_id,quantity,unit_price)
  ON s.no=x.no;

DECLARE @detail TABLE(goods_id bigint,goods_name nvarchar(100),sold_quantity bigint,
                      gross_sales_amount decimal(38,2),order_count bigint);
INSERT @detail SELECT * FROM dbo.fn_sales_by_goods('2098-06-01','2098-06-02');
IF (SELECT COUNT(*) FROM @detail)<>2
   OR NOT EXISTS(SELECT 1 FROM @detail WHERE goods_id=3 AND sold_quantity=3 AND gross_sales_amount=30 AND order_count=2)
   OR NOT EXISTS(SELECT 1 FROM @detail WHERE goods_id=4 AND sold_quantity=1 AND gross_sales_amount=15 AND order_count=1)
    THROW 53011,N'销售表值函数日期边界或明细错误。',1;
IF EXISTS(SELECT 1 FROM dbo.fn_sales_by_goods(NULL,'2098-06-02'))
   OR EXISTS(SELECT 1 FROM dbo.fn_sales_by_goods('2098-06-02','2098-06-01'))
    THROW 53011,N'非法日期范围应返回空集。',1;
DECLARE @results TABLE(result_json nvarchar(max));
EXECUTE AS USER=N'week10_check_manager';
INSERT @results EXEC api.usp_sales_statistics @manager,1,'2098-06-01','2098-06-02';
INSERT @results EXEC api.usp_sales_statistics @manager,1,'2098-06-01','2098-06-02';
REVERT;
DECLARE @report nvarchar(max)=(SELECT TOP(1) result_json FROM @results);
IF (SELECT COUNT(*) FROM @results WHERE result_json=@report)<>2
   OR ISNULL(TRY_CONVERT(bigint,JSON_VALUE(@report,'$.order_count')),-1)<>2
   OR ISNULL(TRY_CONVERT(bigint,JSON_VALUE(@report,'$.sold_quantity')),-1)<>4
   OR ISNULL(TRY_CONVERT(decimal(10,2),JSON_VALUE(@report,'$.gross_sales_amount')),-1)<>45
   OR ISNULL(TRY_CONVERT(decimal(10,2),JSON_VALUE(@report,'$.paid_amount')),-1)<>42.25
    THROW 53011,N'统计过程总计错误或重复查询不一致。',1;
DECLARE @parsed TABLE(goods_id bigint,goods_name nvarchar(100),sold_quantity bigint,
                      gross_sales_amount decimal(38,2),order_count bigint);
INSERT @parsed SELECT * FROM OPENJSON(@report,'$.records') WITH(
    goods_id bigint,goods_name nvarchar(100),sold_quantity bigint,gross_sales_amount decimal(38,2),order_count bigint);
IF EXISTS(SELECT * FROM @detail EXCEPT SELECT * FROM @parsed)
   OR EXISTS(SELECT * FROM @parsed EXCEPT SELECT * FROM @detail)
    THROW 53011,N'过程和表值函数的商品明细不一致。',1;
DELETE @results;
EXECUTE AS USER=N'week10_check_manager';
INSERT @results EXEC api.usp_sales_statistics @manager,1,'2098-06-04','2098-06-04';
REVERT;
DECLARE @empty nvarchar(max)=(SELECT result_json FROM @results);
IF ISNULL(JSON_VALUE(@empty,'$.order_count'),'')<>'0' OR ISNULL(JSON_VALUE(@empty,'$.sold_quantity'),'')<>'0'
   OR ISNULL(TRY_CONVERT(decimal(10,2),JSON_VALUE(@empty,'$.paid_amount')),-1)<>0
   OR ISNULL(TRY_CONVERT(decimal(10,2),JSON_VALUE(@empty,'$.gross_sales_amount')),-1)<>0
   OR ISNULL(JSON_QUERY(@empty,'$.records'),N'')<>N'[]'
    THROW 53011,N'空日期区间应返回零总计和空明细。',1;
SELECT N'W10-S01' test_case,N'2098-06-01..2098-06-02; repeated; TVF comparison' inputs,
    JSON_VALUE(@report,'$.order_count') orders,JSON_VALUE(@report,'$.sold_quantity') units,
    JSON_VALUE(@report,'$.gross_sales_amount') gross_amount,JSON_VALUE(@report,'$.paid_amount') paid_amount;
SELECT N'W10-S02' test_case,goods_id,sold_quantity,gross_sales_amount,order_count FROM @parsed ORDER BY goods_id;
SELECT N'W10-S03' test_case,@empty actual_empty_report;

UPDATE dbo.goods SET stock_total=12,reserved_qty=4 WHERE id=3;
SELECT N'W10-R01' test_case,target,expected,dbo.fn_replenishment_quantity(3,target) actual
FROM (VALUES (10,2),(8,0),(7,0)) x(target,expected);
IF EXISTS (SELECT 1 FROM (VALUES (10,2),(8,0),(7,0)) x(target,expected)
           WHERE ISNULL(dbo.fn_replenishment_quantity(3,target),-1)<>expected)
   OR dbo.fn_replenishment_quantity(3,NULL) IS NOT NULL
   OR dbo.fn_replenishment_quantity(3,-1) IS NOT NULL
   OR dbo.fn_replenishment_quantity(9223372036854775807,10) IS NOT NULL
    THROW 53012,N'补货函数边界错误。',1;
DELETE @results;
EXECUTE AS USER=N'week10_check_inventory';
INSERT @results EXEC api.usp_replenishment @inventory,1,3,10;
INSERT @results EXEC api.usp_replenishment @inventory,1,3,10;
REVERT;
IF (SELECT COUNT(*) FROM @results WHERE JSON_VALUE(result_json,'$.suggested_quantity')='2')<>2
   OR (SELECT stock_total FROM dbo.goods WHERE id=3)<>12
   OR (SELECT reserved_qty FROM dbo.goods WHERE id=3)<>4
   OR (SELECT COUNT_BIG(*) FROM dbo.stock_movement)<>@movement_before
   OR (SELECT COUNT_BIG(*) FROM dbo.purchase_request)<>@purchases_before
    THROW 53012,N'补货过程结果不一致或产生库存写入。',1;
SELECT TOP(1) N'W10-R02' test_case,result_json FROM @results;

IF ISNULL(dbo.fn_member_discount_rate(@silver),-1)<>0.95
   OR ISNULL(dbo.fn_member_discount_rate(@gold),-1)<>0.90
   OR ISNULL(dbo.fn_member_discount_rate(NULL),-1)<>1.00
   OR dbo.fn_member_discount_rate('99999999999') IS NOT NULL
    THROW 53013,N'会员折扣率函数错误。',1;
IF NOT EXISTS(SELECT 1 FROM dbo.fn_sale_discount(101.23,@silver)
              WHERE discount_rate=0.95 AND discounted_amount=96.17 AND discount_amount=5.06)
   OR NOT EXISTS(SELECT 1 FROM dbo.fn_sale_discount(101.23,NULL)
                 WHERE discount_rate=1.00 AND discounted_amount=101.23 AND discount_amount=0)
   OR EXISTS(SELECT 1 FROM dbo.fn_sale_discount(101.23,'99999999999'))
   OR EXISTS(SELECT 1 FROM dbo.fn_sale_discount(NULL,@silver))
    THROW 53013,N'折扣函数舍入或会员折扣处理错误。',1;
SELECT N'W10-D01' test_case,101.23 subtotal,d.* FROM dbo.fn_sale_discount(101.23,@silver) d;
SELECT N'W10-D02' test_case,N'silver 0.95; no member 1.00; unknown member / NULL subtotal: zero rows' actual;

DECLARE @key uniqueidentifier=NEWID(),@payload nvarchar(max)=N'{"id":3,"quantity":1,"note":"W10 SQL test"}';
DELETE @results;
EXECUTE AS USER=N'week10_check_inventory';
INSERT @results EXEC api.usp_operation_write @inventory,1,'damage',@key,@payload;
INSERT @results EXEC api.usp_operation_write @inventory,1,'damage',@key,@payload;
REVERT;
IF NOT EXISTS(SELECT 1 FROM dbo.goods WHERE id=3 AND stock_total=11 AND reserved_qty=4)
   OR (SELECT COUNT(*) FROM dbo.stock_movement WHERE goods_id=3 AND change_type=N'损坏'
       AND quantity=-1 AND note=N'W10 SQL test' AND changed_by=@inventory)<>1
    THROW 53014,N'报损调减、预订保护或同键重试错误。',1;
SELECT N'W10-I01' test_case,12 stock_before,stock_total stock_after,reserved_qty,
       (SELECT COUNT_BIG(*) FROM dbo.stock_movement)-@movement_before AS movements_added
FROM dbo.goods WHERE id=3;

-- 仅给事务内的无登录测试用户授予权限，回滚时随用户一并移除。
GRANT EXECUTE ON OBJECT::api.usp_adjust_stock TO week10_check_inventory;
EXECUTE AS USER=N'week10_check_inventory';
EXEC api.usp_adjust_stock 3,-2,N'损坏',@inventory,1,@reason=N'W10 direct stock';
REVERT;
IF NOT EXISTS(SELECT 1 FROM dbo.goods WHERE id=3 AND stock_total=9 AND reserved_qty=4)
   OR (SELECT COUNT(*) FROM dbo.stock_movement WHERE goods_id=3 AND change_type=N'损坏'
       AND quantity=-2 AND note=N'W10 direct stock' AND changed_by=@inventory)<>1
    THROW 53014,N'库存内部过程直调结果错误。',1;
SELECT N'W10-I03' test_case,11 stock_before,stock_total stock_after,reserved_qty,1 movements_added
FROM dbo.goods WHERE id=3;

-- 直接调用的契约由调用方持有事务。先验证失败时依然可读且没有半写入。
SET XACT_ABORT OFF;
DECLARE @direct_error int=NULL;
EXECUTE AS USER=N'week10_check_inventory';
BEGIN TRY
    EXEC api.usp_adjust_stock 3,-6,N'损坏',@inventory,1,@reason=N'W10 direct insufficient';
END TRY
BEGIN CATCH
    SET @direct_error=ERROR_NUMBER();
END CATCH;
REVERT;
IF ISNULL(@direct_error,0)<>52302 OR @@TRANCOUNT<>1 OR XACT_STATE()<>1
   OR NOT EXISTS(SELECT 1 FROM dbo.goods WHERE id=3 AND stock_total=9 AND reserved_qty=4)
   OR (SELECT COUNT_BIG(*) FROM dbo.stock_movement)<>@movement_before+2
    THROW 53014,N'库存内部过程失败后留下变更或破坏调用方事务。',1;
SELECT N'W10-I04' test_case,@direct_error actual_error,@@TRANCOUNT transaction_count,XACT_STATE() transaction_state,1 state_unchanged;
SET XACT_ABORT ON;
ROLLBACK;

IF (SELECT COUNT_BIG(*) FROM dbo.sale)<>@sale_before
   OR (SELECT COUNT_BIG(*) FROM dbo.stock_movement)<>@movement_before
   OR NOT EXISTS(SELECT 1 FROM dbo.goods WHERE id=3 AND stock_total=@stock_before AND reserved_qty=@reserved_before)
   OR DATABASE_PRINCIPAL_ID(N'week10_check_manager') IS NOT NULL
   OR DATABASE_PRINCIPAL_ID(N'week10_check_inventory') IS NOT NULL
   OR EXISTS(SELECT 1 FROM auth.employee_credential)
    THROW 53014,N'测试没有恢复至初始状态。',1;
SELECT N'W10-Z01' test_case,N'PASS: fixture, movements, credentials and role principals rolled back' actual;

-- 从无外层事务的真实入口执行负例，检验过程返回时的状态。
DECLARE @cases TABLE(test_case varchar(20) PRIMARY KEY,goods_id bigint,target int,from_date date,to_date date,
                     payload nvarchar(max),expected_error int);
INSERT @cases VALUES
('W10-S04-null',NULL,NULL,NULL,'2098-06-02',NULL,53001),
('W10-S04-reversed',NULL,NULL,'2098-06-02','2098-06-01',NULL,53001),
('W10-R03-id',9223372036854775807,10,NULL,NULL,NULL,52304),
('W10-R03-id-null',9223372036854775807,NULL,NULL,NULL,NULL,52304),
('W10-R03-id-neg',9223372036854775807,-1,NULL,NULL,NULL,52304),
('W10-R03-id-zero',0,10,NULL,NULL,NULL,52301),
('W10-R03-null',3,NULL,NULL,NULL,NULL,52301),
('W10-R03-negative',3,-1,NULL,NULL,NULL,52301),
('W10-I02-zero',NULL,NULL,NULL,NULL,N'{"id":3,"quantity":0,"note":"W10 negative"}',52301),
('W10-I02-negative',NULL,NULL,NULL,NULL,N'{"id":3,"quantity":-1,"note":"W10 negative"}',52301),
('W10-I02-reason',NULL,NULL,NULL,NULL,N'{"id":3,"quantity":1}',52301),
('W10-I02-id',NULL,NULL,NULL,NULL,N'{"id":9223372036854775807,"quantity":1,"note":"W10 negative"}',52302),
('W10-I02-stock',NULL,NULL,NULL,NULL,N'{"id":3,"quantity":1000,"note":"W10 negative"}',52302);
DECLARE @case varchar(20),@goods_id bigint,@target int,@start date,@finish date,@expected int,@actual int;
IF ISNULL(@stock_before-@reserved_before,1000)>=1000 THROW 53015,N'负例样例可售量须低于 1000。',1;
-- 主体和凭据先提交，负例结束后统一撤销。
BEGIN TRANSACTION;
CREATE USER week10_check_manager WITHOUT LOGIN;
CREATE USER week10_check_inventory WITHOUT LOGIN;
ALTER ROLE bookstore_app_manager ADD MEMBER week10_check_manager;
ALTER ROLE bookstore_app_inventory ADD MEMBER week10_check_inventory;
INSERT auth.employee_credential(employee_phone,password_hash)
SELECT phone,REPLICATE('x',24) FROM dbo.employee WHERE phone IN (@manager,@inventory);
COMMIT;
DECLARE @failed bit=0;
DECLARE errors CURSOR LOCAL STATIC FOR SELECT * FROM @cases ORDER BY test_case;
OPEN errors;
FETCH NEXT FROM errors INTO @case,@goods_id,@target,@start,@finish,@payload,@expected;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @actual=NULL;
    SET @key=NEWID();
    IF @case LIKE 'W10-S%' EXECUTE AS USER=N'week10_check_manager';
    ELSE EXECUTE AS USER=N'week10_check_inventory';
    BEGIN TRY
        IF @case LIKE 'W10-S%' EXEC api.usp_sales_statistics @manager,1,@start,@finish;
        ELSE IF @case LIKE 'W10-R%' EXEC api.usp_replenishment @inventory,1,@goods_id,@target;
        ELSE EXEC api.usp_operation_write @inventory,1,'damage',@key,@payload;
    END TRY
    BEGIN CATCH
        SET @actual=ERROR_NUMBER();
    END CATCH;
    DECLARE @returned_count int=@@TRANCOUNT,@returned_state int=XACT_STATE();
    DECLARE @unchanged bit=NULL;
    IF @returned_count<>0 OR @returned_state<>0
    BEGIN
        -- 事务泄漏直接判失败，清理后的数据不能用作通过证据。
        SET @failed=1;
        IF @@TRANCOUNT>0 ROLLBACK;
    END;
    REVERT;
    IF @returned_count=0 AND @returned_state=0
        SET @unchanged=CASE WHEN (SELECT COUNT_BIG(*) FROM dbo.stock_movement)=@movement_before
           AND EXISTS(SELECT 1 FROM dbo.goods WHERE id=3 AND stock_total=@stock_before AND reserved_qty=@reserved_before)
           AND NOT EXISTS(SELECT 1 FROM api.operation_request WHERE request_key=@key) THEN 1 ELSE 0 END;
    IF ISNULL(@actual,-1)<>@expected OR ISNULL(@unchanged,0)=0 SET @failed=1;
    SELECT @case test_case,@expected expected_error,@actual actual_error,
           @returned_count transaction_count,@returned_state transaction_state,@unchanged state_unchanged;
    FETCH NEXT FROM errors INTO @case,@goods_id,@target,@start,@finish,@payload,@expected;
END;
CLOSE errors;
DEALLOCATE errors;
BEGIN TRANSACTION;
DELETE FROM auth.employee_credential WHERE employee_phone IN (@manager,@inventory);
DROP USER week10_check_manager;
DROP USER week10_check_inventory;
COMMIT;
IF @failed=1 THROW 53015,N'负例返回错误码或状态不符合预期。',1;
GO
