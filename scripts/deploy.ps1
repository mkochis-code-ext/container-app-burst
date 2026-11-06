param(
    [ValidateSet("dev")]
    [string]$Environment = "dev",
    [Parameter(Mandatory = $true)]
    [ValidateSet("T4", "A100")]
    [string]$GpuType,
    [string]$SubscriptionId,
    [string]$Location = "eastus",
    [string]$Workload = "containerappburst",
    # Full:        Bootstrap + Lockdown in one run (default).
    # Bootstrap:   phase 1, everything public; builds the image, creates the share
    #              folders and deploys the Function. Stops before private networking.
    # Lockdown:    phase 2, adds private endpoints/DNS and creates the Container Apps
    #              environment and Jobs (while ACR is still reachable), then turns
    #              public access off.
    # Maintenance: day-2 changes. Temporarily re-opens public access, runs the data
    #              steps (and rebuilds the image with -RebuildImage), then locks down again.
    [ValidateSet("Full", "Bootstrap", "Lockdown", "Maintenance")]
    [string]$Phase = "Full",
    # Lockdown/Maintenance: use this existing image tag instead of the newest in ACR.
    [string]$ImageTag,
    # Maintenance: build and roll out a new worker image.
    [switch]$RebuildImage,
    # Maintenance smoke test: upload one input file with this number into every Input
    # folder, and optionally overwrite every weight.txt with -TestWeight. The timer
    # Function starts the Jobs within a minute of the lock-down.
    [string]$TestInput,
    [string]$TestWeight,
    [ValidateSet("Local", "Remote")]
    [string]$StateMode = "Local",
    [string]$TfStateStorageAccount,
    [string]$TfStateResourceGroup,
    # Skip 'az login' when the caller (for example a pipeline) is already signed in.
    [switch]$SkipLogin
)

# Every step here either uses the Azure management plane (Terraform, ACR Tasks) or
# the public data plane while the resources are still public. Nothing needs a VPN,
# jump box or private runner. Once phase 2 completes, use -Phase Maintenance for
# any change that needs the data plane.

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$environmentPath = Join-Path $repoRoot "terraform/environments/$Environment"
$backendPath = Join-Path $environmentPath "backend.tf"
$imageName = "number-worker"
$placeholderImage = "mcr.microsoft.com/k8se/quickstart-jobs"
$placeholderTag = "latest"

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

function Invoke-NativeOutput {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $output = & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }

    return ($output | Out-String).Trim()
}

function Invoke-InEnvironment {
    param([scriptblock]$Script)

    Push-Location $environmentPath
    try {
        & $Script
    }
    finally {
        Pop-Location
    }
}

function Invoke-TerraformApply {
    param(
        [ValidateSet("bootstrap", "private", "maintenance")]
        [string]$Mode,
        [string]$Image,
        [string]$Tag
    )

    Write-Host ""
    Write-Host "=== terraform apply (network_mode=$Mode, image=$Image`:$Tag) ==="
    Invoke-InEnvironment {
        Invoke-Native "terraform" @(
            "apply", "-auto-approve", "-input=false",
            "-var=environment_prefix=$Environment",
            "-var=location=$Location",
            "-var=workload=$Workload",
            "-var=gpu_type=$GpuType",
            "-var=network_mode=$Mode",
            "-var=worker_image=$Image",
            "-var=worker_image_tag=$Tag"
        )
    }
}

function Get-TerraformOutput {
    param(
        [string]$Name,
        [switch]$Json
    )

    # 'terraform output -raw' exits 0 and prints a warning when the state is empty,
    # so read the full JSON document and check the output exists explicitly.
    $script:tfOutput = $null
    Invoke-InEnvironment { $script:tfOutput = Invoke-NativeOutput "terraform" @("output", "-json") }
    $outputs = $script:tfOutput | ConvertFrom-Json
    $property = $outputs.PSObject.Properties[$Name]
    if (-not $property) {
        throw "Terraform output '$Name' was not found. Has the infrastructure been applied yet?"
    }

    return $property.Value.value
}

function Build-Image {
    param([string]$RegistryName)

    $tag = Get-Date -Format "yyyyMMddHHmmss"
    Write-Host ""
    Write-Host "=== az acr build ($imageName`:$tag) ==="
    Invoke-Native "az" @(
        "acr", "build",
        "--registry", $RegistryName,
        "--image", "$imageName`:$tag",
        (Join-Path $repoRoot "number-worker")
    )

    return $tag
}

