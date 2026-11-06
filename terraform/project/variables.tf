variable "environment_prefix" {
  type = string
}

variable "suffix" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "workload" {
  type = string
}

variable "location" {
  type = string
}

variable "gpu_type" {
  type = string

  validation {
    condition     = contains(["T4", "A100"], var.gpu_type)
    error_message = "gpu_type must be T4 or A100."
  }
}

variable "network_mode" {
  type = string

  validation {
    condition     = contains(["bootstrap", "private", "maintenance"], var.network_mode)
    error_message = "network_mode must be bootstrap, private, or maintenance."
  }
}

variable "worker_image" {
  type = string
}

variable "worker_image_tag" {
  type = string
}
