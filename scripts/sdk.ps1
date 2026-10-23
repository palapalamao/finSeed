Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SeedRoot {
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-SeedSdk {
    param([string]$SdkPath, [string]$DestinationPath)
    $seedRoot = Get-SeedRoot
    $seedLocal = Join-Path $seedRoot '.local\sdk'
    if (-not $SdkPath) { $SdkPath = $env:FINSEED_SDK }
    if (-not $SdkPath) { $SdkPath = 'C:\Program Files (x86)\FIN\FIN 5.3.0.2761' }
    $seedSource = (Resolve-Path -LiteralPath $SdkPath).Path
    if (-not $DestinationPath) { $DestinationPath = $seedLocal }
    $seedDestination = [IO.Path]::GetFullPath($DestinationPath)
    $seedAllowedDestinations = @([IO.Path]::GetFullPath($seedLocal), [IO.Path]::GetFullPath((Join-Path $seedRoot '.local\runtime-sdk')))
    if ($seedDestination.TrimEnd('\') -notin $seedAllowedDestinations) { throw 'SDK copy destination must be this repository .local\sdk or .local\runtime-sdk.' }
    if ($seedSource.TrimEnd('\') -ne $seedDestination.TrimEnd('\')) {
        if (-not (Test-Path -LiteralPath (Join-Path $seedSource 'lib\fan\finBuild.pod'))) {
            throw 'SDK must contain lib\fan\finBuild.pod.'
        }
        # Explicit static allowlist: never copy var, projects, user databases or licenses.
        New-Item -ItemType Directory -Force -Path $seedDestination | Out-Null
        foreach ($seedDir in @('bin', 'lib\fan', 'lib\java', 'lib\java\ext', 'etc\sys', 'etc\build')) {
            New-Item -ItemType Directory -Force -Path (Join-Path $seedDestination $seedDir) | Out-Null
        }
        foreach ($seedLauncher in @('fan.bat', 'fanlaunch.bat', 'fant.bat', 'fin.bat')) {
            Copy-Item -LiteralPath (Join-Path $seedSource "bin\$seedLauncher") -Destination (Join-Path $seedDestination "bin\$seedLauncher") -Force
        }
        # SDK Pod and JVM archives are static code only; compiled finSeed is local.
        Get-ChildItem -LiteralPath (Join-Path $seedSource 'lib\fan') -Filter '*.pod' -File |
            Where-Object { $_.Name -notin @('finSeed.pod', 'enerCubix.pod') } | ForEach-Object {
                $seedTarget = Join-Path $seedDestination "lib\fan\$($_.Name)"
                if (-not (Test-Path -LiteralPath $seedTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $seedTarget }
            }
        Get-ChildItem -LiteralPath (Join-Path $seedSource 'lib\java') -File | ForEach-Object {
            $seedTarget = Join-Path $seedDestination "lib\java\$($_.Name)"
            if (-not (Test-Path -LiteralPath $seedTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $seedTarget }
        }
        Get-ChildItem -LiteralPath (Join-Path $seedSource 'lib\java\ext') -Filter '*.jar' -File | ForEach-Object {
            $seedTarget = Join-Path $seedDestination "lib\java\ext\$($_.Name)"
            if (-not (Test-Path -LiteralPath $seedTarget)) { Copy-Item -LiteralPath $_.FullName -Destination $seedTarget }
        }
        foreach ($seedNative in @('host32.dll', 'host64.dll')) {
            $seedTarget = Join-Path $seedDestination "lib\java\ext\$seedNative"
            if (-not (Test-Path -LiteralPath $seedTarget)) { Copy-Item -LiteralPath (Join-Path $seedSource "lib\java\ext\$seedNative") -Destination $seedTarget }
        }
        foreach ($seedConfig in @('ext2mime.props', 'timezone-aliases.props', 'timezones.ftz', 'units.txt')) {
            Copy-Item -LiteralPath (Join-Path $seedSource "etc\sys\$seedConfig") -Destination (Join-Path $seedDestination "etc\sys\$seedConfig") -Force
        }
        # Generated isolated configuration avoids copying host-specific options or secrets.
        [IO.File]::WriteAllText((Join-Path $seedDestination 'etc\sys\config.props'), "runtime=java`njava.options=-Dfile.encoding=UTF8`n", [Text.UTF8Encoding]::new($false))
        Copy-Item -LiteralPath (Join-Path $seedSource 'etc\build\config.props') -Destination (Join-Path $seedDestination 'etc\build\config.props') -Force
        [IO.File]::WriteAllText((Join-Path $seedDestination 'fan.props'), '', [Text.UTF8Encoding]::new($false))
    }
    if (-not (Test-Path -LiteralPath (Join-Path $seedDestination 'bin\fan.bat'))) { throw 'Local SDK is incomplete.' }
    return $seedDestination
}

function Invoke-SeedCommand {
    param([string]$Command, [string[]]$Arguments, [string]$FailurePattern)
    $seedOutput = & $Command @Arguments 2>&1
    $seedExit = $LASTEXITCODE
    $seedOutput | ForEach-Object { Write-Host $_ }
    if ($seedExit -ne 0) { throw "$Command failed with exit code $seedExit." }
    if ($FailurePattern -and ($seedOutput -join "`n") -match $FailurePattern) {
        throw "$Command reported a failed build/test despite exit code 0."
    }
}
