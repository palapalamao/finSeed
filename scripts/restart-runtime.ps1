param([string]$ExpectedSha256)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$finEnergyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$finEnergySdk = Join-Path $finEnergyRoot '.local\sdk'
$finEnergyRuntimeSdk = Join-Path $finEnergyRoot '.local\runtime-sdk'
$finEnergyVar = Join-Path $finEnergyRoot '.local\runtime-var'
$finEnergyLauncher = Join-Path $finEnergyRoot '.local\run-native.ps1'
if (-not (Test-Path -LiteralPath $finEnergyLauncher)) { throw 'Isolated runtime launcher is missing.' }
$finEnergyPodSource = Join-Path $finEnergySdk 'lib\fan\finEnergy.pod'
$finEnergyPodTarget = Join-Path $finEnergyRuntimeSdk 'lib\fan\finEnergy.pod'
if (-not (Test-Path -LiteralPath (Join-Path $finEnergyRuntimeSdk 'bin\fan.bat'))) { throw 'Prepare the separate runtime SDK before restarting.' }
$finEnergySourceHash = (Get-FileHash -LiteralPath $finEnergyPodSource -Algorithm SHA256).Hash
if ($ExpectedSha256 -and $finEnergySourceHash -ne $ExpectedSha256) { throw 'Candidate Pod hash differs from the requested stable artifact.' }
$finEnergyListeners = @(Get-NetTCPConnection -State Listen -LocalPort 38085 -ErrorAction SilentlyContinue)
if ($finEnergyListeners.Count -ne 1 -or $finEnergyListeners[0].LocalAddress -ne '127.0.0.1') {
    throw 'Expected one loopback-only isolated FIN listener on port 38085.'
}
$finEnergyProcessId = $finEnergyListeners[0].OwningProcess
$finEnergyProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$finEnergyProcessId"
$finEnergyKnownHome = $finEnergyProcess -and ($finEnergyProcess.CommandLine -match ([regex]::Escape("-Dfan.home=$finEnergySdk") + '(?=["\s])') -or $finEnergyProcess.CommandLine -match ([regex]::Escape("-Dfan.home=$finEnergyRuntimeSdk") + '(?=["\s])'))
if (-not $finEnergyKnownHome -or $finEnergyProcess.CommandLine -notmatch ([regex]::Escape("-var $finEnergyVar") + '(?=["\s]|$)') -or $finEnergyProcess.CommandLine -notmatch 'fanx\.tools\.Fan\s+finStackHost') {
    throw 'Refusing to stop a process outside the isolated FIN home and var directory.'
}
Stop-Process -Id $finEnergyProcessId -Force
for ($finEnergyAttempt = 0; $finEnergyAttempt -lt 20; $finEnergyAttempt++) {
    if (-not (Get-Process -Id $finEnergyProcessId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 250
}
if (Get-Process -Id $finEnergyProcessId -ErrorAction SilentlyContinue) { throw 'Isolated process did not stop; Pod was not replaced.' }
Copy-Item -LiteralPath $finEnergyPodSource -Destination $finEnergyPodTarget -Force
if ((Get-FileHash -LiteralPath $finEnergyPodTarget -Algorithm SHA256).Hash -ne $finEnergySourceHash) { throw 'Candidate Pod changed during restart; leave runtime stopped and select a stable artifact.' }
$finEnergyStamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')
foreach ($finEnergyLog in @('native-out.log', 'native-err.log')) {
    $finEnergyLogPath = Join-Path $finEnergyRoot ".local\$finEnergyLog"
    if (Test-Path -LiteralPath $finEnergyLogPath) { Copy-Item -LiteralPath $finEnergyLogPath -Destination "$finEnergyLogPath.$finEnergyStamp" }
}
$finEnergyChild = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-File', $finEnergyLauncher) -WorkingDirectory $finEnergyRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $finEnergyRoot '.local\native-out.log') -RedirectStandardError (Join-Path $finEnergyRoot '.local\native-err.log') -PassThru
[IO.File]::WriteAllText((Join-Path $finEnergyRoot '.local\runtime-host.pid'), $finEnergyChild.Id.ToString())
Write-Output "Restarted isolated FIN only; stopped Java PID $finEnergyProcessId; new launcher PID $($finEnergyChild.Id); runtime Pod SHA256=$finEnergySourceHash."
