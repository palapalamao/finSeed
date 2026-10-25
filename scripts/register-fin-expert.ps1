param(
    [string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile',
    [string]$CredentialFile = (Join-Path $PSScriptRoot '..\.local\runtime-credentials.json'),
    [string]$Project = 'enerCubix_acceptance',
    [string]$ConnectionId = 'enerCubix-acceptance-local'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$enerCubixPython = Join-Path $ExpertWorkspace '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $enerCubixPython)) { throw 'FIN Expert Python runtime is unavailable.' }
$enerCubixPreviousPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = Join-Path $ExpertWorkspace 'src'
    & $enerCubixPython (Join-Path $PSScriptRoot 'register-fin-expert.py') --workspace $ExpertWorkspace --credentials $CredentialFile --connection-id $ConnectionId --project $Project
    if ($LASTEXITCODE -ne 0) { throw 'Official FIN Expert CLI registration failed.' }
}
finally { $env:PYTHONPATH = $enerCubixPreviousPythonPath }
