# Timer Function Source

This folder contains the .NET isolated Function app source.

The timer uses:
- `TimerTrigger("0 * * * * *")` for one-minute scheduling;
- Azure Storage File Shares for private SMB data-plane discovery;
- `DefaultAzureCredential` for Azure Resource Manager access;
- the Container Apps Jobs start/list/stop REST operations;
- `ACA_JOB_RESOURCE_IDS` JSON to dynamically route `NumberTest1/Input` and `NumberTest2/Input` to their matching Job.

Official Microsoft NuGet packages are used for Azure Functions, Azure Identity, and Azure Storage Files.

## Build and Publish

```powershell
dotnet build ContainerAppBurst.slnx --configuration Release
./scripts/package-function.ps1
```

`package-function.ps1` publishes the Function and writes `artifacts/timer-function.zip`. `scripts/deploy-data.ps1` zip-deploys it with `az functionapp deployment source config-zip` while the Function app is still publicly reachable (bootstrap or maintenance mode); in steady state the app has public access disabled.

In bootstrap there are no Container Apps Jobs yet, so `ACA_JOB_RESOURCE_IDS` is `{}`. The timer logs that no jobs are configured and returns; a missing setting still fails. Once the `private` apply creates the Jobs, the setting is populated and the timer starts working.

For local Function startup, create `timer-function/local.settings.json` with private-development placeholders only; the file is excluded from Git. The real deployment receives Key Vault-backed settings from Terraform.
