use actix_cors::Cors;
use actix_web::{App, HttpServer, web};
use clap::Parser;

use crate::rest::endpoints::{get_connection, list_connections, not_found};
use crate::utils::ServerConfig;
use anyhow::Result;
use config::{Config, File};

mod rest;
mod utils;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct CommandLineArgs {
    /// Enable JSON logs
    #[arg(short, long, default_value = "false")]
    json_logs: bool,

    /// Config file for this server
    #[arg(short, long, default_value = "config/config.toml")]
    config: String,
}

fn load_config(config_file: String) -> Result<ServerConfig> {
    let config = Config::builder()
        .add_source(File::with_name(config_file.as_str()))
        .build()?;

    let config: ServerConfig = config.try_deserialize()?;
    Ok(config)
}

#[actix_web::main]
async fn main() -> Result<()> {
    let args = CommandLineArgs::parse();
    let config = load_config(args.config)?;

    commons::utils::init_tracing(args.json_logs);
    tracing::info!("Starting DataConnectorHub API service");

    HttpServer::new(|| {
        let cors = Cors::default()
            .allow_any_origin()
            .send_wildcard()
            .allow_any_method()
            .allow_any_header();

        App::new()
            .wrap(cors)
            .service(
                web::scope("/v1/data")
                    .service(web::resource("/connections").to(list_connections))
                    .service(web::resource("/connections/{namespace}").to(list_connections))
                    .service(web::resource("/connections/{namespace}/{name}").to(get_connection)),
            )
            .default_service(web::route().to(not_found))
    })
    .bind((config.server.address, config.server.port))?
    .run()
    .await?;

    Ok(())
}
