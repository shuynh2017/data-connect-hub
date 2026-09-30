#!/bin/bash
set -euo pipefail

. ./common-vars.sh

API_PATH="/api/v1alpha1/data/connection-types"

. ./get-token.sh

CT_DATA='{
"name":"test-postgres-1",
"provider":"postgres",
"credentials_fields":[
  {"name":"URI",
   "label":"URL",
   "type":"string",
   "required":true
  }],
"description":"test connection type"
 }'

echo Gateway URL=$GW_URL

curl -k -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $user_token" -H "x-tenant-id: $TENANT_NAMESPACE" -d "$CT_DATA"  "${GW_URL}${API_PATH}" 
