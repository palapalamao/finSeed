param(
    [Parameter(Mandatory = $true)][string]$RequestFile,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$seedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$seedOutput = [IO.Path]::GetFullPath($OutputFile)
if (-not ($seedOutput.StartsWith((Join-Path $seedRoot '.local\'), [StringComparison]::OrdinalIgnoreCase) -or $seedOutput.StartsWith((Join-Path $seedRoot 'out\'), [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Acceptance output must be inside this repository .local or out directory.'
}
$seedPython = Join-Path $ExpertWorkspace '.venv\Scripts\python.exe'
$seedPreviousPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = Join-Path $ExpertWorkspace 'src'
    & $seedPython (Join-Path $PSScriptRoot 'audited-fin.py') --workspace $ExpertWorkspace --request $RequestFile --output $seedOutput
    if ($LASTEXITCODE -ne 0) { throw 'Audited acceptance operation did not succeed; inspect report without retrying unknown mutations.' }
}
finally { $env:PYTHONPATH = $seedPreviousPythonPath }
