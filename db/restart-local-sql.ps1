#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$statusPath = Join-Path $PSScriptRoot '..\app\sql-restart.local.json'
try {
    if ($env:COMPUTERNAME -ne 'LZQ') {
        throw 'This restart helper is restricted to the verified local machine LZQ.'
    }
    $sqlService = Get-Service -Name MSSQLSERVER
    $activeDependents = @($sqlService.DependentServices | Where-Object { $_.Status -ne 'Stopped' })
    if ($activeDependents.Count -gt 0) {
        throw 'A dependent service is active; refusing to force-stop it.'
    }
    Restart-Service -Name MSSQLSERVER -ErrorAction Stop
    (Get-Service -Name MSSQLSERVER).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    @{ success = $true; service = 'MSSQLSERVER'; status = 'Running' } |
        ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    exit 0
} catch {
    @{ success = $false; message = $_.Exception.Message } |
        ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    exit 1
}
