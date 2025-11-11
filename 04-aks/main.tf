# ==========================================================================================
# Azure Provider and Data Sources
# ------------------------------------------------------------------------------------------
# This configuration:
#   - Defines the AzureRM provider (required boilerplate)
#   - Retrieves subscription and client context for reference
#   - Looks up existing resources (resource group, custom image, network, subnet, key vault)
# ==========================================================================================


# ------------------------------------------------------------------------------------------
# Azure Provider
# ------------------------------------------------------------------------------------------
provider "azurerm" {
  features {} # Required boilerplate to enable all default provider features
}


# ------------------------------------------------------------------------------------------
# Subscription and Client Context
# ------------------------------------------------------------------------------------------

# Subscription metadata (e.g., ID, display name)
data "azurerm_subscription" "primary" {}

# Client metadata (e.g., tenant ID, object ID, client ID, subscription)
data "azurerm_client_config" "current" {}


# ------------------------------------------------------------------------------------------
# Resource Group Lookups
# - Existing resource group used for image, network, and secrets
# ------------------------------------------------------------------------------------------
data "azurerm_resource_group" "aks_rg" {
  name = var.aks_group_name
}

data "azurerm_resource_group" "project_rg" {
  name = var.project_group_name
}

# ------------------------------------------------------------------------------------------
# Virtual Network Lookup
# - Existing VNet where resources will be placed
# ------------------------------------------------------------------------------------------
data "azurerm_virtual_network" "cluster_vnet" {
  name                = var.vnet_name
  resource_group_name = data.azurerm_resource_group.project_rg.name
}

# -----------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------
# Key Vault Lookup
# - Existing Key Vault used for credentials and secrets
# ------------------------------------------------------------------------------------------
data "azurerm_key_vault" "ad_key_vault" {
  name                = var.vault_name
  resource_group_name = data.azurerm_resource_group.project_rg.name
}

# ---------------------------------------------------------
# Azure Container Registry Lookup (ACR)
# ---------------------------------------------------------
data "azurerm_container_registry" "rstudio_acr" {
  name                = var.acr_name  # Registry name provided via Terraform variable
  resource_group_name = data.azurerm_resource_group.aks_rg.name
  # Used to grant ACR Pull permissions to AKS identity and to reference private image URIs.
}

