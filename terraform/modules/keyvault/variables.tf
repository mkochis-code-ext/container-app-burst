variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "key_vault_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "private_endpoints_subnet_id" {
  type = string
}

variable "public_network_access_enabled" {
  type = bool
}

variable "private_endpoints_enabled" {
  type = bool
}

variable "private_dns_zone_ids" {
  type = map(string)
}

variable "storage_account_primary_key" {
  type      = string
  sensitive = true
}
