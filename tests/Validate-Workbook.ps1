[CmdletBinding()]
param(
    [string] $WorkbookSchemaPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$rules = Get-Content -LiteralPath (Join-Path $root 'pricing-rules.json') -Raw | ConvertFrom-Json
$workbook = Get-Content -LiteralPath (Join-Path $root 'workbook.json') -Raw | ConvertFrom-Json
$compute = Get-Content -LiteralPath (Join-Path $root 'queries\compute.kql') -Raw
$storage = Get-Content -LiteralPath (Join-Path $root 'queries\storage.kql') -Raw
$script:checks = 0

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
    $script:checks++
}

function Assert-Contains([string] $Text, [string] $Expected, [string] $Message) {
    Assert-True ($Text.Contains($Expected)) $Message
}

function Get-LegacySeries([string] $Size) {
    $matches = @($rules.legacyVmSeries | Where-Object { $Size.ToLowerInvariant() -cmatch $_.pattern })
    Assert-True ($matches.Count -le 1) "Patterns must not overlap for $Size"
    if ($matches.Count -eq 1) {
        return $matches[0].name
    }
    return ''
}

function Get-Rate([string] $Size, [string] $Region) {
    if (Get-LegacySeries $Size) {
        return $rules.legacyApproximateIncreasePercent
    }
    if ($Size.ToLowerInvariant() -cmatch $rules.regionalExcludedVmPattern) {
        return 0
    }
    $match = @($rules.regions | Where-Object { $_.name -eq $Region })
    if ($match.Count -eq 1) {
        return $match[0].increasePercent
    }
    return 0
}

$expectedSeries = @('Bv1', 'D', 'Ds', 'F', 'Fs', 'G', 'Gs', 'Ls', 'NP', 'HC', 'Av2', 'Amv2', 'Dv2', 'Dsv2', 'Fsv2', 'Lsv2')
Assert-True (@(Compare-Object $expectedSeries @($rules.legacyVmSeries.name)).Count -eq 0) 'Exact supported legacy family list'
Assert-True ($rules.effectiveDate -eq '2027-02-01') 'Effective date'
Assert-True ($rules.legacyApproximateIncreasePercent -eq 25) 'Approximate legacy rate'

$legacyFixtures = @(
    @('Standard_B1ls', 'Bv1'), @('Standard_B1ms', 'Bv1'), @('Standard_B2s', 'Bv1'),
    @('Standard_B20ms', 'Bv1'), @('Standard_D1', 'D'), @('Basic_D2', 'D'),
    @('Standard_DS14', 'Ds'), @('Standard_F16', 'F'), @('Standard_F16s', 'Fs'),
    @('Standard_G5', 'G'), @('Standard_GS5', 'Gs'), @('Standard_GS5-8', 'Gs'),
    @('Standard_L32s', 'Ls'), @('Standard_NP10s', 'NP'), @('Standard_HC44rs', 'HC'),
    @('Standard_A8_v2', 'Av2'), @('Standard_A8m_v2', 'Amv2'),
    @('Standard_D15_v2', 'Dv2'), @('Standard_DS15_v2', 'Dsv2'),
    @('Standard_DS13-4_v2', 'Dsv2'), @('Standard_F72s_v2', 'Fsv2'),
    @('Standard_L80s_v2', 'Lsv2'), @('STANDARD_DS2_V2', 'Dsv2')
)
foreach ($fixture in $legacyFixtures) {
    Assert-True ((Get-LegacySeries $fixture[0]) -ceq $fixture[1]) "Legacy family for $($fixture[0])"
    foreach ($region in @($rules.regions.name) + @('eastus')) {
        Assert-True ((Get-Rate $fixture[0] $region) -eq 25) "Legacy rate never stacks: $($fixture[0]) / $region"
    }
}

$nonLegacy = @(
    'Standard_A1', 'Standard_D4_v3', 'Standard_D4s_v3', 'Standard_E4_v3', 'Standard_E4s_v3',
    'Standard_B2s_v2', 'Standard_B2as_v2', 'Standard_B2als_v2',
    'Standard_D4as_v7', 'Standard_D4ads_v7', 'Standard_F4als_v7',
    'Standard_NCasT4_v3', 'Standard_HB120rs_v2', 'Standard_M64ms_v2',
    'Standard_L8s_v3', 'Standard_D2ads_v5', 'Standard_DC2s_v2',
    'Standard_D2_v20', 'Standard_F2s_v20', 'Standard_DS2_v2_extra', 'unrecognized'
)
foreach ($size in $nonLegacy) {
    Assert-True ((Get-LegacySeries $size) -eq '') "Do not infer legacy from version alone: $size"
}

