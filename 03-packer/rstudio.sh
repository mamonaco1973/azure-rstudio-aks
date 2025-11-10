#!/bin/bash

# ---------------------------------------------------------------------------------
# Install R
# ---------------------------------------------------------------------------------

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y software-properties-common dirmngr
apt-get update
apt-get install -y r-base r-base-dev

# ---------------------------------------------------------------------------------
# Install Various R packages and rebuild them.
# ---------------------------------------------------------------------------------

# Installing R Packages can take a quite a long time - users can install these
# dynamically so I'll skip making these part of the AMI.

#Rscript -e 'install.packages(c("jsonlite", "png", "reticulate","ggplot2","gganimate"), repos="https://cloud.r-project.org")'

# ---------------------------------------------------------------------------------
# Install RStudio Community Edition
# ---------------------------------------------------------------------------------

cd /tmp
wget -q https://rstudio.org/download/latest/stable/server/jammy/rstudio-server-latest-amd64.deb
apt-get install -y ./rstudio-server-latest-amd64.deb
rm -f -r rstudio-server-latest-amd64.deb

# ---------------------------------------------------------------------------------
# Configure PAM for RStudio to use SSSD and AD
# ---------------------------------------------------------------------------------

cat <<'EOF' | tee /etc/pam.d/rstudio > /dev/null
# PAM configuration for RStudio Server

auth     include   common-auth
auth     [success=ok new_authtok_reqd=ok ignore=ignore user_unknown=bad default=die] pam_exec.so /etc/pam.d/rstudio-mkhomedir.sh
account  include   common-account
password include   common-password
session  include   common-session
EOF

# ---------------------------------------------------------------------------------
# Deploy PAM script to create home directories on first login
# ---------------------------------------------------------------------------------

cat <<'EOF' | tee /etc/pam.d/rstudio-mkhomedir.sh > /dev/null
#!/bin/bash
su -c "exit" $PAM_USER
EOF

chmod +x /etc/pam.d/rstudio-mkhomedir.sh
