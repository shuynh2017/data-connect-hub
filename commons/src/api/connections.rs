use crate::errors::{MetaStoreError, SecretStoreError};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Admin {
    pub secret_ref: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DataConnection {
    pub id: String,
    pub name: String,
    pub data_connection_type_id: String,
    pub format: String,
    pub tenant_id: String,
    pub admin: Admin,
    pub created_at: String,
    pub updated_at: String,
    pub properties: HashMap<String, String>,
    // Skip credentials from serialization. Credentials are loaded from the secret and only kept in memory.
    #[serde(skip)]
    pub credentials: HashMap<String, String>,
}
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct EnumValue {
    pub value: String,
    pub label: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Field {
    pub name: String,
    pub label: String,
    pub description: Option<String>,
    pub required: bool,
    #[serde(rename = "type")]
    pub d_type: String,
    pub enum_values: Option<Vec<EnumValue>>,
    pub default_value: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DataConnectionType {
    pub id: String,
    pub tenant_id: Option<String>,
    pub name: String,
    pub provider: String,
    pub description: Option<String>,
    pub credentials_fields: Vec<Field>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Secret {
    pub name: String,
    pub namespace: String,
    pub properties: HashMap<String, String>,
}

#[async_trait::async_trait]
pub trait MetaStore {
    async fn get_connection(&self, tenant_id: &str, uid: &str) -> Result<DataConnection, MetaStoreError>;
    async fn get_data_connection_type(&self, tenant_id: &str, id: &str) -> Result<DataConnectionType, MetaStoreError>;
}

#[async_trait::async_trait]
pub trait SecretStore { 
    async fn get_secret(&self, namespace: &str, name: &str) -> Result<&Secret, SecretStoreError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_connection() -> DataConnection {
        DataConnection {
            id: "123".to_string(),
            name: "test-conn".to_string(),
            data_connection_type_id: "postgres".to_string(),
            format: "jdbc".to_string(),
            tenant_id: "tenant-1".to_string(),
            admin: Admin {
                secret_ref: "secret/test-conn".to_string(),
            },
            created_at: "2026-01-01T00:00:00Z".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
            properties: HashMap::from([("key".to_string(), "value".to_string())]),
            credentials: HashMap::new(),
        }
    }

    #[test]
    fn test_admin_serialize_deserialize() {
        let admin = Admin {
            secret_ref: "secret/test".to_string(),
        };
        let json = serde_json::to_string(&admin).unwrap();
        let deserialized: Admin = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.secret_ref, admin.secret_ref);
    }

    #[test]
    fn test_data_connection_serialize_deserialize() {
        let fixture = serde_json::json!({
            "id": "123",
            "name": "test-conn",
            "data_connection_type": "postgres",
            "format": "jdbc",
            "tenant_id": "tenant-1",
            "admin": { "secret_ref": "secret/test-conn", "location": "postgresql://localhost:5432/db" },
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
            "properties": { "key": "value" }
        });

        let conn: DataConnection = serde_json::from_value(fixture.clone()).unwrap();

        assert_eq!(conn.id, "123");
        assert_eq!(conn.name, "test-conn");
        assert_eq!(conn.data_connection_type_id, "postgres");
        assert_eq!(conn.format, "jdbc");
        assert_eq!(conn.tenant_id, "tenant-1");
        assert_eq!(conn.admin.secret_ref, "secret/test-conn");
        assert_eq!(conn.created_at, "2026-01-01T00:00:00Z");
        assert_eq!(conn.updated_at, "2026-01-01T00:00:00Z");
        assert_eq!(conn.properties["key"], "value");

        let round_tripped = serde_json::to_value(&conn).unwrap();
        assert_eq!(round_tripped, fixture);
    }

    #[test]
    fn test_data_connection_clone() {
        let conn = sample_connection();
        let cloned = conn.clone();

        assert_eq!(cloned.id, conn.id);
        assert_eq!(cloned.admin.secret_ref, conn.admin.secret_ref);
        assert_eq!(cloned.properties, conn.properties);
    }
}