function Invoke-DataSteps {
    param(
        [string]$ResourceGroup,
        [string[]]$Folders
    )

    $packagePath = Join-Path $repoRoot "artifacts/timer-function.zip"
    & (Join-Path $PSScriptRoot "package-function.ps1") -OutputPath $packagePath

    $dataArguments = @{
        ResourceGroup = $ResourceGroup
        FolderNames   = $Folders
        PackagePath   = $packagePath
    }
    if ($SubscriptionId) {
        $dataArguments.SubscriptionId = $SubscriptionId
    }
    if ($TestInput) {
        $dataArguments.TestInput = $TestInput
    }
    if ($TestWeight) {
        $dataArguments.TestWeight = $TestWeight
    }
}

Assert-Command "az"
Assert-Command "terraform"
Assert-Command "dotnet"

if (($TestInput -or $TestWeight) -and $Phase -ne "Maintenance") {
    throw "-TestInput and -TestWeight need the data plane, so they only work with -Phase Maintenance."
}

if (-not $SkipLogin) {
    Invoke-Native "az" @("login", "--use-device-code")
}
if ($SubscriptionId) {
    Invoke-Native "az" @("account", "set", "--subscription", $SubscriptionId)
}

Push-Location $repoRoot
try {
    Invoke-Native "dotnet" @("build", "ContainerAppBurst.slnx", "--configuration", "Release", "--nologo")
    Invoke-Native "dotnet" @("test", "ContainerAppBurst.slnx", "--configuration", "Release", "--no-build", "--nologo")
}
finally {
    Pop-Location
}

$effectiveStateMode = $StateMode
if ($TfStateStorageAccount -or $TfStateResourceGroup) {
    $effectiveStateMode = "Remote"
}

if ($effectiveStateMode -eq "Remote") {
    if (-not $TfStateStorageAccount -or -not $TfStateResourceGroup) {
        throw "Both -TfStateStorageAccount and -TfStateResourceGroup are required for -StateMode Remote."
    }

    $backend = @"
terraform {
  backend "azurerm" {
    storage_account_name = "$TfStateStorageAccount"
    container_name       = "tfstate"
    key                  = "$Environment.terraform.tfstate"
    resource_group_name  = "$TfStateResourceGroup"
    use_azuread_auth     = true
  }
}
"@
    Set-Content -Path $backendPath -Value $backend -Encoding utf8
    Invoke-InEnvironment { Invoke-Native "terraform" @("init", "-migrate-state", "-input=false") }
}
else {
    if (Test-Path $backendPath) {
        throw "Local state mode found terraform/environments/$Environment/backend.tf. Remove it or use -StateMode Remote with explicit state storage values."
    }

    Invoke-InEnvironment { Invoke-Native "terraform" @("init", "-reconfigure") }
}

$acrLoginServer = $null
$resourceGroup = $null
$folders = @("NumberTest1", "NumberTest2")
$workerImage = "$placeholderImage"
$workerTag = $placeholderTag

function Get-CurrentNetworkMode {
    try {
        return Get-TerraformOutput "network_mode"
    }
    catch {
        return $null
    }
}

