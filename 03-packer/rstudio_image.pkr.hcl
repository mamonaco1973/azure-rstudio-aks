# ==========================================================================================
# Packer Build: RStudio Custom Image on Ubuntu 24.04 (Noble) for Azure
# ------------------------------------------------------------------------------------------
# Purpose:
#   - Uses Packer to build a custom Azure Managed Image containing RStudio Server
#   - Starts from the official Canonical Ubuntu 24.04 LTS base image
#   - Installs prerequisites (base packages, Azure CLI, RStudio Server)
#   - Produces a tagged, timestamped Managed Image for later use in Terraform or VM launches
# ==========================================================================================


# ------------------------------------------------------------------------------------------
# Packer Plugin Configuration
# - Defines the Azure ARM plugin required to interact with Microsoft Azure
# ------------------------------------------------------------------------------------------
packer {
  required_plugins {
    azure = {
      source   = "github.com/hashicorp/azure"            # Official Azure plugin for Packer
      version  = "~> 2"                                  # Lock to major version 2 for stability
    }
  }
}

# ------------------------------------------------------------------------------------------
# Local Variables
# - Generates a compact timestamp for unique image naming
# ------------------------------------------------------------------------------------------
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "") # Format: YYYYMMDDHHMMSS
}

# ------------------------------------------------------------------------------------------
# Variables: Build-Time Inputs
# - Credentials and context required for Azure authentication
# - Resource placement for the resulting custom image
# ------------------------------------------------------------------------------------------
variable "client_id" {
  description = "Azure AD Application (Client) ID"
  type        = string
}

variable "client_secret" {
  description = "Azure AD Application (Client) Secret"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure Tenant (Directory) ID"
  type        = string
}

variable "resource_group" {
  description = "Azure Resource Group where the custom image will be created"
  type        = string
}

# ------------------------------------------------------------------------------------------
# Source Block: Azure ARM Builder
# - Launches a temporary VM from the Canonical Ubuntu 24.04 Marketplace image
# - Installs required software and configuration
# - Captures a reusable Managed Image with a timestamp-based name
# ------------------------------------------------------------------------------------------
source "azure-arm" "rstudio_image" {
  # Azure authentication context
  client_id       = var.client_id
  client_secret   = var.client_secret
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # Base image (Ubuntu 24.04 LTS from Canonical)
  image_offer     = "ubuntu-24_04-lts"                   # Marketplace offer name
  image_publisher = "canonical"                          # Publisher: Canonical (Ubuntu)
  image_sku       = "server"                             # Image SKU: server edition
  
  ssh_username    = "ubuntu"                              # Default Ubuntu username

  # Build VM configuration
  location        = "Central US"                          # Azure region
  vm_size         = "Standard_DS1_v2"                       
  os_type         = "Linux"

  os_disk_size_gb           = 64                           # Root disk size

  # Output managed image
  managed_image_name                 = "rstudio_image_${local.timestamp}" # Unique name
  managed_image_resource_group_name  = var.resource_group               # Target RG
}

# ------------------------------------------------------------------------------------------
# Build Block: Provisioning Scripts
# - Executes provisioning scripts inside the temporary VM
# - Each script installs specific components
# ------------------------------------------------------------------------------------------
build {
  sources = ["source.azure-arm.rstudio_image"]  

  # Install base packages and dependencies
  provisioner "shell" {
    script          = "./packages.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install Azure CLI tools
  provisioner "shell" {
    script          = "./azcli.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install and configure RStudio Server
  provisioner "shell" {
    script          = "./rstudio.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }
}
