use std::sync::Arc;

use arrow::array::{Array, StringArray};
use arrow_flight::{flight_service_server::FlightServiceServer, sql::client::FlightSqlServiceClient};
use commons::api::connections::{DataConnection, DataLocation, MetaStore};
use commons::errors::metastore::MetaStoreError;
use flight_service::flight::registry::ConnectorsRegistry;
use flight_service::flight::service::TabularDataService;
use futures::TryStreamExt;
use std::collections::HashMap;
use tokio::net::TcpListener;
use tonic::transport::{Channel, Server};

struct TestMetaStore;

#[async_trait::async_trait]
impl MetaStore for TestMetaStore {
    async fn get_connection(&self, _connection_id: &str) -> Result<DataConnection, MetaStoreError> {
        Ok(DataConnection {
            uid: "3495723045234587698".to_string(),
            namespace: "test".to_string(),
            name: "test-db".to_string(),
            provider: "postgres".to_string(),
            format: "jdbc".to_string(),
            tenant_id: "tenant-test".to_string(),
            location: DataLocation {
                url: "postgresql://mdanciu@localhost:5432/mdanciu".to_string(),
            },
            created_at: "2026-07-21T00:00:00Z".to_string(),
            updated_at: "2026-07-21T00:00:00Z".to_string(),
            properties: HashMap::new(),
        })
    }
}

#[tokio::test]
async fn test_flight_sql_select_prompts() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let service = TabularDataService::new(Arc::new(ConnectorsRegistry::new()), Arc::new(TestMetaStore));

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
    client.set_header("x-dch-connection-id", "default/test-db");

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
