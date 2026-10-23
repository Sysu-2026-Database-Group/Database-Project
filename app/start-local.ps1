$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '..\run.ps1') start
if ($LASTEXITCODE -ne 0) { throw "Application exited with code $LASTEXITCODE. See .runner logs." }
