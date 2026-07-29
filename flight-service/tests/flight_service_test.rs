use std::sync::Arc;

use arrow::array::{Array, StringArray};
use arrow_flight::{flight_service_server::FlightServiceServer, sql::client::FlightSqlServiceClient};
use commons::api::X_DATA_CONNECTION_ID;
use commons::api::connections::{Admin, DataConnection, DataConnectionType, MetaStore};
use commons::errors::MetaStoreError;
use flight_service::flight::service::TabularDataService;
use flight_service::flight::{InMemorySecretStore, registry::ConnectorsRegistry};
use futures::TryStreamExt;
use postgres_connector::connector::PgConnector;
use std::collections::HashMap;
use std::time::Duration;
use tokio::net::TcpListener;
use tonic::transport::{Channel, Server};
use commons::api::connections::Secret;

struct TestMetaStore;

#[async_trait::async_trait]
impl MetaStore for TestMetaStore {
    async fn get_connection(&self, _tenant_id: &str, _connection_id: &str) -> Result<DataConnection, MetaStoreError> {
        Ok(DataConnection {
            id: "3495723045234587698".to_string(),
            name: "test-db".to_string(),
            data_connection_type_id: "postgres".to_string(),
            format: "tabular".to_string(),
            tenant_id: "tenant-test".to_string(),
            admin: Admin {
                secret_ref: "secret/test-db".to_string(),
            },
            created_at: "2026-07-21T00:00:00Z".to_string(),
            updated_at: "2026-07-21T00:00:00Z".to_string(),
            properties: HashMap::new(),
            credentials: HashMap::from([(
                "url".to_string(),
                "postgresql://db_user@localhost:5432/db_name".to_string(),
            )]),
        })
    }
    async fn get_data_connection_type(&self, _tenant_id: &str, _id: &str) -> Result<DataConnectionType, MetaStoreError> {
        Ok(DataConnectionType {
            id: "pg-jdbc".to_string(),
            tenant_id: None,
            name: "PostgreSQL JDBC".to_string(),
            provider: "postgres".to_string(),
            description: None,
            credentials_fields: vec![commons::api::connections::Field {
                name: "url".to_string(),
                label: "Url".to_string(),
                d_type: "string".to_string(),
                description: Some("The host of the PostgreSQL server".to_string()),
                required: true,
                enum_values: None,
                default_value: None,
            }],
        })
    }
}

#[tokio::test]
async fn test_flight_sql_select_prompts() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let connectors_registry = ConnectorsRegistry::new().with_connector(Arc::new(PgConnector::new(
        Duration::from_secs(300),
        Duration::from_secs(60),
        10,
    )));

    let secret_store = InMemorySecretStore::new(vec![Secret {
        name: "prompts".to_string(),
        namespace: "secret".to_string(),
        properties: HashMap::from([(
            "url".to_string(),
            "postgresql://db_user@localhost:5432/db_name".to_string(),
        )]),
    }]);

    let service = TabularDataService::new(
        Arc::new(connectors_registry),
        Arc::new(TestMetaStore),
        Arc::new(secret_store),
    );

    tokio::spawn(async move {
        Server::builder()
            .add_service(FlightServiceServer::new(service))
            .serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener))
            .await
            .unwrap();
    });

    let channel = Channel::from_shared(format!("http://{addr}"))
        .unwrap()
        .connect()
        .await
        .unwrap();

    let mut client = FlightSqlServiceClient::new(channel);
    client.set_header(X_DATA_CONNECTION_ID, "default/test-db");

    let flight_info = client.execute("SELECT * FROM prompts".to_string(), None).await.unwrap();

    let endpoint = &flight_info.endpoint[0];
    let ticket = endpoint.ticket.clone().unwrap();

    let stream = client.do_get(ticket).await.unwrap();
    let batches: Vec<_> = stream.try_collect().await.unwrap();

    let total_rows: usize = batches.iter().map(|b| b.num_rows()).sum();
    assert_eq!(total_rows, 10);

    for batch in &batches {
        let prompts = batch.column(2).as_any().downcast_ref::<StringArray>().unwrap();
        for i in 0..prompts.len() {
            println!("prompt[{}]: {}", i, prompts.value(i));
        }
    }
}
