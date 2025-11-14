#!/bin/bash

echo "NOTE: Validating that required commands are found in your PATH."

# List of required commands
commands=("az" "terraform" "docker" "kubectl" "jq")

# Flag to track if all commands are found
all_found=true

# Iterate through each command and check if it's available
for cmd in "${commands[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is not found in the current PATH."
    all_found=false
  else
    echo "NOTE: $cmd is found in the current PATH."
  fi
done

# Final status
if [ "$all_found" = true ]; then
  echo "NOTE: All required commands are available."
else
  echo "ERROR: One or more commands are missing."
  exit 1
fi

echo "NOTE: Validating that required environment variables are set."
# Array of required environment variables
required_vars=("ARM_CLIENT_ID" "ARM_CLIENT_SECRET" "ARM_SUBSCRIPTION_ID" "ARM_TENANT_ID")

# Flag to check if all variables are set
all_set=true

# Loop through the required variables and check if they are set
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "ERROR: $var is not set or is empty."
    all_set=false
  else
    echo "NOTE: $var is set."
  fi
done

# Final status
if [ "$all_set" = true ]; then
  echo "NOTE: All required environment variables are set."
else
  echo "ERROR: One or more required environment variables are missing or empty."
  exit 1
fi

echo "NOTE: Logging in to Azure using Service Principal..."
az login --service-principal --username "$ARM_CLIENT_ID" --password "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID" > /dev/null 2>&1

# Check the return code of the login command
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to log into Azure. Please check your credentials and environment variables."
  exit 1
else
  echo "NOTE: Successfully logged into Azure."
fi

# ---------------------------------------------------------
# Ensure Microsoft.App Resource Provider is Registered
# ---------------------------------------------------------

echo "NOTE: Registering 'Microsoft.App' resource provider..."

az provider register --namespace Microsoft.App &>/dev/null

# Wait until registration is confirmed
until [[ "$(az provider show --namespace Microsoft.App --query "registrationState" -o tsv)" == "Registered" ]]; do
  echo "NOTE: Waiting for 'Microsoft.App' to register..."
  sleep 10
done

echo "NOTE: 'Microsoft.App' is registered."

# ---------------------------------------------------------
# Validate Role Assignment
# ---------------------------------------------------------

echo "NOTE: Checking for 'User Access Administrator' role assignment..."

ASSIGNEE=$(az account show --query "user.name" -o tsv)

if [ -z "$ASSIGNEE" ]; then
  echo "ERROR: Failed to retrieve the current user or service principal."
  exit 1
fi

ROLE_ASSIGNED=$(az role assignment list \
  --assignee "$ASSIGNEE" \
  --query "[?roleDefinitionName=='User Access Administrator']" \
  -o tsv)

if [ -z "$ROLE_ASSIGNED" ]; then
  echo "ERROR: 'User Access Administrator' role is NOT assigned to '$ASSIGNEE'."
  exit 1
fi

echo "NOTE: 'User Access Administrator' role is assigned to '$ASSIGNEE'."