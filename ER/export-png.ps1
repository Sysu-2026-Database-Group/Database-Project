# 把 .drawio 导出为 PNG（draw.io 桌面端 CLI）
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File export-png.ps1 er-diagram-v1.0
#
# 注意（踩过的坑）：
#  1) 不要给 draw.io 加 -WindowStyle Hidden —— Electron 会被搞挂，导出无产出；
#  2) 前台阻塞调用容易被外层超时掐断 → 用 Start-Process + 轮询文件（含写锁探测）；
#  3) 首次调用偶发"跑完不出图"（冷启动）→ 已内置重试一次。
param([string]$name = 'er-diagram-v1.0')

$ErrorActionPreference = 'Continue'
$dir = $PSScriptRoot
$png = $dir

$exe = Join-Path $env:LOCALAPPDATA 'Programs\draw.io\draw.io.exe'
if (-not (Test-Path $exe)) { $exe = 'C:\Users\38499\AppData\Local\Programs\draw.io\draw.io.exe' }
if (-not (Test-Path $exe)) { Write-Output 'draw.io.exe NOT FOUND'; exit 1 }

$src = Join-Path $dir ($name + '.drawio')
$out = Join-Path $png ($name + '.png')
if (-not (Test-Path $src)) { Write-Output ('source NOT FOUND: ' + $src); exit 1 }
if (Test-Path $out) { Remove-Item $out -Force }

$p = Start-Process -FilePath $exe -ArgumentList @('--export', '--format', 'png', '--scale', '2', '--border', '10', '--output', $out, $src) -PassThru
Write-Output ('exporting ' + $name + ' ...')

$ok = $false
for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 2
    if (Test-Path $out) {
        try { $fs = [System.IO.File]::Open($out, 'Open', 'Read', 'None'); $fs.Close(); $ok = $true; break } catch {}
    }
}
if (-not $p.HasExited) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {} }

# draw.io 首次调用是冷启动，偶发"跑完不出图"（2026-10-11 实测一次）→ 自动重试一次
if (-not $ok) {
    Write-Output 'first attempt produced nothing (cold start?), retrying once ...'
    Start-Sleep -Seconds 2
    if (Test-Path $out) { Remove-Item $out -Force }
    $p = Start-Process -FilePath $exe -ArgumentList @('--export', '--format', 'png', '--scale', '2', '--border', '10', '--output', $out, $src) -PassThru
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 2
        if (Test-Path $out) {
            try { $fs = [System.IO.File]::Open($out, 'Open', 'Read', 'None'); $fs.Close(); $ok = $true; break } catch {}
        }
    }
    if (-not $p.HasExited) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {} }
}

if ($ok) {
    $b = [System.IO.File]::ReadAllBytes($out)
    $isPng = 'NO'; if ($b[0] -eq 0x89 -and $b[1] -eq 0x50) { $isPng = 'YES' }
    Write-Output ('OK  ' + $out + '  PNG=' + $isPng + '  bytes=' + $b.Length)
} else {
    Write-Output 'FAILED: no PNG produced'
}
