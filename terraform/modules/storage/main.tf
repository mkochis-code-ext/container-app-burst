resource "azurerm_storage_account" "main" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  large_file_share_enabled        = true
  shared_access_key_enabled       = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = var.public_network_access_enabled
  tags                            = var.tags

  network_rules {
    default_action = var.public_network_access_enabled ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_storage_share" "processing" {
  name               = var.file_share_name
  storage_account_id = azurerm_storage_account.main.id
  quota              = 1024
  enabled_protocol   = "SMB"
  access_tier        = "TransactionOptimized"
}

# Flex Consumption apps load their code package from a blob container.
resource "azurerm_storage_container" "function_deployment" {
  name                  = "function-deployments"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

locals {
  storage_private_endpoints = {
    blob  = "blob"
    file  = "file"
    queue = "queue"
    table = "table"
  }

  storage_private_dns_zones = {
    blob  = "privatelink.blob.core.windows.net"
    file  = "privatelink.file.core.windows.net"
    queue = "privatelink.queue.core.windows.net"
    table = "privatelink.table.core.windows.net"
  }
}

resource "azurerm_private_endpoint" "storage" {
  for_each            = var.private_endpoints_enabled ? local.storage_private_endpoints : {}
  name                = "pe-${var.storage_account_name}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "storage-${each.key}"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = [each.value]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "storage-${each.key}-dns"
    private_dns_zone_ids = [
      var.private_dns_zone_ids[local.storage_private_dns_zones[each.key]]
    ]
  }
}
