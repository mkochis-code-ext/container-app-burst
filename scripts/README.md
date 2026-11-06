# Deployment Scripts

Deployment runs in two phases, **public bootstrap** then **private lockdown**, driven by the Terraform `network_mode` variable. Every step uses the Azure control plane or the public data plane while resources are still public, so nothing needs a VPN, jump box or private runner. No script requires Docker.

| Script | Purpose | Runs from |
|--------|---------|-----------|
| `deploy.ps1` | Orchestrator for all phases | Any machine with internet access |
| `deploy-data.ps1` | Data-plane steps: share folders, default weights, Function zip deploy | Called by `deploy.ps1`; needs the storage account and Function to be publicly reachable |
| `package-function.ps1` | Publishes the timer Function to a zip | Anywhere with the .NET 10 SDK |

## `deploy.ps1`

Builds and tests the C# solution, initializes Terraform state, and runs the selected phase.

Prerequisites: Azure CLI, Terraform, PowerShell 7, .NET 10 SDK.

| Phase | `-Phase` | What it does |
|-------|----------|--------------|
| Bootstrap | `Bootstrap` | Applies `network_mode=bootstrap` (VNet, Storage, Key Vault, ACR, Function; all public; placeholder image), runs `deploy-data.ps1`, builds the worker image with `az acr build` (hosted ACR Tasks, tag is a timestamp), and stops. |
| Lockdown | `Lockdown` | Requires the state to be `bootstrap`, or `private` to resume a Lockdown that failed part-way (the recorded image tag is reused because ACR public access may already be off). Applies `network_mode=maintenance` (private endpoints, DNS, Container Apps environment and Jobs, with public access still on because Container Apps validates the registry pull from its public control plane when a Job is created), then `network_mode=private` (public access off). Uses the newest image in ACR (or `-ImageTag`). |
| Full (default) | `Full` | Bootstrap followed by Lockdown with the image it just built. |
| Maintenance | `Maintenance` | Requires a locked-down state. Applies `network_mode=maintenance` (public access back on), runs the data steps, rebuilds and rolls out the image with `-RebuildImage` (or pins one with `-ImageTag`), then **always** re-applies `private`, even if a step failed (the failure is rethrown afterwards). |

Never apply `network_mode=bootstrap` after `private`: it would destroy the Container Apps environment and private endpoints. The script refuses to run Full/Bootstrap once the environment has left bootstrap.

Every resource that supports tags receives `SecurityControl: Ignore` from the first apply.

State is local by default. The local `.tfstate` file is stored under `terraform/environments/dev/` and remains excluded from Git.

```powershell
Copy-Item terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
./scripts/deploy.ps1 -Environment dev -GpuType T4
```

For A100:

```powershell
./scripts/deploy.ps1 -Environment dev -GpuType A100
```

Run one phase at a time, or make day-2 changes:

```powershell
./scripts/deploy.ps1 -GpuType T4 -Phase Bootstrap
./scripts/deploy.ps1 -GpuType T4 -Phase Lockdown
./scripts/deploy.ps1 -GpuType T4 -Phase Maintenance                 # re-seed weights, redeploy the Function
./scripts/deploy.ps1 -GpuType T4 -Phase Maintenance -RebuildImage   # also build and roll out a new worker image
./scripts/deploy.ps1 -GpuType T4 -Phase Maintenance -TestInput 5 -TestWeight 10   # smoke test: expect 15 in each Output folder
```

To select a subscription explicitly:

```powershell
./scripts/deploy.ps1 -Environment dev -GpuType T4 -SubscriptionId "<subscription-id>"
```

For remote Terraform state, select `Remote` and supply the external state storage account and resource group:

```powershell
./scripts/deploy.ps1 `
  -Environment dev `
  -GpuType T4 `
  -StateMode Remote `
  -TfStateStorageAccount "<state-account>" `
  -TfStateResourceGroup "<state-resource-group>"
```

Options:

| Parameter | Purpose |
|-----------|---------|
| `-GpuType` | Required. `T4` or `A100`. |
| `-Phase` | `Full` (default), `Bootstrap`, `Lockdown` or `Maintenance`. |
| `-ImageTag` | Lockdown/Maintenance: use this existing worker image tag instead of the newest in ACR. |
| `-RebuildImage` | Maintenance: build a new worker image and roll it out. |
| `-TestInput` | Maintenance: upload one `smoke-test-<timestamp>.txt` containing this number into every `Input/` folder. The timer Function starts the Jobs within a minute of the lock-down. |
| `-TestWeight` | Maintenance: overwrite every `Weights/weight.txt` with this number (so the sum differs from the input). |
| `-Location` | Azure region. Defaults to `eastus` (both T4 and A100 serverless GPU profiles are available there). |
| `-Workload` | Name component for resources. Defaults to `containerappburst`. |
| `-SubscriptionId` | Subscription to select. |
| `-StateMode`, `-TfStateStorageAccount`, `-TfStateResourceGroup` | Local (default) or remote Terraform state. |
| `-SkipLogin` | Skip `az login`; used by the pipelines, which are already signed in. |

## `deploy-data.ps1` (data plane)

Needs only Azure CLI and PowerShell 7; it does not use Terraform. It takes the resource group, discovers the storage account and Function app in it, and:

1. creates `<folder>/Input`, `<folder>/Output`, and `<folder>/Weights` on the file share for every name in `-FolderNames` (default `NumberTest1` and `NumberTest2`);
2. seeds `<folder>/Weights/weight.txt` with `0` only when the file does not already exist;
3. zip-deploys the timer Function package with `az functionapp deployment source config-zip` (the `az functionapp deploy` command fails on Flex Consumption with HTTP 415), then confirms the `CheckForInputFiles` function is registered. The CLI's post-deploy host-key health probe can report an error even when the package deployed, so registration is the success check.

It stops with an error when the storage account's public network access is not `Enabled`, because the data plane would be unreachable. The script is idempotent and safe to re-run; `deploy.ps1` calls it in Bootstrap and Maintenance.

```powershell
./scripts/deploy-data.ps1 -ResourceGroup "<resource-group>"
```

| Parameter | Purpose |
|-----------|---------|
| `-ResourceGroup` | Required. Resource group created by Terraform (output `resource_group_name`). |
| `-SubscriptionId` | Subscription to select. |
| `-FolderNames` | Share root folders to create. Defaults to `NumberTest1`, `NumberTest2`. |
| `-ShareName` | File share name. Defaults to `processing`. |
| `-TestInput` | Optional number; uploads `<folder>/Input/smoke-test-<timestamp>.txt` containing it. |
| `-TestWeight` | Optional number; overwrites `<folder>/Weights/weight.txt` with it. |
| `-PackagePath` | Function zip to deploy. Defaults to `artifacts/timer-function.zip`. |
| `-SkipShareContent` | Skip folder and weight creation. |
| `-SkipFunctionDeploy` | Skip the Function zip deploy. |

## Helper: `package-function.ps1`

Publishes `timer-function` and writes a zip (forward-slash entry paths, as the Linux Function host expects) to `artifacts/timer-function.zip`, or to `-OutputPath`.

```powershell
./scripts/package-function.ps1
```
