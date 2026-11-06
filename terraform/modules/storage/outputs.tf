output "account_name" {
  value = azurerm_storage_account.main.name
}

output "account_id" {
  value = azurerm_storage_account.main.id
}

output "primary_access_key" {
  value     = azurerm_storage_account.main.primary_access_key
  sensitive = true
}

output "primary_blob_endpoint" {
  value = azurerm_storage_account.main.primary_blob_endpoint
}

output "function_deployment_container_endpoint" {
  value = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.function_deployment.name}"
}

output "share_name" {
  value = azurerm_storage_share.processing.name
}

output "share_url" {
  value = azurerm_storage_share.processing.url
}
