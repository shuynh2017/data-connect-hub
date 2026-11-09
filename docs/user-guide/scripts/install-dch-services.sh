#!/bin/bash
set -euo pipefail

. ./common-vars.sh

export tokenReviewAudiences=`oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}'`
echo "tokenReviewAudiences=$tokenReviewAudiences"

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
    - "$tokenReviewAudiences"
EOF
