# ==================================================================================================
# Virtual Network, Subnets, NAT Gateway, and Network Security Groups
# - Creates VNet with dedicated subnets for VMs, mini-AD, Bastion, and App Gateway
# - Adds NAT Gateway for explicit outbound internet access
# - Configures NSGs with explicit inbound + outbound rules
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Virtual Network
# --------------------------------------------------------------------------------------------------
resource "azurerm_virtual_network" "aks_vnet" {
  name                = "aks-vnet"
  address_space       = ["10.0.0.0/8"] # Overall VNet range
  location            = azurerm_resource_group.ad.location
  resource_group_name = azurerm_resource_group.ad.name
}

# --------------------------------------------------------------------------------------------------
# NAT Gateway + Public IP
# --------------------------------------------------------------------------------------------------
resource "azurerm_public_ip" "nat_gateway_pip" {
  name                = "nat-gateway-pip"
  location            = azurerm_resource_group.ad.location
  resource_group_name = azurerm_resource_group.ad.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "vm_nat_gateway" {
  name                    = "vm-nat-gateway"
  location                = azurerm_resource_group.ad.location
  resource_group_name     = azurerm_resource_group.ad.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
}

resource "azurerm_nat_gateway_public_ip_association" "nat_gw_pip_assoc" {
  nat_gateway_id       = azurerm_nat_gateway.vm_nat_gateway.id
  public_ip_address_id = azurerm_public_ip.nat_gateway_pip.id
}

# --------------------------------------------------------------------------------------------------
# Network Security Group for VM Subnet
# --------------------------------------------------------------------------------------------------
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "vm-nsg"
  location            = azurerm_resource_group.ad.location
  resource_group_name = azurerm_resource_group.ad.name

  # Inbound Rules
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SMB"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "445"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-RStudio"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8787"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

    security_rule {
    name                       = "Allow-NFS"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2049"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1006
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Outbound Rules
  security_rule {
    name                       = "Allow-All-Internet-Outbound"
    priority                   = 2001
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# --------------------------------------------------------------------------------------------------
# Subnets (created sequentially to avoid 409 conflicts)
# --------------------------------------------------------------------------------------------------

# VM Subnet
resource "azurerm_subnet" "vm_subnet" {
  name                          = "vm-subnet"
  resource_group_name           = azurerm_resource_group.ad.name
  virtual_network_name          = azurerm_virtual_network.aks_vnet.name
  address_prefixes              = ["10.240.0.0/24"]   
  default_outbound_access_enabled = false
  service_endpoints = ["Microsoft.Storage"]
  depends_on = [azurerm_virtual_network.aks_vnet]
}

# Mini-AD Subnet
resource "azurerm_subnet" "mini_ad_subnet" {
  name                          = "mini-ad-subnet"
  resource_group_name           = azurerm_resource_group.ad.name
  virtual_network_name          = azurerm_virtual_network.aks_vnet.name
  address_prefixes              = ["10.240.1.0/24"]
  default_outbound_access_enabled = false

  depends_on = [azurerm_subnet.vm_subnet]
}

# Bastion Subnet
resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.ad.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.240.2.0/24"]
  default_outbound_access_enabled = false

  depends_on = [azurerm_subnet.mini_ad_subnet]
}
# --------------------------------------------------------------------------------------------------
# Associations (serialized per subnet)
# --------------------------------------------------------------------------------------------------

# NAT GW association -> VM subnet
resource "azurerm_subnet_nat_gateway_association" "vm_nat_assoc" {
  subnet_id      = azurerm_subnet.vm_subnet.id
  nat_gateway_id = azurerm_nat_gateway.vm_nat_gateway.id

  depends_on = [
    azurerm_subnet.vm_subnet,
    azurerm_nat_gateway_public_ip_association.nat_gw_pip_assoc
  ]
}

# NSG association -> VM subnet (after NAT GW is applied)
resource "azurerm_subnet_network_security_group_association" "vm_nsg_assoc" {
  subnet_id                 = azurerm_subnet.vm_subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id

  depends_on = [azurerm_subnet_nat_gateway_association.vm_nat_assoc]
}

# NAT GW association -> Mini-AD subnet
resource "azurerm_subnet_nat_gateway_association" "mini_ad_nat_assoc" {
  subnet_id      = azurerm_subnet.mini_ad_subnet.id
  nat_gateway_id = azurerm_nat_gateway.vm_nat_gateway.id

  depends_on = [
    azurerm_subnet.mini_ad_subnet,
    azurerm_nat_gateway_public_ip_association.nat_gw_pip_assoc
  ]
}

