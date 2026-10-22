#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$evidence = $PSScriptRoot
$repo = [IO.DirectoryInfo]::new($evidence)
while ($repo -and -not (Test-Path -LiteralPath (Join-Path $repo.FullName 'db/accept-week-6.ps1'))) { $repo = $repo.Parent }
if (-not $repo) { throw 'Cannot locate repository root.' }
$repo = $repo.FullName
$steps = @(Get-Content (Join-Path $evidence 'steps.json') -Raw | ConvertFrom-Json)
if ($steps.Count -ne 45) { throw 'Expected 45 executed steps.' }
$checks = [Collections.Generic.List[object]]::new()
foreach ($step in $steps) {
    $raw = Get-Content (Join-Path $evidence $step.output) -Raw -Encoding utf8
    $valid = if ($step.expected_error -eq 0) { $step.exit_code -eq 0 } else {
        $step.exit_code -ne 0 -and $raw -match ('消息 '+$step.expected_error+'，')
    }
    if (-not $valid) { throw "Independent exit/error check failed: $($step.step)" }
}
$checks.Add([pscustomobject]@{check='45 recorded exit/error checks independently reread';passed=$true})
foreach ($pair in @(@('01-source-before','04-restored-snapshot'),@('04-restored-snapshot','10-migrated-snapshot'),@('01-source-before','38-source-after'),@('01-source-before','44-source-final'),@('15-expanded-before-tests','30-expanded-after-tests'),@('32-failure-snapshot-before','36-failure-snapshot-after'))) {
    $before = @(Get-Content (Join-Path $evidence ($pair[0]+'.txt')) | Where-Object { $_ -match '^[a-z_]+\|\d+\|[A-F0-9]{64}$' })
    $after = @(Get-Content (Join-Path $evidence ($pair[1]+'.txt')) | Where-Object { $_ -match '^[a-z_]+\|\d+\|[A-F0-9]{64}$' })
    if ($before.Count -ne 19 -or $after.Count -ne 19 -or (Compare-Object $before $after)) { throw "Snapshot difference: $pair" }
    $checks.Add([pscustomobject]@{check=($pair -join ' / ');tables=19;passed=$true})
}
if ((Get-Content (Join-Path $evidence '06-query-before.txt') -Raw) -cne (Get-Content (Join-Path $evidence '11-query-after.txt') -Raw)) { throw 'Query text differs.' }
$checks.Add([pscustomobject]@{check='Full migration before/after query output identical';passed=$true})
$negative = @(Get-Content (Join-Path $evidence '16-regression-negative.txt') | Where-Object { $_ -match '^\d+\|.*\|PASS\|' })
if ($negative.Count -ne 22) { throw 'Expected 22 actual negative result rows.' }
$role = @(Get-Content (Join-Path $evidence '17-role.txt') | Where-Object { $_ -match '^PASS\|229\|' })
if ($role.Count -ne 3) { throw 'Expected three actual permission-denied rows.' }
$checks.Add([pscustomobject]@{check='Actual rejected rows';negative_cases=$negative.Count;permission_229=$role.Count;passed=$true})
# 保留审核发生时的 source-manifest 与环境记录，不把整理后的文件冒充当时执行的版本。
$layoutManifest = Join-Path $evidence 'source-layout-manifest.json'
$currentManifest = Join-Path $evidence 'source-current-manifest.json'
$manifest = if (Test-Path -LiteralPath $currentManifest) { $currentManifest } elseif (Test-Path -LiteralPath $layoutManifest) { $layoutManifest } else { Join-Path $evidence 'source-manifest.json' }
foreach ($item in (Get-Content -LiteralPath $manifest -Raw -Encoding utf8 | ConvertFrom-Json)) {
    $source = Join-Path $repo $item.file
    $expected = if ($item.PSObject.Properties.Name -contains 'current_sha256') { $item.current_sha256 } else { $item.sha256 }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $expected) { throw "Source differs from recorded layout: $($item.file)" }
}
& python (Join-Path $repo 'db/checks/audit-week-6-artifacts.py')
if ($LASTEXITCODE -ne 0) { throw 'Current artifact audit failed.' }
$erRecord = Get-Content (Join-Path $evidence 'er-consistency.json') -Raw -Encoding utf8 | ConvertFrom-Json
Write-Host "Historical raw evidence and current AI self-check PASS; recorded ER human acceptance: $($erRecord.human_visual_signoff)."
