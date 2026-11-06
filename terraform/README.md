# Terraform Deployment

The Terraform configuration follows the same two-layer structure as the referenced module example:

```text
terraform/
  environments/dev/
  project/
  modules/
    network/
    private-dns/
    storage/
    keyvault/
    acr/
    aca/
    function/
```

## Prerequisites

- Azure CLI
- Terraform 1.11 or newer (the Log Analytics key is passed to the environment through the azapi provider's write-only `sensitive_body`)
- Azure subscription and permissions to create resources and role assignments
- Serverless GPU quota for the chosen T4 or A100 profile
- No private-network access is needed: Terraform only uses Azure Resource Manager, and the data-plane work (share folders, weights, Function zip) runs while the resources are still public, in the bootstrap phase. See [Network modes](#network-modes)

## Configure

Authenticate and select the subscription:

```powershell
az login
az account set --subscription "<subscription-id>"
```

Copy the environment example:

```powershell
Copy-Item terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
```

Set `gpu_type` to `T4` or `A100`. The variable has no implicit default.

## Network Modes

The `network_mode` variable (`bootstrap`, `private` or `maintenance`; default `bootstrap`) is the only difference between phases:

| Mode | Private endpoints and DNS | Container Apps environment and Jobs | Public access on Storage, ACR, Key Vault, Function |
|------|---------------------------|-------------------------------------|-----------------------------------------------------|
| `bootstrap` | No | No | Enabled |
| `private` | Yes | Yes | Disabled |
| `maintenance` | Yes | Yes | Enabled (temporary, for day-2 data-plane work) |

Go `bootstrap` -> `private` -> (`maintenance` <-> `private`). **Never go from `private` or `maintenance` back to `bootstrap`**: it would destroy the private endpoints and the Container Apps environment, whose network type cannot be changed in place.

`private_dns` and `aca` are gated with `count` in `terraform/project/main.tf`, so bootstrap creates neither. In bootstrap the Function's `ACA_JOB_RESOURCE_IDS` is `{}`.

The Container Apps environment is the one resource defined with the Microsoft-published `Azure/azapi` provider (`azapi_resource`, `Microsoft.App/managedEnvironments`) instead of `azurerm`. The `azurerm` provider always sends `minimumCount`/`maximumCount` for non-`Consumption` workload profiles, and the API rejects them for the serverless T4 and A100 GPU profiles (`WorkloadProfilePropertyNotSupported`, [hashicorp/terraform-provider-azurerm#31763](https://github.com/hashicorp/terraform-provider-azurerm/issues/31763)). Everything else in the module (storage mount, Jobs, DNS) still uses `azurerm` and reads the environment's ID, default domain and static IP from the azapi resource. The `azapi` provider authenticates the same way as `azurerm` (Azure CLI login or `ARM_*` variables).

Every taggable resource gets `SecurityControl = "Ignore"`, merged last in `local.tags` in `environments/dev/main.tf` so `var.tags` cannot override it.

The Flex Consumption Function (`terraform/modules/function/`) uses `storage_authentication_type = "StorageAccountConnectionString"` with the storage account key. The `azurerm` provider always writes an `AzureWebJobsStorage` app setting for Flex apps; under identity authentication its `AccountKey` is empty and it overrides the `AzureWebJobsStorage__*` identity settings, so the host starts but the timer never fires. The Function's managed identity therefore holds only `Container Apps Jobs Operator` (per Job) and `Key Vault Secrets User`. `azurerm_monitor_diagnostic_setting.function` sends `FunctionAppLogs` to the Container Apps Log Analytics workspace, because Flex Consumption has no Kudu or log stream.

Tenant policy shapes two modules: the Key Vault is created with purge protection and RBAC authorization (guardrail initiative "Enforce recommended guardrails for Azure Key Vault"), so the Function gets `Key Vault Secrets User` through a role assignment instead of an access policy; and the subnets are inline `subnet` blocks of the VNet, each created with its own NSG, because the policy "Subnets must have a Network Security Group" denies a subnet created without one.

Useful outputs: `network_mode`, `processing_folder_names`, `worker_image` and `worker_image_tag` (the last three are read back by `deploy.ps1` for Maintenance).

## Initialize and Apply

For local development, run Terraform without a `backend.tf` file. Terraform uses local state in the environment directory:

```powershell
cd terraform/environments/dev
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var gpu_type=T4
terraform apply -var gpu_type=T4
```

The `.tfstate` files are excluded from Git. Use local state only for development, isolated testing, or work that does not require shared state.

`scripts/deploy.ps1` automates the whole sequence: bootstrap apply with the placeholder image, share folders and Function zip (`scripts/deploy-data.ps1`), image build with hosted `az acr build`, then the `private` apply with the new image. To run it manually, apply with `-var network_mode=bootstrap`, build the image, then apply with `-var network_mode=private -var worker_image=<acr>.azurecr.io/number-worker -var worker_image_tag=<tag>`.

Terraform creates the storage account and `processing` share but not the share folders or weight files (Azure Files directories are data-plane objects); `scripts/deploy-data.ps1` creates `NumberTest1` and `NumberTest2` with `Input`, `Output`, and `Weights` and deploys the timer Function package. The Key Vault secret holding the storage key is created through an ARM template deployment (`azurerm_resource_group_template_deployment`), so no Key Vault data-plane access is needed during apply.

## Remote State

Create an Azure Storage backend before deployment and configure it in `backend.tf`. The repository template uses Azure AD authentication:

```powershell
az storage account create `
  --name "<state-account>" `
  --resource-group "<state-resource-group>" `
  --location eastus `
  --sku Standard_LRS `
  --allow-blob-public-access false

az storage container create `
  --name tfstate `
  --account-name "<state-account>" `
  --auth-mode login
```

Use the values in `terraform/environments/dev/backend.tf.example`.

To configure it for local manual commands, copy the example and replace the placeholders:

```powershell
Copy-Item terraform/environments/dev/backend.tf.example terraform/environments/dev/backend.tf
```

When switching backends, use Terraform migration rather than silently creating a second state:

```powershell
# Copy an existing local state to Azure after creating backend.tf
cd terraform/environments/dev
terraform init -migrate-state

# Move Azure remote state back to local:
Remove-Item backend.tf
terraform init -migrate-state
```

The deployment script defaults to local state and asks you to handle an existing `backend.tf` explicitly rather than removing or changing it automatically. The script's `Remote` mode calls `terraform init -migrate-state -input=false` to copy existing local state when moving to Azure Blob storage. Never commit local `.tfstate` files.

## GPU Profiles

The environment always includes:
- standard `Consumption`;
- custom profile `gpu-t4` with `Consumption-GPU-NC8as-T4`;
- custom profile `gpu-a100` with `Consumption-GPU-NC24-A100`.

Use East US with the supplied defaults. Serverless GPU capacity and profile availability can vary by subscription and region.

## Cleanup

```powershell
terraform destroy
```
