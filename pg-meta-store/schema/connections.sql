-- The `data` column stores a DataConnection JSON object:
--
--   {
--     "namespace":  "analytics",
--     "name":       "clickstream-db",
--     "provider":   "postgres",
--     "format":     "jdbc",
--     "tenant_id":  "tenant-001",
--     "location":   { "url": "postgresql://host:5432/mydb" },
--     "created_at": "2026-07-20T10:00:00Z",
--     "updated_at": "2026-07-20T10:00:00Z",
--     "properties": { "key": "value" }
--   }

CREATE TABLE IF NOT EXISTS data_connections (
    data JSONB NOT NULL
);

CREATE INDEX idx_data_connections_tenant ON data_connections ((data->>'tenant_id'));
CREATE INDEX idx_data_connections_namespace ON data_connections ((data->>'namespace'));
CREATE INDEX idx_data_connections_name ON data_connections ((data->>'name'));
