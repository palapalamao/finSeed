param([string]$ExpectedSha256)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$seedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$seedSdk = Join-Path $seedRoot '.local\sdk'
$seedRuntimeSdk = Join-Path $seedRoot '.local\runtime-sdk'
$seedVar = Join-Path $seedRoot '.local\runtime-var'
$seedLauncher = Join-Path $seedRoot '.local\run-native.ps1'
if (-not (Test-Path -LiteralPath $seedLauncher)) { throw 'Isolated runtime launcher is missing.' }
$seedPodSource = Join-Path $seedSdk 'lib\fan\enerCubix.pod'
$seedPodTarget = Join-Path $seedRuntimeSdk 'lib\fan\enerCubix.pod'
if (-not (Test-Path -LiteralPath (Join-Path $seedRuntimeSdk 'bin\fan.bat'))) { throw 'Prepare the separate runtime SDK before restarting.' }
if (Test-Path -LiteralPath (Join-Path $seedRuntimeSdk 'lib\fan\finSeed.pod')) { throw 'Legacy finSeed Pod remains in the isolated runtime; migrate the extension and archive the old Pod before restarting.' }
$seedSourceHash = (Get-FileHash -LiteralPath $seedPodSource -Algorithm SHA256).Hash
if ($ExpectedSha256 -and $seedSourceHash -ne $ExpectedSha256) { throw 'Candidate Pod hash differs from the requested stable artifact.' }
$seedListeners = @(Get-NetTCPConnection -State Listen -LocalPort 38085 -ErrorAction SilentlyContinue)
if ($seedListeners.Count -ne 1 -or $seedListeners[0].LocalAddress -ne '127.0.0.1') {
    throw 'Expected one loopback-only isolated FIN listener on port 38085.'
}
$seedProcessId = $seedListeners[0].OwningProcess
$seedProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$seedProcessId"
$seedKnownHome = $seedProcess -and ($seedProcess.CommandLine -match ([regex]::Escape("-Dfan.home=$seedSdk") + '(?=["\s])') -or $seedProcess.CommandLine -match ([regex]::Escape("-Dfan.home=$seedRuntimeSdk") + '(?=["\s])'))
if (-not $seedKnownHome -or $seedProcess.CommandLine -notmatch ([regex]::Escape("-var $seedVar") + '(?=["\s]|$)') -or $seedProcess.CommandLine -notmatch 'fanx\.tools\.Fan\s+finStackHost') {
    throw 'Refusing to stop a process outside the isolated FIN home and var directory.'
}
Stop-Process -Id $seedProcessId -Force
for ($seedAttempt = 0; $seedAttempt -lt 20; $seedAttempt++) {
    if (-not (Get-Process -Id $seedProcessId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 250
}
if (Get-Process -Id $seedProcessId -ErrorAction SilentlyContinue) { throw 'Isolated process did not stop; Pod was not replaced.' }
Copy-Item -LiteralPath $seedPodSource -Destination $seedPodTarget -Force
if ((Get-FileHash -LiteralPath $seedPodTarget -Algorithm SHA256).Hash -ne $seedSourceHash) { throw 'Candidate Pod changed during restart; leave runtime stopped and select a stable artifact.' }
$seedStamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')
foreach ($seedLog in @('native-out.log', 'native-err.log')) {
    $seedLogPath = Join-Path $seedRoot ".local\$seedLog"
    if (Test-Path -LiteralPath $seedLogPath) { Copy-Item -LiteralPath $seedLogPath -Destination "$seedLogPath.$seedStamp" }
}
$seedChild = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-File', $seedLauncher) -WorkingDirectory $seedRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $seedRoot '.local\native-out.log') -RedirectStandardError (Join-Path $seedRoot '.local\native-err.log') -PassThru
[IO.File]::WriteAllText((Join-Path $seedRoot '.local\runtime-host.pid'), $seedChild.Id.ToString())
Write-Output "Restarted isolated FIN only; stopped Java PID $seedProcessId; new launcher PID $($seedChild.Id); runtime Pod SHA256=$seedSourceHash."
