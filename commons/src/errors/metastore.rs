use thiserror::Error;

#[derive(Error, Debug)]
pub enum MetaStoreError {
    #[error("Connection error: {0}")]
    Connection(String),
    #[error("Invalid request: {0}")]
    InvalidRequest(String),
    #[error("Config error: {0}")]
    Config(String),
    #[error("Query error: {0}")]
    Query(String),
    #[error("Serialization error: {0}")]
    Serialization(String),
    #[error("Deserialization error: {0}")]
    Deserialization(String),
}
