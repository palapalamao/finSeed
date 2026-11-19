param([string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$finEnergyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$finEnergyPython = Join-Path $ExpertWorkspace '.venv\Scripts\python.exe'
$finEnergyCredentials = Join-Path $finEnergyRoot '.local\runtime-reader-credentials.json'
$finEnergyEvidence = Join-Path $finEnergyRoot '.local\runtime-reader-evidence.json'
$finEnergyPreviousPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = Join-Path $ExpertWorkspace 'src'
    & $finEnergyPython (Join-Path $PSScriptRoot 'create-test-reader.py') --workspace $ExpertWorkspace --credentials $finEnergyCredentials --evidence $finEnergyEvidence
    if ($LASTEXITCODE -ne 0) { throw 'Native reader setup did not succeed; inspect evidence without retrying.' }
    & (Join-Path $PSScriptRoot 'register-fin-expert.ps1') -ExpertWorkspace $ExpertWorkspace -CredentialFile $finEnergyCredentials -Project finEnergy_acceptance -ConnectionId finEnergy-acceptance-reader
}
finally { $env:PYTHONPATH = $finEnergyPreviousPythonPath }
