#!/bin/bash

. ./common-vars.sh

oc apply -n "$TENANT_NAMESPACE" -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${TENANT_DB_INSTANCE}
spec:
  instances: 1
  storage:
    size: 5Gi
  bootstrap:
    initdb:
      database: ${TENANT_DB}
      owner: tenant_a
EOF
