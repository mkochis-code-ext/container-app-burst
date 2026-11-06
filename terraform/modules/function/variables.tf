variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "function_plan_name" {
  type = string
}

variable "function_app_name" {
  type = string
}

variable "deployment_container_endpoint" {
  type        = string
  description = "Blob container URL (https://<account>.blob.core.windows.net/<container>) holding the Flex Consumption code package."
}

variable "function_subnet_id" {
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

variable "storage_account_name" {
  type = string
}

variable "storage_account_primary_key" {
  type        = string
  sensitive   = true
  description = "Storage account key used for the Function host (AzureWebJobsStorage) and the code-package container."
}

variable "storage_account_primary_key_secret_id" {
  type      = string
  sensitive = true
}

variable "storage_share_name" {
  type = string
}

variable "container_app_job_resource_ids" {
  type = map(string)
}

variable "private_dns_zone_ids" {
  type = map(string)
}
