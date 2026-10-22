#requires -Version 7.0
<#
从现有 v0.1 库 COPY_ONLY 备份并还原到新库，保存 SQLCMD 原始输出和退出码。
不覆盖 / 删除已有数据库、备份或结果目录；测试库保留以供 SSMS 人工复查。
#>
param(
    [string]$Server = 'localhost',
    [ValidatePattern('^ShiguangBookstoreWeek6[A-Za-z0-9_]+$')]
    [string]$DatabaseName = ('ShiguangBookstoreWeek6Acceptance' + (Get-Date -Format 'yyyyMMddHHmmss')),
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')]
    [string]$SourceDatabaseName = 'ShiguangBookstoreWeek3',
    [string]$EvidenceDirectory = ''
)
$ErrorActionPreference = 'Stop'
$sqlcmd = (Get-Command sqlcmd -ErrorAction Stop).Source
$repo = Split-Path $PSScriptRoot -Parent
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $PSScriptRoot ('results/week-6/' + $DatabaseName) }
$evidence = [IO.Path]::GetFullPath($EvidenceDirectory)
if (Test-Path -LiteralPath $evidence) { throw "结果目录已存在，停止以免覆盖：$evidence" }
$failureDatabase = $DatabaseName + 'Failure'
if ($failureDatabase.Length -gt 128) { throw '数据库名过长。' }
if ($DatabaseName -eq $SourceDatabaseName -or $failureDatabase -eq $SourceDatabaseName) { throw '验收库不能等于来源库。' }
$common = @('-S', $Server, '-E', '-C', '-b', '-l', '10', '-t', '120', '-f', '65001', '-W', '-s', '|')
$preflight = & $sqlcmd @common -h -1 -Q "SET NOCOUNT ON; IF DB_ID(N'$DatabaseName') IS NOT NULL OR DB_ID(N'$failureDatabase') IS NOT NULL THROW 51990,N'验收目标已存在，禁止覆盖。',1; IF DB_ID(N'$SourceDatabaseName') IS NULL THROW 51991,N'来源库不存在。',1; SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')); SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath')); SELECT name FROM sys.master_files WHERE database_id=DB_ID(N'$SourceDatabaseName') ORDER BY type;"
if ($LASTEXITCODE -ne 0) { throw ($preflight -join "`n") }
$paths = @($preflight | Where-Object { $_.Trim() })
if ($paths.Count -ne 4) { throw '要求来源库恰有一个数据文件和一个日志文件，且实例目录可解析。' }
# 本入口面向本机实例；所有文件由本机 SQL Server 服务账号访问。
if ($Server -notin @('localhost', '.', $env:COMPUTERNAME)) { throw '备份路径检查仅支持本机默认实例。' }
$dataPath, $backupPath, $logicalData, $logicalLog = $paths
$backup = Join-Path $backupPath ($DatabaseName + '.bak')
foreach ($candidate in @($backup, (Join-Path $dataPath "$DatabaseName.mdf"), (Join-Path $dataPath "${DatabaseName}_log.ldf"), (Join-Path $dataPath "$failureDatabase.mdf"), (Join-Path $dataPath "${failureDatabase}_log.ldf"))) {
    if (Test-Path -LiteralPath $candidate) { throw "目标文件已存在，停止：$candidate" }
}
New-Item -ItemType Directory -Path $evidence | Out-Null
$steps = [Collections.Generic.List[object]]::new()
function Invoke-Step {
    param([string]$Name, [string]$Database = $DatabaseName, [string]$Script = '', [string]$Query = '', [int]$ExpectedError = 0)
    $output = Join-Path $evidence ($Name + '.txt')
    $commandArgs = $common + @('-v', "DatabaseName=$Database", '-o', $output)
    if ($Script) {
        $scriptPath = if ([IO.Path]::IsPathRooted($Script)) { $Script } else { Join-Path $PSScriptRoot $Script }
        $commandArgs += @('-i', $scriptPath)
    }
    else { $commandArgs += @('-Q', $Query) }
    & $sqlcmd @commandArgs
    $code = $LASTEXITCODE
    $text = if (Test-Path -LiteralPath $output) { Get-Content -LiteralPath $output -Raw -Encoding utf8 } else { '' }
    $ok = if ($ExpectedError) { $code -ne 0 -and $text -match "\b$ExpectedError\b" } else { $code -eq 0 }
    $steps.Add([pscustomobject]@{step=$Name; database=$Database; script=$Script; query=$Query; exit_code=$code; expected_error=$ExpectedError; passed=$ok; output=($Name+'.txt')})
    $steps | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'steps.json') -Encoding utf8
    if (-not $ok) { throw "步骤 $Name 未符合预期（退出码 $code）；见 $output" }
    Write-Host "$Name PASS (exit=$code)"
}
function Assert-SnapshotEqual {
    param([string]$Before, [string]$After)
    $a = @(Get-Content -LiteralPath (Join-Path $evidence "$Before.txt") | Where-Object { $_ -match '^\w+\|\d+\|[A-F0-9]{64}$' })
    $b = @(Get-Content -LiteralPath (Join-Path $evidence "$After.txt") | Where-Object { $_ -match '^\w+\|\d+\|[A-F0-9]{64}$' })
    if ($a.Count -ne 19 -or $b.Count -ne 19 -or (Compare-Object $a $b)) { throw "完整旧列快照不同：$Before / $After" }
}
function Restore-Copy {
    param([string]$Target, [string]$StepName)
    $dataFile = (Join-Path $dataPath "$Target.mdf").Replace("'", "''")
    $logFile = (Join-Path $dataPath "${Target}_log.ldf").Replace("'", "''")
    Invoke-Step -Name $StepName -Database $Target -Query "IF DB_ID(N'$Target') IS NOT NULL THROW 51990,N'禁止覆盖已有库。',1; RESTORE DATABASE [$Target] FROM DISK=N'$($backup.Replace("'", "''"))' WITH MOVE N'$($logicalData.Replace("'", "''"))' TO N'$dataFile', MOVE N'$($logicalLog.Replace("'", "''"))' TO N'$logFile', CHECKSUM;"
}
Invoke-Step -Name '00-environment' -Query "SET NOCOUNT ON; SELECT @@VERSION AS version, SUSER_SNAME() AS executor, SYSDATETIMEOFFSET() AS executed_at; SELECT name,state_desc FROM sys.databases WHERE name LIKE N'Shiguang%';"
Invoke-Step -Name '01-source-before' -Database $SourceDatabaseName -Script 'checks/legacy-snapshot.sql'
Invoke-Step -Name '02-backup' -Query "BACKUP DATABASE [$SourceDatabaseName] TO DISK=N'$($backup.Replace("'", "''"))' WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY FROM DISK=N'$($backup.Replace("'", "''"))' WITH CHECKSUM;"
Restore-Copy -Target $DatabaseName -StepName '03-restore'
Invoke-Step -Name '04-restored-snapshot' -Script 'checks/legacy-snapshot.sql'
Assert-SnapshotEqual '01-source-before' '04-restored-snapshot'
Invoke-Step -Name '05-baseline' -Script 'checks/verify.sql'
Invoke-Step -Name '06-query-before' -Script 'query.sql'
Invoke-Step -Name '07-constraint' -Script 'constraint.sql'
Invoke-Step -Name '08-migration' -Script 'migration.sql'
Invoke-Step -Name '09-migration-check' -Script 'checks/migration-check.sql'
Invoke-Step -Name '10-migrated-snapshot' -Script 'checks/legacy-snapshot.sql'
Assert-SnapshotEqual '04-restored-snapshot' '10-migrated-snapshot'
Invoke-Step -Name '11-query-after' -Script 'query.sql'
if (Compare-Object (Get-Content (Join-Path $evidence '06-query-before.txt')) (Get-Content (Join-Path $evidence '11-query-after.txt'))) { throw '迁移前后关键查询输出不一致。' }
Invoke-Step -Name '12-migration-repeat' -Script 'migration.sql'
Invoke-Step -Name '13-sample' -Script 'sample-data-week-6.sql'
Invoke-Step -Name '14-regression' -Script 'regression.sql'
Invoke-Step -Name '15-expanded-before-tests' -Script 'checks/legacy-snapshot.sql'
$tests = @('tests/regression-negative.sql','role.sql','tests/transaction-week-6.sql','tests/price-snapshot-week-6.sql','tests/supplier-audit-week-6.sql','tests/unique-index-week-6.sql','tests/sales-statistics-week-6.sql','tests/inventory-query-week-6.sql','tests/supplier-cost-week-6.sql','tests/member-validity-week-6.sql','tests/duplicate-cancel-boundary-check.sql','tests/auto-expiry-boundary-check.sql')
$index = 16
foreach ($test in $tests) {
    Invoke-Step -Name ('{0:D2}-{1}' -f $index,[IO.Path]::GetFileNameWithoutExtension($test)) -Script $test
    $index++
}
Invoke-Step -Name '28-sample-repeat' -Script 'sample-data-week-6.sql'
Invoke-Step -Name '29-final-regression' -Script 'regression.sql'
Invoke-Step -Name '30-expanded-after-tests' -Script 'checks/legacy-snapshot.sql'
Assert-SnapshotEqual '15-expanded-before-tests' '30-expanded-after-tests'
# 第二个还原副本专用于错误路径，不向原始库或正常验收库注入故障。
Restore-Copy -Target $failureDatabase -StepName '31-failure-restore'
Invoke-Step -Name '32-failure-snapshot-before' -Database $failureDatabase -Script 'checks/legacy-snapshot.sql'
Invoke-Step -Name '33-inject-index-conflict' -Database $failureDatabase -Query "USE [$failureDatabase]; CREATE INDEX UX_point_movement_return ON dbo.point_movement(member_phone);"
Invoke-Step -Name '34-migration-rollback' -Database $failureDatabase -Script 'migration.sql' -ExpectedError 1913
Invoke-Step -Name '35-rollback-assertions' -Database $failureDatabase -Query "USE [$failureDatabase]; SET NOCOUNT ON; IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>19 OR (SELECT COUNT(*) FROM sys.foreign_keys)<>47 OR OBJECT_ID(N'dbo.schema_migration',N'U') IS NOT NULL OR COL_LENGTH(N'dbo.supplier',N'updated_by') IS NOT NULL OR EXISTS(SELECT 1 FROM sys.indexes WHERE name IN(N'UX_goods_book_isbn',N'UX_goods_toy_code',N'UX_sale_reservation_id',N'UX_point_movement_earn',N'UX_point_movement_use')) THROW 51992,N'迁移失败后存在部分结构。',1; SELECT N'PASS: migration DDL rolled back' AS result;"
Invoke-Step -Name '36-failure-snapshot-after' -Database $failureDatabase -Script 'checks/legacy-snapshot.sql'
Assert-SnapshotEqual '32-failure-snapshot-before' '36-failure-snapshot-after'
# 变异检查：在同一权限测试路径注入非权限异常，必须失败而不是误记 PASS。
$roleSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'role.sql') -Raw -Encoding utf8
$needle = 'UPDATE dbo.[goods] SET [price] = [price] WHERE [id] = 1;'
if (-not $roleSource.Contains($needle)) { throw '找不到权限变异测试锚点。' }
$mutant = $roleSource.Replace($needle, "THROW 51039,N'injected non-permission error',1;")
$mutantPath = Join-Path $evidence 'role-unexpected-error.sql'
$mutant | Set-Content -LiteralPath $mutantPath -Encoding utf8
Invoke-Step -Name '37-role-rejects-unexpected-error' -Database $failureDatabase -Script ([IO.Path]::GetRelativePath($PSScriptRoot,$mutantPath)) -ExpectedError 51039
Invoke-Step -Name '38-source-after' -Database $SourceDatabaseName -Script 'checks/legacy-snapshot.sql'
Assert-SnapshotEqual '01-source-before' '38-source-after'
Invoke-Step -Name '39-backup-metadata' -Query "SET NOCOUNT ON; SELECT bs.database_name,bs.is_copy_only,bs.has_backup_checksums,bs.backup_size,bs.backup_finish_date,bmf.physical_device_name FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id=bs.media_set_id WHERE bmf.physical_device_name=N'$($backup.Replace("'", "''"))';"
Invoke-Step -Name '40-original-target-rejected' -Database $SourceDatabaseName -Script 'migration.sql' -ExpectedError 51040
# 故障副本授予原本不允许的权限；正式判据必须发现泄漏并以 51030 失败。
Invoke-Step -Name '41-inject-permission-leak' -Database $failureDatabase -Query "USE [$failureDatabase]; GRANT UPDATE(price) ON dbo.goods TO bookstore_cashier;"
Invoke-Step -Name '42-role-rejects-permission-leak' -Database $failureDatabase -Script 'role.sql' -ExpectedError 51030
Invoke-Step -Name '43-remove-injected-permission' -Database $failureDatabase -Query "USE [$failureDatabase]; REVOKE UPDATE(price) ON dbo.goods FROM bookstore_cashier;"
Invoke-Step -Name '44-source-final' -Database $SourceDatabaseName -Script 'checks/legacy-snapshot.sql'
Assert-SnapshotEqual '01-source-before' '44-source-final'
$manifest = Get-ChildItem -LiteralPath $evidence -File | ForEach-Object { [pscustomobject]@{file=$_.Name; bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} }
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'manifest.json') -Encoding utf8
[pscustomobject]@{status='PASS';source=$SourceDatabaseName;database=$DatabaseName;failure_database=$failureDatabase;backup=$backup;backup_integrity='COPY_ONLY, BACKUP CHECKSUM and RESTORE VERIFYONLY CHECKSUM; file hash not collected';steps=$steps.Count;source_unchanged=$true;legacy_rows_preserved=$true;test_rows_restored=$true;human_signoff='pending';executed_at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
Write-Host "Week6 executable acceptance PASS. Evidence: $evidence"
