#!/bin/bash
set -euo pipefail

. ./common-vars.sh

oc new-project "$INFRA_NAMESPACE" 2>/dev/null || oc project "$INFRA_NAMESPACE"
oc new-project "$TENANT_NAMESPACE" 2>/dev/null || oc project "$TENANT_NAMESPACE"
