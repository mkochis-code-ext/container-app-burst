resource "azurerm_container_registry" "main" {
  name                = var.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  # Premium is required to disable public access and use private endpoints.
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = var.public_network_access_enabled
  anonymous_pull_enabled        = false
  network_rule_bypass_option    = "None"
  tags                          = var.tags
}

resource "azurerm_private_endpoint" "acr" {
  count               = var.private_endpoints_enabled ? 1 : 0
  name                = "pe-${var.registry_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "acr-registry"
    private_connection_resource_id = azurerm_container_registry.main.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "acr-dns"
    private_dns_zone_ids = [
      var.private_dns_zone_ids["privatelink.azurecr.io"]
    ]
  }
}
