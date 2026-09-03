#!/bin/bash
set -euo pipefail

CONN_ID="${1}"
TICKET="${2}"

decode_arrow_data() {
  python3 -c "
import sys, json, base64, struct

raw = sys.stdin.read().strip()
chunks = []
decoder = json.JSONDecoder()
pos = 0
while pos < len(raw):
    s = raw[pos:].lstrip()
    if not s:
        break
    try:
        obj, end = decoder.raw_decode(s)
        chunks.append(obj)
        pos = len(raw) - len(s) + end
    except json.JSONDecodeError:
        break

arrow_msgs = [c for c in chunks if isinstance(c, dict) and 'dataHeader' in c]
if not arrow_msgs:
    for line in raw.splitlines()[:10]:
        print(f'  {line}')
    sys.exit(1)

try:
    import pyarrow as pa
    buf = bytearray()
    for msg in arrow_msgs:
        hdr = base64.b64decode(msg['dataHeader'])
        body = base64.b64decode(msg.get('dataBody', '')) if msg.get('dataBody') else b''
        buf.extend(struct.pack('<I', 0xFFFFFFFF))
        pad = (8 - len(hdr) % 8) % 8
        buf.extend(struct.pack('<i', len(hdr) + pad))
        buf.extend(hdr)
        buf.extend(b'\x00' * pad)
        if body:
            buf.extend(body)
            bp = (8 - len(body) % 8) % 8
            buf.extend(b'\x00' * bp)
    buf.extend(struct.pack('<I', 0xFFFFFFFF))
    buf.extend(struct.pack('<i', 0))
    reader = pa.ipc.open_stream(pa.py_buffer(bytes(buf)))
    table = reader.read_all()
    print(f'  Rows: {table.num_rows}')
    col_widths = {}
    for c in table.column_names:
        vals = [str(v) for v in table.column(c).to_pylist()]
        w = max(len(c), max((len(v) for v in vals), default=0))
        col_widths[c] = min(w, 50)
    header = '  ' + ' | '.join(f'{c:<{col_widths[c]}}' for c in table.column_names)
    print(header)
    print('  ' + '-+-'.join('-' * col_widths[c] for c in table.column_names))
    for i in range(min(table.num_rows, 50)):
        row = []
        for c in table.column_names:
            v = str(table.column(c)[i].as_py())
            if len(v) > 50:
                v = v[:47] + '...'
            row.append(f'{v:<{col_widths[c]}}')
        print('  ' + ' | '.join(row))
    if table.num_rows > 50:
        print(f'  ... ({table.num_rows - 50} more rows)')
except Exception as e:
    print(f'  Arrow decode error: {e}')
    for c in chunks[:3]:
        for k, v in c.items():
            if isinstance(v, str) and len(v) > 80:
                print(f'  {k}: [{len(v)} chars]')
            else:
                print(f'  {k}: {v}')
" <<< "$1" 2>/dev/null || echo "$1"
}

CMD="grpcurl -insecure -import-path \"$PROTO_DIR\" -proto Flight.proto -H 'Authorization: Bearer $user_token' -H 'x-tenant-id: $TENANT_ID' -H 'x-data-connection-id: $CONN_ID' -d '{\"ticket\":\"$TICKET\"}' localhost:$FLIGHT_LOCAL_PORT arrow.flight.protocol.FlightService/DoGet"

echo $CMD
do_get_output=$(eval "$CMD")
decode_arrow_data "$do_get_output"
