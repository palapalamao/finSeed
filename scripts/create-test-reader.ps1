param([string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$enerCubixRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$enerCubixPython = Join-Path $ExpertWorkspace '.venv\Scripts\python.exe'
$enerCubixCredentials = Join-Path $enerCubixRoot '.local\runtime-reader-credentials.json'
$enerCubixEvidence = Join-Path $enerCubixRoot '.local\runtime-reader-evidence.json'
$enerCubixPreviousPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = Join-Path $ExpertWorkspace 'src'
    & $enerCubixPython (Join-Path $PSScriptRoot 'create-test-reader.py') --workspace $ExpertWorkspace --credentials $enerCubixCredentials --evidence $enerCubixEvidence
    if ($LASTEXITCODE -ne 0) { throw 'Native reader setup did not succeed; inspect evidence without retrying.' }
    & (Join-Path $PSScriptRoot 'register-fin-expert.ps1') -ExpertWorkspace $ExpertWorkspace -CredentialFile $enerCubixCredentials -Project enerCubix_acceptance -ConnectionId enerCubix-acceptance-reader
}
finally { $env:PYTHONPATH = $enerCubixPreviousPythonPath }
