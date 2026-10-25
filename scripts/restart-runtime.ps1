param([string]$ExpectedSha256)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$enerCubixRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$enerCubixSdk = Join-Path $enerCubixRoot '.local\sdk'
$enerCubixRuntimeSdk = Join-Path $enerCubixRoot '.local\runtime-sdk'
$enerCubixVar = Join-Path $enerCubixRoot '.local\runtime-var'
$enerCubixLauncher = Join-Path $enerCubixRoot '.local\run-native.ps1'
if (-not (Test-Path -LiteralPath $enerCubixLauncher)) { throw 'Isolated runtime launcher is missing.' }
$enerCubixPodSource = Join-Path $enerCubixSdk 'lib\fan\enerCubix.pod'
$enerCubixPodTarget = Join-Path $enerCubixRuntimeSdk 'lib\fan\enerCubix.pod'
if (-not (Test-Path -LiteralPath (Join-Path $enerCubixRuntimeSdk 'bin\fan.bat'))) { throw 'Prepare the separate runtime SDK before restarting.' }
$enerCubixSourceHash = (Get-FileHash -LiteralPath $enerCubixPodSource -Algorithm SHA256).Hash
if ($ExpectedSha256 -and $enerCubixSourceHash -ne $ExpectedSha256) { throw 'Candidate Pod hash differs from the requested stable artifact.' }
$enerCubixListeners = @(Get-NetTCPConnection -State Listen -LocalPort 38085 -ErrorAction SilentlyContinue)
if ($enerCubixListeners.Count -ne 1 -or $enerCubixListeners[0].LocalAddress -ne '127.0.0.1') {
    throw 'Expected one loopback-only isolated FIN listener on port 38085.'
}
$enerCubixProcessId = $enerCubixListeners[0].OwningProcess
$enerCubixProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$enerCubixProcessId"
$enerCubixKnownHome = $enerCubixProcess -and ($enerCubixProcess.CommandLine -match ([regex]::Escape("-Dfan.home=$enerCubixSdk") + '(?=["\s])') -or $enerCubixProcess.CommandLine -match ([regex]::Escape("-Dfan.home=$enerCubixRuntimeSdk") + '(?=["\s])'))
if (-not $enerCubixKnownHome -or $enerCubixProcess.CommandLine -notmatch ([regex]::Escape("-var $enerCubixVar") + '(?=["\s]|$)') -or $enerCubixProcess.CommandLine -notmatch 'fanx\.tools\.Fan\s+finStackHost') {
    throw 'Refusing to stop a process outside the isolated FIN home and var directory.'
}
Stop-Process -Id $enerCubixProcessId -Force
for ($enerCubixAttempt = 0; $enerCubixAttempt -lt 20; $enerCubixAttempt++) {
    if (-not (Get-Process -Id $enerCubixProcessId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 250
}
if (Get-Process -Id $enerCubixProcessId -ErrorAction SilentlyContinue) { throw 'Isolated process did not stop; Pod was not replaced.' }
Copy-Item -LiteralPath $enerCubixPodSource -Destination $enerCubixPodTarget -Force
if ((Get-FileHash -LiteralPath $enerCubixPodTarget -Algorithm SHA256).Hash -ne $enerCubixSourceHash) { throw 'Candidate Pod changed during restart; leave runtime stopped and select a stable artifact.' }
$enerCubixStamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')
foreach ($enerCubixLog in @('native-out.log', 'native-err.log')) {
    $enerCubixLogPath = Join-Path $enerCubixRoot ".local\$enerCubixLog"
    if (Test-Path -LiteralPath $enerCubixLogPath) { Copy-Item -LiteralPath $enerCubixLogPath -Destination "$enerCubixLogPath.$enerCubixStamp" }
}
$enerCubixChild = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-File', $enerCubixLauncher) -WorkingDirectory $enerCubixRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $enerCubixRoot '.local\native-out.log') -RedirectStandardError (Join-Path $enerCubixRoot '.local\native-err.log') -PassThru
[IO.File]::WriteAllText((Join-Path $enerCubixRoot '.local\runtime-host.pid'), $enerCubixChild.Id.ToString())
Write-Output "Restarted isolated FIN only; stopped Java PID $enerCubixProcessId; new launcher PID $($enerCubixChild.Id); runtime Pod SHA256=$enerCubixSourceHash."
