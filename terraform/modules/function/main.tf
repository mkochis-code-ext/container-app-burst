# Flex Consumption (FC1) is pay-per-execution and does not consume App Service VM quota
# (EP1 and P1v3 quota are 0 in this subscription). It supports VNet integration and
# private endpoints, so the Function still follows the private-networking model.
resource "azurerm_service_plan" "function" {
  name                = var.function_plan_name
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = var.tags
}

resource "azurerm_function_app_flex_consumption" "main" {
  name                = var.function_app_name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.function.id

  runtime_name    = "dotnet-isolated"
  runtime_version = "10.0"

  # The provider always writes an AzureWebJobsStorage connection string for Flex apps. With
  # SystemAssignedIdentity it has an empty AccountKey, which takes precedence over the
  # AzureWebJobsStorage__accountName settings and stops the timer host from ever running.
  # Using a real key here gives that setting a valid value (traffic still uses the private endpoints).
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = var.deployment_container_endpoint
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = var.storage_account_primary_key

  https_only                                     = true
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.function_subnet_id
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    minimum_tls_version = "1.2"
  }

  # Flex Consumption rejects FUNCTIONS_WORKER_RUNTIME and FUNCTIONS_EXTENSION_VERSION;
  # the runtime comes from runtime_name/runtime_version.
  app_settings = {
    STORAGE_ACCOUNT_NAME          = var.storage_account_name
    STORAGE_ACCOUNT_KEY           = "@Microsoft.KeyVault(SecretUri=${var.storage_account_primary_key_secret_id})"
    STORAGE_FILE_SHARE_NAME       = var.storage_share_name
    ACA_JOB_RESOURCE_IDS          = jsonencode(var.container_app_job_resource_ids)
    ARM_API_VERSION               = "2025-07-01"
    ACA_JOB_MAX_EXECUTION_MINUTES = "30"
  }
}

resource "azurerm_private_endpoint" "function" {
  count               = var.private_endpoints_enabled ? 1 : 0
  name                = "pe-${var.function_app_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "function-sites"
    private_connection_resource_id = azurerm_function_app_flex_consumption.main.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "function-sites-dns"
    private_dns_zone_ids = [
      var.private_dns_zone_ids["privatelink.azurewebsites.net"]
    ]
  }
}
