# Azure VM and Storage pricing exposure Workbook

Deploy an Azure Monitor Workbook to identify deployed resources potentially exposed to the Azure VM and Storage pricing changes beginning **February 1, 2027**.

**Inventory exposure, not a cost forecast. Azure public cloud only.** This is a community-maintained tool, not an official price quote. Verify current prices, affected meters, and agreement terms before making financial decisions.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkevinsul%2Fazure-vm-storage-pricing-workbook%2Fmain%2Fazuredeploy.json)

## What you get

- Subscription and resource-group filters, including multiple selections.
- An introductory explanation and exactly two inventory tables:
  - **VM and scale-set model inventory - legacy ~25% and regional changes**
  - **Regional Storage inventory - included products, candidates and unconfirmed resources**
- Clickable resource names that open the corresponding resource in the Azure portal.
- The increase percentage immediately after the linked resource name.
- Search and export, with deployed or reported-running compute views.

Deployment creates **one shared Azure Monitor Workbook**. It does not create VMs, storage accounts, Log Analytics workspaces, agents, diagnostic settings, role assignments, or test infrastructure. Queries run through Azure Resource Graph using the viewer's Azure permissions; there is no external inventory service.

## Pricing rules represented

### Legacy VM families

Approximately **25%** across Azure public-cloud regions for:

`Bv1`, `D`, `Ds`, `F`, `Fs`, `G`, `Gs`, `Ls`, `NP`, `HC`, `Av2`, `Amv2`, `Dv2`, `Dsv2`, `Fsv2`, and `Lsv2`.

Matching uses explicit SKU-family patterns, not a blanket match for all v1/v2 names. Legacy and regional VM increases **do not stack**.

### Regional VM and select Storage services

| Region | Increase |
|---|---:|
| West Europe | 9% |
| North Europe | 17% |
| France Central | 11% |
| France South | 11% |
| Norway East | 9% |
| Norway West | 9% |
| Southeast Asia | 8% |

Regional VM exclusions include the legacy families above and `Dsv7`, `Ddsv7`, `Dlsv7`, `Dldsv7`, `Esv7`, and `Edsv7`. Other v7 families are not automatically excluded. A VM excluded from a regional compute increase can still have separately billed storage affected by a regional increase.

Storage inventory covers mapped Standard HDD/SSD, Premium SSD v1/v2 and Ultra managed disks, Elastic SAN, NetApp Files volumes, File Sync, eligible file shares when exposed by Resource Graph, and storage-account candidates.

- **Included service/SKU:** the product is in scope, but this does not assert that every related meter or reservation increases.
- **Candidate - verify service/meter:** a storage account can host affected and excluded services. Kind/SKU alone cannot establish affected billed usage. The displayed percentage is conditional.
- **Review:** unknown metadata or unconfirmed inclusion, including snapshots. **0 = review**, not a confirmed zero increase.
- Excluded storage services include General Block Blob (not v2), Standard Page Blob (not v2), Transaction-Optimized Files, Queues/Queues v2, Tables, Blob Features, Change Feed, Storage Bandwidth, Storage Actions, and Storage Discovery. NetApp Files Cross Region Replication is excluded.

Existing VM reservations retain purchase pricing through their contracted term. Actual impact depends on usage, covered meters, discounts, commitments, and agreement terms. No dollar forecast or reservation-utilization analysis is performed.

## Deploy in your Azure tenant

### Option 1: Azure portal

1. Select **Deploy to Azure** above and sign in to your Azure tenant.
2. Select your subscription and an existing or new resource group.
3. Choose a Workbook location and display name. The location stores the Workbook; it does not restrict the regions queried.
4. Review and create the deployment.
5. Open the `workbookPortalUrl` deployment output, or find the shared Workbook in **Azure Monitor > Workbooks**.

The portal button uses the compiled ARM template in this repository; no local tooling is required.

### Option 2: Azure CLI and Bicep

Prerequisites: Git, Azure CLI with Bicep support, and permission to deploy `Microsoft.Insights/workbooks` into the target resource group (for example, Contributor or an appropriate custom role). A viewer needs permission to read the Workbook and the resources they want to inventory; Reader at the desired scopes is a common choice. Deployment does not grant those permissions.

PowerShell example:

