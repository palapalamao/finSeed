Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FinEnergyRoot {
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-FinEnergySdk {
    param([string]$SdkPath, [string]$DestinationPath)
    $finEnergyRoot = Get-FinEnergyRoot
    $finEnergyLocal = Join-Path $finEnergyRoot '.local\sdk'
    if (-not $SdkPath) { $SdkPath = $env:FINENERGY_SDK }
    if (-not $SdkPath) { $SdkPath = 'C:\Program Files (x86)\FIN\FIN 5.3.0.2761' }
    $finEnergySource = (Resolve-Path -LiteralPath $SdkPath).Path
    if (-not $DestinationPath) { $DestinationPath = $finEnergyLocal }
    $finEnergyDestination = [IO.Path]::GetFullPath($DestinationPath)
    $finEnergyAllowedDestinations = @([IO.Path]::GetFullPath($finEnergyLocal), [IO.Path]::GetFullPath((Join-Path $finEnergyRoot '.local\runtime-sdk')))
    if ($finEnergyDestination.TrimEnd('\') -notin $finEnergyAllowedDestinations) { throw 'SDK copy destination must be this repository .local\sdk or .local\runtime-sdk.' }
    if ($finEnergySource.TrimEnd('\') -ne $finEnergyDestination.TrimEnd('\')) {
        if (-not (Test-Path -LiteralPath (Join-Path $finEnergySource 'lib\fan\finBuild.pod'))) {
            throw 'SDK must contain lib\fan\finBuild.pod.'
        }
        # Explicit static allowlist: never copy var, projects, user databases or licenses.
        New-Item -ItemType Directory -Force -Path $finEnergyDestination | Out-Null
        foreach ($finEnergyDir in @('bin', 'lib\fan', 'lib\java', 'lib\java\ext', 'etc\sys', 'etc\build')) {
            New-Item -ItemType Directory -Force -Path (Join-Path $finEnergyDestination $finEnergyDir) | Out-Null
        }
        foreach ($finEnergyLauncher in @('fan.bat', 'fanlaunch.bat', 'fant.bat', 'fin.bat')) {
            Copy-Item -LiteralPath (Join-Path $finEnergySource "bin\$finEnergyLauncher") -Destination (Join-Path $finEnergyDestination "bin\$finEnergyLauncher") -Force
        }
        # SDK Pod and JVM archives are static code only; compiled finEnergy is local.
        Get-ChildItem -LiteralPath (Join-Path $finEnergySource 'lib\fan') -Filter '*.pod' -File |
            Where-Object { $_.Name -notin @('finEnergy.pod') } | ForEach-Object {
                $finEnergyTarget = Join-Path $finEnergyDestination "lib\fan\$($_.Name)"
                if (-not (Test-Path -LiteralPath $finEnergyTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $finEnergyTarget }
            }
        Get-ChildItem -LiteralPath (Join-Path $finEnergySource 'lib\java') -File | ForEach-Object {
            $finEnergyTarget = Join-Path $finEnergyDestination "lib\java\$($_.Name)"
            if (-not (Test-Path -LiteralPath $finEnergyTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $finEnergyTarget }
        }
        Get-ChildItem -LiteralPath (Join-Path $finEnergySource 'lib\java\ext') -Filter '*.jar' -File | ForEach-Object {
            $finEnergyTarget = Join-Path $finEnergyDestination "lib\java\ext\$($_.Name)"
            if (-not (Test-Path -LiteralPath $finEnergyTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $finEnergyTarget }
        }
        foreach ($finEnergyNative in @('host32.dll', 'host64.dll')) {
            $finEnergyTarget = Join-Path $finEnergyDestination "lib\java\ext\$finEnergyNative"
            if (-not (Test-Path -LiteralPath $finEnergyTarget)) { Copy-Item -LiteralPath (Join-Path $finEnergySource "lib\java\ext\$finEnergyNative") -Destination $finEnergyTarget }
        }
        foreach ($finEnergyConfig in @('ext2mime.props', 'timezone-aliases.props', 'timezones.ftz', 'units.txt')) {
            Copy-Item -LiteralPath (Join-Path $finEnergySource "etc\sys\$finEnergyConfig") -Destination (Join-Path $finEnergyDestination "etc\sys\$finEnergyConfig") -Force
        }
        # Generated isolated configuration avoids copying host-specific options or secrets.
        [IO.File]::WriteAllText((Join-Path $finEnergyDestination 'etc\sys\config.props'), "runtime=java`njava.options=-Dfile.encoding=UTF8`n", [Text.UTF8Encoding]::new($false))
        Copy-Item -LiteralPath (Join-Path $finEnergySource 'etc\build\config.props') -Destination (Join-Path $finEnergyDestination 'etc\build\config.props') -Force
        [IO.File]::WriteAllText((Join-Path $finEnergyDestination 'fan.props'), '', [Text.UTF8Encoding]::new($false))
    }
    if (-not (Test-Path -LiteralPath (Join-Path $finEnergyDestination 'bin\fan.bat'))) { throw 'Local SDK is incomplete.' }
    return $finEnergyDestination
}

function Invoke-FinEnergyCommand {
    param([string]$Command, [string[]]$Arguments, [string]$FailurePattern)
    $finEnergyOutput = & $Command @Arguments 2>&1
    $finEnergyExit = $LASTEXITCODE
    $finEnergyOutput | ForEach-Object { Write-Host $_ }
    if ($finEnergyExit -ne 0) { throw "$Command failed with exit code $finEnergyExit." }
    if ($FailurePattern -and ($finEnergyOutput -join "`n") -match $FailurePattern) {
        throw "$Command reported a failed build/test despite exit code 0."
    }
}
