data "azurerm_client_config" "current" {}

locals {
  resource_group_name = "rg-${var.workload}-${var.environment_prefix}-${var.suffix}"
  vnet_name           = "vnet-${var.workload}-${var.environment_prefix}-${var.suffix}"
  storage_name        = substr(lower("st${replace(var.workload, "-", "")}${var.suffix}"), 0, 24)
  registry_name       = substr(lower("acr${replace(var.workload, "-", "")}${var.suffix}"), 0, 50)
  key_vault_name      = substr(lower("kv${replace(var.workload, "-", "")}${var.suffix}"), 0, 24)
  environment_name    = "cae-${var.workload}-${var.environment_prefix}-${var.suffix}"
  job_name            = "job-${var.environment_prefix}-${var.suffix}"
  function_plan_name  = "plan-${var.workload}-${var.environment_prefix}-${var.suffix}"
  function_app_name   = substr(lower("func-${replace(var.workload, "_", "-")}-${var.environment_prefix}-${var.suffix}"), 0, 32)

  # Each key is a top-level folder on the file share and one Container Apps Job.
  job_keys = ["NumberTest1", "NumberTest2"]

  # bootstrap: public, no private endpoints, no Container Apps.
  # private: private endpoints + DNS, public access off, Container Apps created.
  # maintenance: as private, but public access re-enabled for day-2 data-plane work.
  private_endpoints_enabled     = var.network_mode != "bootstrap"
  public_network_access_enabled = var.network_mode != "private"
  container_apps_enabled        = var.network_mode != "bootstrap"

  private_dns_zones = [
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.table.core.windows.net",
    "privatelink.azurecr.io",
    "privatelink.vaultcore.azure.net",
    "privatelink.azurewebsites.net"
  ]
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

module "network" {
  source = "../modules/network"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
  vnet_name           = local.vnet_name
}

module "private_dns" {
  count  = local.private_endpoints_enabled ? 1 : 0
  source = "../modules/private-dns"

  resource_group_name = azurerm_resource_group.main.name
  virtual_network_id  = module.network.vnet_id
  tags                = var.tags
  zone_names          = local.private_dns_zones
}

locals {
  private_dns_zone_ids = local.private_endpoints_enabled ? module.private_dns[0].zone_ids : {}
}

module "storage" {
  source = "../modules/storage"

  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  tags                          = var.tags
  storage_account_name          = local.storage_name
  file_share_name               = "processing"
  private_endpoints_subnet_id   = module.network.private_endpoints_subnet_id
  public_network_access_enabled = local.public_network_access_enabled
  private_endpoints_enabled     = local.private_endpoints_enabled
  private_dns_zone_ids          = local.private_dns_zone_ids
}

module "acr" {
  source = "../modules/acr"

  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  tags                          = var.tags
  registry_name                 = local.registry_name
  private_endpoints_subnet_id   = module.network.private_endpoints_subnet_id
  public_network_access_enabled = local.public_network_access_enabled
  private_endpoints_enabled     = local.private_endpoints_enabled
  private_dns_zone_ids          = local.private_dns_zone_ids
}

module "keyvault" {
  source = "../modules/keyvault"

  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  tags                          = var.tags
  key_vault_name                = local.key_vault_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  private_endpoints_subnet_id   = module.network.private_endpoints_subnet_id
  public_network_access_enabled = local.public_network_access_enabled
  private_endpoints_enabled     = local.private_endpoints_enabled
  private_dns_zone_ids          = local.private_dns_zone_ids
  storage_account_primary_key   = module.storage.primary_access_key
}

module "aca" {
  count  = local.container_apps_enabled ? 1 : 0
  source = "../modules/aca"

  resource_group_name         = azurerm_resource_group.main.name
  resource_group_id           = azurerm_resource_group.main.id
  location                    = azurerm_resource_group.main.location
  tags                        = var.tags
  environment_name            = local.environment_name
  job_name                    = local.job_name
  job_keys                    = local.job_keys
  container_apps_subnet_id    = module.network.container_apps_subnet_id
  storage_account_name        = module.storage.account_name
  storage_account_primary_key = module.storage.primary_access_key
  file_share_name             = module.storage.share_name
  acr_id                      = module.acr.id
  acr_login_server            = module.acr.login_server
  worker_gpu_type             = var.gpu_type
  worker_image                = var.worker_image
  worker_image_tag            = var.worker_image_tag
  virtual_network_id          = module.network.vnet_id

  # Private endpoints and DNS must exist before the environment mounts the share.
  depends_on = [module.storage, module.acr, module.private_dns]
}

locals {
  job_names                      = local.container_apps_enabled ? module.aca[0].job_names : {}
  job_resource_ids               = local.container_apps_enabled ? module.aca[0].job_resource_ids : {}
  container_app_environment_name = local.container_apps_enabled ? module.aca[0].environment_name : null
}

module "function" {
  source = "../modules/function"

  resource_group_name                   = azurerm_resource_group.main.name
  location                              = azurerm_resource_group.main.location
  tags                                  = var.tags
  function_plan_name                    = local.function_plan_name
  function_app_name                     = local.function_app_name
  deployment_container_endpoint         = module.storage.function_deployment_container_endpoint
  function_subnet_id                    = module.network.function_subnet_id
  private_endpoints_subnet_id           = module.network.private_endpoints_subnet_id
  public_network_access_enabled         = local.public_network_access_enabled
  private_endpoints_enabled             = local.private_endpoints_enabled
  storage_account_name                  = module.storage.account_name
  storage_account_primary_key           = module.storage.primary_access_key
  storage_account_primary_key_secret_id = module.keyvault.storage_secret_id
  storage_share_name                    = module.storage.share_name
  container_app_job_resource_ids        = local.job_resource_ids
  private_dns_zone_ids                  = local.private_dns_zone_ids
}

resource "azurerm_role_assignment" "function_job_operator" {
  for_each             = local.container_apps_enabled ? toset(local.job_keys) : toset([])
  scope                = local.job_resource_ids[each.key]
  role_definition_name = "Container Apps Jobs Operator"
  principal_id         = module.function.function_app_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "function_key_vault_secrets" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.function.function_app_principal_id
  principal_type       = "ServicePrincipal"
}

# The Function has no Application Insights, so its host and timer logs go to the shared workspace.
resource "azurerm_monitor_diagnostic_setting" "function" {
  count                          = local.container_apps_enabled ? 1 : 0
  name                           = "diag-function-logs"
  target_resource_id             = module.function.function_app_id
  log_analytics_workspace_id     = module.aca[0].log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "FunctionAppLogs"
  }
}
