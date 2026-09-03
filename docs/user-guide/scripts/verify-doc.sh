#!/bin/bash
#set -euo pipefail
#
GATEWAY_NAME="${GATEWAY_NAME:-dch-gateway}"
GATEWAY_NS="${GATEWAY_NS:-openshift-ingress}"

verify_dsci() {
  echo ""
  echo "================================== Pre-req: RHOAI DataScienceClusterInitialization  ============"

  cmd="oc get dsci -A"
  run_cmd "oc get dsci -A"
  return
  dsci_output=$(oc get dsci -A -o jsonpath='{.items[0].metadata.name},{.items[0].status.phase}' 2>/dev/null) || true

  if [ -z "$dsci_output" ]; then
   echo "  FAILED: no DSCI found in the cluster"
   echo "  Run: oc get dsci -A"
   exit 1
  fi

  dsci_name=$(echo "$dsci_output" | cut -d',' -f1)
  dsci_phase=$(echo "$dsci_output" | cut -d',' -f2)

  echo "  Name:  $dsci_name"
  echo "  Phase: $dsci_phase"

  if [ "$dsci_phase" != "Ready" ]; then
    echo "  FAILED: DSCI '$dsci_name' is not Ready (phase=$dsci_phase)"
    echo "  Run: oc get dsci -A"
    exit 1
  fi

  echo "  PASSED: DSCI '$dsci_name' is Ready"
  echo ""
}


