output "function_app_name" {
  value = azurerm_function_app_flex_consumption.main.name
}

output "function_app_default_hostname" {
  value = azurerm_function_app_flex_consumption.main.default_hostname
}

output "function_app_id" {
  value = azurerm_function_app_flex_consumption.main.id
}

output "function_app_principal_id" {
  value = azurerm_function_app_flex_consumption.main.identity[0].principal_id
}
