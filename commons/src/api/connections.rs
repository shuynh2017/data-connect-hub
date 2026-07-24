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

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_connection() -> DataConnection {
        DataConnection {
            id: "123".to_string(),
            namespace: "test-ns".to_string(),
            name: "test-conn".to_string(),
            provider: "postgres".to_string(),
            format: "jdbc".to_string(),
            tenant_id: "tenant-1".to_string(),
            location: DataLocation {
                url: "postgresql://localhost:5432/db".to_string(),
            },
            created_at: "2026-01-01T00:00:00Z".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
            properties: HashMap::from([("key".to_string(), "value".to_string())]),
        }
    }

    #[test]
    fn test_data_location_serialize_deserialize() {
        let location = DataLocation {
            url: "postgresql://localhost:5432/db".to_string(),
        };
        let json = serde_json::to_string(&location).unwrap();
        let deserialized: DataLocation = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.url, location.url);
    }

    #[test]
    fn test_data_connection_serialize_deserialize() {
        let conn = sample_connection();
        let json = serde_json::to_string(&conn).unwrap();
        let deserialized: DataConnection = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.id, conn.id);
        assert_eq!(deserialized.namespace, conn.namespace);
        assert_eq!(deserialized.name, conn.name);
        assert_eq!(deserialized.provider, conn.provider);
        assert_eq!(deserialized.format, conn.format);
        assert_eq!(deserialized.tenant_id, conn.tenant_id);
        assert_eq!(deserialized.location.url, conn.location.url);
        assert_eq!(deserialized.created_at, conn.created_at);
        assert_eq!(deserialized.updated_at, conn.updated_at);
        assert_eq!(deserialized.properties, conn.properties);
    }

    #[test]
    fn test_data_connection_clone() {
        let conn = sample_connection();
        let cloned = conn.clone();

        assert_eq!(cloned.id, conn.id);
        assert_eq!(cloned.namespace, conn.namespace);
        assert_eq!(cloned.location.url, conn.location.url);
        assert_eq!(cloned.properties, conn.properties);
    }
}
