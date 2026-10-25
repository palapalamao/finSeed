Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EnerCubixRoot {
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-EnerCubixSdk {
    param([string]$SdkPath, [string]$DestinationPath)
    $enerCubixRoot = Get-EnerCubixRoot
    $enerCubixLocal = Join-Path $enerCubixRoot '.local\sdk'
    if (-not $SdkPath) { $SdkPath = $env:ENERCUBIX_SDK }
    if (-not $SdkPath) { $SdkPath = 'C:\Program Files (x86)\FIN\FIN 5.3.0.2761' }
    $enerCubixSource = (Resolve-Path -LiteralPath $SdkPath).Path
    if (-not $DestinationPath) { $DestinationPath = $enerCubixLocal }
    $enerCubixDestination = [IO.Path]::GetFullPath($DestinationPath)
    $enerCubixAllowedDestinations = @([IO.Path]::GetFullPath($enerCubixLocal), [IO.Path]::GetFullPath((Join-Path $enerCubixRoot '.local\runtime-sdk')))
    if ($enerCubixDestination.TrimEnd('\') -notin $enerCubixAllowedDestinations) { throw 'SDK copy destination must be this repository .local\sdk or .local\runtime-sdk.' }
    if ($enerCubixSource.TrimEnd('\') -ne $enerCubixDestination.TrimEnd('\')) {
        if (-not (Test-Path -LiteralPath (Join-Path $enerCubixSource 'lib\fan\finBuild.pod'))) {
            throw 'SDK must contain lib\fan\finBuild.pod.'
        }
        # Explicit static allowlist: never copy var, projects, user databases or licenses.
        New-Item -ItemType Directory -Force -Path $enerCubixDestination | Out-Null
        foreach ($enerCubixDir in @('bin', 'lib\fan', 'lib\java', 'lib\java\ext', 'etc\sys', 'etc\build')) {
            New-Item -ItemType Directory -Force -Path (Join-Path $enerCubixDestination $enerCubixDir) | Out-Null
        }
        foreach ($enerCubixLauncher in @('fan.bat', 'fanlaunch.bat', 'fant.bat', 'fin.bat')) {
            Copy-Item -LiteralPath (Join-Path $enerCubixSource "bin\$enerCubixLauncher") -Destination (Join-Path $enerCubixDestination "bin\$enerCubixLauncher") -Force
        }
        # SDK Pod and JVM archives are static code only; compiled enerCubix is local.
        Get-ChildItem -LiteralPath (Join-Path $enerCubixSource 'lib\fan') -Filter '*.pod' -File |
            Where-Object { $_.Name -notin @('enerCubix.pod') } | ForEach-Object {
                $enerCubixTarget = Join-Path $enerCubixDestination "lib\fan\$($_.Name)"
                if (-not (Test-Path -LiteralPath $enerCubixTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $enerCubixTarget }
            }
        Get-ChildItem -LiteralPath (Join-Path $enerCubixSource 'lib\java') -File | ForEach-Object {
            $enerCubixTarget = Join-Path $enerCubixDestination "lib\java\$($_.Name)"
            if (-not (Test-Path -LiteralPath $enerCubixTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $enerCubixTarget }
        }
        Get-ChildItem -LiteralPath (Join-Path $enerCubixSource 'lib\java\ext') -Filter '*.jar' -File | ForEach-Object {
            $enerCubixTarget = Join-Path $enerCubixDestination "lib\java\ext\$($_.Name)"
            if (-not (Test-Path -LiteralPath $enerCubixTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $enerCubixTarget }
        }
        foreach ($enerCubixNative in @('host32.dll', 'host64.dll')) {
            $enerCubixTarget = Join-Path $enerCubixDestination "lib\java\ext\$enerCubixNative"
            if (-not (Test-Path -LiteralPath $enerCubixTarget)) { Copy-Item -LiteralPath (Join-Path $enerCubixSource "lib\java\ext\$enerCubixNative") -Destination $enerCubixTarget }
        }
        foreach ($enerCubixConfig in @('ext2mime.props', 'timezone-aliases.props', 'timezones.ftz', 'units.txt')) {
            Copy-Item -LiteralPath (Join-Path $enerCubixSource "etc\sys\$enerCubixConfig") -Destination (Join-Path $enerCubixDestination "etc\sys\$enerCubixConfig") -Force
        }
        # Generated isolated configuration avoids copying host-specific options or secrets.
        [IO.File]::WriteAllText((Join-Path $enerCubixDestination 'etc\sys\config.props'), "runtime=java`njava.options=-Dfile.encoding=UTF8`n", [Text.UTF8Encoding]::new($false))
        Copy-Item -LiteralPath (Join-Path $enerCubixSource 'etc\build\config.props') -Destination (Join-Path $enerCubixDestination 'etc\build\config.props') -Force
        [IO.File]::WriteAllText((Join-Path $enerCubixDestination 'fan.props'), '', [Text.UTF8Encoding]::new($false))
    }
    if (-not (Test-Path -LiteralPath (Join-Path $enerCubixDestination 'bin\fan.bat'))) { throw 'Local SDK is incomplete.' }
    return $enerCubixDestination
}

function Invoke-EnerCubixCommand {
    param([string]$Command, [string[]]$Arguments, [string]$FailurePattern)
    $enerCubixOutput = & $Command @Arguments 2>&1
    $enerCubixExit = $LASTEXITCODE
    $enerCubixOutput | ForEach-Object { Write-Host $_ }
    if ($enerCubixExit -ne 0) { throw "$Command failed with exit code $enerCubixExit." }
    if ($FailurePattern -and ($enerCubixOutput -join "`n") -match $FailurePattern) {
        throw "$Command reported a failed build/test despite exit code 0."
    }
}
