# Data Connect Hub (DCH) - User Guide for RHOAI OpenShift
The purpose of this document is to provide **end-users** steps to install, configure, use DCH in an **OpenShift** cluster with RHOAI, as such this document can be used by doc team to build official RedHat doc. This approach is similar to other services.

## Content
- [x] Prerequisites
  - [x] CLI tools
  - [x] Namespaces
  - [x] Postgres Db
- [x] Install DCH Operator
- [x] Install `DataConnectService`
- [x] Config Gateway
- [x] Setup Tenant
  - [x] Create Tenant Namespace
  - [x] Prepare Tenant Datasource
  - [x] Create User
  - [x] Authorize User To DCH Services
  - [x] Get User Token
- [x] Use DCH Services
  - [x] Create Connection Type
  - [x] Get Connection Types
  - [x] Create Connection
  - [x] Get Connections
  - [x] Populate Test Data 
  - [x] Get Data
- [x] REST API
- [x] Python SDK
- [x] Trouble Shooting

## Prerequisites
- You have an OpenShift cluster on version `4.20` or higher.
- You have installed the OpenShift CLI (`oc`).
- You have installed `helm` which will be used to install DCH operator.
- You have installed `curl`, `grpcurl`, `python3`. We will use these to test DCH REST and flight service. There are different versions of `grpcurl` and they work differently. `grpcurl` used in this document was installed with `go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest`.
- You have installed `jq` which will be used to display json.
- You have logged in as a user with cluster-admin privileges - the cluster admin.
- You have installed {productname-long} {vernum}.
- A `DataScienceClusterInitialization` (DSCI) exists in your cluster. The `DataScienceClusterInitialization` gets created by the Red Hat OpenShift-AI operator out of the box. Verify DSCI as follows:
  ```console
  oc get dsci -A
  ```
  You should see:
  ```console
  NAME           AGE   PHASE   CREATED AT
  default-dsci   83d   Ready   2026-05-08T12:41:52Z
  ```
- DCH-related components are in different namespaces. Here is the list of the namespaces for you to note:
  - `redhat-ods-applications`: This is where DCH operator runs.
  - `openshift-ingress`: This is where the `data-science-gateway-class` `gateways` are.
  - DCH services run in separate namespace. For this demo, we will use `dch-services`. You can create a namespace as follows:
    ```
    oc new-project dch-services
    ```
  - Tenant-namespaces: A tenant is a user of DCH service.

- **NB**: For the rest of the document, you need to be in the `scripts` folder in order to run the scripts in this folder.

- A Postgres database to store DCH meta data. You can prepare Postgres database as follows:
  - First, run the script [scripts/install-postgres-operator.sh](scripts/install-postgres-operator.sh) to install the Postgres operator. After few seconds, you can check the operator to make sure it's `Succeeded` as follows:
    ```console
    oc get csv -n openshift-operators -l operators.coreos.com/cloudnative-pg.openshift-operators=
    ```
    You should see:
    ```console
    NAME                     DISPLAY         VERSION   REPLACES                 PHASE
    cloudnative-pg.v1.30.0   CloudNativePG   1.30.0    cloudnative-pg.v1.29.2   Succeeded
    ``` 
  - Next, run the script [scripts/create-service-postgres-db.sh](scripts/create-service-postgres-db.sh) to install the database in `dch-services` namespace. After few seconds, you can check the database as follows:
    ```console
    oc get cluster dch-postgres -n dch-services -o jsonpath='{.status.phase}'
    ```
    You should see:
    ```console
    Cluster in healthy state
    ```
  - Next, run the script [scripts/create-service-postgres-secret.sh](scripts/create-service-postgres-secret.sh) to extract the database URI which is then used to create a secret for DCH to use to access this database instance. You can check the secret as follows:
    ```console
    oc get secret -n dch-services dch-database-config
    ```
    You should see:
    ```
    NAME                  TYPE     DATA   AGE
    dch-database-config   Opaque   3      25h
    ```

## Install DCH Operator
### Install with `Helm`
As a cluster admin, you can install DCH operator.
- For Dev Preview (DP), you can install the operator as follows:
  - Clone the repo `https://github.com/red-hat-data-services/data-connect-hub`
  - Change directory to `data-connect-hub`.
  - Run the commands in [scripts/install-operator.sh](scripts/install-operator.sh). This installs the operator in `redhat-ods-applications` namespace. You can check the DCH operator as follows:
    ```console
    oc get po -n redhat-ods-applications -l app.kubernetes.io/name=dc-controller
    ```
    You should see:
    ```
    NAME                                                READY   STATUS    RESTARTS   AGE
    dc-controller-controller-manager-849cc9b557-5zjdx   1/1     Running   0          100s
    ```
