#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/dch.env"

KIND_CLUSTER="${KIND_CLUSTER:-dch-e2e}"
DCH_POSTGRES_IMAGE="${DCH_POSTGRES_IMAGE:-docker.io/library/postgres:16}"

kind_create() {
	if ! command -v kind >/dev/null 2>&1; then
		echo "kind is not installed; see https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
		exit 1
	fi
	if kind get clusters 2>/dev/null | grep -qx "${KIND_CLUSTER}"; then
		echo "kind cluster '${KIND_CLUSTER}' already exists"
	else
		echo "creating kind cluster '${KIND_CLUSTER}'"
		kind create cluster --name "${KIND_CLUSTER}"
	fi
}

create_dch_postgres() {
  echo ""
  echo "========== create_dch_postgres ==="
  kubectl create namespace "$DCH_SERVICE_NAMESPACE" 2>/dev/null || true
  kubectl apply --namespace "$DCH_SERVICE_NAMESPACE" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  labels:
    app: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: $DCH_POSTGRES_IMAGE
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              value: postgres
            - name: POSTGRES_PASSWORD
              value: postgres
            - name: POSTGRES_DB
              value: postgres
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
EOF
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  local timeout=60
  if kubectl wait --namespace "$DCH_SERVICE_NAMESPACE" \
    --for=condition=Ready pods -l app=postgres \
    --timeout="${timeout}s"; then
    echo "Postgres pod is running."
  else
    echo "Timed out waiting for postgres pod to be running."
    kubectl get pods --namespace "$DCH_SERVICE_NAMESPACE"
    exit 1
  fi
}

create_dch_postgres_db() {
  echo ""
  echo "========== create_dch_service_postgres_dataconnecthub ==="
  kubectl apply --namespace "$DCH_SERVICE_NAMESPACE" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dch-postgres
  labels:
    app: dch-postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dch-postgres
  template:
    metadata:
      labels:
        app: dch-postgres
    spec:
      containers:
        - name: postgres
          image: $DCH_POSTGRES_IMAGE
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              value: dch
            - name: POSTGRES_PASSWORD
              value: dch
            - name: POSTGRES_DB
              value: dataconnecthub
---
apiVersion: v1
kind: Service
metadata:
  name: dch-postgres
spec:
  selector:
    app: dch-postgres
  ports:
    - port: 5432
      targetPort: 5432
EOF
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  local timeout=120
  if kubectl wait --namespace "$DCH_SERVICE_NAMESPACE" \
    --for=condition=Ready pods -l app=dch-postgres \
    --timeout="${timeout}s"; then
    echo "dch-postgres is ready."
  else
    echo "Timed out waiting for dch-postgres to be ready."
    kubectl get pods --namespace "$DCH_SERVICE_NAMESPACE"
    exit 1
  fi
}

verify_dch_postgres_db() {
  echo ""
  echo "========== verify_dch_service_postgres_dataconnecthub ==="
  local pg_pod
  pg_pod=$(kubectl get po -n "$DCH_SERVICE_NAMESPACE" -l app=dch-postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [ -z "$pg_pod" ]; then
    echo "  FAILED: no postgres pod found in namespace '$DCH_SERVICE_NAMESPACE'"
    echo "  Run: kubectl get po -n $DCH_SERVICE_NAMESPACE -l app=dch-postgres"
    exit 1
  fi
  echo "  Pod: $pg_pod"

  echo "  Waiting for postgres to accept connections..."
  local attempts=0
  until kubectl exec -i "$pg_pod" -n "$DCH_SERVICE_NAMESPACE" -- \
    pg_isready -U dch -d dataconnecthub >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 30 ]; then
      echo "  FAILED: postgres not accepting connections after $attempts attempts"
      exit 1
    fi
    sleep 2
  done

  echo "  Populating database..."
  kubectl exec -i "$pg_pod" -n "$DCH_SERVICE_NAMESPACE" -- \
    psql -U dch -d dataconnecthub -v ON_ERROR_STOP=1 <<EOF
CREATE TABLE IF NOT EXISTS test_prompts (
    id INTEGER PRIMARY KEY,
    category TEXT NOT NULL,
    prompt TEXT NOT NULL
);

INSERT INTO test_prompts (id, category, prompt) VALUES
    (1, 'greeting', 'Hello, world!'),
    (2, 'question', 'How are you?')
ON CONFLICT (id) DO NOTHING;
EOF
  if [[ $? -ne 0 ]]; then
    echo "  FAILED: could not populate database"
    exit 1
  fi

  echo "  Verifying data..."
  local count
  count=$(kubectl exec -i "$pg_pod" -n "$DCH_SERVICE_NAMESPACE" -- \
    psql -U dch -d dataconnecthub -tAc "SELECT count(*) FROM test_prompts;" 2>/dev/null)
  if [ "$count" -ge 2 ]; then
    echo "  OK: test_prompts has $count rows"
  else
    echo "  FAILED: expected at least 2 rows, got '$count'"
    exit 1
  fi
}

create_dch_postgres_secret() {
  echo ""
  echo "========== create_dch_postgres_secret ==="
  local URI="postgresql://dch:dch@dch-postgres.${DCH_SERVICE_NAMESPACE}.svc.cluster.local:5432/dataconnecthub"

  kubectl apply --namespace "$DCH_SERVICE_NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: dch-database-config
stringData:
  DATABASE_URL: "$URI"
  url: "$URI"
  secret-config.toml: |
    [database]
    url = "$URI"
EOF
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  echo "Secret dch-database-config created."
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

kind_create

create_dch_postgres
create_dch_postgres_db
verify_dch_postgres_db
create_dch_postgres_secret

#create_tenant_a_namespace
#create_tenant_a_dch_admin
#create_tenant_a_dch_user