$excludedV7 = @(
    'Standard_D4s_v7', 'Standard_D4ds_v7', 'Standard_D4ls_v7',
    'Standard_D4lds_v7', 'Standard_E4s_v7', 'Standard_E4ds_v7',
    'Standard_E32-8s_v7', 'Standard_E32-8ds_v7'
)
foreach ($size in $excludedV7) {
    Assert-True ($size.ToLowerInvariant() -cmatch $rules.regionalExcludedVmPattern) "Explicit regional exclusion: $size"
    foreach ($region in $rules.regions.name) {
        Assert-True ((Get-Rate $size $region) -eq 0) "No regional rate for excluded $size"
    }
}

$expectedRegions = @{
    westeurope = 9; northeurope = 17; francecentral = 11; francesouth = 11
    norwayeast = 9; norwaywest = 9; southeastasia = 8
}
Assert-True ($rules.regions.Count -eq 7) 'Exactly seven regions'
foreach ($region in $rules.regions) {
    Assert-True ($expectedRegions[$region.name] -eq $region.increasePercent) "Configured rate for $($region.name)"
    foreach ($size in @('Standard_D4as_v7', 'Standard_NC4as_T4_v3', 'Standard_B2as_v2', 'Standard_D4_v3')) {
        Assert-True ((Get-Rate $size $region.name) -eq $region.increasePercent) "Regional eligible SKU: $size / $($region.name)"
    }
}
Assert-True ((Get-Rate 'Standard_D4as_v7' 'eastus') -eq 0) 'Regional change does not apply outside seven regions'

$expectedDiskSkus = @('standard_lrs', 'standardssd_lrs', 'standardssd_zrs', 'premium_lrs', 'premium_zrs', 'premiumv2_lrs', 'ultrassd_lrs')
Assert-True (@(Compare-Object $expectedDiskSkus @($rules.managedDiskSkus.name)).Count -eq 0) 'All managed-disk SKUs'
Assert-True (($rules.managedDiskSkus | Where-Object name -eq 'premiumv2_lrs').service -eq 'Premium SSD v2') 'Premium SSD v2 mapping'

$legacyCases = ($rules.legacyVmSeries | ForEach-Object { "vmSize matches regex @'$($_.pattern)', '$($_.name)'" }) -join ', '
$regionCases = ($rules.regions | ForEach-Object { "location =~ '$($_.name)', $($_.increasePercent)" }) -join ', '
$diskCases = ($rules.managedDiskSkus | ForEach-Object { "skuName == '$($_.name)', '$($_.service)'" }) -join ', '
$compute = $compute.Replace('__LEGACY_CASE__', $legacyCases).
    Replace('__REGION_CASE__', $regionCases).
    Replace('__REGIONAL_EXCLUDED_PATTERN__', $rules.regionalExcludedVmPattern).
    Replace('__LEGACY_PERCENT__', [string] $rules.legacyApproximateIncreasePercent).
    Replace('__PUBLIC_CLOUD__', 'true')
$storage = $storage.Replace('__REGION_CASE__', $regionCases).
    Replace('__DISK_CASE__', $diskCases).
    Replace('__PUBLIC_CLOUD__', 'true')

$scopeFilter = "'*' in ({ResourceGroups}) or tolower(strcat('/subscriptions/', subscriptionId, '/resourceGroups/', resourceGroup)) in ({ResourceGroups})"
foreach ($query in @($compute, $storage)) {
    Assert-Contains $query $scopeFilter 'All queries filter by full resource-group ID'
    Assert-Contains $query '| where true' 'Explicit cloud guard expansion'
    Assert-True ($query -notmatch '__[A-Z_]+__') 'All rule tokens expanded'
    Assert-Contains $query $regionCases 'All queries use same regional cases'
}

