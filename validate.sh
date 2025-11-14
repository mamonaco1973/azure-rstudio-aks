#!/bin/bash
# ==============================================================================
# Script: validate.sh
# Purpose:
#   - Fetch DNS name for the AKS ingress public IP.
#   - Poll RStudio auth URL until HTTP 200 is returned.
# ==============================================================================

# ------------------------------------------------------------------------------
# Get DNS name for Public IP "nginx-ingress-ip" in RG "rstudio-aks-rg". The DNS
# name must exist for the ingress endpoint to resolve.
# ------------------------------------------------------------------------------
DNS_NAME=$(az network public-ip show \
  --resource-group rstudio-aks-rg \
  --name nginx-ingress-ip \
  --query "dnsSettings.fqdn" \
  -o tsv)

# ------------------------------------------------------------------------------
# Validate DNS_NAME. If empty, the Public IP has no DNS label or the resource
# reference is wrong.
# ------------------------------------------------------------------------------
if [[ -z "$DNS_NAME" ]]; then
  echo "ERROR: DNS name not found for Public IP." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Poll HTTP endpoint until it returns 200. This confirms the ingress, service,
# and RStudio pod are fully reachable.
# ------------------------------------------------------------------------------
echo "NOTE: Waiting for endpoint: http://${DNS_NAME}"

MAX_ATTEMPTS=50
SLEEP_SECONDS=10

for ((j=1; j<=MAX_ATTEMPTS; j++)); do
  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://${DNS_NAME}/auth-sign-in")

  if [[ "$STATUS_CODE" == "200" ]]; then
    echo "NOTE: RStudio ready at: http://${DNS_NAME}"
    exit 0
  fi

  echo "WARN: Try $j/${MAX_ATTEMPTS}: HTTP ${STATUS_CODE}. Retrying..." 
  sleep "${SLEEP_SECONDS}"
done

echo "ERROR: Timed out waiting for HTTP 200."
exit 1
