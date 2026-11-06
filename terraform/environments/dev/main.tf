terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result

  # Required tags are merged last so var.tags cannot override them. Every module
  # receives this map, so all taggable resources are tagged from the first apply.
  tags = merge(
    var.tags,
    {
      Environment     = var.environment_prefix
      ManagedBy       = "Terraform"
      Solution        = "container-app-burst"
      SecurityControl = "Ignore"
    }
  )
}

module "project" {
  source = "../../project"

  environment_prefix = var.environment_prefix
  suffix             = local.suffix
  tags               = local.tags
  workload           = var.workload
  location           = var.location
  gpu_type           = var.gpu_type
  network_mode       = var.network_mode
  worker_image       = var.worker_image
  worker_image_tag   = var.worker_image_tag
}
