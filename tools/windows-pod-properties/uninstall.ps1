[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'Registration.ps1')
Require-Administrator
if (!(Test-Path -LiteralPath $stateFile)) { throw 'No FIN Energy property handler installation record was found.' }
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
if ($state.owner -ne $handlerId -or $state.schemaId -ne $schemaId -or $state.version -ne 1) { throw 'Unexpected installation record.' }
if (!$PSCmdlet.ShouldProcess('.pod FIN Energy metadata', 'Restore original values and unregister the owned schema')) { return }
$entries = @($state.entries)
[array]::Reverse($entries)
foreach ($entry in $entries) { Restore-RegistryValue $entry }
foreach ($entry in $entries) { Remove-EmptyCreatedKey $entry }
if ($state.schemaRegistered) {
    $schemaPath = Join-Path $installFolder 'FinEnergy.propdesc'
    $schemaRecord = $state.files | Where-Object name -EQ 'FinEnergy.propdesc'
    if (!$schemaRecord -or !(Test-Path -LiteralPath $schemaPath) -or (Get-FileHash -LiteralPath $schemaPath).Hash -cne $schemaRecord.sha256) { throw 'Registered schema file changed. Keep it for manual review.' }
    $schemaPresent = $false
    $keyBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(20)
    try {
        foreach ($name in @('FinEnergy.Edition','FinEnergy.LicenseMode')) {
            if ([FinEnergyPropertyRegistration]::PSGetPropertyKeyFromName($name, $keyBuffer) -eq 0) {
                $format = [Runtime.InteropServices.Marshal]::PtrToStructure($keyBuffer, [type][Guid])
                if ($format -ne [Guid]$schemaId) { throw 'A later property schema was preserved. Review registration manually.' }
                $schemaPresent = $true
            }
        }
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($keyBuffer) }
    if ($schemaPresent) { [Runtime.InteropServices.Marshal]::ThrowExceptionForHR([FinEnergyPropertyRegistration]::PSUnregisterPropertySchema($schemaPath)) }
    $state.schemaRegistered = $false
    Save-State $state
}
Notify-Shell
foreach ($file in $state.files) {
    if ($file.name -notin @('fin_energy_properties.dll','inspect.exe','FinEnergy.propdesc','Registration.ps1','install.ps1','uninstall.ps1','README.md','README.zh-CN.md')) { throw 'Unexpected recorded file.' }
    $path = Join-Path $installFolder $file.name
    if (!(Test-Path -LiteralPath $path)) { continue }
    if ((Get-FileHash -LiteralPath $path).Hash -cne $file.sha256) { throw "File $($file.name) changed. Keep it for manual review." }
    try { Remove-Item -LiteralPath $path }
    catch { throw "Registration has been removed. Close Explorer or sign out, then rerun this script to remove the locked file $($file.name)." }
}
if (@(Get-ChildItem -LiteralPath $installFolder -Force).Count) { throw 'Unrelated installation files were preserved. Review the directory.' }
Remove-Item -LiteralPath $installFolder
Remove-Item -LiteralPath $stateFile
Remove-Item -LiteralPath $stateFolder
Write-Output 'FIN Energy property handler removed. Previous FullDetails values were restored wherever the installed values were still owned by this handler.'
