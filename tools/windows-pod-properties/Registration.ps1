Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$handlerId = '{177765E4-6E21-4C9B-9EC0-DD3B108543B8}'
$schemaId = '{36CE443D-5BF0-4C59-A51F-8337390063A1}'
$installFolder = Join-Path $env:ProgramFiles 'FIN Energy Pod Properties'
$stateFolder = Join-Path $env:ProgramData 'FIN Energy Pod Properties'
$stateFile = Join-Path $stateFolder 'registration.json'
$machine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
$currentUser = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
if (!('FinEnergyPropertyRegistration' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FinEnergyPropertyRegistration {
  [DllImport("propsys.dll", CharSet=CharSet.Unicode)] public static extern int PSRegisterPropertySchema(string path);
  [DllImport("propsys.dll", CharSet=CharSet.Unicode)] public static extern int PSUnregisterPropertySchema(string path);
  [DllImport("propsys.dll", CharSet=CharSet.Unicode)] public static extern int PSGetPropertyKeyFromName(string name, IntPtr key);
  [DllImport("shell32.dll")] public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
}
'@
}
function Require-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (![Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this reviewed script from an administrator PowerShell window.'
    }
    if (![Environment]::Is64BitProcess -or [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') {
        throw 'This build requires x64 Windows and a 64-bit PowerShell process.'
    }
}
function Protect-Folder([string]$path) {
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A managed folder cannot be a reparse point.' }
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($entry in @(@('S-1-5-18','FullControl'), @('S-1-5-32-544','FullControl'), @('S-1-5-32-545','ReadAndExecute'))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($entry[0]), [Security.AccessControl.FileSystemRights]$entry[1], $inherit, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    Set-Acl -LiteralPath $path -AclObject $acl
}
function Registry-Snapshot([string]$path, [string]$name, [string]$installed) {
    $key = $machine.OpenSubKey($path)
    try {
        $present = $null -ne $key -and $name -in $key.GetValueNames()
        if ($present -and $key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String) { throw "Unsupported registry value type at $path" }
        return [ordered]@{ path=$path; name=$name; keyExisted=($null -ne $key); existed=$present; before=$(if ($present) {$key.GetValue($name)} else {$null}); installed=$installed }
    } finally { if ($key) { $key.Dispose() } }
}
function Write-RegistryValue($entry) {
    $key = $machine.CreateSubKey($entry.path)
    try {
        $present = $entry.name -in $key.GetValueNames()
        if ($present -ne $entry.existed -or ($present -and ($key.GetValueKind($entry.name) -ne [Microsoft.Win32.RegistryValueKind]::String -or $key.GetValue($entry.name) -cne $entry.before))) {
            throw "Registration changed during installation at $($entry.path)."
        }
        $key.SetValue($entry.name, $entry.installed, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally { $key.Dispose() }
}
function Restore-RegistryValue($entry) {
    $key = $machine.OpenSubKey($entry.path, $true)
    if (!$key) { return }
    try {
        if ($entry.name -notin $key.GetValueNames()) { return }
        if ($key.GetValueKind($entry.name) -ne [Microsoft.Win32.RegistryValueKind]::String -or $key.GetValue($entry.name) -cne $entry.installed) {
            Write-Warning "A later change was preserved at $($entry.path)."
            return
        }
        if ($entry.existed) { $key.SetValue($entry.name, $entry.before, [Microsoft.Win32.RegistryValueKind]::String) }
        else { $key.DeleteValue($entry.name, $false) }
    } finally { $key.Dispose() }
}
function Remove-EmptyCreatedKey($entry) {
    if ($entry.keyExisted) { return }
    $key = $machine.OpenSubKey($entry.path)
    $empty = $key -and $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
    if ($key) { $key.Dispose() }
    if ($empty) { $machine.DeleteSubKey($entry.path, $false) }
}
function Save-State($state) {
    $text = $state | ConvertTo-Json -Depth 8
    $temporary = Join-Path $stateFolder ('registration-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $stateFile) { [IO.File]::Replace($temporary, $stateFile, $null) }
        else { [IO.File]::Move($temporary, $stateFile) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
function Notify-Shell { [FinEnergyPropertyRegistration]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero) }
