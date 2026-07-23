use crate::flight::registry::ConnectorsRegistry;
use arrow_flight::{
    FlightDescriptor, FlightEndpoint, FlightInfo, Ticket,
    encode::FlightDataEncoderBuilder,
    error::FlightError,
    flight_service_server::FlightService,
    sql::{
        CommandGetSqlInfo, CommandStatementQuery, ProstMessageExt, SqlInfo, TicketStatementQuery,
        metadata::SqlInfoDataBuilder, server::FlightSqlService,
    },
};
use commons::api::connections::MetaStore;
use futures::TryStreamExt;
use log::info;
use prost::Message;
use prost::bytes::Bytes;
use std::sync::Arc;
use tonic::{Request, Response, Status};

pub struct TabularDataService {
    connectors_registry: Arc<ConnectorsRegistry>,
    meta_store: Arc<dyn MetaStore + Send + Sync>,
    sql_info: arrow_flight::sql::metadata::SqlInfoData,
}

impl TabularDataService {
    pub fn new(connectors_registry: Arc<ConnectorsRegistry>, meta_store: Arc<dyn MetaStore + Send + Sync>) -> Self {
        let mut builder = SqlInfoDataBuilder::new();
        builder.append(SqlInfo::FlightSqlServerName, "Data Connect Hub");
        builder.append(SqlInfo::FlightSqlServerVersion, env!("CARGO_PKG_VERSION"));
        builder.append(SqlInfo::FlightSqlServerArrowVersion, "1.3");
        builder.append(SqlInfo::FlightSqlServerReadOnly, true);
        builder.append(SqlInfo::FlightSqlServerSql, true);
        builder.append(SqlInfo::FlightSqlServerSubstrait, false);

        Self {
            connectors_registry,
            meta_store,
            sql_info: builder.build().expect("valid sql info"),
        }
    }

    fn query_to_string(query: &CommandGetSqlInfo) -> Vec<String> {
        query
            .info
            .iter()
            .map(|id| {
                SqlInfo::try_from(*id as i32)
                    .map(|s| format!("{s:?}"))
                    .unwrap_or_else(|_| format!("Unknown({id})"))
            })
            .collect()
    }
}

#[tonic::async_trait]
impl FlightSqlService for TabularDataService {
    type FlightService = TabularDataService;

    async fn register_sql_info(&self, _id: i32, _result: &SqlInfo) {}

    async fn get_flight_info_sql_info(
        &self,
        query: CommandGetSqlInfo,
        request: Request<FlightDescriptor>,
    ) -> Result<Response<FlightInfo>, Status> {
        let requested: Vec<String> = Self::query_to_string(&query);

        info!("get_flight_info_sql_info: {:?}", requested);

        let flight_descriptor = request.into_inner();
        let ticket = Ticket::new(query.as_any().encode_to_vec());
        let endpoint = FlightEndpoint::new().with_ticket(ticket);

        let flight_info = FlightInfo::new()
            .try_with_schema(self.sql_info.schema().as_ref())
            .map_err(|e| Status::internal(e.to_string()))?
            .with_descriptor(flight_descriptor)
            .with_endpoint(endpoint);

        Ok(Response::new(flight_info))
    }

    async fn do_get_sql_info(
        &self,
        query: CommandGetSqlInfo,
        _request: Request<Ticket>,
    ) -> Result<Response<<Self as FlightService>::DoGetStream>, Status> {
        let requested: Vec<String> = Self::query_to_string(&query);

        info!("do_get_sql_info: {:?}", requested);

        let batch = query
            .into_builder(&self.sql_info)
            .build()
            .map_err(|e| Status::internal(e.to_string()))?;

        let stream = futures::stream::once(async { Ok(batch) });
        let flight_stream = FlightDataEncoderBuilder::new()
            .with_schema(self.sql_info.schema())
            .build(stream)
            .map_err(|e| Status::internal(e.to_string()));

        Ok(Response::new(
            Box::pin(flight_stream) as <Self as FlightService>::DoGetStream
        ))
    }

    async fn get_flight_info_statement(
        &self,
        query: CommandStatementQuery,
        request: Request<FlightDescriptor>,
    ) -> Result<Response<FlightInfo>, Status> {
        info!("Received SQL Query: '{}'", query.query);

        let metadata = request.metadata();
        let connection_id = metadata
            .get("x-dch-connection-id")
            .ok_or(Status::internal("x-dch-connection-id is required"))?
            .to_str()
            .map_err(|e| Status::internal(e.to_string()))?;

        let connection = self
            .meta_store
            .get_connection(connection_id)
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        let connector = self
            .connectors_registry
            .get_connector(connection.provider.as_str())
            .map_err(|e| Status::internal(e.to_string()))?;

        let reader = connector
            .get_reader(&connection)
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        let pg_state = reader
            .schema(query.query.as_str())
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        let schema = pg_state.schema.clone();

        let ticket_stmt = TicketStatementQuery {
            statement_handle: Bytes::from(query.query),
        };
        let ticket = Ticket::new(ticket_stmt.as_any().encode_to_vec());

        let endpoint = FlightEndpoint::new().with_ticket(ticket);

        let flight_info = FlightInfo::new()
            .try_with_schema(&schema)
            .map_err(|e| Status::internal(e.to_string()))?
            .with_endpoint(endpoint)
            .with_total_records(-1)
            .with_total_bytes(-1);

        Ok(Response::new(flight_info))
    }

    async fn do_get_statement(
        &self,
        ticket: TicketStatementQuery,
        request: Request<Ticket>,
    ) -> Result<Response<<Self as FlightService>::DoGetStream>, Status> {
        let query = String::from_utf8(ticket.statement_handle.to_vec())
            .map_err(|_| Status::invalid_argument("Invalid statement handle"))?;
        info!("do_get_statement: '{}'", query);

        let metadata = request.metadata();
        let connection_id = metadata
            .get("x-dch-connection-id")
            .ok_or(Status::internal("x-dch-connection-id is required"))?
            .to_str()
            .map_err(|e| Status::internal(e.to_string()))?;

        let connection = self
            .meta_store
            .get_connection(connection_id)
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        let connector = self
            .connectors_registry
            .get_connector(connection.provider.as_str())
            .map_err(|e| Status::internal(e.to_string()))?;

        let reader = connector
            .get_reader(&connection)
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        let state = reader
            .schema(query.as_str())
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        let schema = state.schema.clone();

        let stream = reader
            .read(state, 512)
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        let flight_stream = FlightDataEncoderBuilder::new()
            .with_schema(schema)
            .build(stream.map_err(|e| FlightError::ExternalError(Box::new(e))))
            .map_err(|e| Status::internal(e.to_string()));

        Ok(Response::new(
            Box::pin(flight_stream) as <Self as FlightService>::DoGetStream
        ))
    }
}
