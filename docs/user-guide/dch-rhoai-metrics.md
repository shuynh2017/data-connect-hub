# DCH - Metrics

## Prerequisites
- Red Hat build of OpenTelemetry operator
- A working installation of DCH
- OpenShift User Workload Monitoring (UWM) is enabled in the cluster for Prometheus metrics collection. For instructions on how to do this, refer to, [the official Red Hat docs](https://docs.redhat.com/en/documentation/monitoring_stack_for_red_hat_openshift/4.20/html/configuring_user_workload_monitoring/index). You can check by:

  ```
  oc get cm cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}'
  ```
  You should get the following if it's enabled:
  ```
  enableUserWorkload: true
  ```

## Enable DCH Metrics
### Label Namespace
Namespaces containing services to be monitored must be labeled appropriately for metrics to be collected. Assuming DCH services run in `dch-services` namespace, run the following:

```console
kubectl label namespaces dch-services opendatahub.io/dashboard=true monitoring.opendatahub.io/scrape=true 
```
You should see:
```
namespace/dch-services labeled
```

### Enable DCH Service Metrics
Metrics are enabled by default for DCH REST and flight services. You can check as follows:

```console
oc get cm -n dch-services dch-default-dataconnectservice-flight-config -o yaml
```
You should see:
```console
  [metrics]
    enabled = true
    address = "0.0.0.0"
    port = 9090
```
And
```console
oc get cm -n dch-services dch-rest-service-config -o yaml
```
You should see:
```console
  [metrics]
    enabled = true
    address = "0.0.0.0"
    port = 9090
```

### Create ServiceMonitor CR
ServiceMonitor CR is automatically created. You can check as follows:
```
oc get servicemonitor -n dch-services
```
You should see:
```
NAME                 AGE
dch-servicemonitor   8s
```

### NetworkPolicy
A network policy is needed to allow ingress to target namespace for metric scraping. In this case, there are already dch-flight-service and dch-rest-service networkpolicy to allow ingress. You can query as follows:
```console
 oc get networkpolicy -n dch-services
```
You should see:
```
NAME                 POD-SELECTOR                            AGE
dch-flight-service   app.kubernetes.io/name=flight-service   26h
dch-rest-service     app.kubernetes.io/name=rest-service     26h
```

## Query Metrics
Finally, to check metrics have been successfuly scraped:
```
TOKEN=$(oc whoami -t)
THANOS=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
curl -sk -G -H "Authorization: Bearer $TOKEN" "https://$THANOS/api/v1/query" \
    --data-urlencode 'query={__name__=~"dch_flight.*"}' | jq '.data.result'
```
You should see:
```
[
  {
    "metric": {
      "__name__": "dch_flight_request_duration_seconds",
      "container": "flight-service",
      "endpoint": "metrics",
      "instance": "10.130.2.33:9090",
      "job": "dch-flight-service",
      "method": "arrow.flight.protocol.FlightService/DoGet",
      "namespace": "dch-services",
      "operation": "statement",
      "pod": "dch-flight-service-7dc75cb9c5-26r8z",
      "prometheus": "openshift-user-workload-monitoring/user-workload",
      "quantile": "0.0",
      "service": "dch-flight-service",
      "status": "OK"
    },
    "value": [
      1789749781.221,
      "0"
    ]
  },
  {
    "metric": {
      "__name__": "dch_flight_request_duration_seconds",
      "container": "flight-service",
      "endpoint": "metrics",
      "instance": "10.130.2.33:9090",
      "job": "dch-flight-service",
      "method": "arrow.flight.protocol.FlightService/DoGet",
      "namespace": "dch-services",
      "operation": "statement",
      "pod": "dch-flight-service-7dc75cb9c5-26r8z",
      "prometheus": "openshift-user-workload-monitoring/user-workload",
      "quantile": "0.5",
      "service": "dch-flight-service",
      "status": "OK"
    },
    "value": [
      1789749781.221,
      "0"
    ]
  },
```

## Metrics
### dch_flight_request_duration_seconds
