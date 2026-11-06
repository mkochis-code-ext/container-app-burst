# Purge protection and RBAC authorization are required by the tenant guardrail
# initiative "Enforce recommended guardrails for Azure Key Vault" (effect: Deny).
resource "azurerm_key_vault" "main" {
  name                          = var.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  rbac_authorization_enabled    = true
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = var.public_network_access_enabled ? "Allow" : "Deny"
  }
}

locals {
  storage_secret_name = "storage-account-primary-key"
}

# The secret is written through ARM (management plane) instead of the Key Vault
# data plane, so Terraform can run from hosts without private network access.
resource "azurerm_resource_group_template_deployment" "storage_account_key" {
  name                = "kv-secret-${local.storage_secret_name}"
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"
  tags                = var.tags

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      vaultName   = { type = "string" }
      secretName  = { type = "string" }
      secretValue = { type = "securestring" }
    }
    resources = [
      {
        type       = "Microsoft.KeyVault/vaults/secrets"
        apiVersion = "2023-07-01"
        name       = "[format('{0}/{1}', parameters('vaultName'), parameters('secretName'))]"
        tags       = var.tags
        properties = {
          value       = "[parameters('secretValue')]"
          contentType = "Azure Storage account key"
        }
      }
    ]
  })

  parameters_content = jsonencode({
    vaultName   = { value = azurerm_key_vault.main.name }
    secretName  = { value = local.storage_secret_name }
    secretValue = { value = var.storage_account_primary_key }
  })
}

resource "azurerm_private_endpoint" "key_vault" {
  count               = var.private_endpoints_enabled ? 1 : 0
  name                = "pe-${var.key_vault_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "key-vault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "key-vault-dns"
    private_dns_zone_ids = [
      var.private_dns_zone_ids["privatelink.vaultcore.azure.net"]
    ]
  }
}