```powershell
git clone https://github.com/kevinsul/azure-vm-storage-pricing-workbook.git
Set-Location azure-vm-storage-pricing-workbook

az login
$subscriptionId = '<your-subscription-id>'
$resourceGroup = 'rg-pricing-workbook'
$location = 'eastus'

az group create --subscription $subscriptionId --name $resourceGroup --location $location

az deployment group create `
  --subscription $subscriptionId `
  --resource-group $resourceGroup `
  --name pricing-exposure-workbook `
  --template-file .\main.bicep `
  --parameters location=$location `
  --query properties.outputs
```

Alternatively, edit the tenant-neutral [workbook.bicepparam](workbook.bicepparam) and deploy with `--parameters .\workbook.bicepparam`.

| Parameter | Default | Purpose |
|---|---|---|
| `location` | Resource-group location | Location of the Workbook resource, not the queried inventory |
| `workbookDisplayName` | Azure VM and Storage pricing exposure - February 2027 | Name shown in Azure Monitor |
| `workbookId` | Deterministic GUID from resource-group ID and display name | Stable resource identity |
| `tags` | `{}` | Tags on the Workbook only |

Redeploying with the same resource group, name, and ID updates the existing Workbook. If you change the display name but want to update the same Workbook, explicitly supply its existing GUID as `workbookId`; otherwise the default generates a new resource ID.

## Use and interpret the report

1. Select subscriptions, then resource groups. Resource-group values use full resource IDs so identically named groups across subscriptions remain distinct.
2. Leave **All deployed** selected to include stopped/deallocated VMs, unknown power states, and scale-set models. **Reported running VMs only** includes VMs whose Resource Graph power state reports running.
3. Include the resource groups containing disks and storage accounts. **The compute-state filter does not filter storage.**
4. Select a linked resource name to open its Azure portal overview. Consult the assessment column before treating an increase as applicable.

### Limitations

- Azure public cloud only; other clouds intentionally return no inventory.
- Resource Graph is eventually consistent and returns only resources the viewer can read. A blank table does not prove that no affected billing exists.
- Tables and resource-group pickers return at most **1,000 rows per query**. Narrow the scope for larger environments.
- Scale-set model capacity is configured capacity, not a verified running instance count. Do not add it to member VM counts.
- Not all child resources or service-specific billing metadata are exposed in Resource Graph. A storage account can appear alongside its child shares; resource counts are not billable meter counts.
- No price-sheet, billing-export, currency, reservation-coverage, or negotiated-rate lookup is performed.

## Source and validation

| File | Purpose |
|---|---|
| [main.bicep](main.bicep) | Workbook resource and query assembly |
| [workbook.json](workbook.json) | Introduction, filters, table formatting, and portal links |
| [pricing-rules.json](pricing-rules.json) | Exact VM-family patterns, regional rates, and disk-SKU mappings |
| [queries/compute.kql](queries/compute.kql) | Compute classification |
| [queries/storage.kql](queries/storage.kql) | Storage classification |
| [azuredeploy.json](azuredeploy.json) | Generated ARM template used by the portal button |
| [tests/Validate-Workbook.ps1](tests/Validate-Workbook.ps1) | Local rule, layout, link, and build checks |

The KQL files contain build-time tokens and are assembled by Bicep; they are not standalone queries as stored.

Run local checks with PowerShell 7 and Azure CLI/Bicep installed:

```powershell
pwsh -NoProfile -File .\tests\Validate-Workbook.ps1
az bicep build --file .\main.bicep --outfile .\azuredeploy.json
```

Local checks do not sign in to Azure, query a tenant, or deploy resources. To additionally validate the expanded Workbook against the official schema, download the [Microsoft Workbook schema](https://raw.githubusercontent.com/microsoft/Application-Insights-Workbooks/master/schema/workbook.json) and pass its local path with `-WorkbookSchemaPath`.

After changing source, regenerate and commit [azuredeploy.json](azuredeploy.json) so portal deployments match Bicep deployments. Live query execution and signed-in portal interaction should also be smoke-tested in your own tenant.

## Remove the Workbook

Delete the Workbook resource in the Azure portal. This does not delete or change inventoried resources. Delete its resource group only if it is dedicated to this Workbook and contains nothing else you need.

## License

[MIT](LICENSE).
