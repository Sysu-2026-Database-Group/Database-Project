-- 第六周自动过期边界检查：固定测试时刻，不执行状态更新
-- 本脚本只读，用于确认当前是否存在自动把有效预订改为已过期的机制。
USE [ShiguangBookstoreWeek6Work];
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'ShiguangBookstoreWeek6Work'
    THROW 51810, N'当前数据库不是 ShiguangBookstoreWeek6Work，停止自动过期边界检查。', 1;

DECLARE @as_of DATETIME2 = '2026-10-01T12:00:00';
DECLARE @expired_effective BIGINT;
SELECT @expired_effective = COUNT_BIG(*)
FROM dbo.reservation
WHERE status=N'有效'
  AND expires_at <= @as_of;

SELECT @as_of AS fixed_test_time,
       @expired_effective AS effective_reservations_past_expiry,
       CASE WHEN @expired_effective=0
            THEN N'NO_EXPIRED_EFFECTIVE_RESERVATION'
            ELSE N'AUTO_EXPIRY_NOT_APPLIED'
       END AS observed_behavior;

SELECT code, status, created_at, expires_at, cancelled_by_employee, cancelled_at
FROM dbo.reservation
WHERE status=N'有效'
  AND expires_at <= @as_of
ORDER BY expires_at, code;

PRINT N'auto-expiry-boundary-check.sql PASS: read-only observation completed; no reservation status was changed.';
