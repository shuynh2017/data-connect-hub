#!/bin/bash
#
. ./common-vars.sh

pff_pid=""

cleanup() {
  if [ -n "$pff_pid" ]; then
    kill $pff_pid 2>/dev/null || true
    wait $pff_pid 2>/dev/null || true
  fi
}

echo "  Finding flight-service pod..."
flight_pod=$(oc get po -n "$INFRA_NAMESPACE" -l app.kubernetes.io/name=flight-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
if [ -z "$flight_pod" ]; then
  echo "  FAILED: no flight-service pod found in namespace '$INFRA_NAMESPACE'"
  exit 1
fi
echo "  Pod: $flight_pod"

echo "  Port-forwarding $flight_pod:50051 -> localhost:$FLIGHT_LOCAL_PORT..."
lsof -ti :$FLIGHT_LOCAL_PORT 2>/dev/null | xargs kill 2>/dev/null || true
oc port-forward "pod/$flight_pod" -n "$INFRA_NAMESPACE" "$FLIGHT_LOCAL_PORT:8443" &>/dev/null &
pff_pid=$!
sleep 2

if ! kill -0 $pff_pid 2>/dev/null; then
  echo "  FAILED: port-forward died"
  exit 1
fi
echo "  Port-forward ready (pid=$pff_pid)"
echo ""
