
import base64, os, tempfile
DCH_S3_QUERY="datasets/dch-test-prompts.jsonl"

# Build the serialized FlightDescriptor.cmd bytes for S3 Parquet query
type_url = b"type.googleapis.com/arrow.flight.protocol.sql.CommandStatementQuery"
query_str = DCH_S3_QUERY.encode()
csq = b'\x0a' + bytes([len(query_str)]) + query_str

any_msg = b'\x0a' + bytes([len(type_url)]) + type_url + b'\x12' + bytes([len(csq)]) + csq

cmd_b64 = base64.b64encode(any_msg).decode()
print(f"{cmd_b64}\n")
