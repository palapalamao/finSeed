param([string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$finEnergyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$finEnergyRequests = Join-Path $finEnergyRoot '.local\acceptance-requests'
$finEnergyReports = Join-Path $finEnergyRoot 'out\native'
New-Item -ItemType Directory -Force -Path $finEnergyRequests, $finEnergyReports | Out-Null
$finEnergyChecks = [ordered]@{}

function Invoke-FinEnergyAcceptanceStep([string]$Name, [string]$Connection, [string]$Expression) {
    $finEnergyRequest = [ordered]@{ operation = 'axon'; connection_id = $Connection; expression = "try $Expression catch (err) {caught:err.toStr}"; max_rows = 10; max_bytes = 25000; timeout_seconds = 60 }
    $finEnergyRequestPath = Join-Path $finEnergyRequests "$Name.json"
    $finEnergyReportPath = Join-Path $finEnergyReports "$Name.json"
    [IO.File]::WriteAllText($finEnergyRequestPath, ($finEnergyRequest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & "$PSScriptRoot\audited-fin.ps1" -RequestFile $finEnergyRequestPath -OutputFile $finEnergyReportPath -ExpertWorkspace $ExpertWorkspace
    $finEnergyResponse = Get-Content -Raw -LiteralPath $finEnergyReportPath | ConvertFrom-Json
    $finEnergyRow = $finEnergyResponse.data.data.data.rows[0]
    if ('caught' -in $finEnergyRow.PSObject.Properties.Name) { throw "$Name failed: $($finEnergyRow.caught)" }
    if ('result' -notin $finEnergyRow.PSObject.Properties.Name) { throw "$Name returned no acceptance result." }
    $finEnergyResult = $finEnergyRow.result | ConvertFrom-Json
    if ($finEnergyResult.status -ne 'passed') { throw "$Name did not pass." }
    $finEnergyChecks[$Name] = [ordered]@{ auditId = $finEnergyResponse.data.audit_id; result = $finEnergyResult }
}

# Each invocation authenticates through the official FIN Expert registry and audit facade.
# The functions themselves refuse any project/host outside this independent fixture.
Invoke-FinEnergyAcceptanceStep 'calculation-persistence-history' 'finEnergy-acceptance-local' 'finEnergyAcceptance()'
Invoke-FinEnergyAcceptanceStep 'three-tree-persistence-migration-rollback' 'finEnergy-acceptance-local' 'finEnergyThreeTreeAcceptance()'
Invoke-FinEnergyAcceptanceStep 'native-space-refresh-and-isolation' 'finEnergy-acceptance-local' 'finEnergyNativeSpaceAcceptance()'
Invoke-FinEnergyAcceptanceStep 'engineering-atomic-operations' 'finEnergy-acceptance-local' 'finEnergyEngineeringAcceptance()'
Invoke-FinEnergyAcceptanceStep 'real-http-business-routes' 'finEnergy-acceptance-local' 'finEnergyTransportAcceptance()'
Invoke-FinEnergyAcceptanceStep 'native-readonly-permissions' 'finEnergy-acceptance-reader' 'finEnergyPermissionAcceptance()'
$finEnergyRuntimePod = Join-Path $finEnergyRoot '.local\runtime-sdk\lib\fan\finEnergy.pod'
$finEnergySummary = [ordered]@{ checkedAt = [DateTime]::UtcNow.ToString('o'); targetFin = '5.3.0.2761'; project = 'finEnergy_acceptance'; podSha256 = (Get-FileHash -LiteralPath $finEnergyRuntimePod -Algorithm SHA256).Hash.ToLowerInvariant(); status = 'passed'; checks = $finEnergyChecks; browserScope = 'Native HTTP and audited FIN identity are checked here. Separate browser suites distinguish controlled API fixtures from real FIN business responses through the audited loopback bridge; they do not certify native browser-cookie login.' }
[IO.File]::WriteAllText((Join-Path $finEnergyRoot 'out\runtime-acceptance.json'), ($finEnergySummary | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
Write-Output 'Native FIN calculation, persistence, real HTTP routes and readonly permissions passed. See out/runtime-acceptance.json.'
