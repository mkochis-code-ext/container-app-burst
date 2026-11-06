# The tenant policy "Subnets must have a Network Security Group" denies a subnet that is
# created without an NSG. azurerm_subnet cannot attach an NSG at creation time (the
# azurerm_subnet_network_security_group_association is a second call), so the subnets are
# defined inline on the virtual network with their NSG already attached.
locals {
  subnet_names = {
    container_apps    = "snet-container-apps"
    function          = "snet-function"
    private_endpoints = "snet-private-endpoints"
  }
}

# Default rules only: allow VNet and load balancer inbound, deny Internet inbound, and
# allow outbound (Container Apps and Functions need outbound access to Microsoft services).
resource "azurerm_network_security_group" "subnet" {
  for_each = local.subnet_names

  name                = "nsg-${each.value}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags

  subnet {
    name             = local.subnet_names.container_apps
    address_prefixes = ["10.40.1.0/27"]
    security_group   = azurerm_network_security_group.subnet["container_apps"].id

    # Required for workload profiles environments.
    delegation {
      name = "containerapps"

      service_delegation {
        name    = "Microsoft.App/environments"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }

  subnet {
    name             = local.subnet_names.function
    address_prefixes = ["10.40.2.0/27"]
    security_group   = azurerm_network_security_group.subnet["function"].id

    # Flex Consumption Function apps integrate through this delegation.
    delegation {
      name = "functionapp"

      service_delegation {
        name    = "Microsoft.App/environments"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }

  subnet {
    name                              = local.subnet_names.private_endpoints
    address_prefixes                  = ["10.40.3.0/27"]
    security_group                    = azurerm_network_security_group.subnet["private_endpoints"].id
    private_endpoint_network_policies = "Disabled"
  }
}
