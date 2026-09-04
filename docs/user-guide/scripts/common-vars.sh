#!/bin/bash

export INFRA_NAMESPACE="dch-services"
export TENANT_NAMESPACE="dch-tenant-a"
export TENANT_ID=$TENANT_NAMESPACE

export TENANT_DB_INSTANCE="dch-tenant-postgres"
export TENANT_DB="tenant_a_db"
export TENANT_DB_SECRET="tenant-database-secret"

export REST_LOCAL_PORT=18080
export REST_API_BASE="http://localhost:${REST_LOCAL_PORT}/api/v1alpha1/data"

export FLIGHT_LOCAL_PORT=15051
export DCH_S3_SECRET_NAME="s3-test-creds"

export SA_NAME="${SA_NAME:-dch-test-user}"
export GW_HOST=`oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}'`
export GW_PORT=443
export GW_URL="https://${GW_HOST}"
