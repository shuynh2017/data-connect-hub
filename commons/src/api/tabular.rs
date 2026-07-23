use crate::api::connections::DataConnection;
use crate::errors::ApiError;
use arrow::datatypes::Schema;
use arrow::record_batch::RecordBatch;
use futures::Stream;
use std::pin::Pin;
use std::sync::Arc;

pub type OutputStream = Pin<Box<dyn Stream<Item = Result<RecordBatch, ApiError>> + Send>>;
pub type QueryOutput = Result<OutputStream, ApiError>;

pub struct TabularState {
    pub query: String,
    pub schema: Arc<Schema>,
}

impl TabularState {
    pub fn new(query: String, schema: Arc<Schema>) -> Self {
        Self { query, schema }
    }
}

#[async_trait::async_trait]
pub trait TabularReader: Send + Sync {
    fn provider(&self) -> String;

    async fn schema(&self, query: &str) -> Result<Arc<TabularState>, ApiError>;

    async fn read(&self, state: Arc<TabularState>, batch_size: usize) -> QueryOutput;
}

#[async_trait::async_trait]
pub trait FlightConnector: Send + Sync {
    fn provider(&self) -> String;
    async fn get_reader(&self, data_connection: &DataConnection) -> Result<Arc<dyn TabularReader>, ApiError>;
}
