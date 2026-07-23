use pg_meta_store::store::DatabaseConfig;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Server {
    pub address: String,
    pub port: u16,
}

#[derive(Debug, Deserialize)]
pub struct ServerConfig {
    pub server: Server,
    #[serde(rename = "database")]
    pub _database: DatabaseConfig,
}
