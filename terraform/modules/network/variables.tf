variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "vnet_name" {
  type = string
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.40.0.0/16"]
}
