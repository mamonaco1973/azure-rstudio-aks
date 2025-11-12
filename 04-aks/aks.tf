# ---------------------------------------------------------
# AKS Cluster Resource Definition (with node labels)
# ---------------------------------------------------------
resource "azurerm_kubernetes_cluster" "rstudio_aks" {
  name                = "rstudio-aks"                               # Name of the Azure Kubernetes Service (AKS) cluster
  location            = data.azurerm_resource_group.aks_rg.location # Use the same region as the target resource group
  resource_group_name = data.azurerm_resource_group.aks_rg.name     # Reference the existing resource group
  dns_prefix          = "rstudio"                                   # Used to create the public FQDN for the AKS API server

  # -------------------------------------------------------
  # Default Node Pool Configuration
  # -------------------------------------------------------
  default_node_pool {
    name                = "default"         # Name of the system node pool
    min_count           = 1                 # Minimum node count for autoscaler
    max_count           = 3                 # Maximum node count for autoscaler
    vm_size             = "Standard_D2s_v3" # VM size used for the nodes
    enable_auto_scaling = true              # Enable cluster autoscaler
    vnet_subnet_id      = data.azurerm_subnet.aks_subnet.id

    # Upgrade strategy for safer and faster rolling upgrades
    upgrade_settings {
      drain_timeout_in_minutes      = 0     # Graceful pod drain wait time is zero (aggressive drain)
      max_surge                     = "10%" # Allow temporary extra nodes during upgrades
      node_soak_duration_in_minutes = 0     # Skip waiting period after upgrades
    }

    # Node labels to assist cluster autoscaler and workload scheduling
    node_labels = {
      cluster-autoscaler-enabled = "true"        # Label to indicate autoscaling is active on this node pool
      cluster-autoscaler-name    = "rstudio-aks" # Custom label (useful for autoscaler selectors)
    }
  }

  # -------------------------------------------------------
  # Networking Configuration
  # -------------------------------------------------------
  network_profile {
    network_plugin    = "azure"    # Use Azure CNI (supports VNet integration, custom IPs per pod)
    load_balancer_sku = "standard" # Use Standard Load Balancer for higher availability and features
  }

  # -------------------------------------------------------
  # OIDC and Workload Identity (For Secure Pod-to-Azure Access)
  # -------------------------------------------------------
  oidc_issuer_enabled       = true # Enables OIDC issuer URL on the cluster (required for federated identity)
  workload_identity_enabled = true # Enables Azure Workload Identity integration with Kubernetes service accounts

  # ==============================================================================================
  # Enable CSI drivers (incl. Azure Files) via storage_profile block
  # ==============================================================================================
  storage_profile {
    file_driver_enabled         = true # Enables Azure Files CSI driver for dynamic volume provisioning
  }

  # -------------------------------------------------------
  # Cluster Identity (User-Assigned Managed Identity)
  # -------------------------------------------------------
  identity {
    type         = "UserAssigned"                                   # Use user-managed identity (preferred for reuse and least privilege)
    identity_ids = [azurerm_user_assigned_identity.k8s_identity.id] # Reference to the managed identity to use
  }
}

# ================================================================================================
# Role Assignment: Grant AKS Kubelet Pull Access to ACR
# ================================================================================================
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = data.azurerm_container_registry.rstudio_acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.rstudio_aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
  # ---------------------------------------------------------------------------------------------
  # Key Points:
  #  - This gives the AKS cluster’s node identity permission to pull images from the ACR.
  #  - It replaces the CLI: az aks update --attach-acr.
  #  - Ensures Terraform fully manages the permission and state.
  # ---------------------------------------------------------------------------------------------
}

# ---------------------------------------------------------
# Kubernetes Provider Configuration (for Terraform)
# ---------------------------------------------------------
provider "kubernetes" {
  # Connects to the AKS cluster using Terraform-provided credentials
  host                   = azurerm_kubernetes_cluster.rstudio_aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.rstudio_aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.rstudio_aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.rstudio_aks.kube_config[0].cluster_ca_certificate)
}

# ================================================================================
# Service Account : Key Vault Access (Workload Identity)
# 
# Defines the Kubernetes Service Account used by pods that need to access
# Azure Key Vault via the AKS managed identity and Workload Identity binding.
# ================================================================================

resource "kubernetes_service_account" "keyvault_access" {
  metadata {
    name      = "keyvault-access-sa" # Service account name for Key Vault access
    namespace = "default"            # Namespace where this SA is created

    annotations = {
      # Binds the SA to the AKS managed identity for token exchange
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.k8s_identity.client_id
    }
  }
}

# ---------------------------------------------------------
# Service Account for Cluster Autoscaler
# ---------------------------------------------------------
resource "kubernetes_service_account" "autoscaler" {
  metadata {
    name      = "cluster-autoscaler" # Name expected by the autoscaler Helm chart or deployment
    namespace = "kube-system"        # System-level namespace (standard location for system services)

    annotations = {
      # Bind to the same managed identity for workload identity access
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.k8s_identity.client_id
    }
  }
}
# ---------------------------------------------------------
# Lookup the AKS-Generated Node Resource Group
# ---------------------------------------------------------
data "azurerm_resource_group" "aks_node_rg" {
  name = azurerm_kubernetes_cluster.rstudio_aks.node_resource_group
  # Dynamically resolves the special RG Azure creates for AKS agent resources (e.g., VMSS, NSGs, disks)
}

