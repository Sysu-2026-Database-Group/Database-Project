#requires -Version 5.1
<#
Reviewer B 独立复现 runner（PowerShell 5.1 + 命名实例）。
与 db/accept-week-6.ps1 同序，差异仅三处：
  1) 支持 host\instance（官方入口只接受 localhost / . / 主机名）；
  2) 不要求 PowerShell 7；
  3) 源库由参数指定，默认使用本机干净的 v0.1 库 ShiguangBookstoreVerify2。
不覆盖已有库、备份或结果目录；故障注入只发生在 Failure 副本。
#>
param(
    [string]$Server = '.\SQLEXPRESS',
    [string]$SourceDatabaseName = 'ShiguangBookstoreVerify2',
    [string]$DatabaseName = 'ShiguangBookstoreWeek6B20261022',
    [string]$EvidenceDirectory = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$sqlcmd = (Get-Command sqlcmd -ErrorAction Stop).Source
$repo = Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
$evidence = [IO.Path]::GetFullPath($EvidenceDirectory)
if (-not (Test-Path -LiteralPath $evidence)) { New-Item -ItemType Directory -Path $evidence | Out-Null }
$failureDatabase = $DatabaseName + 'Failure'
if ($DatabaseName -notlike 'ShiguangBookstoreWeek6*') { throw '验收库名必须以 ShiguangBookstoreWeek6 开头。' }
if ($DatabaseName -eq $SourceDatabaseName) { throw '验收库不能等于来源库。' }

$common = @('-S', $Server, '-E', '-C', '-b', '-l', '15', '-t', '180', '-f', '65001', '-W', '-s', '|')
$preflight = & $sqlcmd @common -h -1 -Q "SET NOCOUNT ON; IF DB_ID(N'$DatabaseName') IS NOT NULL OR DB_ID(N'$failureDatabase') IS NOT NULL THROW 51990,N'验收目标已存在，禁止覆盖。',1; IF DB_ID(N'$SourceDatabaseName') IS NULL THROW 51991,N'来源库不存在。',1; SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')); SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath')); SELECT name FROM sys.master_files WHERE database_id=DB_ID(N'$SourceDatabaseName') ORDER BY type;"
if ($LASTEXITCODE -ne 0) { throw ($preflight -join "`n") }
$paths = @($preflight | Where-Object { $_.Trim() })
if ($paths.Count -ne 4) { throw "要求来源库恰有一个数据文件和一个日志文件；实得 $($paths.Count) 行。" }
$dataPath, $backupPath, $logicalData, $logicalLog = $paths
$backup = Join-Path $backupPath ($DatabaseName + '.bak')
foreach ($candidate in @($backup, (Join-Path $dataPath "$DatabaseName.mdf"), (Join-Path $dataPath "${DatabaseName}_log.ldf"), (Join-Path $dataPath "$failureDatabase.mdf"), (Join-Path $dataPath "${failureDatabase}_log.ldf"))) {
    if (Test-Path -LiteralPath $candidate) { throw "目标文件已存在，停止：$candidate" }
}

$steps = @()
function Invoke-Step {
    param([string]$Name, [string]$Database = $DatabaseName, [string]$Script = '', [string]$Query = '', [int]$ExpectedError = 0)
    $output = Join-Path $evidence ($Name + '.txt')
    $cli = $common + @('-v', "DatabaseName=$Database", '-o', $output)
    if ($Script) {
        $scriptPath = if ([IO.Path]::IsPathRooted($Script)) { $Script } else { Join-Path $repo $Script }
        $cli += @('-i', $scriptPath)
    } else { $cli += @('-Q', $Query) }
    & $sqlcmd @cli
    $code = $LASTEXITCODE
    $text = if (Test-Path -LiteralPath $output) { Get-Content -LiteralPath $output -Raw -Encoding utf8 } else { '' }
    $ok = if ($ExpectedError) { $code -ne 0 -and $text -match ("消息 " + $ExpectedError + "，") } else { $code -eq 0 }
    $script:steps += [pscustomobject]@{ step = $Name; database = $Database; script = $Script; exit_code = $code; expected_error = $ExpectedError; passed = $ok; output = ($Name + '.txt') }
    $script:steps | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'steps.json') -Encoding utf8
    if (-not $ok) { throw "步骤 $Name 未符合预期（退出码 $code）；见 $output" }
    Write-Host "$Name PASS (exit=$code)"
}
function Assert-SnapshotEqual {
    param([string]$Before, [string]$After)
    $a = @(Get-Content -LiteralPath (Join-Path $evidence "$Before.txt") | Where-Object { $_ -match '^\w+\|\d+\|[A-F0-9]{64}$' })
    $b = @(Get-Content -LiteralPath (Join-Path $evidence "$After.txt") | Where-Object { $_ -match '^\w+\|\d+\|[A-F0-9]{64}$' })
    if ($a.Count -ne 19 -or $b.Count -ne 19 -or (Compare-Object $a $b)) { throw "完整旧列快照不同：$Before / $After" }
    Write-Host "snapshot equal: $Before = $After"
}
function Restore-Copy {
    param([string]$Target, [string]$StepName)
    $dataFile = (Join-Path $dataPath "$Target.mdf").Replace("'", "''")
    $logFile = (Join-Path $dataPath "${Target}_log.ldf").Replace("'", "''")
    Invoke-Step -Name $StepName -Database 'master' -Query "IF DB_ID(N'$Target') IS NOT NULL THROW 51990,N'禁止覆盖已有库。',1; RESTORE DATABASE [$Target] FROM DISK=N'$($backup.Replace("'", "''"))' WITH MOVE N'$($logicalData.Replace("'", "''"))' TO N'$dataFile', MOVE N'$($logicalLog.Replace("'", "''"))' TO N'$logFile', CHECKSUM;"
}

