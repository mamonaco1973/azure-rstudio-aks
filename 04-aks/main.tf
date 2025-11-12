# ==========================================================================================
# Azure Provider and Data Sources
# ------------------------------------------------------------------------------------------
# This configuration:
#   - Defines the AzureRM provider (required boilerplate)
#   - Retrieves subscription and client context for reference
#   - Looks up existing resources (resource group, custom image, network, subnet, key vault)
# ==========================================================================================

# ------------------------------------------------------------------------------------------
# Provider version constraints (MUST be in a `terraform {}` block)
# ------------------------------------------------------------------------------------------
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"          # <-- REQUIRED for the `kubernetes {}` block
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

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

data "azurerm_resource_group" "network_rg" {
  name = var.network_group_name
}

# ------------------------------------------------------------------------------------------
# Virtual Network Lookup
# - Existing VNet where resources will be placed
# ------------------------------------------------------------------------------------------
data "azurerm_virtual_network" "cluster_vnet" {
  name                = var.vnet_name
  resource_group_name = data.azurerm_resource_group.network_rg.name
}

# -----------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------
# Key Vault Lookup
# - Existing Key Vault used for credentials and secrets
# ------------------------------------------------------------------------------------------
data "azurerm_key_vault" "ad_key_vault" {
  name                = var.vault_name
  resource_group_name = data.azurerm_resource_group.network_rg.name
}

# ---------------------------------------------------------
# Azure Container Registry Lookup (ACR)
# ---------------------------------------------------------
data "azurerm_container_registry" "rstudio_acr" {
  name                = var.acr_name # Registry name provided via Terraform variable
  resource_group_name = data.azurerm_resource_group.aks_rg.name
  # Used to grant ACR Pull permissions to AKS identity and to reference private image URIs.
}

# ---------------------------------------------------------
# Subnet Lookup (for AKS Node Pool)
# ---------------------------------------------------------
data "azurerm_subnet" "aks_subnet" {
  name                 = "vm-subnet"                                    # Subnet that AKS will use for worker nodes
  virtual_network_name = data.azurerm_virtual_network.cluster_vnet.name # Ensure subnet is in the correct VNet
  resource_group_name  = data.azurerm_resource_group.network_rg.name
  # Must be delegated to "Microsoft.ContainerService/managedClusters" if using Azure CNI
}

