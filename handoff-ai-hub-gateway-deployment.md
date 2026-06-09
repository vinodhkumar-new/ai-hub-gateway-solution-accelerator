# AI Hub Gateway Deployment Handoff

## Purpose

This note captures the current deployment investigation state for the AI Hub Gateway accelerator so the work can be resumed next week without re-discovering the same blockers.

## Current Goal

Deploy the AI Hub Gateway accelerator into the FHA/BCH Azure subscription using the repository's `azd up` workflow, starting with a dev environment.

## Repo and Deployment Entry Points

- Repository: `HaoWangFH/ai-hub-gateway-solution-accelerator`
- Local path: `C:\users\hwang5\projects\fha-eist-appservices\smart-kb\projects\ai-hub-gateway-solution-accelerator`
- `azd` entry point: `azure.yaml`
- Main Bicep template: `bicep\infra\main.bicep`
- `azd up` parameter file: `bicep\infra\main.bicepparam`
- Dev reference parameter file: `bicep\infra\main.parameters.dev.bicepparam`

Important: `azd up` uses `main.bicepparam`, which reads values from `azd env`. It does not directly use `main.parameters.dev.bicepparam`.

## Environment and Region Findings

For Canada deployment:

- Core Azure location / Foundry location should use `canadaeast`.
- API Center location should use `canadacentral`.

Reason: the allowed regions for Foundry / AI Services and API Center do not fully overlap.

Recommended `azd env` values:

```powershell
azd env set AZURE_ENV_NAME dev
azd env set AZURE_LOCATION canadaeast
azd env set APIC_LOCATION canadacentral
```

## Required Tags

Initial deployment failed because the Azure Landing Zone policy requires tags on resource groups, including `SolutionName`.

Tags found from `C:\Users\hwang5\Projects\FHA-IDS\Function\pipelines\terraform\locals.tf`:

```bicep
param tags = {
  BCHOCostCenter: '960.71.1252518'
  Environment: 'Development'
  Classification: 'Medium'
  OwnerBCHO: 'FHA'
  ServiceOwner: 'fhenterpriseintegrationapim@fraserhealth.ca'
  SolutionName: 'FHA.IDS'
}
```

The current `rg-dev` resource group exists and has tags similar to:

```text
BCHOCostCenter = 960.71.1252518
Environment = dev
Classification = Medium
OwnerBCHO = FHA_
Project = AI Hub
ServiceOwner = fhenterpriseintegrationapim@fraserhealth.ca
SolutionName = FH.APIM.AIHub
```

## Deployment Attempt

The deployment was run using `azd up`.

Deployment name:

```text
dev-1780703119
```

Subscription:

```text
8ec4d8c8-09af-4f21-8d34-2caa6384fe4e
```

The resource group deployment succeeded:

```text
rg-dev: Succeeded
```

## Current Blocker

The deployment fails because the template tries to create Private DNS Zones locally.

Failing resource type:

```text
Microsoft.Network/privateDnsZones
```

Policy blocking the deployment:

```text
BCH - ALZ - Central DNS for Private Endpoints
DNS - Deny privatelinks Private DNS Zones
```

Failed zones included:

```text
privatelink.blob.core.windows.net
privatelink.queue.core.windows.net
privatelink.vaultcore.azure.net
privatelink.services.ai.azure.com
privatelink.openai.azure.com
privatelink.documents.azure.com
privatelink.servicebus.windows.net
privatelink.table.core.windows.net
privatelink.cognitiveservices.azure.com
privatelink.azure-api.net
privatelink.redis.azure.net
privatelink.file.core.windows.net
```

Conclusion: the Azure Landing Zone requires Private Endpoint DNS to use centrally managed Private DNS Zones. Application subscriptions are not allowed to create their own `privatelink.*` zones.

## VNet Finding

VNet creation itself appears to be allowed.

A minimal VNet deployment validation in `rg-dev` / `canadaeast` succeeded when required tags were included. The observed blocker is not `Microsoft.Network/virtualNetworks`; it is specifically `Microsoft.Network/privateDnsZones`.

Important template behavior:

- When `USE_EXISTING_VNET=false`, `main.bicep` creates Private DNS Zones through `dnsDeployment`.
- The VNet module depends on `dnsDeployment`, so the deployment fails before VNet creation is reached.
- When `USE_EXISTING_VNET=true`, the template skips creating Private DNS Zones and expects existing DNS configuration.

## Current Best Path

The most practical path with the current template is to use existing enterprise networking:

```powershell
azd env set USE_EXISTING_VNET true
azd env set VNET_NAME "<existing-vnet-name>"
azd env set EXISTING_VNET_RG "<existing-vnet-resource-group>"
azd env set APIM_SUBNET_NAME "<existing-apim-subnet>"
azd env set PRIVATE_ENDPOINT_SUBNET_NAME "<existing-private-endpoint-subnet>"
azd env set FUNCTION_APP_SUBNET_NAME "<existing-functionapp-subnet>"
azd env set DNS_ZONE_RG "<central-private-dns-zone-rg>"
azd env set DNS_SUBSCRIPTION_ID "<central-dns-subscription-id>"
```

Optional simplifications for the next attempt:

```powershell
azd env set FOUNDRY_NETWORK_INJECTION_ENABLED false
azd env set ENABLE_MANAGED_REDIS false
```

Rationale:

- Disabling Foundry network injection avoids needing an existing delegated agent subnet.
- Disabling Managed Redis removes one private endpoint / DNS dependency while validating the base deployment path.

## Alternative Path

If the team wants the accelerator to create a new VNet while still using central DNS, the Bicep template likely needs a small change:

- Add a mode where `useExistingVnet = false` creates a new VNet but does not create Private DNS Zones.
- Use existing central Private DNS Zone resource IDs through the existing `existingPrivateDnsZones` parameter pattern.
- Ensure private endpoint DNS zone groups reference the central zones.
- Confirm whether central DNS allows virtual network links from newly created app VNets.

## Questions for Platform / Network Team

1. Which existing VNet and subnets should be used for this accelerator?
2. Are the required subnets already available for APIM, private endpoints, and Function App integration?
3. Should Foundry network injection be disabled for the initial dev deployment, or is there an existing delegated agent subnet?
4. What is the central Private DNS Zone resource group/subscription?
5. Can the team provide full resource IDs for the required central Private DNS Zones?
6. Are app teams allowed to create virtual network links from app VNets to central Private DNS Zones?
7. Is creating a new app VNet allowed if DNS zones remain centralized?

## Useful Commands

Check current `azd` environment:

```powershell
azd env get-values
azd env list
```

Check Azure account:

```powershell
az account show --output table
```

Inspect failed deployment operations:

```powershell
az deployment operation sub list `
  --name dev-1780703119 `
  --query "[?properties.provisioningState=='Failed'].{target:properties.targetResource.resourceName,type:properties.targetResource.resourceType,error:properties.statusMessage.error.message}" `
  --output table
```

Show resource group tags:

```powershell
az group show --name rg-dev --query "{name:name,location:location,tags:tags,provisioningState:properties.provisioningState}" --output json
```

## Next Recommended Steps

1. Confirm the central DNS and existing VNet/subnet details with the platform/network team.
2. Set `USE_EXISTING_VNET=true` and configure the existing VNet/subnet/DNS settings.
3. Run a new `azd up`.
4. If existing VNet is not available, update the template to support new VNet + central DNS.
5. Keep the initial dev deployment lean by disabling Redis and Foundry network injection until the base deployment path succeeds.
