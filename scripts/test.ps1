param(
    [ValidateSet('China','HQ')][string]$Edition,
    [string]$ReleaseVersion,
    [string]$SdkPath,
    [string]$LicenseKeyring,
    [string]$StageRoot,
    [string]$OutputRoot,
    [switch]$SkipBuild
)
. "$PSScriptRoot\sdk.ps1"
if (!$Edition) { throw 'Choose -Edition China or -Edition HQ.' }
if (!$OutputRoot) { $OutputRoot = Join-Path (Get-FinEnergyRoot) 'out' }
if (-not $SkipBuild) {
    $buildArgs = @{Edition=$Edition;SdkPath=$SdkPath;LicenseKeyring=$LicenseKeyring;StageRoot=$StageRoot;OutputRoot=$OutputRoot}
    if ($ReleaseVersion) { $buildArgs.ReleaseVersion=$ReleaseVersion }
    & "$PSScriptRoot\build.ps1" @buildArgs
}
$editionId=$Edition.ToLowerInvariant()
$receipt=Get-Content -LiteralPath (Join-Path $OutputRoot "$editionId\build-receipt.json") -Raw | ConvertFrom-Json
if ($receipt.edition -cne $editionId -or ($ReleaseVersion -and $receipt.version -cne $ReleaseVersion)) { throw 'Wrong build receipt.' }
$finEnergyRoot=$receipt.stage
$finEnergySdk=$receipt.sdk
$compiled=Join-Path $finEnergySdk 'lib\fan\finEnergy.pod'
if ((Get-FileHash -LiteralPath $compiled).Hash.ToLowerInvariant() -cne $receipt.sha256) { throw 'Test Pod differs from the build receipt.' }
$finEnergyPreviousHome = $env:FAN_HOME
$previousEdition = $env:FINENERGY_BUILD_EDITION
try {
    $env:FAN_HOME = $finEnergySdk
    $env:FINENERGY_BUILD_EDITION = $editionId
    Push-Location $finEnergyRoot
    try {
        Invoke-FinEnergyCommand (Join-Path $finEnergySdk 'bin\fant.bat') @('finEnergy') -FailurePattern '(?m)(Tests failed|0 tests,)'
        Invoke-FinEnergyCommand 'npm.cmd' @('--prefix', 'finEnergy.pod/ts', 'test', '--', '--run')
    }
    finally { Pop-Location }
}
finally {
    $env:FAN_HOME = $finEnergyPreviousHome
    $env:FINENERGY_BUILD_EDITION = $previousEdition
}
