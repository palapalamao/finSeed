[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'Registration.ps1')
Require-Administrator
$handlerPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\PropertySystem\PropertyHandlers\.pod'
$clsidPath = "SOFTWARE\Classes\CLSID\$handlerId"
$detailsPath = 'SOFTWARE\Classes\SystemFileAssociations\.pod'
if ((Test-Path -LiteralPath $stateFile) -or (Test-Path -LiteralPath $installFolder)) { throw 'This handler already has installation files. Review and uninstall the previous installation first.' }
foreach ($hive in @($machine, $currentUser)) {
    foreach ($path in @($handlerPath, $clsidPath)) {
        $existing = $hive.OpenSubKey($path)
        if ($existing) { $existing.Dispose(); throw "Existing property handler or COM registration at $path. No registration was changed." }
    }
}
$keyBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(20)
try {
    foreach ($name in @('FinEnergy.Edition','FinEnergy.LicenseMode')) {
        if ([FinEnergyPropertyRegistration]::PSGetPropertyKeyFromName($name, $keyBuffer) -eq 0) { throw "Custom property $name is already registered. Resolve the existing schema first." }
    }
} finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($keyBuffer) }
$files = @('fin_energy_properties.dll','inspect.exe','FinEnergy.propdesc','Registration.ps1','install.ps1','uninstall.ps1','README.md','README.zh-CN.md')
foreach ($file in $files) { if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) { throw "Missing installation file $file. Run build.ps1 and install from dist." } }
$priorDetails = Registry-Snapshot $detailsPath 'FullDetails' ''
$fullDetails = if ($priorDetails.existed -and $priorDetails.before) { $priorDetails.before } else { 'prop:System.PropGroup.Description' }
if (!$fullDetails.StartsWith('prop:')) { throw 'Existing FullDetails is not a property list.' }
foreach ($name in @('System.Software.ProductName','System.Software.ProductVersion','FinEnergy.Edition','FinEnergy.LicenseMode')) {
    if ($name -notin $fullDetails.Substring(5).Split(';')) { $fullDetails += ";$name" }
}
$entries = @(
    (Registry-Snapshot $clsidPath '' 'FIN Energy Pod Properties'),
    (Registry-Snapshot "$clsidPath\InprocServer32" '' (Join-Path $installFolder 'fin_energy_properties.dll')),
    (Registry-Snapshot "$clsidPath\InprocServer32" 'ThreadingModel' 'Both'),
    (Registry-Snapshot $handlerPath '' $handlerId),
    (Registry-Snapshot $detailsPath 'FullDetails' $fullDetails)
)
if (!$PSCmdlet.ShouldProcess('.pod FIN Energy metadata', 'Install read-only property handler and custom schema')) { return }
if (Test-Path -LiteralPath $stateFolder) { throw 'Installation state directory already exists. Review it before proceeding.' }
New-Item -ItemType Directory -Path $stateFolder | Out-Null
Protect-Folder $stateFolder
New-Item -ItemType Directory -Path $installFolder | Out-Null
Protect-Folder $installFolder
$state = [ordered]@{ owner=$handlerId; schemaId=$schemaId; version=1; status='prepared'; schemaRegistered=$false; files=@(); entries=$entries }
Save-State $state
try {
    foreach ($file in $files) {
        $target = Join-Path $installFolder $file
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $target
        $state.files += [ordered]@{ name=$file; sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash }
        Save-State $state
    }
    $schema = Join-Path $installFolder 'FinEnergy.propdesc'
    # Record the attempt before registration so uninstall can reconcile an interruption.
    $state.schemaRegistered = $true
    Save-State $state
    [Runtime.InteropServices.Marshal]::ThrowExceptionForHR([FinEnergyPropertyRegistration]::PSRegisterPropertySchema($schema))
    foreach ($entry in $entries) { Write-RegistryValue $entry }
    $state.status = 'installed'
    Save-State $state
    Notify-Shell
    Write-Output 'Installed FIN Energy Pod properties. Close and reopen the Properties window. Run inspect.exe --registered against both editions before accepting this installation.'
} catch {
    $failure = $_
    $reverse = @($entries)
    [array]::Reverse($reverse)
    foreach ($entry in $reverse) { Restore-RegistryValue $entry }
    $state.status = 'installationFailed'
    Save-State $state
    Write-Warning 'Registration values were restored conditionally. Run uninstall.ps1 to remove the schema and retained installation files.'
    throw $failure
}
