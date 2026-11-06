# Number Processing Worker

This folder contains the on-demand C# worker image.

On startup it reads every regular file in the configured Input directory, reads one numeric weight from the configured Weights file, adds the values, writes a UTC-datetime-named output file, and deletes only successful input files.

Directories are configurable through environment variables:
- `WORKER_INPUT_DIR`, default `/mnt/processing/NumberTest1/Input`
- `WORKER_WEIGHTS_DIR`, default `/mnt/processing/NumberTest1/Weights`
- `WORKER_OUTPUT_DIR`, default `/mnt/processing/NumberTest1/Output`
- `WORKER_WEIGHT_FILE`, default `weight.txt`

See `Dockerfile` and unit tests for build and validation details.

## Build and Test

```powershell
dotnet build number-worker/NumberWorker.csproj --configuration Release
dotnet test ContainerAppBurst.slnx --configuration Release
az acr build --registry "<acr-name>" --image "number-worker:local" "number-worker"
```

`az acr build` uses hosted ACR Tasks, so no local Docker is needed. It only works while the registry is publicly reachable (bootstrap or maintenance mode); `./scripts/deploy.ps1 -Phase Maintenance -RebuildImage` handles that and rolls out the new image.

Run locally with temporary directories:

```powershell
$env:WORKER_INPUT_DIR="C:/temp/processing/NumberTest1/Input"
$env:WORKER_WEIGHTS_DIR="C:/temp/processing/NumberTest1/Weights"
$env:WORKER_OUTPUT_DIR="C:/temp/processing/NumberTest1/Output"
$env:WORKER_WEIGHT_FILE="weight.txt"
dotnet run --project number-worker/NumberWorker.csproj
```
