# ================================================================================================
# Linux Virtual Machine Scale Set (VMSS) for RStudio Cluster
#
# PURPOSE:
#   - Deploys an Azure VM Scale Set (VMSS) to host RStudio Server instances.
#   - Integrates with Application Gateway for load balancing.
#   - Bootstraps each VM with a cloud-init script for RStudio install, AD domain
#     join, and NFS-backed Samba integration.
#   - Enables automatic instance repair and health monitoring.
#
# COMPONENTS:
#   1. VMSS definition (size, image, networking, bootstrap).
#   2. Autoscale settings for CPU-based elasticity.
#   3. Managed identity with Key Vault secret access.
# ================================================================================================

# --------------------------------------------------------------------------------
# VM SCALE SET: Defines Linux VMSS for RStudio with load balancer integration
# --------------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine_scale_set" "rstudio_vmss" {
  name                = "rstudio-vmss"  # Logical name of the VM scale set
  location            = data.azurerm_resource_group.cluster_rg.location
  resource_group_name = data.azurerm_resource_group.cluster_rg.name

  # VM configuration
  sku             = "Standard_DS1_v2"   # Instance size (baseline dev/test)
  instances       = 2                  # Initial instance count
  admin_username  = "ubuntu"           # Default admin username
  admin_password  = var.ubuntu_password
  disable_password_authentication = false
  source_image_id = data.azurerm_image.rstudio_image.id

  # OS Disk settings
  os_disk {
    caching              = "ReadWrite"    # Enable disk caching
    storage_account_type = "Standard_LRS" # Locally redundant storage
  }

  # Network interface configuration
  network_interface {
    name    = "rstudio-vmss-nic" # NIC logical name
    primary = true                # Mark NIC as primary

    ip_configuration {
      name      = "internal" # IP config name
      subnet_id = data.azurerm_subnet.cluster_subnet.id

      # Attach instances to Application Gateway backend pool
      application_gateway_backend_address_pool_ids = [
        tolist(azurerm_application_gateway.rstudio_app_gateway.backend_address_pool)[0].id
      ]
    }
  }

  # Bootstrap script (cloud-init)
  custom_data = base64encode(templatefile("${path.module}/scripts/rstudio_booter.sh", {
    vault_name      = data.azurerm_key_vault.ad_key_vault.name
    domain_fqdn     = var.dns_zone
    storage_account = var.nfs_storage_account
    netbios         = var.netbios
    realm           = var.realm
    force_group     = "rstudio-users"
  }))

  # VMSS runtime settings
  computer_name_prefix = "rstudio"
  upgrade_mode         = "Automatic"

  # Enable automatic repair of unhealthy instances
  automatic_instance_repair {
    enabled      = true
    grace_period = "PT10M"
  }

  # Application Health Extension
  extension {
    name                 = "HealthExtension"
    publisher            = "Microsoft.ManagedServices"
    type                 = "ApplicationHealthLinux"
    type_handler_version = "1.0"

    settings = jsonencode({
      protocol    = "http"
      port        = 8787
      requestPath = "/auth-sign-in"
    })
  }

  # Assign a system-managed identity for Key Vault access
  identity {
    type = "SystemAssigned"
  }
}

# --------------------------------------------------------------------------------
# AUTOSCALE: Adjust VMSS instance count based on CPU utilization
# --------------------------------------------------------------------------------
resource "azurerm_monitor_autoscale_setting" "rstudio_vmss_autoscale" {
  name                = "rstudio-vmss-autoscale"
  location            = data.azurerm_resource_group.cluster_rg.location
  resource_group_name = data.azurerm_resource_group.cluster_rg.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.rstudio_vmss.id

  profile {
    name = "default"

    capacity {
      minimum = 1  # Lower bound (ensure at least one VM)
      default = 2  # Default steady-state
      maximum = 4  # Upper bound (prevent runaway scaling)
    }

    # Rule: Scale up when CPU utilization > 60% for 1 minute
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.rstudio_vmss.id
        operator           = "GreaterThan"
        statistic          = "Average"
        threshold          = 60
        time_grain         = "PT1M"
        time_window        = "PT1M"
        time_aggregation   = "Average"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}

# --------------------------------------------------------------------------------
# ROLE ASSIGNMENT: Permit VMSS identity to read Key Vault secrets
# --------------------------------------------------------------------------------
resource "azurerm_role_assignment" "vm_vmss_key_vault_secrets_user" {
  scope                = data.azurerm_key_vault.ad_key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine_scale_set.rstudio_vmss.identity[0].principal_id
}
