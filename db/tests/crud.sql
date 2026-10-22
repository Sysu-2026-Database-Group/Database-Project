:On Error exit
-- SQLCMD 模式；演示记录从不提交，不能用这些 DELETE 去删除真实历史单据。
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51009, N'请在无外层事务的新查询窗口执行本脚本。', 1;
BEGIN TRY
    BEGIN TRANSACTION;
    -- 一、商品 CRUD：独立测试文创，尚无库存和成交。
    INSERT dbo.toy (inner_code, spec) VALUES ('DEMO-W3-CRUD', N'第三周事务演示');
    INSERT dbo.goods (category, name, toy_code, created_by)
        VALUES (N'文创', N'CRUD 测试书签', 'DEMO-W3-CRUD', '13800000002');
    DECLARE @goods_id bigint = SCOPE_IDENTITY();
    SELECT N'goods INSERT / UPDATE 前' AS step, * FROM dbo.goods WHERE id=@goods_id;
    UPDATE dbo.goods SET price=10, on_shelf=1,
        updated_by='13800000001', updated_at=SYSDATETIME() WHERE id=@goods_id;
    SELECT N'goods UPDATE 后' AS step, * FROM dbo.goods WHERE id=@goods_id;
    IF NOT EXISTS (SELECT 1 FROM dbo.goods WHERE id=@goods_id AND price=10 AND on_shelf=1)
        THROW 51100, N'商品更新结果不符合预期。', 1;

    -- 二、库存相关 CRUD：采购草稿先完成数量修订，再付款入库。
    INSERT dbo.purchase_request (no, supplier_id, created_by)
        VALUES ('DEMO-W3-PR', 2, '13800000002');
    DECLARE @request_id bigint = SCOPE_IDENTITY();
    INSERT dbo.purchase_request_item (request_id, goods_id, request_qty, unit_cost)
        VALUES (@request_id, @goods_id, 5, 2);
    SELECT N'采购草稿 UPDATE 前' AS step, * FROM dbo.purchase_request WHERE id=@request_id;
    UPDATE dbo.purchase_request SET status=N'已提交', submitted_by='13800000002',
        submitted_at=SYSDATETIME() WHERE id=@request_id;
    SELECT N'采购审批 UPDATE 前' AS step, * FROM dbo.purchase_request WHERE id=@request_id;
    UPDATE dbo.purchase_request SET status=N'已审批', approved_by='13800000001',
        approved_at=SYSDATETIME() WHERE id=@request_id;

    DECLARE @before decimal(12,2);
    SELECT TOP (1) @before=fund_after FROM dbo.fund_flow ORDER BY recorded_at DESC,id DESC;
    INSERT dbo.fund_flow (amount,direction,reason_type,request_id,fund_before,fund_after,recorded_by)
        VALUES (10,N'付',N'采购付款',@request_id,@before,@before-10,'13800000001');
    INSERT dbo.stock_movement (goods_id,change_type,quantity,changed_by,request_id)
        VALUES (@goods_id,N'购入',5,'13800000002',@request_id);
    DECLARE @movement_id bigint = SCOPE_IDENTITY();
    SELECT N'stock_movement INSERT / UPDATE 前' AS step,* FROM dbo.stock_movement WHERE id=@movement_id;
    -- 只补充本事务尚未提交记录的文字说明，不修改历史流水或已确认数量。
    UPDATE dbo.stock_movement SET note=N'演示采购正常足量入库' WHERE id=@movement_id;
    SELECT N'stock_movement UPDATE 后' AS step,* FROM dbo.stock_movement WHERE id=@movement_id;
    SELECT N'库存计数同步前' AS step,id,stock_total FROM dbo.goods WHERE id=@goods_id;
    UPDATE dbo.goods SET stock_total=(SELECT SUM(quantity) FROM dbo.stock_movement WHERE goods_id=@goods_id)
        WHERE id=@goods_id;
    SELECT N'库存计数同步后' AS step,id,stock_total FROM dbo.goods WHERE id=@goods_id;
    SELECT N'采购完成 UPDATE 前' AS step,* FROM dbo.purchase_request WHERE id=@request_id;
    UPDATE dbo.purchase_request SET status=N'已收货' WHERE id=@request_id;

    -- 三、订单 CRUD：销售 1 件，再全额退回。UPDATE 用业务允许的状态迁移。
    INSERT dbo.sale (no,cashier_by,subtotal_amount,discount_rate,point_deduction_amount,paid_amount)
        VALUES ('DEMO-W3-SALE','13800000003',10,1,0,10);
    DECLARE @sale_id bigint = SCOPE_IDENTITY();
    INSERT dbo.sale_item (sale_id,goods_id,quantity,unit_price) VALUES (@sale_id,@goods_id,1,10);
    DECLARE @sale_item_id bigint = SCOPE_IDENTITY();
    INSERT dbo.stock_movement (goods_id,change_type,quantity,changed_by,sale_id)
        VALUES (@goods_id,N'卖出',-1,'13800000003',@sale_id);
    SELECT N'销售出库计数 UPDATE 前' AS step,id,stock_total FROM dbo.goods WHERE id=@goods_id AND stock_total-reserved_qty>=1;
    UPDATE dbo.goods SET stock_total=stock_total-1 WHERE id=@goods_id AND stock_total-reserved_qty>=1;
    IF @@ROWCOUNT<>1 THROW 51101, N'可售库存不足，取消整个演示事务。', 1;
    INSERT dbo.fund_flow (amount,direction,reason_type,sale_id,fund_before,fund_after,recorded_by)
        VALUES (10,N'收',N'销售收款',@sale_id,@before-10,@before,'13800000003');
    SELECT N'sale INSERT / 退货前' AS step,* FROM dbo.sale WHERE id=@sale_id;

    INSERT dbo.goods_return (no,sale_id,refund_amount,handled_by)
        VALUES ('DEMO-W3-RETURN',@sale_id,10,'13800000004');
    DECLARE @return_id bigint = SCOPE_IDENTITY();
    INSERT dbo.goods_return_item (return_id,sale_item_id,quantity,refund_amount)
        VALUES (@return_id,@sale_item_id,1,10);
    DECLARE @return_item_id bigint = SCOPE_IDENTITY();
    INSERT dbo.stock_movement (goods_id,change_type,quantity,changed_by,return_item_id)
        VALUES (@goods_id,N'退货',1,'13800000002',@return_item_id);
    SELECT N'退货入库计数 UPDATE 前' AS step,id,stock_total FROM dbo.goods WHERE id=@goods_id;
    UPDATE dbo.goods SET stock_total=stock_total+1 WHERE id=@goods_id;
    INSERT dbo.fund_flow (amount,direction,reason_type,sale_id,return_id,fund_before,fund_after,recorded_by)
        VALUES (10,N'付',N'退货退款',@sale_id,@return_id,@before,@before-10,'13800000004');
    SELECT N'sale UPDATE 前' AS step,* FROM dbo.sale WHERE id=@sale_id;
    UPDATE dbo.sale SET status=N'已全退' WHERE id=@sale_id;
    SELECT N'sale UPDATE 后' AS step,* FROM dbo.sale WHERE id=@sale_id;
    IF NOT EXISTS (SELECT 1 FROM dbo.sale WHERE id=@sale_id AND status=N'已全退')
        THROW 51102, N'销售状态迁移失败。', 1;
    IF EXISTS (SELECT 1 FROM dbo.goods WHERE id=@goods_id AND stock_total<>
        (SELECT SUM(quantity) FROM dbo.stock_movement WHERE goods_id=@goods_id))
        THROW 51103, N'演示库存与流水不一致。', 1;

    -- DELETE 只演示删除本事务新建的、从未提交的实验数据；实际业务历史记录不可删除。
    -- 按外键依赖顺序清理，每条 DELETE 前用相同 WHERE 查询目标。
    SELECT N'fund_flow DELETE 前' AS step,* FROM dbo.fund_flow WHERE request_id=@request_id OR sale_id=@sale_id;
    DELETE dbo.fund_flow WHERE request_id=@request_id OR sale_id=@sale_id;
    SELECT N'stock_movement DELETE 前' AS step,* FROM dbo.stock_movement WHERE goods_id=@goods_id;
    DELETE dbo.stock_movement WHERE goods_id=@goods_id;
    SELECT N'stock_movement DELETE 后' AS step,COUNT(*) AS remaining FROM dbo.stock_movement WHERE goods_id=@goods_id;
    SELECT N'清理库存计数 UPDATE 前' AS step,id,stock_total FROM dbo.goods WHERE id=@goods_id;
    UPDATE dbo.goods SET stock_total=COALESCE((SELECT SUM(quantity) FROM dbo.stock_movement WHERE goods_id=@goods_id),0)
        WHERE id=@goods_id;
    SELECT N'return_item DELETE 前' AS step,* FROM dbo.goods_return_item WHERE return_id=@return_id;
    DELETE dbo.goods_return_item WHERE return_id=@return_id;
    SELECT N'return DELETE 前' AS step,* FROM dbo.goods_return WHERE id=@return_id;
    DELETE dbo.goods_return WHERE id=@return_id;
    SELECT N'sale_item DELETE 前' AS step,* FROM dbo.sale_item WHERE sale_id=@sale_id;
    DELETE dbo.sale_item WHERE sale_id=@sale_id;
    SELECT N'sale DELETE 前' AS step,* FROM dbo.sale WHERE id=@sale_id;
    DELETE dbo.sale WHERE id=@sale_id;
    SELECT N'sale DELETE 后' AS step,COUNT(*) AS remaining FROM dbo.sale WHERE id=@sale_id;
    SELECT N'purchase_item DELETE 前' AS step,* FROM dbo.purchase_request_item WHERE request_id=@request_id;
    DELETE dbo.purchase_request_item WHERE request_id=@request_id;
    SELECT N'purchase DELETE 前' AS step,* FROM dbo.purchase_request WHERE id=@request_id;
    DELETE dbo.purchase_request WHERE id=@request_id;
    SELECT N'goods DELETE 前' AS step,* FROM dbo.goods WHERE id=@goods_id;
    DELETE dbo.goods WHERE id=@goods_id;
    SELECT N'goods DELETE 后' AS step,COUNT(*) AS remaining FROM dbo.goods WHERE id=@goods_id;
    SELECT N'toy DELETE 前' AS step,* FROM dbo.toy WHERE inner_code='DEMO-W3-CRUD';
    DELETE dbo.toy WHERE inner_code='DEMO-W3-CRUD';

    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.toy WHERE inner_code='DEMO-W3-CRUD')
        THROW 51104, N'演示记录未清理。', 1;
    PRINT N'crud.sql PASS: goods / inventory / sale CRUD completed and rolled back.';
    -- IDENTITY 可能留下号段间隙，这是 SQL Server 的正常行为；基线行和值保持不变。
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
