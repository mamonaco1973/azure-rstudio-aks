# ================================================================================================
# Application Gateway for RStudio Cluster
#
# PURPOSE:
#   - Provides a public entry point for RStudio VM Scale Set instances.
#   - Routes HTTP traffic on port 80 and forwards to backend pool (port 8787).
#   - Includes a custom health probe for continuous monitoring.
#   - Uses a randomized DNS suffix to ensure unique public FQDN.
#
# COMPONENTS:
#   1. Random suffix generator for DNS labels.
#   2. Public IP definition for the gateway.
#   3. Application Gateway with frontend, backend, probe, and routing rules.
# ================================================================================================

# --------------------------------------------------------------------------------
# RANDOM STRING: Generate a 6-character suffix for DNS uniqueness
# --------------------------------------------------------------------------------
resource "random_string" "gateway_suffix" {
  length  = 6     # Length of suffix
  special = false # Exclude special characters
  upper   = false # Lowercase only
}

# --------------------------------------------------------------------------------
# PUBLIC IP: Used by Application Gateway frontend
# --------------------------------------------------------------------------------
resource "azurerm_public_ip" "rstudio_app_gateway_pip" {
  name                = "rstudio-app-gateway-pip"
  location            = data.azurerm_resource_group.cluster_rg.location
  resource_group_name = data.azurerm_resource_group.cluster_rg.name
  allocation_method   = "Static"   # Static allocation for predictable IP
  sku                 = "Standard" # Required SKU for App Gateway v2
  domain_name_label   = "rstudio-cluster-${random_string.gateway_suffix.result}"
}

# --------------------------------------------------------------------------------
# APPLICATION GATEWAY: Routes traffic to RStudio backend instances
# --------------------------------------------------------------------------------
resource "azurerm_application_gateway" "rstudio_app_gateway" {
  name                = "rstudio-app-gateway"
  location            = data.azurerm_resource_group.cluster_rg.location
  resource_group_name = data.azurerm_resource_group.cluster_rg.name

  # SKU configuration
  sku {
    name     = "Standard_v2" # App Gateway SKU
    tier     = "Standard_v2" # Feature tier
    capacity = 1             # Initial instance count
  }

  # Gateway IP configuration
  gateway_ip_configuration {
    name      = "app-gateway-ip-config"
    subnet_id = data.azurerm_subnet.app_gateway_subnet.id
  }

  # Frontend IP configuration
  frontend_ip_configuration {
    name                 = "app-gateway-frontend"
    public_ip_address_id = azurerm_public_ip.rstudio_app_gateway_pip.id
  }

  # Frontend port configuration
  frontend_port {
    name = "http-port"
    port = 80 # Accept HTTP traffic
  }

  # Backend address pool (populated by VMSS NICs)
  backend_address_pool {
    name = "app-gateway-backend-pool"
  }

  # Backend HTTP settings
  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Enabled"  # Enable sticky sessions
    path                  = "/"
    port                  = 8787       # RStudio Server port
    protocol              = "Http"
    request_timeout       = 30         # Timeout in seconds
    host_name = azurerm_public_ip.rstudio_app_gateway_pip.fqdn # Use gateway FQDN
  }

  # Custom health probe
  probe {
    name                = "custom-health-probe"
    protocol            = "Http"
    path                = "/auth-sign-in"      # Probe login page (returns 200 if RStudio is up)
    interval            = 5                    # Check every 5 seconds
    timeout             = 5                    # 5-second response timeout
    unhealthy_threshold = 5                    # Mark unhealthy after five failures
    port                = 8787                  # RStudio Server port
    pick_host_name_from_backend_http_settings = true # Use backend hostnames
  }

  # HTTP listener configuration
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "app-gateway-frontend"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  # Request routing rule
  request_routing_rule {
    name                       = "http-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "app-gateway-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 1
  }
}