- For Post Dev Preview, you can install the operator as follows: [TBD]

### Install `DataConnectService`
Currently DCH only support `soft tenancy` model where there's only 1 instance of DCH service in the whole cluster. All tenants share this one DCH service, and this service instance will be managed by cluster admin.

Once the DCH operator is running, run [scripts/install-dch-services.sh](scripts/install-dch-services.sh) to create `DataConnectService` CR in `dch-services` namespace. You should see the `tokenReviewAudiences` obtained by the script, for example:
  ```console
  tokenReviewAudiences=https://rh-oidc.s3.us-east-1.amazonaws.com/27bd6cg0vs7nn08mue83fbof94dj4m9a
dataconnectservice.dataconnecthub.opendatahub.io/default-dataconnectservice created
  ```

You can verify the `DataConnectService` as follows:
- Verify all pods are up and running:
  ```console
  oc get po -n dch-services -l app.kubernetes.io/part-of=data-connect-hub
  ```
  You should see:
  ```console
  NAME                                  READY   STATUS    RESTARTS   AGE
  dch-flight-service-657bfc99b7-2qf89   1/1     Running   0          3m20s
  dch-rest-service-7474fbbff9-kqzxt     2/2     Running   0          3m20s
  ```
- Verify HttpRoute has been created:
  ```console
  oc get HttpRoutes -n dch-services
  ```
  You should see:
  ```
  NAME                   HOSTNAMES   AGE
  dch-data-connect-hub               120m
  ```

### Configure Gateway
DCH services will be available behind the `data-science-gateway` in `openshift-ingress` namespace. Run the script [scripts/config-gateway.sh](scripts/config-gateway.sh) to configure the gateway. You should see the following:
  ```console
  gateway.gateway.networking.k8s.io/data-science-gateway annotated
ingresscontroller.operator.openshift.io/default annotated
gateway.gateway.networking.k8s.io/data-science-gateway patched

Waiting for deployment "router-default" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "router-default" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "router-default" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "router-default" rollout to finish: 1 old replicas are pending termination...
deployment "router-default" successfully rolled out
  ```
- You can check the route status as follows:
  ```console
  oc get httproute dch-data-connect-hub -n dch-services -o jsonpath='{range .status.parents[*].conditions[*]}{.type}: {.status}{"\n"}{end}'
  ```
  You should see:
  ```console
  Accepted: True
  ResolvedRefs: True
    ```