Invoke-Step -Name '00-environment' -Database 'master' -Query "SET NOCOUNT ON; SELECT @@VERSION AS version, SUSER_SNAME() AS executor, SYSDATETIMEOFFSET() AS executed_at, N'$Server' AS instance; SELECT name,state_desc FROM sys.databases WHERE name LIKE N'Shiguang%';"
Invoke-Step -Name '01-source-before' -Database $SourceDatabaseName -Script 'db/checks/legacy-snapshot.sql'
Invoke-Step -Name '02-backup' -Database 'master' -Query "BACKUP DATABASE [$SourceDatabaseName] TO DISK=N'$($backup.Replace("'", "''"))' WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY FROM DISK=N'$($backup.Replace("'", "''"))' WITH CHECKSUM;"
Restore-Copy -Target $DatabaseName -StepName '03-restore'
Invoke-Step -Name '04-restored-snapshot' -Script 'db/checks/legacy-snapshot.sql'
Assert-SnapshotEqual '01-source-before' '04-restored-snapshot'
Invoke-Step -Name '05-baseline' -Script 'db/checks/verify.sql'
Invoke-Step -Name '06-query-before' -Script 'db/query.sql'
Invoke-Step -Name '07-constraint' -Script 'db/constraint.sql'
Invoke-Step -Name '08-migration' -Script 'db/migration.sql'
Invoke-Step -Name '09-migration-check' -Script 'db/checks/migration-check.sql'
Invoke-Step -Name '10-migrated-snapshot' -Script 'db/checks/legacy-snapshot.sql'
Assert-SnapshotEqual '04-restored-snapshot' '10-migrated-snapshot'
Invoke-Step -Name '11-query-after' -Script 'db/query.sql'
if ((Get-Content (Join-Path $evidence '06-query-before.txt') -Raw) -cne (Get-Content (Join-Path $evidence '11-query-after.txt') -Raw)) { throw '迁移前后关键查询输出不一致。' }
Write-Host 'query before/after identical'
Invoke-Step -Name '12-migration-repeat' -Script 'db/migration.sql'
Invoke-Step -Name '13-sample' -Script 'db/sample-data-week-6.sql'
Invoke-Step -Name '14-regression' -Script 'db/regression.sql'
Invoke-Step -Name '15-expanded-before-tests' -Script 'db/checks/legacy-snapshot.sql'
$tests = @('db/tests/regression-negative.sql','db/role.sql','db/tests/transaction-week-6.sql','db/tests/price-snapshot-week-6.sql','db/tests/supplier-audit-week-6.sql','db/tests/unique-index-week-6.sql','db/tests/sales-statistics-week-6.sql','db/tests/inventory-query-week-6.sql','db/tests/supplier-cost-week-6.sql','db/tests/member-validity-week-6.sql','db/tests/duplicate-cancel-boundary-check.sql','db/tests/auto-expiry-boundary-check.sql')
$index = 16
foreach ($test in $tests) {
    Invoke-Step -Name ('{0:D2}-{1}' -f $index, [IO.Path]::GetFileNameWithoutExtension($test)) -Script $test
    $index++
}
Invoke-Step -Name '28-sample-repeat' -Script 'db/sample-data-week-6.sql'
Invoke-Step -Name '29-final-regression' -Script 'db/regression.sql'
Invoke-Step -Name '30-expanded-after-tests' -Script 'db/checks/legacy-snapshot.sql'
Assert-SnapshotEqual '15-expanded-before-tests' '30-expanded-after-tests'
Restore-Copy -Target $failureDatabase -StepName '31-failure-restore'
Invoke-Step -Name '32-failure-snapshot-before' -Database $failureDatabase -Script 'db/checks/legacy-snapshot.sql'
Invoke-Step -Name '33-inject-index-conflict' -Database $failureDatabase -Query "USE [$failureDatabase]; CREATE INDEX UX_point_movement_return ON dbo.point_movement(member_phone);"
Invoke-Step -Name '34-migration-rollback' -Database $failureDatabase -Script 'db/migration.sql' -ExpectedError 1913
Invoke-Step -Name '35-rollback-assertions' -Database $failureDatabase -Query "USE [$failureDatabase]; SET NOCOUNT ON; IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>19 OR (SELECT COUNT(*) FROM sys.foreign_keys)<>47 OR OBJECT_ID(N'dbo.schema_migration',N'U') IS NOT NULL OR COL_LENGTH(N'dbo.supplier',N'updated_by') IS NOT NULL OR EXISTS(SELECT 1 FROM sys.indexes WHERE name IN(N'UX_goods_book_isbn',N'UX_goods_toy_code',N'UX_sale_reservation_id',N'UX_point_movement_earn',N'UX_point_movement_use')) THROW 51992,N'迁移失败后存在部分结构。',1; SELECT N'PASS: migration DDL rolled back' AS result;"
Invoke-Step -Name '36-failure-snapshot-after' -Database $failureDatabase -Script 'db/checks/legacy-snapshot.sql'
Assert-SnapshotEqual '32-failure-snapshot-before' '36-failure-snapshot-after'
Invoke-Step -Name '37-source-after' -Database $SourceDatabaseName -Script 'db/checks/legacy-snapshot.sql'
Assert-SnapshotEqual '01-source-before' '37-source-after'
Invoke-Step -Name '38-original-target-rejected' -Database $SourceDatabaseName -Script 'db/migration.sql' -ExpectedError 51040
Invoke-Step -Name '39-source-final' -Database $SourceDatabaseName -Script 'db/checks/legacy-snapshot.sql'
Assert-SnapshotEqual '01-source-before' '39-source-final'

$manifest = Get-ChildItem -LiteralPath $evidence -File | Where-Object { $_.Name -ne 'manifest.json' } | ForEach-Object { [pscustomobject]@{ file = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower() } }
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'manifest.json') -Encoding utf8
[pscustomobject]@{
    status = 'PASS'; reviewer = 'Reviewer B'; server = $Server; source = $SourceDatabaseName;
    database = $DatabaseName; failure_database = $failureDatabase; backup = $backup;
    backup_integrity = 'COPY_ONLY + BACKUP CHECKSUM + RESTORE VERIFYONLY CHECKSUM; file hash not collected';
    steps = $steps.Count; source_unchanged = $true; legacy_rows_preserved = $true; test_rows_restored = $true;
    power_shell = $PSVersionTable.PSVersion.ToString(); executed_at = (Get-Date).ToString('o');
    skipped = '37-43 官方权限变异步骤（grant/revoke 注入）未复现；改由 role.sql 常规越权用例覆盖，见 README'
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
Write-Host "Reviewer B acceptance PASS. Evidence: $evidence"
