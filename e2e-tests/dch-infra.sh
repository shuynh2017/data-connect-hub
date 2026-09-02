#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DCH_TEMP_DIR="${DCH_TEMP_DIR:-/tmp}"

echo dir=$SCRIPT_DIR
source "${SCRIPT_DIR}/dch.env"


install_dch_operator() {
  echo ""
  echo "========== install_dch_operator in $DCH_OPERATOR_NAMESPACE namespace ==="
  kubectl create namespace "$DCH_OPERATOR_NAMESPACE" 2>/dev/null || true
  helm delete dc-controller --namespace "$DCH_OPERATOR_NAMESPACE" 2>/dev/null || true
  helm install dc-controller dc-controller/charts/ \
    --namespace "$DCH_OPERATOR_NAMESPACE" --create-namespace \
    --set controllerManager.image.pullPolicy=Always
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  echo "Waiting for operator deployment '$DCH_OPERATOR_DEPLOYMENT' to be available..."
  if ! kubectl rollout status deployment "$DCH_OPERATOR_DEPLOYMENT" \
    --namespace "$DCH_OPERATOR_NAMESPACE" --timeout=120s; then
    echo "Operator deployment did not become available in time."
    kubectl get pods --namespace "$DCH_OPERATOR_NAMESPACE"
    exit 1
  fi
}

create_tenant_a_namespace() {
  kubectl create namespace "$TENANT_A_NS" 2>/dev/null || true
}

create_tenant_a_dch_admin() {
  echo ""
  echo "========== create_tenant_a_dch_admin (and grant): $TENANT_A_DCH_ADMIN in $TENANT_A_NS ==="
  kubectl create serviceaccount "$TENANT_A_DCH_ADMIN" -n "$TENANT_A_NS" 2>/dev/null || true
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${TENANT_A_DCH_ADMIN}-token
  namespace: $TENANT_A_NS
  annotations:
    kubernetes.io/service-account.name: $TENANT_A_DCH_ADMIN
type: kubernetes.io/service-account-token
EOF

  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${TENANT_A_DCH_ADMIN}-dch-read-write
  namespace: $TENANT_A_NS
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: dch-read-write
subjects:
- kind: ServiceAccount
  name: $TENANT_A_DCH_ADMIN
  namespace: $TENANT_A_NS
EOF
}

create_tenant_a_dch_user() {
  echo ""
  echo "========== create_tenant_a_dch_user (and grant): $TENANT_A_DCH_USER in $TENANT_A_NS ==="
  kubectl create serviceaccount "$TENANT_A_DCH_USER" -n "$TENANT_A_NS" 2>/dev/null || true
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${TENANT_A_DCH_USER}-token
  namespace: $TENANT_A_NS
  annotations:
    kubernetes.io/service-account.name: $TENANT_A_DCH_USER
type: kubernetes.io/service-account-token
EOF

  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${TENANT_A_DCH_USER}-dch-read
  namespace: $TENANT_A_NS
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: dch-read
subjects:
- kind: ServiceAccount
  name: $TENANT_A_DCH_USER
  namespace: $TENANT_A_NS
EOF
}

create_tenant_a_none_dch_user() {
  echo ""
  echo "========== create_tenant_a_none_dch_user (and grant): $TENANT_A_NONE_DCH_USER in $TENANT_A_NS ==="
  kubectl create serviceaccount "$TENANT_A_NONE_DCH_USER" -n "$TENANT_A_NS" 2>/dev/null || true
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${TENANT_A_NONE_DCH_USER}-token
  namespace: $TENANT_A_NS
  annotations:
    kubernetes.io/service-account.name: $TENANT_A_NONE_DCH_USER
type: kubernetes.io/service-account-token
EOF
}

create_dch_service() {
  echo ""
  echo "========== create_dch_service ==="
  kubectl apply --namespace "$DCH_SERVICE_NAMESPACE" -f - <<EOF
apiVersion: dataconnecthub.opendatahub.io/v1alpha1
kind: DataConnectService
metadata:
  name: $DCH_SERVICE_NAMESPACE
  namespace: $DCH_SERVICE_NAMESPACE
spec:
  restService: {}
  flightService: {}
  tokenReviewAudiences:
    - "https://kubernetes.default.svc"
EOF
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  echo "DataConnectService default-dataconnectservice created."
}

