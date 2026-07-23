use thiserror::Error;

#[derive(Error, Debug)]
pub enum ApiError {
    #[error("SQL error: {0}")]
    SQLError(String),
    #[error("Connection error: {0}")]
    ConnectionError(String),
    #[error("No data returned")]
    NoDataError(),
    #[error("Invalid request: {0}")]
    InvalidRequest(String),
    #[error("Config error: {0}")]
    ConfigError(String),
}