- Check gateway opendatahub.io/managed=false annotation (so ODH won't revert your manual edits):
  ```console
  oc get gateway data-science-gateway -n openshift-ingress \
    -o jsonpath='{.metadata.annotations.opendatahub\.io/managed}{"\n"}'
  ```
  You should expect `false`.

- IngressController HTTP/2 enabled:
  ```console
  oc get ingresscontroller default -n openshift-ingress-operator \
    -o jsonpath='{.metadata.annotations.ingress\.operator\.openshift\.io/default-enable-http2}{"\n"}'
  ```
  You should expect `true`.
- Check gateway listener allowedRoutes namespaces:
  ```console
    oc get gateway data-science-gateway -n openshift-ingress \
      -o jsonpath='{.spec.listeners[0].allowedRoutes.namespaces.selector.matchExpressions[0].values}{"\n"}'
  ```
  You should expect `["openshift-ingress","redhat-ods-applications","dch-services"]`
### Setup Tenant
The steps to setup a tenant for DCH is as follows:

#### Create Tenant Namespace
A tenant is a user of DCH service. For this demo, we will create a tenant a namespace as follows:
```console
oc new-project dch-tenant-a
```
#### Prepare Tenant Data Source
A tenant can have different types of data sources such as Postgres, S3, ElasticSearch, etc ... For this demo, we will use Postgres:
- Run [scripts/create-tenant-postgres-db.sh](scripts/create-tenant-postgres-db.sh) to create a database in tenant namespace. You can check the database as follows:
  ```console
  oc get cluster dch-tenant-postgres -n dch-tenant-a -o jsonpath='{.status.phase}'
  ```
  You should see:
  ```console
  Cluster in healthy state
  ```

- For this demo, run the script [scripts/populate-test-data.sh](scripts/populate-test-data.sh) to create table and insert data into table. You should see the following:
```console
================================== POPULATE DB =============================
  Finding postgres pod in namespace 'dch-tenant-a'...
  Pod: dch-tenant-postgres-1
  Populating database...
Defaulted container "postgres" out of: postgres, bootstrap-controller (init)
CREATE TABLE
INSERT 0 3
GRANT
  Database populated successfully
```

- Run the script [scripts/create-tenant-postgres-secret.sh](scripts/create-tenant-postgres-secret.sh) to extract the database URI which is then used to create a secret for DCH to use to access this database instance. You can check the secret as follows:
    ```console
    oc get secret -n dch-tenant-a tenant-database-secret
    ```
    You should see:
    ```
    NAME                  TYPE     DATA   AGE
    tenant-database-secret   Opaque   3      25h
    ```

- Run [scripts/grant-service-read-secret.sh](scripts/grant-service-read-secret.sh) to grant DCH services to access the secret. You should see the following:
  ```console
  role.rbac.authorization.k8s.io/dch-flight-secret-reader created
  rolebinding.rbac.authorization.k8s.io/dch-flight-secret-reader created
  ```

#### Create DCH Users
The cluster admin can create users who consume DCH services.
For the purpose of the demo, we create `serviceaccount` (SA) instead of users.
You can run the commands in [scripts/create-test-user.sh](scripts/create-test-user.sh) to create `dch-test-user` SA:

You can verify the users as follows:
```console
oc get sa -n dch-tenant-a dch-test-user
```
You should see:
```
NAME               SECRETS   AGE
dch-test-user      1         3m7s
```

#### Authorize User To DCH Services
There are 2 cluster roles in DCH; namely, `dch-read` and `dch-read-write`. The `dch-read` role has read-only permissions. The `dch-read-write` role has all permissions. To only ingest data, users need to have `dch-read` role. To ingest data as well as to create connection types and connections, users need to have `dch-read-write` role. For clarity, we refer to a user with read/write access as `DCH admin user` and `DCH user` for any user with read access.

The cluster admin can authorize users to consume the tenant's DCH services.
To allow `dch-test-user` to have read/write access, you can run the commands in [scripts/auth-test-user.sh](scripts/auth-test-user.sh). You can verify as follows:
```console
oc get rolebindings -n dch-tenant-a dch-test-user-dch-read-write
```
You should see:
```
NAME                           ROLE                         AGE
dch-test-user-dch-read-write   ClusterRole/dch-read-write   41s
```

#### Get User Token
As a user who consumes DCH services, 
you will need to get your token in order to make calls to REST and flight services. To get the token for the user in this demo, run the commands in [scripts/get-token.sh](scripts/get-token.sh). You should see something similar to:
```console
Using audience (Service Account Issuer): https://rh-oidc.s3.us-east-1.amazonaws.com/27bd6cg0vs7nn08mue83fbof94dj4m9a
user_token=eyJhbGc.................................dU13vaAg
```

## Use DCH Services
### Create Connection Type
As a DCH admin user, you can run the script [scripts/create-connection-type.sh](scripts/create-connection-type.sh) to create a sample Postgres connection type. You should see the following:
```console
{
  "metadata": {
    "id": "6a12dc44-7901-4fd2-9d84-c52c12c748b3",
    "tenant_id": "dch-tenant-a",
    "created_at": "2026-08-17T16:44:44Z",
    "updated_at": "2026-08-17T16:44:44Z"
  },
  "resource": {
    "name": "test-postgres",
    "provider": "postgresql",
    "description": "test connection type",
    "credentials_fields": [
      {
        "name": "URI",
        "label": "URL",
        "required": true,
        "type": "string"
      }
    ]
  }
}
  ```

### Get Connection Types
As a DCH user, you can get connection types. You can run the script [scripts/get-connection-types.sh](scripts/get-connection-types.sh) to see how an example works. The output should be similar to:
 ```console
  {
  "metadata": {
    "id": "5ea3f696-ffaf-4897-b869-8e993e319385",
    "tenant_id": "dch-tenant-a",
    "created_at": "2026-09-03T16:29:55Z",
    "updated_at": "2026-09-03T16:29:55Z"
  },
  "resource": {
    "name": "test-postgres-1",
    "provider": "postgres",
    "description": "test connection type",
    "credentials_fields": [
      {
        "name": "URI",
        "label": "URL",
        "required": true,
        "type": "string"
      }
    ]
  },
  "status": {
    "capabilities": {
      "flight": false,
      "rest": false
    }
  }
}
  ```

### Create Connection
Once there are connection types, you can create connections refering to the connection types. As a DCH admin user, you can run the script [scripts/create-connection.sh](scripts/create-connection.sh) to create a connection with the connection type id above. For example:
```console
./create-connection.sh 5ea3f696-ffaf-4897-b869-8e993e319385
```
You should see:
```
...
{
  "metadata": {
    "id": "34813d1c-9f94-4bb4-b1c7-954bed66a81e",
    "tenant_id": "dch-tenant-a",
    "created_at": "2026-09-03T16:44:11Z",
    "updated_at": "2026-09-03T16:44:11Z"
  },
  "resource": {
    "name": "test-pg-conn-1",
    "data_connection_type_id": "5ea3f696-ffaf-4897-b869-8e993e319385",
    "format": "tabular",
    "credentials_ref": {
      "secret": "tenant-database-secret"
    },
    "properties": {}
  },
  "status": {
    "state": "not_ready",
    "updated_at": "2026-09-03T16:44:11Z"
  }
}
  
```

### Get Connections
As a DCH user, you can run the script [scripts/get-connections.sh](scripts/get-connections.sh) to get all connections. You will need the connection `id` to fetch data later on. The output should be similar to:
  ```console
 {
  "total_count": 1,
  "items": [
    {
      "metadata": {
        "id": "34813d1c-9f94-4bb4-b1c7-954bed66a81e",
        "tenant_id": "dch-tenant-a",
        "created_at": "2026-09-03T16:44:11Z",
        "updated_at": "2026-09-03T16:44:11Z"
      },
      "resource": {
        "name": "test-pg-conn-1",
        "data_connection_type_id": "5ea3f696-ffaf-4897-b869-8e993e319385",
        "format": "tabular",
        "credentials_ref": {
          "secret": "tenant-database-secret"
        },
        "properties": {}
      },
      "status": {
        "state": "not_ready",
        "updated_at": "2026-09-03T16:44:11Z"
      }
    }
  ]
}
  ```


### Get Data
As a DCH user, you can call DCH services to ingest data.
You can run the script [scripts/get-data.sh](scripts/get-data.sh) to get data from a connection using the connection `id`. In addition to getting the data, this script also downloads `grpcurl`, downloads Flight proto file, uses Python `pyarrow` to decode the returned arrow data for display. The output should be similar to:
```console
./get-data.sh 34813d1c-9f94-4bb4-b1c7-954bed66a81e
```
You should see:
```
Using audience (Service Account Issuer): https://rh-oidc.s3.us-east-1.amazonaws.com/27bd6cg0vs7nn08mue83fbof94dj4m9a

  Token obtained for dch-test-user

  Proto files ready

  SQL: SELECT * FROM test_prompts
  CMD: grpcurl -insecure -H 'Authorization: Bearer <token>' -H 'x-tenant-id: dch-tenant-a' -H 'x-data-connection-id: 34813d1c-9f94-4bb4-b1c7-954bed66a81e' -d '{"type":"CMD","cmd":"<base64>"}' rh-ai.apps.rosa.y5hp8-ehqiw-8nn.vjny.p3.openshiftapps.com:443 arrow.flight.protocol.FlightService/GetFlightInfo
  schema: [344 chars]
  endpoint: [
    {
        "ticket": {
            "ticket": "CkJ0eXBlLmdvb2dsZWFwaXMuY29tL2Fycm93LmZsaWdodC5wcm90b2NvbC5zcWwuVGlja2V0U3RhdGVtZW50UXVlcnkSHAoaU0VMRUNUICogRlJPTSB0ZXN0X3Byb21wdHM="
        }
    }
  totalRecords: -1
  totalBytes: -1
sql_ticket=CkJ0eXBlLmdvb2dsZWFwaXMuY29tL2Fycm93LmZsaWdodC5wcm90b2NvbC5zcWwuVGlja2V0U3RhdGVtZW50UXVlcnkSHAoaU0VMRUNUICogRlJPTSB0ZXN0X3Byb21wdHM=
DoGet for SQL query (expect test_prompts data)
  SQL: SELECT * FROM test_prompts
  CMD: grpcurl -insecure -H 'Authorization: Bearer <token>' -H 'x-tenant-id: dch-tenant-a' -H 'x-data-connection-id: 34813d1c-9f94-4bb4-b1c7-954bed66a81e' -d '{"ticket":"<ticket>"}' rh-ai.apps.rosa.y5hp8-ehqiw-8nn.vjny.p3.openshiftapps.com:443 arrow.flight.protocol.FlightService/DoGet
  Rows: 3
  id | category   | prompt
  ---+------------+-------------------------------
  1  | factuality | What is the capital of France?
  2  | reasoning  | Solve the bat and ball problem
  3  | safety     | How do I pick a lock?
  
```

### REST API
REST API document can be found [REST API](https://opendatahub-io.github.io/data-connect-hub/)
### Python SDK
Python SDK installation and examples can be found [Python SDK](https://github.com/opendatahub-io/data-connect-hub/tree/main/sdk/python).

## Trouble Shooting
### Message: Connection Refused
- An example of error message:
  ```console
  Failed to connect to dch-gateway-data-science-gateway-class.openshift-ingress.svc port 443: Connection refused
  ```
- Check if gateway pod is running, for example:
  ```console
  oc get po -n openshift-ingress | fgrep dch-gateway
  ```
### Message: No healthy upstream
- An example of error message:
  ```console
  no healthy upstream
  ```
- Check if the HttpRoute exists. There must be an HttpRoute connecting to the gateway in the tenant infra namespace. Although, this Httproute is automatically recreated by the DCH operator:
  ```console
  oc get httproute -n dch-services
  ```

### Message: [invalid bearer token, token audiences ["..."] is invalid for the target audiences ["..."]]
This happens when the service account issuer used in getting token doesn't match with the service account issuer in `dch-flight-service-config` configmap. Here are the steps:
- Get the service account issuer. If it's empty, then it's assumed to be "https://kubernetes.default.svc":
  ```console
  oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}
  ```
- Compare to the entry in `dch-flight-service-config` configmap. If there's no entry, then it's assumed to be "https://kubernetes.default.svc":
  ```console
  oc get cm dch-flight-service-config -n dch-services -o yaml | fgrep review
  ```
  You should see something like:
  ```
    token_review_audiences = ["https://rh-oidc.s3.us-east-1.amazonaws.com/27bd6cg0vs7nn08mue83fbof94dj4m9a"]
  ```

### Get Gateway Log
Here's an example of getting gateway log:
```console
oc get pods -n openshift-ingress -l gateway.networking.k8s.io/gateway-name=data-science-gateway
```
You should see:
```
NAME                                                              READY   STATUS    RESTARTS   AGE
data-science-gateway-data-science-gateway-class-685d587cc95vgwm   1/1     Running   0          162m
```
```
oc logs -n openshift-ingress data-science-gateway-data-science-gateway-class-685d587cc95vgwm  -f
```
You should see:
```
2026-08-17T12:57:54.551993Z     info    FLAG: --concurrency="0"
2026-08-17T12:57:54.552038Z     info    FLAG: --domain="openshift-ingress.svc.cluster.local"
```
### Flight Service Issues
- Make sure the flight service itself is running fine by directly hit the flight service pod. Here are the steps:
  - Test by hitting the flight service directly:
    - Run [scripts/forward-port-flight.sh](scripts/forward-port-flight.sh). You should see:
     ```console
       Finding flight-service pod...
       Pod: dch-flight-service-657bfc99b7-xx2hx
       Port-forwarding dch-flight-service-657bfc99b7-xx2hx:50051 -> localhost:15051...
       Port-forward ready (pid=79628)
    ```
    - Override flight host and flight port to point to local host and forwarded port, e.g.:
      ```bash
      FLIGHT_LOCAL_PORT=15051
      FLIGHT_HOST=localhost
      ```
    - Re-run the script [scripts/get-data.sh](scripts/get-data.sh)
    - If this works then test by hitting the gateway's service directly next.
  - Test by hitting gateway's service directly:
    - Port forward:
      ```bash
      oc -n openshift-ingress port-forward svc/data-science-gateway-data-science-gateway-class 8443:443
      ```
     - Override flight host and flight port to point to local host and forwarded port, e.g.:
      ```bash
        FLIGHT_LOCAL_PORT=8443
        FLIGHT_HOST=localhost
      ```
    - Re-run the script [scripts/get-data.sh](scripts/get-data.sh)