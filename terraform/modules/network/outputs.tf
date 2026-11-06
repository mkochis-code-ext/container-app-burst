output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "container_apps_subnet_id" {
  value = "${azurerm_virtual_network.main.id}/subnets/${local.subnet_names.container_apps}"
}

output "function_subnet_id" {
  value = "${azurerm_virtual_network.main.id}/subnets/${local.subnet_names.function}"
}

output "private_endpoints_subnet_id" {
  value = "${azurerm_virtual_network.main.id}/subnets/${local.subnet_names.private_endpoints}"
}
