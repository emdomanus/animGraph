#Requires -Version 7.0
[CmdletBinding()]
param([string]$Sourcemap = 'dev-sourcemap.json', [string]$Project = 'dev.project.json')
# Keep the documented entrypoint while sharing the pinned, captured analyzer path.
& (Join-Path $PSScriptRoot 'verify/analyze.ps1') -Sourcemap $Sourcemap -Project $Project
exit $LASTEXITCODE
