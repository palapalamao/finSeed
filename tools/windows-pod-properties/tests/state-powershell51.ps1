$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Registration.ps1')
$testDirectory=Join-Path $root ('.local\state-tests\'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testDirectory | Out-Null
$stateFolder=$testDirectory
$stateFile=Join-Path $testDirectory 'registration.json'
try {
    $state=[ordered]@{status='prepared';files=@()}
    Save-State $state
    $state.status='copied'
    $state.files+=@{name='fixture.dll';sha256=('A'*64)}
    Save-State $state
    $saved=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json
    if($saved.status -ne 'copied' -or @($saved.files).Count -ne 1){throw 'Atomic state update failed.'}
    $state.status='installed'
    Save-State $state
    if((Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json).status -ne 'installed'){throw 'Second replacement failed.'}
    if(@(Get-ChildItem -LiteralPath $testDirectory -Filter '*.tmp').Count){throw 'Temporary state files remain.'}
    [pscustomobject]@{status='passed';powershell=$PSVersionTable.PSVersion.ToString();atomicReplacements=2}|ConvertTo-Json -Compress
} finally {
    Get-ChildItem -LiteralPath $testDirectory -File | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
    Remove-Item -LiteralPath $testDirectory
    $machine.Dispose();$currentUser.Dispose()
}
