# Implementation Plan

- [x] Create the repository structure and implementation tracker.
- [x] Build and test the .NET number-processing worker image.
- [x] Build the .NET isolated timer Function for dynamic NumberTest1/NumberTest2 file discovery and independent Container Apps Job control.
- [x] Add explicit local and Azure Blob remote Terraform state modes with migration support.
- [x] Provision private virtual-network and private-DNS infrastructure.
- [x] Provision the Storage account and SMB share (Terraform); create the NumberTest1/NumberTest2 directory structure and default weights while the account is public (`deploy-data.ps1`).
- [x] Provision the Key Vault and Storage account key secret (ARM template deployment, no data-plane access needed).
- [x] Provision the Premium Azure Container Registry; build the image with hosted ACR Tasks (Docker-free, no agent pool).
- [x] Provision the internal Container Apps environment, T4/A100 workload profiles, SMB mount, and both manual NumberTest1/NumberTest2 processing Jobs using the same image.
- [x] Provision the private Flex Consumption Azure Function app and managed identities.
- [x] Add local deployment scripts and CI/CD automation.
- [x] Deploy in two phases with the `network_mode` variable (`bootstrap` public, then `private` lockdown, plus `maintenance` for day 2) so no private network access is needed to deploy; implemented in scripts, GitHub Actions, and Azure DevOps.
- [x] Tag every taggable resource with `SecurityControl: Ignore` from the initial deploy.
- [x] Document every component, deployment path, and operational workflow.
- [x] Format, build, test, and validate the complete solution.
