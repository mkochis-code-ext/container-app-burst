output "zone_ids" {
  value = { for name, zone in azurerm_private_dns_zone.zones : name => zone.id }
}
