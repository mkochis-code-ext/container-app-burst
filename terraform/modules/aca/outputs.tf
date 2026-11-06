output "environment_name" {
  value = azapi_resource.environment.name
}

output "environment_default_domain" {
  value = azapi_resource.environment.output.properties.defaultDomain
}

output "environment_static_ip_address" {
  value = azapi_resource.environment.output.properties.staticIp
}

output "job_names" {
  value = {
    for key, job in azurerm_container_app_job.worker : key => job.name
  }
}

output "job_resource_ids" {
  value = {
    for key, job in azurerm_container_app_job.worker : key => job.id
  }
}

output "worker_identity_principal_id" {
  value = azurerm_user_assigned_identity.worker.principal_id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}
