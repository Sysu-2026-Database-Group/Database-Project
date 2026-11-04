#requires -Version 5.1
param(
    [string]$Python = 'python',
    [string]$Server = 'localhost',
    [switch]$SkipInstall
)
$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$repairRoot = Split-Path -Parent $PSScriptRoot
$repairPython = Join-Path $repairRoot '.venv\Scripts\python.exe'
$repairExit = 0
Push-Location -LiteralPath $repairRoot
try {
    if (-not $SkipInstall) {
        if (-not (Test-Path -LiteralPath $repairPython)) {
            & $Python -m venv (Join-Path $repairRoot '.venv')
            if ($LASTEXITCODE -ne 0) { throw 'Could not create project virtual environment.' }
        }
        & $repairPython -m pip install --disable-pip-version-check --retries 1 --timeout 20 -r (Join-Path $repairRoot 'requirements.txt')
        if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed. See docs/design/local-environment-repair.md.' }
    }
    if (-not (Test-Path -LiteralPath $repairPython)) { throw 'Missing .venv; rerun without -SkipInstall.' }
    Write-Host 'Checking Python dependencies and installed ODBC drivers...'
    & $repairPython -c "import flask,pyodbc; from importlib.metadata import version; print('Flask:',version('Flask')); print('pyodbc:',version('pyodbc')); print('ODBC:',pyodbc.drivers())"
    if ($LASTEXITCODE -ne 0) { throw 'Python dependencies are still unavailable.' }
    Write-Host 'Running application unit checks...'
    & $repairPython (Join-Path $PSScriptRoot 'project_runner.py') test --unit
    if ($LASTEXITCODE -ne 0) { $repairExit = 1; Write-Warning 'Unit checks failed; inspect the newest .runner/test-* report.' }
    if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
        Write-Warning 'sqlcmd is missing. Install SQL Server command-line utilities.'
        $repairExit = 1
    } else {
        Write-Host 'Checking SQL Server with a read-only query...'
        & sqlcmd -S $Server -E -C -l 5 -t 15 -b -Q "SET NOCOUNT ON; SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) AS server_name,CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')) AS version,CONVERT(int,SERVERPROPERTY('IsIntegratedSecurityOnly')) AS windows_only;"
        if ($LASTEXITCODE -ne 0) { $repairExit = 1; Write-Warning 'SQL connection failed. Follow local-environment-repair.md; no server settings were changed.' }
    }
    if ($repairExit -eq 0) { Write-Host 'Dependency, unit and read-only SQL checks passed. Full isolated acceptance remains required.' }
} catch {
    Write-Error $_ -ErrorAction Continue
    $repairExit = 1
} finally {
    Pop-Location
}
exit $repairExit
