use crate::errors::metastore::MetaStoreError;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DataLocation {
    pub url: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DataConnection {
    pub id: String,
    pub namespace: String,
    pub name: String,
    pub provider: String,
    pub format: String,
    pub tenant_id: String,
    pub location: DataLocation,
    pub created_at: String,
    pub updated_at: String,
    pub properties: HashMap<String, String>,
}

#[async_trait::async_trait]
pub trait MetaStore {
    async fn get_connection(&self, uid: &str) -> Result<DataConnection, MetaStoreError>;
}
