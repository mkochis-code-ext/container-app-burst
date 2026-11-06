output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "network_mode" {
  value = var.network_mode
}

output "storage_account_name" {
  value = module.storage.account_name
}

output "file_share_name" {
  value = module.storage.share_name
}

output "processing_folder_names" {
  description = "Top-level folders on the file share, one per Container Apps Job."
  value       = local.job_keys
}

output "container_registry_login_server" {
  value = module.acr.login_server
}

output "container_registry_name" {
  value = module.acr.name
}

output "worker_image" {
  description = "Worker image repository currently configured for the Container Apps Jobs."
  value       = var.worker_image
}

output "worker_image_tag" {
  description = "Worker image tag currently configured for the Container Apps Jobs."
  value       = var.worker_image_tag
}

output "container_app_environment_name" {
  value = local.container_app_environment_name
}

output "container_app_job_names" {
  value = local.job_names
}

output "container_app_job_resource_ids" {
  value = local.job_resource_ids
}

output "function_app_name" {
  value = module.function.function_app_name
}

output "function_app_default_hostname" {
  value = module.function.function_app_default_hostname
}
