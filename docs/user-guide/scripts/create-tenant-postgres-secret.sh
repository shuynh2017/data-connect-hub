#!/bin/bash
set -euo pipefail

. ./common-vars.sh

NS=$TENANT_NAMESPACE

echo "  Extracting database URI from secret 'dch-tenant-postgres-app' in namespace '$NS'..."
URI=$(oc get secret dch-tenant-postgres-app -n "$NS" -o jsonpath='{.data.uri}' 2>/dev/null | base64 -d) || true

if [ -z "$URI" ]; then
  echo "  FAILED: could not extract URI from secret 'dch-tenant-postgres-app'"
  echo "  Run: oc get secret dch-tenant-postgres-app -n $NS -o yaml"
  exit 1
fi

echo "  Creating secret 'tenant-database-secret' in namespace '$NS'..."
oc apply -n "$NS" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: tenant-database-secret
stringData:
  DATABASE_URL: "$URI"
  URI: "$URI"
  secret-config.toml: |
    [database]
    URI = "$URI"
EOF
