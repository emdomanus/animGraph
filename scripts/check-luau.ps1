param(
	[string]$Sourcemap = "dev-sourcemap.json",
	[string]$Project = "dev.project.json"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

rojo sourcemap $Project --output $Sourcemap | Out-Host

$luauLspCandidates = @()
$toolStorage = Join-Path $env:USERPROFILE ".rokit\tool-storage\johnnymorganz\luau-lsp"
if (Test-Path -LiteralPath $toolStorage) {
	$luauLspCandidates += Get-ChildItem -Path $toolStorage -Filter luau-lsp.exe -Recurse |
		Sort-Object FullName -Descending |
		ForEach-Object { $_.FullName }
}

$command = Get-Command luau-lsp -ErrorAction SilentlyContinue
if ($command -ne $null) {
	$luauLspCandidates += $command.Source
}

if ($luauLspCandidates.Count -eq 0) {
	throw "luau-lsp was not found. Install it with Rokit or put it on PATH."
}

$luauLsp = $luauLspCandidates[0]
$defsDir = Join-Path $env:TEMP "luau-lsp-defs"
$defsPath = Join-Path $defsDir "globalTypes.None.d.luau"
New-Item -ItemType Directory -Force -Path $defsDir | Out-Null

if (-not (Test-Path -LiteralPath $defsPath)) {
	Invoke-WebRequest `
		-Uri "https://luau-lsp.pages.dev/type-definitions/globalTypes.None.d.luau" `
		-OutFile $defsPath
}

$files = rg --files src dev | Where-Object { $_ -match "\.luau$" }

& $luauLsp analyze `
	--sourcemap $Sourcemap `
	--platform roblox `
	"--definitions:@roblox=$defsPath" `
	$files

& $luauLsp require-graph `
	--sourcemap $Sourcemap `
	--platform roblox `
	--output-format json `
	$files |
	Out-Null
