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
    pub _database: DatabaseConfig,
}

#[cfg(test)]
mod tests {
    use config::Config;

    use super::*;

    #[test]
    fn test_server_config_deserialize() {
        let toml_str = r#"
            [server]
            address = "127.0.0.1"
            port = 8080

            [_database]
            url = "postgresql://user:pass@localhost:5432/testdb"
        "#;

        let config = Config::builder()
            .add_source(config::File::from_str(toml_str, config::FileFormat::Toml))
            .build()
            .unwrap();

        let server_config: ServerConfig = config.try_deserialize().unwrap();
        assert_eq!(server_config.server.address, "127.0.0.1");
        assert_eq!(server_config.server.port, 8080);
        assert_eq!(
            server_config._database.url,
            "postgresql://user:pass@localhost:5432/testdb"
        );
    }

    #[test]
    fn test_server_config_missing_field() {
        let toml_str = r#"
            [server]
            address = "127.0.0.1"
        "#;

        let config = Config::builder()
            .add_source(config::File::from_str(toml_str, config::FileFormat::Toml))
            .build()
            .unwrap();

        let result = config.try_deserialize::<ServerConfig>();
        assert!(result.is_err());
    }
}
