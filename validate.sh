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

echo "$DNS_NAME"


# # -------------------------------------
# # Configurable variables
# # -------------------------------------
# RESOURCE_GROUP="rstudio-vmss-rg"       # Resource group containing App Gateway
# APP_GATEWAY_NAME="rstudio-app-gateway" # Application Gateway name
# CHECK_INTERVAL=30                      # Time between health checks (seconds)
# MAX_RETRIES=20                         # Max retries before giving up

# # -------------------------------------
# # Function: check_backend_health
# # Description:
# #   Query Azure App Gateway for backend servers marked "Healthy".
# #   Returns server list if any are healthy, empty otherwise.
# # -------------------------------------
# check_backend_health() {
#     az network application-gateway show-backend-health \
#         --resource-group "$RESOURCE_GROUP" \
#         --name "$APP_GATEWAY_NAME" \
#         --query "backendAddressPools[].backendHttpSettingsCollection[].servers[?health == 'Healthy']" \
#         -o tsv
# }

# # -------------------------------------
# # Main loop: wait until backends are healthy
# # -------------------------------------
# echo "NOTE: Waiting for at least one healthy backend RStudio server..."
# for ((i = 1; i <= MAX_RETRIES; i++)); do
#     HEALTHY_SERVERS=$(check_backend_health)

#     if [[ -n "$HEALTHY_SERVERS" ]]; then
#         echo "NOTE: At least one healthy backend RStudio server found!"

#         # Fetch DNS name of App Gateway public IP
#         export DNS_NAME=$(az network public-ip show \
#             --name rstudio-app-gateway-pip \
#             --resource-group $RESOURCE_GROUP \
#             --query "dnsSettings.fqdn" \
#             --output tsv)

#         echo "NOTE: RStudio Application URL - http://$DNS_NAME"
#         exit 0
#     fi

#     echo "NOTE: Retry $i/$MAX_RETRIES: No healthy servers yet. Retrying..."
#     sleep "$CHECK_INTERVAL"
# done

# # -------------------------------------
# # Exit with error if no servers became healthy
# # -------------------------------------
# echo "ERROR: Timeout reached. No healthy backend servers found."
# exit 1
