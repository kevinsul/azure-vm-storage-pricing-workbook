targetScope = 'resourceGroup'

@description('Azure region in which to store the Workbook. Does not limit the regions queried.')
param location string = resourceGroup().location

@description('Display name in Azure Monitor Workbooks.')
@minLength(1)
@maxLength(256)
param workbookDisplayName string = 'Azure VM and Storage pricing exposure - February 2027'

@description('Stable Workbook resource GUID. Default is deterministic for this resource group and display name.')
param workbookId string = guid(resourceGroup().id, workbookDisplayName)

@description('Tags applied only to the Workbook resource.')
param tags object = {}

var rules = loadJsonContent('pricing-rules.json')
var definition = loadJsonContent('workbook.json')
var legacyCases = join(map(rules.legacyVmSeries, series => 'vmSize matches regex @\'${series.pattern}\', \'${series.name}\''), ', ')
var regionCases = join(map(rules.regions, region => 'location =~ \'${region.name}\', ${region.increasePercent}'), ', ')
var diskCases = join(map(rules.managedDiskSkus, disk => 'skuName == \'${disk.name}\', \'${disk.service}\''), ', ')
var computeQuery = replace(
  replace(
    replace(
      replace(
        replace(loadTextContent('queries/compute.kql'), '__LEGACY_CASE__', legacyCases),
        '__REGION_CASE__', regionCases),
      '__REGIONAL_EXCLUDED_PATTERN__', rules.regionalExcludedVmPattern),
    '__LEGACY_PERCENT__', string(rules.legacyApproximateIncreasePercent)),
  '__PUBLIC_CLOUD__', string(environment().name == 'AzureCloud'))
var storageQuery = replace(
  replace(
    replace(loadTextContent('queries/storage.kql'), '__REGION_CASE__', regionCases),
    '__DISK_CASE__', diskCases),
  '__PUBLIC_CLOUD__', string(environment().name == 'AzureCloud'))
var workbookContent = union(definition, {
  items: map(definition.items, item => item.type == 3 ? union(item, {
    content: union(item.content, {
      query: replace(replace(item.content.query, '__COMPUTE_BASE__', computeQuery), '__STORAGE_BASE__', storageQuery)
    })
  }) : item)
})

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: workbookId
  location: location
  kind: 'shared'
  tags: tags
  properties: {
    displayName: workbookDisplayName
    description: 'Inventory exposure for VM and Storage pricing changes beginning February 1, 2027. Not a cost forecast.'
    category: 'workbook'
    sourceId: 'Azure Monitor'
    version: '1.2'
    serializedData: string(workbookContent)
  }
}

output workbookResourceId string = workbook.id
output workbookPortalUrl string = '${environment().portal}#resource${workbook.id}/workbook'
