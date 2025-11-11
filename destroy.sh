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
# cd 04-aks

vault=$(az keyvault list \
   --resource-group rstudio-network-rg \
   --query "[?starts_with(name, 'ad-key-vault')].name | [0]" \
   --output tsv)

echo "NOTE: Using Key Vault: $vault"

# rstudio_image_name=$(az image list \
#   --resource-group rstudio-vmss-rg \
#   --query "[?starts_with(name, 'rstudio_image')]|sort_by(@, &name)[-1].name" \
#   --output tsv)

# echo "NOTE: Using the latest image ($rstudio_image_name) in rstudio-vmss-rg."

# if [ -z "$rstudio_image_name" ]; then
#   echo "ERROR: No RStudio image with prefix 'rstudio_image' found. Exiting."
#   exit 1
# fi

# secretsJson=$(az keyvault secret show \
#   --name ubuntu-credentials \
#   --vault-name ${vault} \
#   --query value \
#   -o tsv)

# password=$(echo "$secretsJson" | jq -r '.password')

# storage_account=$(az storage account list \
#   --resource-group rstudio-servers-rg \
#   --query "[?starts_with(name, 'nfs')].name | [0]" \
#   -o tsv 2>/dev/null)

# terraform init
# terraform destroy -var="vault_name=$vault" \
#                   -var="nfs_storage_account=$storage_account" \
#                   -var="ubuntu_password=$password" \
#                   -var="rstudio_image_name=$rstudio_image_name" \
#                   -auto-approve

# cd ..

# az image list \
#   --resource-group "rstudio-vmss-rg" \
#   --query "[].name" \
#   -o tsv | while read -r IMAGE; do
#     echo "NOTE: Deleting image: $IMAGE"
#     az image delete \
#       --name "$IMAGE" \
#       --resource-group "rstudio-vmss-rg" \
#       || echo "WARNING: Failed to delete $IMAGE — skipping"
# done

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
