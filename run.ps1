#requires -Version 5.1
param(
    [ValidateSet('help', 'doctor', 'setup', 'start', 'test', 'verify')]
    [string]$Command = 'help',
    [string]$Server,
    [string]$Driver,
    [string]$DatabaseName,
    [string]$LoginPrefix,
    [ValidateRange(1, 65535)][int]$Port = 5000,
    [string]$ConfigFile = 'run.local.json',
    [string]$Python = 'python',
    [switch]$Unit,
    [switch]$Http
)
$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$runnerPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$runnerConfig = if ([IO.Path]::IsPathRooted($ConfigFile)) { $ConfigFile } else { Join-Path $PSScriptRoot $ConfigFile }
try {
    $runnerRootPrefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    $runnerConfig = [IO.Path]::GetFullPath($runnerConfig)
    if (-not $runnerConfig.StartsWith($runnerRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ConfigFile must stay inside the project directory.'
    }
    if ($Command -eq 'setup') {
        if (-not (Test-Path -LiteralPath $runnerPython)) {
            & $Python -m venv (Join-Path $PSScriptRoot '.venv')
            if ($LASTEXITCODE -ne 0) { throw 'Could not create .venv. Install Python 3.10+ and check -Python.' }
        }
        & $runnerPython -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
        if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed. Check pip/network configuration and retry setup.' }
    }
    if (-not (Test-Path -LiteralPath $runnerPython)) {
        if ($Command -notin @('help', 'doctor')) { throw 'Missing .venv. Run .\run.ps1 setup first.' }
        $runnerPython = $Python
    }
    if ($Command -in @('doctor', 'start', 'verify')) {
        $runnerSettingsDirectory = 'app'
        if (Test-Path -LiteralPath $runnerConfig) {
            $runnerOptions = Get-Content -LiteralPath $runnerConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($runnerOptions.settings_directory) { $runnerSettingsDirectory = $runnerOptions.settings_directory }
        }
        $runnerSettings = Join-Path (Join-Path $PSScriptRoot $runnerSettingsDirectory) 'settings.local.ps1'
        $runnerSettings = [IO.Path]::GetFullPath($runnerSettings)
        if (-not $runnerSettings.StartsWith($runnerRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'settings_directory must stay inside the project directory.'
        }
        if (Test-Path -LiteralPath $runnerSettings) { . $runnerSettings }
    }
    $runnerArguments = @((Join-Path $PSScriptRoot 'scripts\project_runner.py'), $Command, '--config', $runnerConfig)
    foreach ($runnerOption in @(@('Server', '--server'), @('Driver', '--driver'), @('DatabaseName', '--database'), @('LoginPrefix', '--login-prefix'), @('Port', '--port'))) {
        if ($PSBoundParameters.ContainsKey($runnerOption[0])) {
            $runnerArguments += @($runnerOption[1], [string]$PSBoundParameters[$runnerOption[0]])
        }
    }
    if ($Unit) { $runnerArguments += '--unit' }
    if ($Http) { $runnerArguments += '--http' }
    & $runnerPython @runnerArguments
    $runnerExitCode = $LASTEXITCODE
} catch {
    Write-Error $_ -ErrorAction Continue
    $runnerExitCode = 1
}
exit $runnerExitCode
