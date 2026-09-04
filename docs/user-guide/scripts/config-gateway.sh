#!/bin/bash

set -euo pipefail

. ./common-vars.sh

oc annotate gateway data-science-gateway -n openshift-ingress  opendatahub.io/managed=false --overwrite || true
oc annotate ingresscontroller default -n openshift-ingress-operator     ingress.operator.openshift.io/default-enable-http2=true || true

oc patch gateway data-science-gateway -n openshift-ingress --type=json -p '[{"op":"replace",
        "path":"/spec/listeners/0/allowedRoutes/namespaces/selector/matchExpressions/0/values",
        "value":["openshift-ingress","redhat-ods-applications","'"$INFRA_NAMESPACE"'"]}]'
oc rollout status -n openshift-ingress deploy/router-default
