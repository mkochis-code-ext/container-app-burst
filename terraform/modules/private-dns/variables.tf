variable "resource_group_name" {
  type = string
}

variable "virtual_network_id" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "zone_names" {
  type = list(string)
}
