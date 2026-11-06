output "resource_group_name" {
  value = module.project.resource_group_name
}

output "network_mode" {
  value = module.project.network_mode
}

output "storage_account_name" {
  value = module.project.storage_account_name
}

output "file_share_name" {
  value = module.project.file_share_name
}

output "processing_folder_names" {
  value = module.project.processing_folder_names
}

output "container_registry_login_server" {
  value = module.project.container_registry_login_server
}

output "container_registry_name" {
  value = module.project.container_registry_name
}

output "worker_image" {
  value = module.project.worker_image
}

output "worker_image_tag" {
  value = module.project.worker_image_tag
}

output "container_app_environment_name" {
  value = module.project.container_app_environment_name
}

output "container_app_job_names" {
  value = module.project.container_app_job_names
}

output "container_app_job_resource_ids" {
  value = module.project.container_app_job_resource_ids
}

output "function_app_name" {
  value = module.project.function_app_name
}

output "function_app_default_hostname" {
  value = module.project.function_app_default_hostname
}
