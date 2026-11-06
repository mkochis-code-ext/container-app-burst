variable "environment_prefix" {
  description = "Environment name used in resource names and tags."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region. East US supports both T4 and A100 serverless GPU profiles."
  type        = string
  default     = "eastus"
}

variable "workload" {
  description = "Workload identifier used in names."
  type        = string
  default     = "containerappburst"
}

variable "gpu_type" {
  description = "GPU profile used by the worker Job. Choose T4 or A100."
  type        = string

  validation {
    condition     = contains(["T4", "A100"], var.gpu_type)
    error_message = "gpu_type must be T4 or A100."
  }
}

variable "network_mode" {
  description = <<-EOT
    Deployment phase.
    bootstrap   - phase 1: Storage, Key Vault, ACR and the Function are publicly reachable (authenticated); no private endpoints and no Container Apps.
    private     - phase 2 / steady state: private endpoints and DNS exist, public access is off, and the Container Apps environment and Jobs are created.
    maintenance - same as private, but public access is temporarily re-enabled so the data plane can be reached for day-2 changes.
  EOT
  type        = string
  default     = "bootstrap"

  validation {
    condition     = contains(["bootstrap", "private", "maintenance"], var.network_mode)
    error_message = "network_mode must be bootstrap, private, or maintenance."
  }
}

variable "worker_image" {
  description = "Worker image repository URI before the image tag."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart-jobs"
}

variable "worker_image_tag" {
  description = "Worker image tag."
  type        = string
  default     = "latest"
}

variable "tags" {
  description = "Base resource tags."
  type        = map(string)
  default     = {}
}
