#!/bin/bash
# ==============================================================================
# Apply Script for RStudio Cluster Deployment on Azure
#
# Purpose:
#   - Validates environment and dependencies before provisioning.
#   - Deploys a complete RStudio cluster environment in **four phases**:
#       1. Directory + Identity Layer:
#          - Mini Active Directory (Samba 4)
#          - Networking (VNet, subnets, NSGs)
#          - Key Vault for credential storage
#       2. Services Layer:
#          - Azure Files NFS share
#          - NFS-Gateway VM (Linux)
#          - AD Admin Windows Server
#       3. Image Layer:
#          - Builds custom RStudio VM image with R + RStudio using Packer
#       4. Cluster Layer:
#          - Deploys RStudio cluster via VM Scale Set (VMSS)
#          - Cluster joins AD and uses NFS backend
#
# Notes:
#   - Requires `az` (Azure CLI), `terraform`, and `packer` installed/authenticated.
#   - `check_env.sh` validates required environment variables and tools.
#   - Secrets are stored in Key Vault (Phase 1) and retrieved securely.
#   - Latest RStudio image from Phase 3 is discovered for Phase 4 deployment.
# ==============================================================================

set -e  # Exit immediately on any unhandled command failure

# ------------------------------------------------------------------------------
# Pre-flight Check: Validate environment
# Runs `check_env.sh` to ensure:
#   - Azure CLI is logged in and subscription is set
#   - Terraform is installed
#   - Packer is installed
#   - Required variables (subscription ID, tenant ID, etc.) are present
# ------------------------------------------------------------------------------
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi

# ------------------------------------------------------------------------------
# Phase 1: Deploy Directory + Identity Layer
# - Deploys foundational resources:
#     * Virtual network, subnets, and security groups
#     * Key Vault for secrets storage
#     * Samba-based Mini Active Directory Domain Controller
# ------------------------------------------------------------------------------
cd 01-directory

terraform init
terraform apply -auto-approve

if [ $? -ne 0 ]; then
  echo "ERROR: Terraform apply failed in 01-directory. Exiting."
  exit 1
fi
cd ..

# ------------------------------------------------------------------------------
# Phase 2: Deploy Services Layer
# - Provisions supporting services:
#     * Azure Files (NFS storage account)
#     * NFS-Gateway VM (Linux, domain joined to Mini-AD)
#     * AD Admin Windows Server (management and GUI tools)
# - Discovers the Key Vault name from Phase 1 for secret retrieval
# ------------------------------------------------------------------------------
cd 02-servers

vault=$(az keyvault list \
  --resource-group rstudio-network-rg \
  --query "[?starts_with(name, 'ad-key-vault')].name | [0]" \
  --output tsv)

echo "NOTE: Key Vault for secrets is $vault"

terraform init
terraform apply -var="vault_name=$vault" -auto-approve
cd ..

# ------------------------------------------------------------------------------
# Phase 3: Build RStudio Container
# ------------------------------------------------------------------------------

cd 03-docker/rstudio

# ------------------------------------------------------------------------------
# Dynamically find the ACR name that starts with 'rstudio'
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# Set image repository and tag
# ------------------------------------------------------------------------------
ACR_REPOSITORY="${ACR_NAME}.azurecr.io/rstudio"
IMAGE_TAG="rstudio-server-rc1"
FULL_IMAGE="${ACR_REPOSITORY}:${IMAGE_TAG}"
echo "NOTE: Full image name: ${FULL_IMAGE}"

# ------------------------------------------------------------------------------
# Retrieve RStudio password from Key Vault
# ------------------------------------------------------------------------------
secretsJson=$(az keyvault secret show \
  --name rstudio-credentials \
  --vault-name "$vault" \
  --query value -o tsv)

RSTUDIO_PASSWORD=$(echo "$secretsJson" | jq -r '.password')

if [ -z "$RSTUDIO_PASSWORD" ] || [ "$RSTUDIO_PASSWORD" = "null" ]; then
  echo "ERROR: Failed to retrieve RStudio password."
fi

# ------------------------------------------------------------------------------
# Check if image already exists in ACR before building
# ------------------------------------------------------------------------------
if az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository "rstudio" \
  --query "[?@=='${IMAGE_TAG}']" \
  --output tsv 2>/dev/null | grep -q "${IMAGE_TAG}"; then
  echo "INFO: Image ${FULL_IMAGE} already exists — skipping build."
else
  echo "NOTE: Building and pushing image: ${FULL_IMAGE}"
  docker build \
    --build-arg RSTUDIO_PASSWORD="${RSTUDIO_PASSWORD}" \
    -t "${FULL_IMAGE}" .
  docker push "${FULL_IMAGE}"
fi

cd ..
cd ..

# ------------------------------------------------------------------------------
# Phase 4: Deploy AKS Cluster
# ------------------------------------------------------------------------------

cd 04-aks
terraform init
terraform apply -var="vault_name=$vault" \
                -auto-approve

cd ..
echo "NOTE: Azure RStudio Cluster deployment completed successfully."

# Validate that the cluster is ready.

./validate.sh
