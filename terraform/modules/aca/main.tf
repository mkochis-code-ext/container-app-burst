locals {
  gpu_profiles = {
    T4 = {
      name   = "gpu-t4"
      type   = "Consumption-GPU-NC8as-T4"
      cpu    = 8
      memory = "56Gi"
    }
    A100 = {
      name   = "gpu-a100"
      type   = "Consumption-GPU-NC24-A100"
      cpu    = 24
      memory = "220Gi"
    }
  }

  selected_gpu_profile = local.gpu_profiles[var.worker_gpu_type]

  # All three are serverless profiles; they take no node counts.
  workload_profiles = [
    { name = "Consumption", type = "Consumption" },
    { name = local.gpu_profiles.T4.name, type = local.gpu_profiles.T4.type },
    { name = local.gpu_profiles.A100.name, type = local.gpu_profiles.A100.type }
  ]
  worker_image = "${var.worker_image}:${var.worker_image_tag}"
  jobs = {
    for key in var.job_keys : key => {
      name = "${var.job_name}-${lower(key)}"
    }
  }
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.environment_name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# The azurerm provider cannot create Consumption GPU workload profiles: it always sends
# minimumCount/maximumCount, which the API rejects for them
# (hashicorp/terraform-provider-azurerm#31763). The environment is therefore defined
# with the Microsoft-published azapi provider, and only this resource uses it.
resource "azapi_resource" "environment" {
  type      = "Microsoft.App/managedEnvironments@2025-07-01"
  name      = var.environment_name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      vnetConfiguration = {
        infrastructureSubnetId = var.container_apps_subnet_id
        internal               = true
      }
      infrastructureResourceGroup = "ME_${var.environment_name}"
      publicNetworkAccess         = "Disabled"
      zoneRedundant               = false
      appLogsConfiguration = {
        destination = "log-analytics"
        logAnalyticsConfiguration = {
          customerId = azurerm_log_analytics_workspace.main.workspace_id
        }
      }
      workloadProfiles = [
        for profile in local.workload_profiles : {
          name                = profile.name
          workloadProfileType = profile.type
        }
      ]
    }
  }

  sensitive_body = {
    properties = {
      appLogsConfiguration = {
        logAnalyticsConfiguration = {
          sharedKey = azurerm_log_analytics_workspace.main.primary_shared_key
        }
      }
    }
  }

  response_export_values = [
    "properties.defaultDomain",
    "properties.staticIp"
  ]
}

resource "azurerm_container_app_environment_storage" "processing" {
  name                         = "processing-files"
  container_app_environment_id = azapi_resource.environment.id
  account_name                 = var.storage_account_name
  access_key                   = var.storage_account_primary_key
  share_name                   = var.file_share_name
  access_mode                  = "ReadWrite"
}

# The registry pull is validated while the job is created, so the identity must
# exist and already hold AcrPull. A per-job system-assigned identity cannot do
# that because it only exists after the job is created.
resource "azurerm_user_assigned_identity" "worker" {
  name                = "id-${var.environment_name}-worker"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "worker_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_container_app_job" "worker" {
  for_each                     = local.jobs
  name                         = each.value.name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azapi_resource.environment.id
  replica_timeout_in_seconds   = 1800
  replica_retry_limit          = 0
  workload_profile_name        = local.selected_gpu_profile.name
  tags                         = var.tags

  lifecycle {
    precondition {
      condition     = length(each.value.name) <= 32 && can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", each.value.name))
      error_message = "Container Apps Job name '${each.value.name}' must be 2-32 lowercase letters, digits or hyphens, start with a letter and end with a letter or digit. Shorten the folder key, environment_prefix or suffix."
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.worker.id]
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.worker.id
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "number-worker"
      image  = local.worker_image
      cpu    = local.selected_gpu_profile.cpu
      memory = local.selected_gpu_profile.memory

      env {
        name  = "WORKER_INPUT_DIR"
        value = "/mnt/processing/${each.key}/Input"
      }

      env {
        name  = "WORKER_WEIGHTS_DIR"
        value = "/mnt/processing/${each.key}/Weights"
      }

      env {
        name  = "WORKER_OUTPUT_DIR"
        value = "/mnt/processing/${each.key}/Output"
      }

      env {
        name  = "WORKER_WEIGHT_FILE"
        value = "weight.txt"
      }

      volume_mounts {
        name = "processing-files"
        path = "/mnt/processing"
      }
    }

    volume {
      name         = "processing-files"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.processing.name
    }
  }

  depends_on = [
    azurerm_container_app_environment_storage.processing,
    azurerm_role_assignment.worker_acr_pull
  ]
}

resource "azurerm_private_dns_zone" "environment" {
  name                = azapi_resource.environment.output.properties.defaultDomain
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "environment" {
  name                  = "container-apps-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.environment.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_a_record" "environment_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.environment.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azapi_resource.environment.output.properties.staticIp]
  tags                = var.tags
}
