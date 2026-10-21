param([string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$seedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$seedPython = Join-Path $ExpertWorkspace '.venv\Scripts\python.exe'
$seedCredentials = Join-Path $seedRoot '.local\runtime-reader-credentials.json'
$seedEvidence = Join-Path $seedRoot '.local\runtime-reader-evidence.json'
$seedPreviousPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = Join-Path $ExpertWorkspace 'src'
    & $seedPython (Join-Path $PSScriptRoot 'create-test-reader.py') --workspace $ExpertWorkspace --credentials $seedCredentials --evidence $seedEvidence
    if ($LASTEXITCODE -ne 0) { throw 'Native reader setup did not succeed; inspect evidence without retrying.' }
    & (Join-Path $PSScriptRoot 'register-fin-expert.ps1') -ExpertWorkspace $ExpertWorkspace -CredentialFile $seedCredentials -Project finseed_acceptance -ConnectionId finseed-acceptance-reader
}
finally { $env:PYTHONPATH = $seedPreviousPythonPath }
