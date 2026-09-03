#!/bin/bash
set -euo pipefail

INFRA_NAMESPACE="${1:-dch-infra-example}"

oc apply -f - <<EOF
apiVersion: dataconnecthub.opendatahub.io/v1alpha1
kind: DataConnectService
metadata:
  name: default-dataconnectservice
  namespace: $INFRA_NAMESPACE
spec:
  restService: {}
  flightService: {}
  gateway:
    name: data-science-gateway
    namespace: openshift-ingress
  tokenReviewAudiences:
    - "https://kubernetes.default.svc"
    - "https://rh-oidc.s3.us-east-1.amazonaws.com/27bd6cg0vs7nn08mue83fbof94dj4m9a"
EOF
