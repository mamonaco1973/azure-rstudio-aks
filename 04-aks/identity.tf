# ---------------------------------------------------------
# User-Assigned Managed Identity for AKS Workload Identity
# ---------------------------------------------------------

# This identity will be bound to Kubernetes service accounts via federated identity credentials.
# It allows AKS pods to securely access Azure resources like ACR and Cosmos DB without needing secrets.

resource "azurerm_user_assigned_identity" "k8s_identity" {
  location            = data.azurerm_resource_group.aks_rg.location # Place identity in same region as AKS cluster
  name                = "k8s-identity"                              # Friendly name for tracking in Azure portal
  resource_group_name = data.azurerm_resource_group.aks_rg.name     # Identity lives in the same RG as AKS
}

resource "azurerm_role_assignment" "k8s_identity_network_contributor" {
  scope                = data.azurerm_resource_group.aks_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.k8s_identity.principal_id
}

# ================================================================================
# Role Assignment : AKS Identity Key Vault Access
# ------------------------------------------------------------------------------
# Grants the AKS managed identity read-only access to Key Vault secrets using
# the built-in "Key Vault Secrets User" role.
# ================================================================================

resource "azurerm_role_assignment" "k8s_keyvault_access" {
  scope                = data.azurerm_key_vault.ad_key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.k8s_identity.principal_id
}

# ================================================================================
# Federated Identity : AKS Service Account Binding
# ------------------------------------------------------------------------------
# Binds the Kubernetes Service Account to the AKS managed identity to enable
# Workload Identity token exchange for Key Vault access.
# ================================================================================

resource "azurerm_federated_identity_credential" "keyvault_sa_binding" {
  name                = "keyvault-federated-cred"
  resource_group_name = data.azurerm_resource_group.aks_rg.name
  parent_id           = azurerm_user_assigned_identity.k8s_identity.id
  issuer              = azurerm_kubernetes_cluster.rstudio_aks.oidc_issuer_url
  subject             = "system:serviceaccount:default:keyvault-access-sa"
  audience            = ["api://AzureADTokenExchange"]
}


# ---------------------------------------------------------
# Federated Identity Credential for Cluster Autoscaler
# ---------------------------------------------------------

# Binds the K8s service account `cluster-autoscaler` in `kube-system` to the Azure managed identity.
# Enables the autoscaler to authenticate to Azure (e.g., to interact with VMSS APIs).

resource "azurerm_federated_identity_credential" "autoscaler" {
  name                = "autoscaler-federated"                         # Unique name for the autoscaler federated credential
  resource_group_name = data.azurerm_resource_group.aks_rg.name        # Same RG as other components
  parent_id           = azurerm_user_assigned_identity.k8s_identity.id # Attach to the shared identity

  issuer   = azurerm_kubernetes_cluster.rstudio_aks.oidc_issuer_url   # AKS cluster's OIDC issuer URL
  subject  = "system:serviceaccount:kube-system:cluster-autoscaler" # Kubernetes SA for the autoscaler workload
  audience = ["api://AzureADTokenExchange"]                         # Audience required for token validation in Azure
}