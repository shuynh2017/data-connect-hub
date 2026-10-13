#!/bin/bash
set -euo pipefail

. ./common-vars.sh
type_id="${1}"

API_PATH="/api/v1alpha1/data/connections"

. ./get-token.sh

CT_DATA="{
\"name\":\"test-pg-conn-1\",
\"data_connection_type_id\": \"${type_id}\",
\"format\": \"tabular\",
\"credentials_ref\": {\"secret\": \"${TENANT_DB_SECRET}\"},
\"properties\": {}
 }"

echo CT_DATA=$CT_DATA

echo curl -k -X POST -H "Content-Type: application/json" -H "Authorization: Bearer <user_token>" -H "x-tenant-id: $TENANT_NAMESPACE" -d "$CT_DATA" "${GW_URL}${API_PATH}" 

curl -k -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $user_token" -H "x-tenant-id: $TENANT_NAMESPACE" -d "$CT_DATA" "${GW_URL}${API_PATH}" | jq .