verify_gateway() {
  echo ""
  echo "================================== VERIFY GATEWAY ============================="
  echo "  Checking for Gateway '$GATEWAY_NAME' in namespace '$GATEWAY_NS'..."

  gw_json=$(oc get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" -o json 2>/dev/null) || true

  if [ -z "$gw_json" ]; then
    echo "  FAILED: Gateway '$GATEWAY_NAME' not found in namespace '$GATEWAY_NS'"
    echo "  Run: oc get gateway -n $GATEWAY_NS"
    exit 1
  fi

  programmed=$(echo "$gw_json" | python3 -c "
import sys, json
gw = json.load(sys.stdin)
conditions = gw.get('status', {}).get('conditions', [])
for c in conditions:
    if c.get('type') == 'Programmed':
        print(c.get('status', 'Unknown'))
        break
else:
    print('NotFound')
" 2>/dev/null) || true

  address=$(echo "$gw_json" | python3 -c "
import sys, json
gw = json.load(sys.stdin)
addrs = gw.get('status', {}).get('addresses', [])
if addrs:
    print(addrs[0].get('value', ''))
" 2>/dev/null) || true

  echo "  Name:       $GATEWAY_NAME"
  echo "  Namespace:  $GATEWAY_NS"
  echo "  Programmed: $programmed"
  echo "  Address:    ${address:-(none)}"

  if [ "$programmed" != "True" ]; then
    echo "  FAILED: Gateway '$GATEWAY_NAME' is not Programmed (status=$programmed)"
    echo "  Run: oc get gateway $GATEWAY_NAME -n $GATEWAY_NS -o yaml"
    exit 1
  fi

  if [ -z "$address" ]; then
    echo "  FAILED: Gateway '$GATEWAY_NAME' has no address"
    echo "  Run: oc get gateway $GATEWAY_NAME -n $GATEWAY_NS -o yaml"
    exit 1
  fi

  echo "  PASSED: Gateway '$GATEWAY_NAME' is Programmed with address '$address'"
  echo ""
}

verify_dch_operator() {
  local operator_ns="redhat-ods-applications"
  local operator_label="app.kubernetes.io/name=dc-controller"

  echo ""
  echo "================================== VERIFY DCH OPERATOR ============================="
  echo "  Waiting for dc-controller pod in namespace '$operator_ns' (up to 60s)..."

  local found=false
  for i in $(seq 1 12); do
    pod_json=$(oc get po -n "$operator_ns" -l "$operator_label" -o json 2>/dev/null) || true
    pod_count=$(echo "$pod_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))" 2>/dev/null) || true
    if [ -n "$pod_count" ] && [ "$pod_count" -gt 0 ]; then
      found=true
      break
    fi
    echo "  Waiting for pod... ($((i * 5))s)"
    sleep 5
  done

  if [ "$found" != "true" ]; then
    echo "  FAILED: no dc-controller pod found after 60s"
    echo "  Run: oc get po -n $operator_ns"
    exit 1
  fi

  echo "  Pod found, waiting for Ready..."
  local pod_name
  pod_name=$(echo "$pod_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['items'][0]['metadata']['name'])" 2>/dev/null) || true
  oc wait --for=condition=Ready pod/"$pod_name" -n "$operator_ns" --timeout=60s 2>/dev/null || true

  pod_json=$(oc get po -n "$operator_ns" -l "$operator_label" -o json 2>/dev/null) || true

  pod_result=$(echo "$pod_json" | python3 -c "
import sys, json
items = json.load(sys.stdin)['items']
all_ok = True
for p in items:
    name = p['metadata']['name']
    phase = p['status'].get('phase', 'Unknown')
    cs_list = p['status'].get('containerStatuses', [])
    restarts = sum(c.get('restartCount', 0) for c in cs_list)
    ready = sum(1 for c in cs_list if c.get('ready'))
    total = len(cs_list)
    ok = phase == 'Running' and ready == total and restarts == 0
    if not ok:
        all_ok = False
    print(f'  {name}  Status: {phase}  Ready: {ready}/{total}  Restarts: {restarts}')
if all_ok and len(items) > 0:
    print('ALL_READY')
" 2>/dev/null) || true

  echo ""
  echo "$pod_result" | grep -v "ALL_READY"
  echo ""

  if ! echo "$pod_result" | grep -q "ALL_READY"; then
    echo "  FAILED: dc-controller pod is not healthy"
    echo "  Run: oc get po -n $operator_ns -l $operator_label"
    exit 1
  fi

  echo "  PASSED: dc-controller is Running, Ready, 0 restarts"
  echo ""
}

install_dch_operator() {
  echo ""
  echo "================================== CLUSTER ADMIN: Install DCH OPERATOR (with helm for DP) ============================="
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/install-operator.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  #echo "  Removing existing helm chart (if any)..."
  #helm delete dc-controller -n redhat-ods-applications --no-hooks 2>/dev/null || true
  #oc delete secret sh.helm.release.v1.dc-controller.v1 -n redhat-ods-applications 2>/dev/null || true
  cd ~/DCH/data-connect-hub-work
  echo pwd=`pwd`
  bash "$script"
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  cd $SCRIPT_DIR
}

verify_data_connect_service() {
  local ns="${1:-dch-infra-example}"
  local label="app.kubernetes.io/part-of=data-connect-hub"
  local timeout=120
  local interval=10

  echo ""
  echo "================================== VERIFY DATA CONNECT SERVICE ============================="
  echo "  Waiting for DCH pods in namespace '$ns' (up to ${timeout}s)..."

  local elapsed=0
  local all_ready=false

  while [ "$elapsed" -lt "$timeout" ]; do
    pod_json=$(oc get po -n "$ns" -l "$label" -o json 2>/dev/null) || true
    pod_count=$(echo "$pod_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))" 2>/dev/null) || true

    if [ -n "$pod_count" ] && [ "$pod_count" -gt 0 ]; then
      pod_summary=$(echo "$pod_json" | python3 -c "
import sys, json
items = json.load(sys.stdin)['items']
all_ok = True
for p in items:
    name = p['metadata']['name']
    phase = p['status'].get('phase', 'Unknown')
    cs_list = p['status'].get('containerStatuses', [])
    restarts = sum(c.get('restartCount', 0) for c in cs_list)
    ready = sum(1 for c in cs_list if c.get('ready'))
    total = len(cs_list)
    ok = phase == 'Running' and ready == total and restarts == 0
    if not ok:
        all_ok = False
    print(f'{name},{phase},{ready}/{total},{restarts},{ok}')
if all_ok and len(items) > 0:
    print('ALL_READY')
" 2>/dev/null) || true

      if echo "$pod_summary" | grep -q "ALL_READY"; then
        all_ready=true
        break
      fi
    fi

    echo "  Waiting for pods... (${elapsed}s)"
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  if [ "$all_ready" != "true" ]; then
    echo "  FAILED: not all DCH pods are ready after ${timeout}s"
    echo ""
    oc get po -n "$ns" -l "$label" 2>/dev/null || true
    echo ""
    echo "  Run: oc get po -n $ns -l $label"
    exit 1
  fi

  echo ""
  pod_json=$(oc get po -n "$ns" -l "$label" -o json 2>/dev/null) || true
  echo "$pod_json" | python3 -c "
import sys, json
items = json.load(sys.stdin)['items']
for p in items:
    name = p['metadata']['name']
    phase = p['status'].get('phase', 'Unknown')
    cs_list = p['status'].get('containerStatuses', [])
    restarts = sum(c.get('restartCount', 0) for c in cs_list)
    ready = sum(1 for c in cs_list if c.get('ready'))
    total = len(cs_list)
    print(f'  {name}  Status: {phase}  Ready: {ready}/{total}  Restarts: {restarts}')
" 2>/dev/null || true

  echo ""
  echo "  PASSED: all DCH pods are Running, Ready, 0 restarts"
  echo ""
}

verify_postgres_operator() {
  echo ""
  echo ""
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/verify-postgres-operator.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

verify_postgres_db() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/verify-postgres-db.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

verify_clusterroles_bindings() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/verify-clusterroles-bindings.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

verify_test_users() {
  echo ""
  echo ""
  echo "================================== VERIFY TEST USERS ============================="
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/verify-test-users.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

verify_rest_api() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/verify-rest-api.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

verify_flight_api() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/verify-flight-api.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

verify_rest_sec() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/verify-rest-sec.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

verify_flight_sec() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/verify-flight-sec.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

populate_db_temp() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  local script="$SCRIPT_DIR/populate-db-temp.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"
}

verify_s3() {
  # Flight S3 connection defaults.
  export DCH_S3_SECRET_NAME="s3-test-creds"
  export DCH_S3_CSV_QUERY="datasets/dch-test-prompts.csv"
  export DCH_S3_PARQUET_QUERY="datasets/dch-test-prompts.parquet"

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

  local script="$SCRIPT_DIR/create-s3-dch-config-secret.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"

  local script="$SCRIPT_DIR/create-s3-connection-type.sh"
  if [ ! -f "$script" ]; then
    echo "  FAILED: $script not found"
    exit 1
  fi
  bash "$script"

}

run_cmd() {
  echo ""
  echo ${1}
  eval $1
}

usage() {
  echo -e "\nUsage: "
  echo -e "  -c all"
  echo -e "  -c verify_gateway"
  echo -e "  -c populate_db_temp"

  echo -e "  -c verify_dch_operator"
  echo -e "  -c install_data_connect_service"
  echo -e "  -c verify_data_connect_service"

  echo -e "  -c verify_clusterroles_bindings"
  echo -e "  -c verify_flight_sec"
  echo -e "  -c verify_rest_sec"
  echo -e "  -c verify_rest_api"
  echo -e "  -c verify_flight_api"
  echo -e "  -c verify_s3"
}


# if less than two arguments supplied, display usage
if [  $# -le 1 ]
then
  usage
  exit 1
fi

while getopts "c:" flag
do
    case "${flag}" in
        c) command_opt=${OPTARG};;
    esac
done

if [ "${command_opt}" == 'verify_gateway' ]; then
  verify_gateway
elif [ "${command_opt}" == 'verify_dch_operator' ]; then
  verify_dch_operator
elif [ "${command_opt}" == 'install_data_connect_service' ]; then
  install_data_connect_service
elif [ "${command_opt}" == 'verify_data_connect_service' ]; then
  verify_data_connect_service
elif [ "${command_opt}" == 'verify_clusterroles_bindings' ]; then
  verify_clusterroles_bindings
elif [ "${command_opt}" == 'verify_rest_api' ]; then
  verify_rest_api
elif [ "${command_opt}" == 'verify_flight_api' ]; then
  verify_flight_api
elif [ "${command_opt}" == 'verify_rest_sec' ]; then
  verify_rest_sec
elif [ "${command_opt}" == 'verify_flight_sec' ]; then
  verify_flight_sec
elif [ "${command_opt}" == 'populate_db_temp' ]; then
  populate_db_temp
elif [ "${command_opt}" == 'verify_s3' ]; then
  verify_s3
elif [ "${command_opt}" == 'all' ]; then
  # All sequence for demo video
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  echo ""
  echo "==================================== Pre-req: Openshift Cluster ======================="
  run_cmd "oc cluster-info"

  echo ""
  echo "==================================== Pre-req: Openshift Version ======================="
  run_cmd "oc version"

  echo ""
  echo "==================================== Pre-req: RHOAI Version ==========================="
  run_cmd "oc get po -n redhat-ods-operator"

  echo ""
  run_cmd "kubectl get deployment rhods-operator -n redhat-ods-operator -o jsonpath='{.spec.template.spec.containers[*].image}'"

  echo ""
  verify_dsci

  # Create own gateway method
  ./create-gateway.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  run_cmd "oc get gateway -n openshift-ingress dch-gateway"

  # Use existing data-science-gateway method
  run_cmd "oc get gateway -n openshift-ingress data-science-gateway"

  echo ""
  echo "================================== Pre-req: CREATE TENANT NAMESPACES ============================="
  ./create-namespace.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  echo ""
  run_cmd "oc get ns dch-example dch-infra-example"

  echo ""
  echo "================================== Pre-req: INSTALL POSTGRES OPERATOR ============================="
  ./install-postgres-operator.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  run_cmd "oc get csv -n openshift-operators -l operators.coreos.com/cloudnative-pg.openshift-operators="

  echo ""
  echo "================================== Pre-req: Create POSTGRES DB for DCH meta data ======"
  ./create-postgres-db.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  run_cmd "oc get po -n dch-infra-example dch-postgres-1"

  echo ""
  echo "================================== Pre-req: Create Postgres secret  ======"
  ./create-postgres-secret.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  run_cmd "oc get secret -n dch-infra-example dch-database-config"

  # DCH specifics
  install_dch_operator
  run_cmd "oc get po -n redhat-ods-applications | fgrep dc-controller"

  echo ""
  echo "================================== CLUSTER ADMIN: install DCH service CR in dch-infra-example  ====="
  ./install-dch-services.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  run_cmd "oc describe DataConnectService -n dch-infra-example"
  run_cmd "oc get po -n dch-infra-example"
  run_cmd "oc describe httproute -n dch-infra-example"

  # ROSA: Patching the gateway starts
  # grpcurl (h2) → OpenShift Route/HAProxy (:443) → Envoy gateway pod → flight-service (:8443 TLS h2
  NS=dch-infra-example
  HOST=$(oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}')

  # Does the Envoy gateway work? (bypass HAProxy)
  oc port-forward -n openshift-ingress $GW_POD 8443:443

  # This one line tells you which hop is broken:
  oc logs -n openshift-ingress $GW_POD --tail=20 | grep GetFlightInfo

  # Verify gateway→backend config
  #  Service must advertise HTTP/2 to Istio (appProtocol grpc or http2; port name grpc/grpc-*)
  oc get svc dch-flight-service -n $NS -o jsonpath='{.spec.ports[0].name}{"appProtocol="}{.spec.ports[0].appProtocol}{"\n"}'
  # grpcappProtocol=grpc
  #
  # flight serves its own TLS → DestinationRule must originate TLS
  oc get destinationrule -n $NS

  # route exists and targets the right service/port
  oc get httproute dch-data-connect-hub -n $NS -o yaml | grep -A4 backendRefs
  # Expect: appProtocol=grpc, a DestinationRule with tls: SIMPLE, and the HTTPRoute backendRef dch-flight-service:8443.
  #
  # tep 6 — Fix the router HTTP/2 downgrade (managed ROSA)

  # cluster-wide is blocked by the managed webhook; do it at the IngressController instead:
  oc annotate ingresscontroller default -n openshift-ingress-operator \
    ingress.operator.openshift.io/default-enable-http2=true --overwrite
  oc rollout status deployment/router-default -n openshift-ingress

  

  run_cmd "oc annotate gateway data-science-gateway -n openshift-ingress \
  opendatahub.io/managed=false --overwrite"

  oc patch gateway data-science-gateway -n openshift-ingress --type=json -p '[{"op":"replace", "path":"/spec/listeners/0/allowedRoutes/namespaces/selector/matchExpressions/0/values", "value":["openshift-ingress","redhat-ods-applications","'"dch-infra-example"'"]}]'

  oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].allowedRoutes.namespaces.selector.matchExpressions[0].values[*]}'

  oc get httproute dch-data-connect-hub -n dch-infra-example   -o jsonpath='{range .status.parents[*].conditions[*]}{.type}: {.status}{"\n"}{end}'

  # ROSA: Patching the gateway ends ...
  #
  #
  #./grant-service-read-secret.sh # skip fow now ...
  #verify_clusterroles_bindings
  #
  echo ""
  echo "================================== CLUSTER ADMIN: CREATE TEST USER in TENANT NAMESPACE dch-example ============================="
  ./create-test-user.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  run_cmd "oc get serviceaccount -n dch-example dch-test-user"

  echo ""
  echo "================================== TENANT ADMIN: authorize test user to DCH services  ===="
  ./auth-test-user.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  run_cmd "oc get rolebindings -n dch-example dch-test-user-dch-read-write"

  echo ""
  echo "==================================== DCH USER: Get token, required for authentication  ===="
  ./get-token.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  echo ""
  echo "==================================== DCH ADMIN USER: Create connection secrets in tenant namespace  ==============="
  ./create-db-secret.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  #./create-s3-db-secret.sh
  #if [[ $? -ne 0 ]]; then
  #  exit 1
  #fi
  #run_cmd "oc get secret s3-test-creds -n dch-example"

  echo ""
  echo "==================================== DCH ADMIN USER: Grant DCH services in tenant infra namespace to read connection secrets in tenant namespace  ======"
  ./grant-service-read-secret.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  echo ""
  echo "==================================== DCH ADMIN USER: Create connection types ==========================="
  ./create-connection-type.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  ./create-s3-connection-type.sh

  echo ""
  echo "==================================== DCH USER: Get all connection types ==========================="
  ./get-connection-types.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  echo ""
  echo "==================================== DCH USER: Get all connections ==========================="
  ./get-connections.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  exit 0

  echo ""
  echo "==================================== DCH ADMIN USER: Create connection for a connection type  ========="
  #./create-connection.sh 0edb0de7-8fce-47dc-a8ca-7c6e90ec81e4
  ./create-s3-connection.sh 46f48ffd-2721-4df3-a8f5-3343b8114b03
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  echo ""
  echo "==================================== DCH ADMIN USER: Populate test data  ======"
  ./populate_test_data.sh
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  echo ""
  echo "==================================== DCH USER: Fetch data using connection ==========================="
  #./get-data.sh dch-infra-example dch-example c57523e0-6869-4709-8bac-065b3c2ec520
  ./get-s3-data.sh dch-infra-example dch-example cf210b03-8bec-434c-8ab3-15d52a7f29dd
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
else
  usage
fi
