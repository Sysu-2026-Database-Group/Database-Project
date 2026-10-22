#requires -Version 5.1
<#
补测官方 45 步中第一轮未跑的 5 步：37 / 39 / 41 / 42 / 43，另加一次撤销后复跑。
针对已完成的验收库（默认 ...B20261022R2），只追加证据，不重跑主流程。
#>
param(
    [string]$Server = '.\SQLEXPRESS',
    [string]$DatabaseName = 'ShiguangBookstoreWeek6B20261022R2',
    [string]$EvidenceDirectory = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$sqlcmd = (Get-Command sqlcmd -ErrorAction Stop).Source
$repo = Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
$evidence = [IO.Path]::GetFullPath($EvidenceDirectory)
$common = @('-S', $Server, '-E', '-C', '-b', '-l', '15', '-t', '180', '-f', '65001', '-W', '-s', '|')
$stepsPath = Join-Path $evidence 'steps.json'
$parsed = Get-Content -LiteralPath $stepsPath -Raw -Encoding utf8 | ConvertFrom-Json
$steps = @()
foreach ($s in $parsed) { if ($s.step -notlike 'supplement-*') { $steps += $s } }
if ($steps.Count -ne 40) { throw "主流程步骤数不是 40（实得 $($steps.Count)），请先跑 run-b.ps1。" }

function Invoke-Step {
    param([string]$Name, [string]$Script = '', [string]$Query = '', [int]$ExpectedError = 0)
    $output = Join-Path $evidence ($Name + '.txt')
    $cli = $common + @('-v', "DatabaseName=$DatabaseName", '-o', $output)
    if ($Script) {
        $scriptPath = if ([IO.Path]::IsPathRooted($Script)) { $Script } else { Join-Path $repo $Script }
        $cli += @('-i', $scriptPath)
    } else { $cli += @('-Q', $Query) }
    & $sqlcmd @cli
    $code = $LASTEXITCODE
    $text = if (Test-Path -LiteralPath $output) { Get-Content -LiteralPath $output -Raw -Encoding utf8 } else { '' }
    $ok = if ($ExpectedError) { $code -ne 0 -and $text -match ("消息 " + $ExpectedError + "，") } else { $code -eq 0 }
    $script:steps += [pscustomobject]@{ step = $Name; database = $DatabaseName; script = $Script; exit_code = $code; expected_error = $ExpectedError; passed = $ok; output = ($Name + '.txt') }
    $script:steps | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stepsPath -Encoding utf8
    if (-not $ok) { throw "步骤 $Name 未符合预期（退出码 $code）；见 $output" }
    Write-Host "$Name PASS (exit=$code)"
}

# 官方 37：把越权更新语句替换为“非权限异常”，判据必须上抛而不是记 PASS
$roleSource = Get-Content -LiteralPath (Join-Path $repo 'db/role.sql') -Raw -Encoding utf8
$needle = 'UPDATE dbo.[goods] SET [price] = [price] WHERE [id] = 1;'
if (-not $roleSource.Contains($needle)) { throw '找不到权限变异测试锚点。' }
$mutantPath = Join-Path $evidence 'role-unexpected-error.sql'
$roleSource.Replace($needle, "THROW 51039,N'injected non-permission error',1;") |
    Set-Content -LiteralPath $mutantPath -Encoding utf8
Invoke-Step -Name 'supplement-37-role-rejects-unexpected-error' -Script $mutantPath -ExpectedError 51039

# 官方 39：备份元数据（只读）
$backup = (Get-Content -LiteralPath (Join-Path $evidence 'summary.json') -Raw -Encoding utf8 | ConvertFrom-Json).backup
Invoke-Step -Name 'supplement-39-backup-metadata' -Query "SET NOCOUNT ON; SELECT bs.database_name, bs.is_copy_only, bs.has_backup_checksums, bs.backup_size, bs.backup_finish_date, bmf.physical_device_name FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id WHERE bmf.physical_device_name = N'$($backup.Replace("'", "''"))';"

# 官方 41—43：注入越权授权 → 判据必须报 51030 → 撤销并断言无残留
Invoke-Step -Name 'supplement-41-inject-permission-leak' -Query "USE [$DatabaseName]; GRANT UPDATE([price]) ON dbo.[goods] TO [bookstore_cashier]; SELECT N'injected: cashier can update price' AS result;"
Invoke-Step -Name 'supplement-42-role-rejects-permission-leak' -Script 'db/role.sql' -ExpectedError 51030
Invoke-Step -Name 'supplement-43-remove-injected-permission' -Query "USE [$DatabaseName]; REVOKE UPDATE([price]) ON dbo.[goods] FROM [bookstore_cashier]; IF EXISTS (SELECT 1 FROM sys.database_permissions p JOIN sys.database_principals dp ON dp.principal_id = p.grantee_principal_id WHERE dp.name = N'bookstore_cashier' AND p.class = 1 AND p.major_id = OBJECT_ID(N'dbo.[goods]') AND p.permission_name = N'UPDATE') THROW 51993, N'越权授权未撤销。', 1; SELECT N'PASS: injected permission revoked' AS result;"
Invoke-Step -Name 'supplement-44-role-after-cleanup' -Script 'db/role.sql'

$summary = Get-Content -LiteralPath (Join-Path $evidence 'summary.json') -Raw -Encoding utf8 | ConvertFrom-Json
$summary.steps = $steps.Count
$summary | Add-Member -NotePropertyName 'supplement' -NotePropertyValue '官方 37 / 39 / 41—43 已补测，另加撤销后复跑' -Force
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
$manifest = Get-ChildItem -LiteralPath $evidence -File | Where-Object { $_.Name -ne 'manifest.json' } |
    ForEach-Object { [pscustomobject]@{ file = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower() } }
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'manifest.json') -Encoding utf8
Write-Host "Supplement PASS. Total steps: $($steps.Count)"
