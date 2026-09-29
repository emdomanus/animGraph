#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutDir,
    [int]$Iterations = 20000,
    [int]$Rounds = 7
)
. (Join-Path $PSScriptRoot '../verify/tools.ps1')
$repoRoot = Get-PackageRoot
$evidence = [IO.Path]::GetFullPath($OutDir, $repoRoot)
if (Test-Path -LiteralPath $evidence) { throw 'Use a fresh benchmark output directory.' }
if ($Iterations -lt 1 -or $Rounds -lt 1) { throw 'Iterations and rounds must be positive.' }
$null = New-Item -ItemType Directory -Path $evidence
$lune = Resolve-PackageTool 'lune'
$sourceHashes = @{}
Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Recurse -Filter '*.luau' | ForEach-Object {
    $sourceHashes[[IO.Path]::GetRelativePath($repoRoot, $_.FullName)] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
}
@{
    head = (git -C $repoRoot rev-parse HEAD)
    lune = $lune
    benchmarkSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'tests/bench/evaluation.luau') -Algorithm SHA256).Hash
    sourceHashes = $sourceHashes
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'metadata.json')
$previousOutput = $env:ANIMGRAPH_BENCH_OUTPUT
$previousIterations = $env:ANIMGRAPH_BENCH_ITERATIONS
$previousRounds = $env:ANIMGRAPH_BENCH_ROUNDS
try {
    $env:ANIMGRAPH_BENCH_OUTPUT = Join-Path $evidence 'results.json'
    $env:ANIMGRAPH_BENCH_ITERATIONS = $Iterations.ToString()
    $env:ANIMGRAPH_BENCH_ROUNDS = $Rounds.ToString()
    $result = Invoke-PackageTool (Get-Process -Id $PID).Path @('-NoProfile', '-File', (Join-Path $PSScriptRoot '../verify/tests.ps1'), '-Spec', 'tests/bench/evaluation.luau')
    [IO.File]::WriteAllText((Join-Path $evidence 'output.txt'), $result.Output)
    Write-Output $result.Output
    if ($result.ExitCode -ne 0) { throw "Benchmark failed with exit $($result.ExitCode)." }
    if (-not (Test-Path -LiteralPath $env:ANIMGRAPH_BENCH_OUTPUT)) { throw 'Benchmark did not produce results.' }
} finally {
    $env:ANIMGRAPH_BENCH_OUTPUT = $previousOutput
    $env:ANIMGRAPH_BENCH_ITERATIONS = $previousIterations
    $env:ANIMGRAPH_BENCH_ROUNDS = $previousRounds
}
