# #!/bin/bash
# # =========================================================================================
# # Script: validate.sh
# # Purpose:
# #   - Poll Azure App Gateway backend health until a healthy server is found.
# #   - Outputs the RStudio Application URL when backends are ready.
# # =========================================================================================

DNS_NAME=$(az network public-ip show \
  --resource-group rstudio-aks-rg \
  --name nginx-ingress-ip \
  --query "dnsSettings.fqdn" \
  -o tsv)

# -------------------------------------------------------------
# Validate DNS_NAME
# -------------------------------------------------------------
if [[ -z "$DNS_NAME" ]]; then
  echo "ERROR: DNS name not found for Public IP 'nginx-ingress-ip' in RG 'rstudio-aks-rg'." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 2: Wait for HTTP 200 Response from Load Balancer
# ------------------------------------------------------------------------------
# Once the hostname is available, continuously poll the endpoint until it
# returns HTTP 200, indicating RStudio is reachable via the Load Balancer.
# ------------------------------------------------------------------------------

echo "NOTE: Waiting for Load Balancer endpoint (http://${DNS_NAME}) to return HTTP 200..."

for ((j=1; j<=MAX_ATTEMPTS; j++)); do
  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${DNS_NAME}/auth-sign-in")

  if [[ "$STATUS_CODE" == "200" ]]; then
    echo "NOTE: RStudio available at: http://${DNS_NAME}"
    exit 0
  fi

  echo "WARNING: Attempt $j/${MAX_ATTEMPTS}: Current status: HTTP ${STATUS_CODE} ... retrying in ${SLEEP_SECONDS}s"
  sleep ${SLEEP_SECONDS}
done

echo "ERROR: Timed out after ${MAX_ATTEMPTS} attempts waiting for HTTP 200 from Load Balancer."
exit 1
