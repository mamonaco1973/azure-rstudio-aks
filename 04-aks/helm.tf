# ---------------------------------------------------------
# Helm Provider Configuration (for Helm Chart Installs)
# ---------------------------------------------------------
provider "helm" {
  # Uses the same kubeconfig as the Kubernetes provider
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.flask_aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.flask_aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.flask_aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.flask_aks.kube_config[0].cluster_ca_certificate)
  }
}

# ---------------------------------------------------------
# Deploy the NGINX Ingress Controller via Helm Chart
# ---------------------------------------------------------
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  namespace  = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"

  create_namespace = true
  # Automatically creates the target namespace if it doesn't exist

  values = [
    templatefile("${path.module}/yaml/nginx-values.yaml.tmpl", {
      ip_address     = azurerm_public_ip.nginx_ingress_ip.ip_address
      resource_group = data.azurerm_resource_group.aks_rg.name
    })
  ]

  depends_on = [ azurerm_public_ip.nginx_ingress_ip,
                 azurerm_kubernetes_cluster.rstudio_aks ]
}

# ---------------------------------------------------------
# Random Suffix Generator for Globally Unique ACR Name
# ---------------------------------------------------------

resource "random_string" "ip_suffix" {
  length  = 6         # Generates an 6-character string
  special = false     # Excludes special characters (e.g., !@#)
  upper   = false     # Lowercase only t
}

resource "azurerm_public_ip" "nginx_ingress_ip" {
  name                = "nginx-ingress-ip"
  location            = data.azurerm_resource_group.aks_rg.location  # Use the same region as the target resource group
  resource_group_name = data.azurerm_resource_group.aks_rg.name      # Reference the existing resource group
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "k8s${random_string.ip_suffix.result}"  
}