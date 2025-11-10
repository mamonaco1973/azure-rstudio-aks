# ==================================================================================================
# Azure Bastion Deployment
# - Creates Network Security Group (NSG) for Bastion
# - Allocates a public IP for Bastion
# - Deploys the Bastion Host in its own subnet
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Allocate a Public IP for the Bastion host
# --------------------------------------------------------------------------------------------------
resource "azurerm_public_ip" "bastion_ip" {
  name                = "bastion-public-ip"
  location            = azurerm_resource_group.ad.location
  resource_group_name = azurerm_resource_group.ad.name
  allocation_method   = "Static"     # Bastion requires static IP
  sku                 = "Standard"   # Bastion requires Standard SKU
}

# --------------------------------------------------------------------------------------------------
# Deploy the Azure Bastion host
# --------------------------------------------------------------------------------------------------
resource "azurerm_bastion_host" "bastion_host" {
  name                = "bastion-host"
  location            = azurerm_resource_group.ad.location
  resource_group_name = azurerm_resource_group.ad.name

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_ip.id
  }
}
