#!/bin/bash
# ==============================================================================
# Destroy Script for Azure RStudio Cluster + Mini Active Directory
#
# PURPOSE:
#   - Fully decommission the Azure RStudio Cluster environment, including:
#       * RStudio VM Scale Set (VMSS), custom images, networking, and storage
#       * Samba-based Mini Active Directory (Mini-AD) domain controller
#       * Key Vault and associated secrets/roles
#
# EXECUTION ORDER:
#   1. Phase 1 – Cluster Layer (RStudio VMSS, custom images)
#   2. Phase 2 – Server Layer (AD admin server and NFS gateway)
#   3. Phase 3 – Directory Layer (Key Vault, Mini-AD VM and roles)
#
# REQUIREMENTS:
#   - Azure CLI (`az`), Terraform, and jq installed and authenticated
#
# WARNINGS:
#   - This script PERMANENTLY deletes all resources
#   - Order of destruction is critical; do not re-sequence phases
# ==============================================================================

set -e  # Exit immediately if any command fails

# ------------------------------------------------------------------------------
# Phase 1: Destroy Cluster Layer
# - Removes RStudio VMSS, supporting infra, and NFS storage
# - Deletes all custom RStudio images in the resource group
# ------------------------------------------------------------------------------

cd 04-aks


RG_NAME="rstudio-servers-rg"

STORAGE_ACCOUNT=$(az storage account list \
  --resource-group $RG_NAME \
  --query "[?starts_with(name, 'nfs')].name | [0]" \
  --output tsv)

if [ -z "$STORAGE_ACCOUNT" ]; then
  echo "ERROR: No storage account starting with 'nfs' found in RG $RG_NAME"
  exit 1
fi

echo "NOTE: Storage account: $STORAGE_ACCOUNT"

RESOURCE_GROUP="rstudio-aks-rg"
ACR_NAME=$(az acr list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'rstudio')].name | [0]" \
  --output tsv)

if [ -z "$ACR_NAME" ] || [ "$ACR_NAME" = "null" ]; then
  echo "ERROR: Failed to retrieve ACR name."
else
  echo "NOTE: Using ACR: $ACR_NAME"
  az acr login --name "$ACR_NAME" > /dev/null  
fi


vault=$(az keyvault list \
   --resource-group rstudio-network-rg \
   --query "[?starts_with(name, 'ad-key-vault')].name | [0]" \
   --output tsv)

echo "NOTE: Using Key Vault: $vault"

terraform init
terraform destroy -var="vault_name=$vault" \
                  -var="acr_name=$ACR_NAME" \
                  -var="storage_account=$STORAGE_ACCOUNT" \
                  -auto-approve

cd ..

# ------------------------------------------------------------------------------
# Phase 2: Destroy Server Layer
# - Tears down the AD Admin VM and NFS Gateway
# - References Key Vault to ensure secrets are available for cleanup
# ------------------------------------------------------------------------------
cd 02-servers

terraform init
terraform destroy -var="vault_name=$vault" \
                  -target=azurerm_private_dns_zone_virtual_network_link.file_link \
                  -auto-approve
sleep 60 # Wait for DNS link deletion to propagate
terraform destroy -var="vault_name=$vault" \
                  -auto-approve

cd ..

# ------------------------------------------------------------------------------
# Phase 3: Destroy Directory Layer
# - Removes foundational resources such as Mini-AD, Key Vault,
#   and resource group–level roles
# - Executed last to ensure no dependencies remain
# ------------------------------------------------------------------------------
cd 01-directory

terraform init
terraform destroy -auto-approve

cd ..
echo "NOTE: Azure RStudio AKS Cluster and Mini-AD environment destroyed successfully."
