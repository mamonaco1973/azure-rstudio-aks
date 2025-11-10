# ==========================================================================================
# Active Directory and Infrastructure Input Variables
# ------------------------------------------------------------------------------------------
# These variables define the DNS, Kerberos, and NetBIOS identities for a Samba AD Domain,
# along with image naming and Azure resource placement defaults.
# ==========================================================================================


# ------------------------------------------------------------------------------------------
# Active Directory DNS Zone / Domain
# - FQDN used by the Samba AD DC for DNS namespace and domain identity
# ------------------------------------------------------------------------------------------
variable "dns_zone" {
  description = "AD DNS zone / domain (e.g., rstudio.mikecloud.com)"
  type        = string
  default     = "rstudio.mikecloud.com"
}


# ------------------------------------------------------------------------------------------
# Kerberos Realm
# - Conventionally matches the dns_zone in UPPERCASE
# - Required by Kerberos configuration and AD integration
# ------------------------------------------------------------------------------------------
variable "realm" {
  description = "Kerberos realm (e.g., RSTUDIO.MIKECLOUD.COM)"
  type        = string
  default     = "RSTUDIO.MIKECLOUD.COM"
}


# ------------------------------------------------------------------------------------------
# NetBIOS Short Domain Name
# - Legacy domain name, up to 15 characters, uppercase alphanumeric
# - Still required by older clients and SMB/CIFS authentication flows
# ------------------------------------------------------------------------------------------
variable "netbios" {
  description = "NetBIOS short domain name (e.g., RSTUDIO)"
  type        = string
  default     = "RSTUDIO"
}


# ------------------------------------------------------------------------------------------
# LDAP Base Distinguished Name for Users
# - Defines the LDAP subtree where user accounts reside
# ------------------------------------------------------------------------------------------
variable "user_base_dn" {
  description = "User base DN for LDAP (e.g., CN=Users,DC=rstudio,DC=mikecloud,DC=com)"
  type        = string
  default     = "CN=Users,DC=rstudio,DC=mikecloud,DC=com"
}


# ------------------------------------------------------------------------------------------
# Custom RStudio Image Name
# - Human-readable identifier for the custom VM image
# - Typically passed in via CLI, tfvars file, or environment variable
# ------------------------------------------------------------------------------------------
variable "rstudio_image_name" {
  description = "Name of the RStudio custom image"
  type        = string
}


# ------------------------------------------------------------------------------------------
# Networking: Virtual Network and Subnet
# - Defaults match values previously hardcoded in templates
# ------------------------------------------------------------------------------------------
variable "vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
  default     = "ad-vnet"
}

variable "subnet_name" {
  description = "Name of the existing subnet"
  type        = string
  default     = "vm-subnet"
}


# ------------------------------------------------------------------------------------------
# Resource Group Name
# - Existing Azure resource group for networking resources
# ------------------------------------------------------------------------------------------
variable "project_group_name" {
  description = "Resource group used for the network resources"
  type        = string
  default     = "rstudio-network-rg"
}

# ------------------------------------------------------------------------------------------
# Resource Group Name
# - For RStudio VMSS deployment
# ------------------------------------------------------------------------------------------

variable "cluster_group_name" {
  description = "Resource group used for the image and network resources"
  type        = string
  default     = "rstudio-vmss-rg"
}

# ------------------------------------------------------------------------------------------
# Ubuntu password for VM instances.
# ------------------------------------------------------------------------------------------

variable "ubuntu_password" {
  description = "Password for the Ubuntu VM"
  type        = string
}

# ------------------------------------------------------------------------------------------
# Storage account for NFS
# ------------------------------------------------------------------------------------------

variable "nfs_storage_account" {
  description = "Name of the NFS storage account"
  type        = string
}

# ------------------------------------------------------------------------------------------
# Input variable: Key Vault name
# - Can be set via CLI, TFVARS, or overridden at apply time
# ------------------------------------------------------------------------------------------

variable "vault_name" {
  description = "The name of the Azure Key Vault for storing secrets"
  type        = string
}
