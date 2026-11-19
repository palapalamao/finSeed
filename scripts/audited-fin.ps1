param(
    [Parameter(Mandatory = $true)][string]$RequestFile,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$finEnergyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$finEnergyOutput = [IO.Path]::GetFullPath($OutputFile)
if (-not ($finEnergyOutput.StartsWith((Join-Path $finEnergyRoot '.local\'), [StringComparison]::OrdinalIgnoreCase) -or $finEnergyOutput.StartsWith((Join-Path $finEnergyRoot 'out\'), [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Acceptance output must be inside this repository .local or out directory.'
}
$finEnergyPython = Join-Path $ExpertWorkspace '.venv\Scripts\python.exe'
$finEnergyPreviousPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = Join-Path $ExpertWorkspace 'src'
    & $finEnergyPython (Join-Path $PSScriptRoot 'audited-fin.py') --workspace $ExpertWorkspace --request $RequestFile --output $finEnergyOutput
    if ($LASTEXITCODE -ne 0) { throw 'Audited acceptance operation did not succeed; inspect report without retrying unknown mutations.' }
}
finally { $env:PYTHONPATH = $finEnergyPreviousPythonPath }