$group1 = '/subscriptions/sub-a/resourceGroups/shared'.ToLowerInvariant()
$group2 = '/subscriptions/sub-b/resourceGroups/shared'.ToLowerInvariant()
Assert-True ($group1 -cne $group2) 'Same-name groups remain distinct across subscriptions'
Assert-Contains $compute "isnotempty(legacySeries), 'Legacy VM - approximately 25%'" 'Legacy classification takes precedence'
Assert-Contains $compute 'regionalRate > 0 and not(isRegionalExcluded)' 'Regional exclusion applies in KQL'
Assert-Contains $compute "isempty(vmSize), 'Review - VM size not exposed'" 'Missing VM size is explicit review'
Assert-Contains $compute "isnotempty(legacySeries), 25, isempty(vmSize), 0, regionalRate" 'Rates do not stack and unknown size gets no asserted rate'
Assert-Contains $compute "'{ComputeState}' == 'AllDeployed' or (resourceKind == 'VM' and powerState == 'powerstate/running')" 'Running filter excludes models and unknown state'
Assert-Contains $compute "'unknown / not exposed'" 'Unknown power state is not silently treated as running'
Assert-True (-not $storage.Contains('{ComputeState}')) 'Compute-state filter does not affect storage'
Assert-Contains $storage "shareTier == 'transactionoptimized', 'Excluded'" 'Transaction-Optimized shares excluded'
Assert-Contains $storage "'microsoft.compute/snapshots', 'Review - inclusion unconfirmed'" 'Snapshots are unconfirmed'
Assert-Contains $storage "isempty(diskService), 'Review - SKU unrecognized'" 'Unknown disk SKU is review'
Assert-Contains $storage "shareTier !in ('premium', 'hot', 'cool'), 'Review - share tier not exposed'" 'Unknown share tier is review'
Assert-Contains $storage "'microsoft.storage/storageaccounts', 'Candidate - verify service/meter'" 'Storage accounts are candidates, not blanket increases'
Assert-Contains $storage "iff(classification startswith 'Review', 0, regionalRate)" 'Review-only storage has no definite assigned increase'
Assert-Contains $storage 'Cross Region Replication SKU is excluded' 'NetApp replication excluded in assessment'

$parameters = @($workbook.items | Where-Object type -eq 9)[0].content.parameters
$subscriptions = $parameters | Where-Object name -eq 'Subscriptions'
$groups = $parameters | Where-Object name -eq 'ResourceGroups'
$state = $parameters | Where-Object name -eq 'ComputeState'
Assert-True ($subscriptions.type -eq 6 -and $subscriptions.multiSelect -and $subscriptions.isRequired) 'Subscription selector'
Assert-True ($groups.type -eq 2 -and $groups.multiSelect -and $groups.isRequired) 'Resource-group selector'
Assert-True ($groups.crossComponentResources[0] -eq '{Subscriptions}') 'Resource groups depend on subscriptions'
Assert-True ($groups.typeSettings.selectAllValue -eq '*') 'Resource-group all sentinel matches query'
Assert-Contains $groups.query 'value = tolower(id)' 'Picker values are normalized group IDs'
Assert-True ($state.value -eq 'AllDeployed') 'Default includes deployed resources'

