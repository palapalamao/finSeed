param(
    [Parameter(Mandatory = $true)][string]$RequestFile,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$enerCubixRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$enerCubixOutput = [IO.Path]::GetFullPath($OutputFile)
if (-not ($enerCubixOutput.StartsWith((Join-Path $enerCubixRoot '.local\'), [StringComparison]::OrdinalIgnoreCase) -or $enerCubixOutput.StartsWith((Join-Path $enerCubixRoot 'out\'), [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Acceptance output must be inside this repository .local or out directory.'
}
$enerCubixPython = Join-Path $ExpertWorkspace '.venv\Scripts\python.exe'
$enerCubixPreviousPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = Join-Path $ExpertWorkspace 'src'
    & $enerCubixPython (Join-Path $PSScriptRoot 'audited-fin.py') --workspace $ExpertWorkspace --request $RequestFile --output $enerCubixOutput
    if ($LASTEXITCODE -ne 0) { throw 'Audited acceptance operation did not succeed; inspect report without retrying unknown mutations.' }
}
finally { $env:PYTHONPATH = $enerCubixPreviousPythonPath }
