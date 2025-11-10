#!/bin/bash
set -euo pipefail

# Set the environment variable to prevent interactive prompts during installation.
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------------
# Install AZ CLI
# ---------------------------------------------------------------------------------

curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/keyrings/microsoft-azure-cli-archive-keyring.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [signed-by=/etc/apt/keyrings/microsoft-azure-cli-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" \
    | tee /etc/apt/sources.list.d/azure-cli.list
apt-get update -y
apt-get install -y azure-cli  >> /root/userdata.log 2>&1

# ---------------------------------------------------------------------------------
# Install AZ NFS Helper
# ---------------------------------------------------------------------------------

curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes \
  -o /etc/apt/keyrings/microsoft.gpg

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] \
https://packages.microsoft.com/ubuntu/22.04/prod jammy main" \
  | sudo tee /etc/apt/sources.list.d/aznfs.list

echo "aznfs aznfs/enable_autoupdate boolean true" | sudo debconf-set-selections

apt-get update -y
apt-get install -y aznfs  >> /root/userdata.log 2>&1
