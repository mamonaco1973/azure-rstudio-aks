#!/bin/bash
# ==============================================================================
# RStudio Server Container Startup Script
# ------------------------------------------------------------------------------
# Initializes an RStudio Server container that uses Active Directory (AD)
# authentication via SSSD. Steps:
#   1. Start DBus for `realm` and `sssd`.
#   2. Retrieve domain join credentials from Azure Key Vault.
#   3. Join the AD domain using `realm join`.
#   4. Update SSSD for simplified usernames and AD-controlled IDs.
#   5. Prepare default user skeletons for clean first logins.
#   6. Launch RStudio Server in the foreground as the main process.
# ==============================================================================
# Logging Helper
# ------------------------------------------------------------------------------
# Formats timestamped log entries to align with RStudio Server log style.
# ==============================================================================
log() {
  local level="$1"; shift
  local msg="$*"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%6NZ")
  echo "${timestamp} [rserver-booter] ${level} ${msg}"
}

# ==============================================================================
# Configuration Variables
# ------------------------------------------------------------------------------
# Load configuration for Key Vault and domain settings.
# ==============================================================================
log INFO "Starting RStudio Server container initialization..."
hostname=$(hostname)
log INFO "Container hostname: ${hostname}"
admin_secret=$(cat /etc/rstudio-config/admin_secret)
vault_name=$(cat /etc/rstudio-config/vault_name)
netbios=$(cat /etc/rstudio-config/netbios)
domain_fqdn=$(cat /etc/rstudio-config/domain_fqdn)

# ==============================================================================
# Initialize System Services
# ------------------------------------------------------------------------------
# `realm` and `sssd` require DBus; start a minimal system instance.
# ==============================================================================
dbus-daemon --system --fork

# ==============================================================================
# Retrieve AD Credentials from Azure Key Vault
# ------------------------------------------------------------------------------
# Secret JSON format:
#   { "username": "MCLOUD\\Admin", "password": "SuperSecurePass123" }
# ==============================================================================
log INFO "Retrieving AD join credentials from Vault..."

az login \
  --federated-token "$(cat $AZURE_FEDERATED_TOKEN_FILE)" \
  --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --tenant "$AZURE_TENANT_ID" \
  --allow-no-subscriptions

secretsJson=$(az keyvault secret show \
  --name ${admin_secret} \
  --vault-name ${vault_name} \
  --query value -o tsv)
admin_password=$(echo "$secretsJson" | jq -r '.password')
admin_username="Admin"

# ==============================================================================
# Join Active Directory Domain
# ==============================================================================

hostname_ad=$(hostname | tr '[:lower:]' '[:upper:]')

log INFO "Attempting to remove existing computer object: ${hostname_ad}"

ldapdelete \
  -H ldap://ad1.rstudio.mikecloud.com:389 \
  -D "CN=Admin,CN=Users,DC=rstudio,DC=mikecloud,DC=com" \
  -w "$admin_password" \
  "CN=${hostname_ad},CN=Computers,DC=rstudio,DC=mikecloud,DC=com"

log INFO "Joining AD domain: ${domain_fqdn}..."
if echo -e "${admin_password}" | sudo /usr/sbin/realm join \
    -U "${admin_username}" \
    "${domain_fqdn}" \
    --verbose --install=/ ; then
  log INFO "Successfully joined domain: ${domain_fqdn}"
else
  rc=$?
  log ERROR "Domain join failed for ${domain_fqdn} (exit code ${rc})"
fi

# ==============================================================================
# SSSD Configuration Adjustments
# ------------------------------------------------------------------------------
# Simplify usernames and ensure IDs are sourced from AD.
# ==============================================================================
log INFO "Adjusting SSSD configuration..."
sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' \
  /etc/sssd/sssd.conf
sudo sed -i 's/ldap_id_mapping = True/ldap_id_mapping = False/g' \
  /etc/sssd/sssd.conf
sudo sed -i 's|fallback_homedir = /home/%u@%d|fallback_homedir = /home/%u|' \
  /etc/sssd/sssd.conf

# ==============================================================================
# Default User Environment Setup
# ------------------------------------------------------------------------------
# Configure /etc/skel and shared NFS mapping for new AD user homes.
# ==============================================================================
log INFO "Preparing default user skeleton directory..."
ln -s /nfs /etc/skel/nfs
sudo sed -i 's/^\(\s*HOME_MODE\s*\)[0-9]\+/\10700/' /etc/login.defs
touch /etc/skel/.Xauthority
chmod 600 /etc/skel/.Xauthority

# ==============================================================================
# Restart SSSD
# ------------------------------------------------------------------------------
# Apply configuration changes and stabilize SSSD.
# ==============================================================================
log INFO "Starting SSSD service..."
sudo systemctl restart sssd
sleep 5

# ==============================================================================
# Configure R Library Paths
# ------------------------------------------------------------------------------
# Add /efs/rlibs to global R library paths.
# ==============================================================================
log INFO "Configuring R library paths..."
cat <<'EOF' | sudo tee /usr/lib/R/etc/Rprofile.site > /dev/null
local({
  userlib <- Sys.getenv("R_LIBS_USER")
  if (!dir.exists(userlib)) {
    dir.create(userlib, recursive = TRUE, showWarnings = FALSE)
  }
  nfs <- "/nfs/rlibs"
  .libPaths(c(userlib, nfs, .libPaths()))
})
EOF

chgrp rstudio-admins /nfs/rlibs
rm -rf /home/rstudio

# ==============================================================================
# Launch RStudio Server
# ------------------------------------------------------------------------------
# Run RStudio Server in foreground and stream logs to stdout.
# ==============================================================================
log INFO "Starting RStudio Server..."
touch /var/log/rstudio/rstudio-server/rserver.log
/usr/lib/rstudio-server/bin/rserver --server-daemonize=0 &

log INFO "RStudio Server initialization complete. Tailing logs..."
tail -f /var/log/rstudio/rstudio-server/rserver.log
