#!/bin/bash
# ==============================================================================
# Apply Script for RStudio Cluster Deployment on Azure (AKS)
#
# Purpose:
#   - Validates environment and dependencies before provisioning.
#   - Deploys a complete RStudio cluster environment in **five phases**:
#       1. Directory + Identity Layer:
#          - Mini Active Directory (Samba 4)
#          - Virtual network, subnets, and network security groups
#          - Key Vault for credential storage
#       2. Services Layer:
#          - Azure Files NFS share
#          - NFS-Gateway VM (Linux, domain joined)
#          - AD Admin Windows Server (GUI and tools)
#       3. Image Layer:
#          - Builds and publishes custom RStudio container image to ACR
#       4. Cluster Layer:
#          - Deploys RStudio cluster on Azure Kubernetes Service (AKS)
#          - Uses ACR image, mounts Azure Files via CSI driver
#          - Integrates with Active Directory for authentication
#       5. Access Layer:
#          - Configures kubectl access and attaches ACR to the AKS cluster
#
# Notes:
#   - Requires `az`, `terraform`, `packer`, `docker`, and `jq` installed.
#   - `check_env.sh` validates environment variables and tools.
#   - Secrets are created in Key Vault (Phase 1) and retrieved securely.
#   - The latest RStudio container from Phase 3 is deployed to AKS in Phase 4.
# ==============================================================================
set -e  # Exit immediately if any unhandled command fails

# ------------------------------------------------------------------------------
# Pre-flight Check: Validate environment
# Runs `check_env.sh` to ensure:
#   - Azure CLI is logged in and subscription is set
#   - Terraform and Packer are installed
#   - Docker and jq are available
#   - Required variables (tenant ID, subscription ID, etc.) are present
# ------------------------------------------------------------------------------
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi

# ------------------------------------------------------------------------------
# Phase 1: Deploy Directory + Identity Layer
# Creates foundational resources for domain integration:
#   - Virtual network, subnets, and security groups
#   - Azure Key Vault for secrets
#   - Samba-based Mini Active Directory domain controller
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
# Provisions core services supporting the Kubernetes cluster:
#   - Azure Files NFS share for user home directories
#   - NFS-Gateway VM (Linux, joined to Mini-AD)
#   - AD Admin Windows Server (management and GUI)
#   - Retrieves Key Vault name from Phase 1 for secret access
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
# Phase 3: Build RStudio Container Image
# Builds and pushes the RStudio container to Azure Container Registry (ACR).
# ------------------------------------------------------------------------------
cd 03-docker/rstudio

# ------------------------------------------------------------------------------
# Locate the Azure Container Registry name beginning with 'rstudio'
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
# Define repository, tag, and full image path for RStudio container
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
# Build container image if not already present in ACR
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

cd ../..

# ------------------------------------------------------------------------------
# Phase 4: Deploy AKS Cluster
# Deploys Azure Kubernetes Service (AKS) cluster hosting RStudio pods:
#   - Installs Helm charts and Terraform manifests for AKS setup
#   - Mounts Azure Files via CSI driver for persistent home directories
#   - Uses Key Vault secrets and ACR image built in previous phases
# ------------------------------------------------------------------------------
cd 04-aks
terraform init
terraform apply -var="vault_name=$vault" \
                -var="acr_name=$ACR_NAME" \
                -auto-approve
cd ..
echo "NOTE: Azure AKS RStudio cluster deployment completed successfully."

# ------------------------------------------------------------------------------
# Phase 5: Configure kubectl Access
# Attaches ACR, downloads kubeconfig, and validates AKS access.
# ------------------------------------------------------------------------------
rm -rf ~/.kube  # Remove any existing kubeconfig
az aks get-credentials \
  --resource-group rstudio-aks-rg \
  --name rstudio-aks
az aks update \
  --name rstudio-aks \
  --resource-group rstudio-aks-rg \
  --attach-acr $ACR_NAME > /dev/null

# ------------------------------------------------------------------------------
# Validate final Kubernetes deployment and RStudio service availability
# ------------------------------------------------------------------------------
./validate.sh