if ($Phase -in @("Full", "Bootstrap")) {
    $existingMode = Get-CurrentNetworkMode
    if ($existingMode -and $existingMode -ne "bootstrap") {
        throw "This environment is already in network_mode '$existingMode'. Re-applying bootstrap would destroy the Container Apps environment and private endpoints. Use -Phase Maintenance for day-2 changes."
    }

    # Phase 1: public, no private endpoints, no Container Apps.
    Invoke-TerraformApply -Mode "bootstrap" -Image $placeholderImage -Tag $placeholderTag

    $resourceGroup = Get-TerraformOutput "resource_group_name"
    $acrName = Get-TerraformOutput "container_registry_name"
    $acrLoginServer = Get-TerraformOutput "container_registry_login_server"
    $folders = @(Get-TerraformOutput "processing_folder_names" -Json)

    Invoke-DataSteps -ResourceGroup $resourceGroup -Folders $folders

    $workerImage = "$acrLoginServer/$imageName"
    $workerTag = Build-Image -RegistryName $acrName

    if ($Phase -eq "Bootstrap") {
        Write-Host ""
        Write-Host "Bootstrap complete. Image: $workerImage`:$workerTag"
        Write-Host "Next: ./scripts/deploy.ps1 -Environment $Environment -GpuType $GpuType -Phase Lockdown"
        return
    }
}
elseif ($Phase -eq "Lockdown") {
    $currentMode = Get-CurrentNetworkMode
    # 'private' is accepted so a Lockdown that failed part-way can be resumed: Terraform
    # records the mode before every resource has been applied.
    if ($currentMode -notin @("bootstrap", "private")) {
        throw "Lockdown expects network_mode 'bootstrap' (or 'private' to resume a Lockdown that failed part-way), but network_mode is '$currentMode'. Use -Phase Maintenance for day-2 changes."
    }

    $acrName = Get-TerraformOutput "container_registry_name"
    $acrLoginServer = Get-TerraformOutput "container_registry_login_server"
    $workerImage = "$acrLoginServer/$imageName"

    if ($ImageTag) {
        $workerTag = $ImageTag
    }
    elseif ($currentMode -eq "private") {
        # ACR public access may already be off, so reuse the tag recorded in state
        # rather than querying the registry from this machine.
        $workerTag = Get-TerraformOutput "worker_image_tag"
        if (-not $workerTag -or $workerTag -eq $placeholderTag) {
            throw "No image tag is recorded in state to resume with. Pass -ImageTag with a tag that exists in $acrName."
        }
        Write-Host "Resuming Lockdown with image tag $workerTag recorded in state."
    }
    else {
        $workerTag = Invoke-NativeOutput "az" @(
            "acr", "repository", "show-tags",
            "--name", $acrName,
            "--repository", $imageName,
            "--orderby", "time_desc",
            "--top", "1",
            "--output", "tsv"
        )
        if (-not $workerTag) {
            throw "No '$imageName' image was found in $acrName. Run -Phase Bootstrap first, or pass -ImageTag."
        }
    }
}

if ($Phase -in @("Full", "Lockdown")) {
    # Phase 2: control plane only. Container Apps validates the registry pull from its
    # own (public) control plane when a Job is created, and the registry denies that
    # request once public access is off. So first create the private endpoints, DNS,
    # environment and Jobs while the registry is still reachable, then close public
    # access in a second apply. Job pulls at run time use the private endpoint.
    Invoke-TerraformApply -Mode "maintenance" -Image $workerImage -Tag $workerTag
    Invoke-TerraformApply -Mode "private" -Image $workerImage -Tag $workerTag
}

if ($Phase -eq "Maintenance") {
    $currentMode = Get-CurrentNetworkMode
    if (-not $currentMode -or $currentMode -eq "bootstrap") {
        throw "The environment has not been locked down yet. Run -Phase Lockdown (or Full) first."
    }

    $resourceGroup = Get-TerraformOutput "resource_group_name"
    $acrName = Get-TerraformOutput "container_registry_name"
    $folders = @(Get-TerraformOutput "processing_folder_names" -Json)
    $workerImage = Get-TerraformOutput "worker_image"
    $workerTag = Get-TerraformOutput "worker_image_tag"

    Invoke-TerraformApply -Mode "maintenance" -Image $workerImage -Tag $workerTag

    $failure = $null
    try {
        Invoke-DataSteps -ResourceGroup $resourceGroup -Folders $folders

        if ($RebuildImage) {
            $workerTag = Build-Image -RegistryName $acrName
        }
        elseif ($ImageTag) {
            $workerTag = $ImageTag
        }
    }
    catch {
        $failure = $_
    }

    # Always close public access again, even when a data step failed.
    Invoke-TerraformApply -Mode "private" -Image $workerImage -Tag $workerTag

    if ($failure) {
        throw $failure
    }
}

$resourceGroup = Get-TerraformOutput "resource_group_name"
$functionApp = Get-TerraformOutput "function_app_name"

Write-Host ""
Write-Host "Deployment complete (phase: $Phase)."
Write-Host "Resource group: $resourceGroup"
Write-Host "Worker image: $workerImage`:$workerTag"
Write-Host "Function app: $functionApp"
Write-Host "Network mode: $(Get-TerraformOutput 'network_mode')"
