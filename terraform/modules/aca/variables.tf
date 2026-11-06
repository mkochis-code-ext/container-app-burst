variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "environment_name" {
  type = string
}

variable "job_name" {
  type = string
}

variable "container_apps_subnet_id" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "storage_account_primary_key" {
  type      = string
  sensitive = true
}

variable "file_share_name" {
  type = string
}

variable "acr_id" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "worker_gpu_type" {
  type = string

  validation {
    condition     = contains(["T4", "A100"], var.worker_gpu_type)
    error_message = "worker_gpu_type must be T4 or A100."
  }
}

variable "worker_image" {
  type = string
}

variable "worker_image_tag" {
  type = string
}

variable "virtual_network_id" {
  type = string
}

variable "job_keys" {
  description = "Job keys. Each key is also the top-level folder on the file share (<key>/Input, <key>/Output, <key>/Weights)."
  type        = list(string)
}
