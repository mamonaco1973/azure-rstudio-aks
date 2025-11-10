#!/bin/bash

# ---------------------------------------------------------------------------------
# Section 1: Mount NFS file system
# ---------------------------------------------------------------------------------

mkdir -p /nfs
echo "${storage_account}.file.core.windows.net:/${storage_account}/nfs /nfs aznfs vers=4.1,defaults 0 0" | \
  sudo tee -a /etc/fstab > /dev/null
systemctl daemon-reload
mount /nfs

mkdir -p /nfs/home
mkdir -p /nfs/data
echo "${storage_account}.file.core.windows.net:/${storage_account}/nfs/home /home aznfs vers=4.1,defaults 0 0" | \
  sudo tee -a /etc/fstab > /dev/null
systemctl daemon-reload
mount /home

# ---------------------------------------------------------------------------------
# Section 2: Join Active Directory Domain
# ---------------------------------------------------------------------------------
az login --identity --allow-no-subscriptions
secretsJson=$(az keyvault secret show --name admin-ad-credentials --vault-name ${vault_name} --query value -o tsv)
admin_password=$(echo "$secretsJson" | jq -r '.password')
admin_username="Admin"

# Join the Active Directory domain using the `realm` command.
# - ${domain_fqdn}: The fully qualified domain name (FQDN) of the AD domain.
# - Log the output and errors to /tmp/join.log for debugging.
echo -e "$admin_password" | sudo /usr/sbin/realm join -U "$admin_username" \
    ${domain_fqdn} --verbose \
    >> /root/join.log 2>> /root/join.log

# ---------------------------------------------------------------------------------
# Section 3: Enable Password Authentication for AD Users
# ---------------------------------------------------------------------------------
# Update SSHD configuration to allow password-based logins (required for AD users)
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' \
    /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

# ---------------------------------------------------------------------------------
# Section 4: Configure SSSD for AD Integration
# ---------------------------------------------------------------------------------
# Adjust SSSD settings for simplified user experience:
#   - Use short usernames instead of user@domain
#   - Disable ID mapping to respect AD-assigned UIDs/GIDs
#   - Adjust fallback homedir format
sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' \
    /etc/sssd/sssd.conf
sudo sed -i 's/ldap_id_mapping = True/ldap_id_mapping = False/g' \
    /etc/sssd/sssd.conf
sudo sed -i 's|fallback_homedir = /home/%u@%d|fallback_homedir = /home/%u|' \
    /etc/sssd/sssd.conf
sudo sed -i 's/^access_provider = ad$/access_provider = simple\nsimple_allow_groups = ${force_group}/' /etc/sssd/sssd.conf

# Prevent XAuthority warnings for new AD users
ln -s /nfs /etc/skel/nfs
touch /etc/skel/.Xauthority
chmod 600 /etc/skel/.Xauthority

# Enable automatic home directory creation and restart services
sudo pam-auth-update --enable mkhomedir
sudo systemctl restart ssh
sudo systemctl restart sssd
sudo systemctl restart rstudio-server
sudo systemctl enable rstudio-server

# ---------------------------------------------------------------------------------
# Section 5: Grant Sudo Privileges to AD Admin Group
# ---------------------------------------------------------------------------------
# Members of "linux-admins" AD group get passwordless sudo access
echo "%linux-admins ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/10-linux-admins

# ---------------------------------------------------------------------------------
# Section 6: Enforce Home Directory Permissions
# ---------------------------------------------------------------------------------
# Force new home directories to have mode 0700 (private)
sudo sed -i 's/^\(\s*HOME_MODE\s*\)[0-9]\+/\10700/' /etc/login.defs

# ---------------------------------------------------------------------------------
# Section 7: Configure R Library Paths to include /nfs/rlibs
# ---------------------------------------------------------------------------------

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

# =================================================================================
# End of Script
# =================================================================================
