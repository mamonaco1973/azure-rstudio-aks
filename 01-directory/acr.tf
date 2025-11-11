# ---------------------------------------------------------
# Random Suffix Generator for Globally Unique ACR Name
# ---------------------------------------------------------

resource "random_string" "acr_suffix" {
  length  = 8         # Generates an 8-character string
  special = false     # Excludes special characters (e.g., !@#)
  upper   = false     # Lowercase only to comply with ACR naming rules

  # Purpose:
  # Ensures the ACR name is globally unique without requiring manual changes.
  # ACR names must be DNS-compliant, lowercase, alphanumeric, and globally unique.
}

# ---------------------------------------------------------
# Azure Container Registry (ACR) for Storing Docker Images
# ---------------------------------------------------------

resource "azurerm_container_registry" "rstudio_acr" {
  name = "rstudio${random_string.acr_suffix.result}"
  # Dynamically generates a unique ACR name like 'flaskappx8s7kp2a'
  # Avoids naming collisions across Azure subscriptions and tenants

  resource_group_name = azurerm_resource_group.aks.name
  # Deploys the ACR into the same resource group as the AKS cluster

  location = azurerm_resource_group.aks.location
  # Ensures ACR is created in the same Azure region for lower latency and reduced egress costs

  sku = "Basic"
  # SKU Options:
  #   - Basic: Good for small projects, dev/test environments
  #   - Standard: Recommended for most production workloads
  #   - Premium: Enables geo-replication, private endpoints, and content trust

  admin_enabled = true
  # Enables the ACR admin user for username/password authentication.
  # Useful for quick testing or scripting, but **not recommended for production**.
  # Prefer `az acr login` via Azure CLI or using managed identity with AKS.
}