$queryItems = @($workbook.items | Where-Object type -eq 3)
Assert-True (($workbook.items.name -join ',') -eq 'overview,scope,compute-details,storage-details') 'Introduction, filters and the two requested inventory tables, in order'
Assert-Contains $workbook.items[0].content.json 'Inventory exposure, not a cost forecast' 'Introduction explains financial scope'
Assert-Contains $workbook.items[0].content.json 'do not stack' 'Introduction explains non-stacking VM changes'
Assert-Contains $workbook.items[0].content.json 'Candidate - verify service/meter' 'Introduction explains conditional storage account exposure'
Assert-Contains $workbook.items[0].content.json 'The compute-state filter does not filter storage' 'Introduction explains independent storage scope'
Assert-True ($queryItems.Count -eq 2) 'Exactly two inventory tables'
foreach ($item in $queryItems) {
    Assert-True ($item.content.crossComponentResources[0] -eq '{Subscriptions}') "$($item.name) subscription scope"
    Assert-True ($item.content.queryType -eq 1 -and $item.content.resourceType -eq 'microsoft.resourcegraph/resources') "$($item.name) ARG data source"
    $item.content.query = $item.content.query.Replace('__COMPUTE_BASE__', $compute).Replace('__STORAGE_BASE__', $storage)
    Assert-True ($item.content.query -notmatch '__[A-Z_]+__') "$($item.name) fully expanded"
    Assert-True ($item.content.gridSettings.rowLimit -eq 1000) "$($item.name) explicit result limit"
    Assert-True ($item.content.visualization -eq 'table') "$($item.name) explicit table rendering"
    Assert-True (-not [string]::IsNullOrWhiteSpace($item.content.noDataMessage)) "$($item.name) empty-state filter guidance"
    if ($item.name.EndsWith('-details')) {
        Assert-Contains $item.content.query '| project id,' "$($item.name) preserves ID for export/paging"
        Assert-Contains $item.content.query '| project id, name, ratePercent,' "$($item.name) increase immediately follows linked resource name"
        Assert-Contains $item.content.query 'id asc' "$($item.name) stable detail sort"
        $nameLink = @($item.content.gridSettings.formatters | Where-Object columnMatch -eq 'name')
        Assert-True ($nameLink.Count -eq 1 -and $nameLink[0].formatter -eq 7) "$($item.name) name uses link renderer"
        Assert-True ($nameLink[0].formatOptions.linkTarget -eq 'Resource') "$($item.name) opens resource overview"
        Assert-True ($nameLink[0].formatOptions.linkColumn -eq 'id') "$($item.name) link uses full resource ID, not ambiguous name"
        Assert-True ($nameLink[0].formatOptions.linkIsContextBlade -eq $false) "$($item.name) opens full Azure resource view"
        Assert-True (@($item.content.gridSettings.formatters | Where-Object { $_.columnMatch -eq 'id' -and $_.formatter -eq 5 }).Count -eq 1) "$($item.name) hides long ID but retains it in query"
    }
}
$storageItem = $queryItems | Where-Object name -eq 'storage-details'
Assert-Contains $storageItem.content.query '| project id, name, ratePercent,' 'Storage service increase immediately follows resource name, with ID hidden'
Assert-True (-not $storageItem.content.query.Contains('{ComputeState}')) 'Storage inventory independent of VM running-state filter'
Assert-True (@($workbook.items.name | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'Unique Workbook item names'
$rendered = $workbook | ConvertTo-Json -Depth 100
Assert-True ($rendered -notmatch '(?i)\bFAQ\b|confidential') 'Report text and expanded queries contain no source-document or confidentiality references'
if ($WorkbookSchemaPath) {
    Assert-True (Test-Json -Json $rendered -SchemaFile $WorkbookSchemaPath) 'Expanded Workbook validates against official schema'
} else {
    Write-Host 'Official schema validation skipped; pass -WorkbookSchemaPath to enable it.'
}

$compiledPath = Join-Path ([IO.Path]::GetTempPath()) "pricing-workbook-$([guid]::NewGuid()).json"
try {
    & az bicep build --file (Join-Path $root 'main.bicep') --outfile $compiledPath
    Assert-True ($LASTEXITCODE -eq 0) 'Bicep compile and lint'
    $template = Get-Content -LiteralPath $compiledPath -Raw | ConvertFrom-Json
    Assert-True ($template.resources.Count -eq 1) 'Creates exactly one resource'
    Assert-True ($template.resources[0].type -eq 'Microsoft.Insights/workbooks') 'Creates only a Workbook'
    Assert-True ($template.resources[0].kind -eq 'shared') 'Shared Workbook'
    Assert-True ($template.resources[0].properties.description -notmatch '(?i)\bFAQ\b|confidential') 'Resource description uses neutral pricing language'
    Assert-True ($template.resources[0].properties.version -eq '1.2') 'Simplified report resource version'
    Assert-True ($template.resources[0].properties.sourceId -eq 'Azure Monitor') 'Unbound Azure Monitor Workbook'
    Assert-True ($template.outputs.PSObject.Properties.Name -contains 'workbookPortalUrl') 'Portal URL output'
    $templateText = Get-Content -LiteralPath $compiledPath -Raw
    Assert-Contains $templateText "environment().name" 'Deployed queries use actual Azure cloud'
    Assert-Contains $templateText "AzureCloud" 'Public cloud comparison survives compilation'
    Assert-Contains $templateText "variables('computeQuery')" 'Compiled Workbook uses assembled compute query'
    Assert-Contains $templateText "variables('storageQuery')" 'Compiled Workbook uses assembled storage query'
    $portalTemplatePath = Join-Path $root 'azuredeploy.json'
    if (Test-Path -LiteralPath $portalTemplatePath) {
        $portalTemplate = Get-Content -LiteralPath $portalTemplatePath -Raw
        Assert-True ($portalTemplate.Trim() -ceq $templateText.Trim()) 'Portal template matches Bicep source; regenerate azuredeploy.json after source changes'
    }
} finally {
    if (Test-Path -LiteralPath $compiledPath) {
        Remove-Item -LiteralPath $compiledPath
    }
}

Write-Host "PASS: $script:checks local checks. No Azure resources were queried or deployed."
Write-Host 'KQL execution and Workbook portal rendering still require tenant smoke tests.'
