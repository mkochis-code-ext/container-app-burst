param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,
    [string]$SubscriptionId,
    [string[]]$FolderNames = @("NumberTest1", "NumberTest2"),
    [string]$ShareName = "processing",
    [string]$PackagePath,
    [switch]$SkipShareContent,
    [switch]$SkipFunctionDeploy,
    # Smoke test: drop one input file containing this number into every <folder>/Input.
    [string]$TestInput,
    # Smoke test: overwrite every <folder>/Weights/weight.txt with this number.
    [string]$TestWeight
)

# Data-plane steps: create the share folders, seed the weight files, and zip-deploy
# the timer Function. These need public network access to the storage account and
# the Function's SCM site, so run them while Terraform network_mode is "bootstrap"
# or "maintenance" (deploy.ps1 does this for you). Only Azure CLI is required.

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not $PackagePath) {
    $PackagePath = Join-Path $repoRoot "artifacts/timer-function.zip"
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments
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

function Get-SingleResourceName {
    param(
        [string]$Description,
        [string[]]$Arguments
    )

    $names = @((Invoke-NativeOutput "az" $Arguments) -split "\r?\n" | Where-Object { $_ })
    if ($names.Count -ne 1) {
        throw "Expected exactly one $Description in resource group '$ResourceGroup' but found $($names.Count)."
    }

    return $names[0]
}

foreach ($pair in @(@("TestInput", $TestInput), @("TestWeight", $TestWeight))) {
    $parsed = [decimal]0
    if ($pair[1] -and -not [decimal]::TryParse($pair[1], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        throw "-$($pair[0]) must be a number, but was '$($pair[1])'."
    }
}

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found on PATH."
}

$signedIn = $false
try {
    & az account show --output none 2>$null
    $signedIn = ($LASTEXITCODE -eq 0)
}
catch {
    $signedIn = $false
}

if (-not $signedIn) {
    Invoke-Native "az" @("login", "--use-device-code")
}

if ($SubscriptionId) {
    Invoke-Native "az" @("account", "set", "--subscription", $SubscriptionId)
}

$storageAccount = Get-SingleResourceName "storage account" @(
    "storage", "account", "list",
    "--resource-group", $ResourceGroup,
    "--query", "[].name",
    "--output", "tsv"
)
$functionApp = Get-SingleResourceName "function app" @(
    "functionapp", "list",
    "--resource-group", $ResourceGroup,
    "--query", "[].name",
    "--output", "tsv"
)

Write-Host "Resource group: $ResourceGroup"
Write-Host "Storage account: $storageAccount"
Write-Host "Function app: $functionApp"

$publicAccess = Invoke-NativeOutput "az" @(
    "storage", "account", "show",
    "--resource-group", $ResourceGroup,
    "--name", $storageAccount,
    "--query", "publicNetworkAccess",
    "--output", "tsv"
)
if ($publicAccess -ne "Enabled") {
    throw "Storage account '$storageAccount' has public network access '$publicAccess'. Re-run deploy.ps1 -Phase Maintenance to open it temporarily."
}

if (-not $SkipShareContent) {
    $weightFile = Join-Path ([System.IO.Path]::GetTempPath()) "container-app-burst-weight.txt"
    Set-Content -Path $weightFile -Value "0" -NoNewline
    $testFile = Join-Path ([System.IO.Path]::GetTempPath()) "container-app-burst-test.txt"

    $env:AZURE_STORAGE_ACCOUNT = $storageAccount
    $env:AZURE_STORAGE_KEY = Invoke-NativeOutput "az" @(
        "storage", "account", "keys", "list",
        "--resource-group", $ResourceGroup,
        "--account-name", $storageAccount,
        "--query", "[0].value",
        "--output", "tsv"
    )

    try {
        foreach ($folder in $FolderNames) {
            Write-Host "Preparing share folders for $folder"
            foreach ($path in @($folder, "$folder/Input", "$folder/Output", "$folder/Weights")) {
                Invoke-Native "az" @(
                    "storage", "directory", "create",
                    "--share-name", $ShareName,
                    "--name", $path,
                    "--output", "none"
                )
            }

            $weightPath = "$folder/Weights/weight.txt"
            $exists = Invoke-NativeOutput "az" @(
                "storage", "file", "exists",
                "--share-name", $ShareName,
                "--path", $weightPath,
                "--query", "exists",
                "--output", "tsv"
            )
            if ($exists -ne "true") {
                Invoke-Native "az" @(
                    "storage", "file", "upload",
                    "--share-name", $ShareName,
                    "--path", $weightPath,
                    "--source", $weightFile,
                    "--output", "none"
                )
                Write-Host "Seeded $weightPath with 0"
            }
            else {
                Write-Host "Keeping existing $weightPath"
            }

            if ($TestWeight) {
                Set-Content -Path $testFile -Value $TestWeight -NoNewline
                Invoke-Native "az" @(
                    "storage", "file", "upload",
                    "--share-name", $ShareName,
                    "--path", $weightPath,
                    "--source", $testFile,
                    "--output", "none"
                )
                Write-Host "Set $weightPath to $TestWeight"
            }

            if ($TestInput) {
                $inputPath = "$folder/Input/smoke-test-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
                Set-Content -Path $testFile -Value $TestInput -NoNewline
                Invoke-Native "az" @(
                    "storage", "file", "upload",
                    "--share-name", $ShareName,
                    "--path", $inputPath,
                    "--source", $testFile,
                    "--output", "none"
                )
                Write-Host "Uploaded test input $inputPath ($TestInput)"
            }
        }
    }
    finally {
        Remove-Item Env:AZURE_STORAGE_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:AZURE_STORAGE_ACCOUNT -ErrorAction SilentlyContinue
        Remove-Item -Force $weightFile, $testFile -ErrorAction SilentlyContinue
    }
}

if (-not $SkipFunctionDeploy) {
    if (-not (Test-Path $PackagePath)) {
        Write-Host "No package at $PackagePath; building one."
        & (Join-Path $PSScriptRoot "package-function.ps1") -OutputPath $PackagePath
    }

    # SCM basic authentication is disabled on the Function app, so the deployment
    # authenticates with the signed-in Microsoft Entra identity. 'functionapp deploy'
    # is rejected by Flex Consumption (HTTP 415); 'config-zip' uses its one-deploy API.
    # The app's managed identity reads the package from storage, and its role
    # assignments can take a few minutes to propagate, so retry on failure.
    # config-zip also runs a post-deploy host-key health probe that can fail even
    # when the package was deployed, so confirm by listing the registered functions.
    $expectedFunction = "CheckForInputFiles"
    $deployed = $false
    for ($attempt = 1; $attempt -le 4 -and -not $deployed; $attempt++) {
        $deployError = $null
        try {
            Invoke-Native "az" @(
                "functionapp", "deployment", "source", "config-zip",
                "--resource-group", $ResourceGroup,
                "--name", $functionApp,
                "--src", $PackagePath
            )
        }
        catch {
            $deployError = $_.Exception.Message
        }

        $registered = @()
        try {
            $registered = @((Invoke-NativeOutput "az" @(
                "functionapp", "function", "list",
                "--resource-group", $ResourceGroup,
                "--name", $functionApp,
                "--query", "[].name",
                "--output", "tsv"
            )) -split "\r?\n" | Where-Object { $_ })
        }
        catch {
            Write-Warning "Could not list functions: $($_.Exception.Message)"
        }

        if ($registered | Where-Object { $_ -like "*/$expectedFunction" -or $_ -eq $expectedFunction }) {
            if ($deployError) {
                Write-Warning "Deployment reported an error but '$expectedFunction' is registered, continuing: $deployError"
            }
            $deployed = $true
        }
        elseif ($attempt -eq 4) {
            throw "Function deployment did not register '$expectedFunction'. $deployError"
        }
        else {
            Write-Warning "Function deploy attempt $attempt did not register '$expectedFunction': $deployError"
            Write-Host "Waiting 60 seconds for role assignments to propagate before retrying."
            Start-Sleep -Seconds 60
        }
    }
}

Write-Host "Data steps complete."
