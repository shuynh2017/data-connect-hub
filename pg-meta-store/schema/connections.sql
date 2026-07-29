
CREATE TABLE IF NOT EXISTS data_connections (
    data JSONB NOT NULL
);

CREATE INDEX idx_data_connections_tenant ON data_connections ((data->>'tenant_id'));
CREATE INDEX idx_data_connections_name ON data_connections ((data->>'name'));

CREATE TABLE IF NOT EXISTS data_connection_types (
    data JSONB NOT NULL
);

CREATE INDEX idx_data_connection_types_id ON data_connection_types ((data->>'id'));
CREATE INDEX idx_data_connection_types_name ON data_connection_types ((data->>'name'));
CREATE INDEX idx_data_connection_types_provider ON data_connection_types ((data->>'provider'));