create_dch_service_tls() {
  echo ""
  echo "========== create_dch_service_tls ==="

  local rest_tls_cert_file rest_tls_key_file
  rest_tls_cert_file="${DCH_TEMP_DIR}/dch-kind-rest-service-tls.crt"
  rest_tls_key_file="${DCH_TEMP_DIR}/dch-kind-rest-service-tls.key"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$rest_tls_key_file" \
    -out "$rest_tls_cert_file" \
    -subj "/CN=${DCH_REST_SERVICE_NAME}.${DCH_SERVICE_NAMESPACE}.svc" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" \
    -addext "subjectAltName=DNS:${DCH_REST_SERVICE_NAME}.${DCH_SERVICE_NAMESPACE}.svc,DNS:${DCH_REST_SERVICE_NAME}.${DCH_SERVICE_NAMESPACE}.svc.cluster.local,DNS:${DCH_REST_SERVICE_NAME}" \
    -days 365 >/dev/null 2>&1 || {
    rm -f "$rest_tls_cert_file" "$rest_tls_key_file"
    echo "failed to generate TLS certificate for '${DCH_REST_SERVICE_NAME}'"
    exit 1
  }
  kubectl create secret tls rest-service-tls -n "$DCH_SERVICE_NAMESPACE" \
    --cert="$rest_tls_cert_file" \
    --key="$rest_tls_key_file" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null || {
    rm -f "$rest_tls_cert_file" "$rest_tls_key_file"
    echo "failed to apply TLS secret 'rest-service-tls'"
    exit 1
  }
  rm -f "$rest_tls_cert_file" "$rest_tls_key_file"

  local flight_tls_cert_file flight_tls_key_file
  flight_tls_cert_file="${DCH_TEMP_DIR}/dch-kind-flight-service-tls.crt"
  flight_tls_key_file="${DCH_TEMP_DIR}/dch-kind-flight-service-tls.key"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$flight_tls_key_file" \
    -out "$flight_tls_cert_file" \
    -subj "/CN=${DCH_FLIGHT_SERVICE_NAME}.${DCH_SERVICE_NAMESPACE}.svc" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" \
    -addext "subjectAltName=DNS:${DCH_FLIGHT_SERVICE_NAME}.${DCH_SERVICE_NAMESPACE}.svc,DNS:${DCH_FLIGHT_SERVICE_NAME}.${DCH_SERVICE_NAMESPACE}.svc.cluster.local,DNS:${DCH_FLIGHT_SERVICE_NAME}" \
    -days 365 >/dev/null 2>&1 || {
    rm -f "$flight_tls_cert_file" "$flight_tls_key_file"
    echo "failed to generate TLS certificate for '${DCH_FLIGHT_SERVICE_NAME}'"
    exit 1
  }
  kubectl create secret tls flight-service-tls -n "$DCH_SERVICE_NAMESPACE" \
    --cert="$flight_tls_cert_file" \
    --key="$flight_tls_key_file" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null || {
    rm -f "$flight_tls_cert_file" "$flight_tls_key_file"
    echo "failed to apply TLS secret 'flight-service-tls'"
    exit 1
  }
  rm -f "$flight_tls_cert_file" "$flight_tls_key_file"
}

wait_dch_service() {
  echo ""
  echo "========== wait_dch_service ==="
  local timeout=60
  if kubectl wait --namespace "$DCH_SERVICE_NAMESPACE" \
    --for=condition=Ready pods --all \
    --timeout="${timeout}s"; then
    echo "All dch service pods are running."
  else
    echo "Timed out waiting for dch service pods to be running."
    kubectl get pods --namespace "$DCH_SERVICE_NAMESPACE"
    exit 1
  fi

  echo "Waiting for DataConnectService '$DCH_SERVICE_NAME' phase to be Ready..."
  local attempts=0 phase=""
  while [ "$attempts" -lt 30 ]; do
    phase=$(kubectl get dataconnectservice "$DCH_SERVICE_NAME" \
      --namespace "$DCH_SERVICE_NAMESPACE" \
      -o jsonpath='{.status.phase}' 2>/dev/null) || true
    if [ "$phase" = "Ready" ]; then
      echo "DataConnectService '$DCH_SERVICE_NAME' is Ready."
      return
    fi
    attempts=$((attempts + 1))
    sleep 2
  done
  echo "Timed out waiting for DataConnectService '$DCH_SERVICE_NAME' to be Ready (phase='$phase')."
  kubectl get dataconnectservice "$DCH_SERVICE_NAME" --namespace "$DCH_SERVICE_NAMESPACE" -o yaml
  exit 1
}

forward_services() {
  echo "  Finding rest-service pod..."
  local rest_pod
  rest_pod=$(kubectl get po -n "$DCH_SERVICE_NAMESPACE" -l app.kubernetes.io/name=rest-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [ -z "$rest_pod" ]; then
    echo "  FAILED: no rest-service pod found in namespace '$DCH_SERVICE_NAMESPACE'"
    exit 1
  fi
  echo "  Pod: $rest_pod"

  echo "  Port-forwarding $rest_pod:8080 -> localhost:$REST_LOCAL_PORT..."
  lsof -ti :"$REST_LOCAL_PORT" 2>/dev/null | xargs kill 2>/dev/null || true
  kubectl port-forward "pod/$rest_pod" -n "$DCH_SERVICE_NAMESPACE" "$REST_LOCAL_PORT:8080" &>/dev/null &
  export pf_rest_pid=$!
  sleep 2

  if ! kill -0 "$pf_rest_pid" 2>/dev/null; then
    echo "  FAILED: port-forward died"
    exit 1
  fi
  echo "  Port-forward ready (pid=$pf_rest_pid)"

  echo "  Port-forwarding $rest_pod:8443 (rbac-proxy) -> localhost:$RBAC_PROXY_LOCAL_PORT..."
  lsof -ti :"$RBAC_PROXY_LOCAL_PORT" 2>/dev/null | xargs kill 2>/dev/null || true
  kubectl port-forward "pod/$rest_pod" -n "$DCH_SERVICE_NAMESPACE" "$RBAC_PROXY_LOCAL_PORT:8443" &>/dev/null &
  export pf_rbac_proxy_pid=$!
  sleep 2

  if ! kill -0 "$pf_rbac_proxy_pid" 2>/dev/null; then
    echo "  FAILED: rbac-proxy port-forward died"
    exit 1
  fi
  echo "  rbac-proxy port-forward ready (pid=$pf_rbac_proxy_pid)"
  echo ""
}

install_dch_operator

create_dch_service_tls
create_dch_service
wait_dch_service

forward_services

create_tenant_a_namespace
create_tenant_a_dch_admin
create_tenant_a_dch_user
create_tenant_a_none_dch_user

