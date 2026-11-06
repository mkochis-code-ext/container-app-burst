output "id" {
  value = azurerm_key_vault.main.id
}

output "storage_secret_id" {
  value      = "${azurerm_key_vault.main.vault_uri}secrets/${local.storage_secret_name}"
  depends_on = [azurerm_resource_group_template_deployment.storage_account_key]
}
