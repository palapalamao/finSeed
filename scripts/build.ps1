param(
    [ValidateSet('China','HQ')][string]$Edition,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$ReleaseVersion,
    [string]$SdkPath,
    [string]$LicenseKeyring,
    [string]$StageRoot,
    [string]$OutputRoot
)
. "$PSScriptRoot\sdk.ps1"
if (!$Edition) { throw 'Choose -Edition China or -Edition HQ.' }
if ($Edition -eq 'China' -and !$LicenseKeyring) { throw 'China requires -LicenseKeyring with approved public verification keys.' }
if ($Edition -eq 'HQ' -and $LicenseKeyring) { throw 'HQ builds do not accept independent license keys.' }
$root = Get-FinEnergyRoot
$editionId = $Edition.ToLowerInvariant()
if (!$ReleaseVersion) { $ReleaseVersion = (Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw | ConvertFrom-Json).version }
if (!$StageRoot) { $StageRoot = Join-Path $root '.local\edition-builds' }
if (!$OutputRoot) { $OutputRoot = Join-Path $root 'out' }
$stage = Join-Path ([IO.Path]::GetFullPath($StageRoot)) "$editionId-$ReleaseVersion-$([guid]::NewGuid().ToString('N'))"
$editionOutput = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $editionId
$stageArgs = @((Join-Path $PSScriptRoot 'stage-edition.mjs'), $root, $stage, $editionId, $ReleaseVersion)
if ($LicenseKeyring) { $stageArgs += (Resolve-Path -LiteralPath $LicenseKeyring).Path }
Invoke-FinEnergyCommand 'node' @((Join-Path $PSScriptRoot 'check-versions.mjs'), $root)
Push-Location $root
try { Invoke-FinEnergyCommand 'node' @('scripts/check-primary-energy-source.mjs') }
finally { Pop-Location }
Invoke-FinEnergyCommand 'node' $stageArgs
Invoke-FinEnergyCommand 'node' @((Join-Path $PSScriptRoot 'check-versions.mjs'), $stage)

# These settings only affect this build process tree.
$previous = @{}
foreach ($name in @('FAN_HOME','FINENERGY_UI_BUILT','FINENERGY_BUILD_EDITION','FINENERGY_BUILD_COMMIT')) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    . (Join-Path $stage 'scripts\sdk.ps1')
    $sdk = Get-FinEnergySdk -SdkPath $SdkPath
    $env:FAN_HOME = $sdk
    $env:FINENERGY_BUILD_EDITION = $editionId
    $env:FINENERGY_BUILD_COMMIT = $null
    if (Test-Path -LiteralPath (Join-Path $root '.git')) {
        $commit = & git -C $root rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$') { throw 'Cannot determine source commit.' }
        $env:FINENERGY_BUILD_COMMIT = $commit
    }
    $podRoot = Join-Path $stage 'finEnergy.pod'
    Invoke-FinEnergyCommand 'npm.cmd' @('--prefix', (Join-Path $podRoot 'ts'), 'run', 'build')
    $env:FINENERGY_UI_BUILT = 'true'
    Push-Location $podRoot
    try { Invoke-FinEnergyCommand (Join-Path $sdk 'bin\fan.bat') @('build.fan') -FailurePattern '(?m)^BUILD FAILED' }
    finally { Pop-Location }
    $built = Join-Path $sdk 'lib\fan\finEnergy.pod'
    Invoke-FinEnergyCommand (Join-Path $sdk 'bin\fan.bat') @((Join-Path $PSScriptRoot 'verify-edition.fan'), $editionId)
    & (Join-Path $stage 'scripts\acceptance.ps1') -PodPath $built -Edition $Edition
    New-Item -ItemType Directory -Force -Path $editionOutput | Out-Null
    $podPath = Join-Path $editionOutput 'finEnergy.pod'
    Copy-Item -LiteralPath $built -Destination $podPath -Force
    if ((Get-FileHash -LiteralPath $built).Hash -cne (Get-FileHash -LiteralPath $podPath).Hash) { throw 'Copied Pod hash mismatch.' }
    & (Join-Path $stage 'scripts\acceptance.ps1') -PodPath $podPath -Edition $Edition
    [ordered]@{
        edition=$editionId; version=$ReleaseVersion; sourceCommit=$env:FINENERGY_BUILD_COMMIT;
        stage=$stage; sdk=$sdk; pod=$podPath; sha256=(Get-FileHash -LiteralPath $podPath).Hash.ToLowerInvariant()
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $editionOutput 'build-receipt.json') -Encoding UTF8
    Write-Host "Built $Edition $ReleaseVersion at $podPath"
}
finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
