# Zenith Framework — Native WebSocket Server Demo (`03-websocket`)

A domain-agnostic demonstration of the native **Zenith WebSocket Server** (`Zenith.WebSocket`), showcasing **RFC 6455** framing, **RFC 7692** `permessage-deflate` compression, binary **CBOR / BSON** model streaming via **DeltaModel**, and **RFC 8392 CBOR Web Token (CWT)** handshake authentication.

---

## 🚀 Key Features & Endpoints

- **`GET /auth/cwt`** — Issues a signed RFC 8392 CBOR Web Token (CWT) encoded in Base64URL for authenticating WebSocket handshakes.
- **`GET /ws/chat`** — Real-time multi-client chat hub supporting:
  - UTF-8 text frames (`wsMsgText`).
  - Binary CBOR frames (`wsMsgBinary`) mapped directly to `TChatMessage` (`DeltaModel`).
  - Subprotocol negotiation (`chat.v1`, `chat.cbor`) and `permessage-deflate` compression (RFC 7692).
- **`GET /ws/telemetry`** — Authenticated IoT telemetry stream (`TSensorTelemetry`) requiring a valid CWT token during the HTTP Upgrade handshake and supporting `telemetry.cbor` and `telemetry.bson` binary subprotocols.

---

## 📦 Domain Models (`Telemetry.Model.pas`)

| Model | Fields | Description |
|---|---|---|
| `TChatMessage` | `room_id`, `sender`, `body`, `sequence` | Real-time chat message payload serialized as JSON text or binary CBOR. |
| `TSensorTelemetry` | `device_id`, `temperature`, `humidity`, `battery_pct`, `online` | IoT sensor telemetry model decoded and broadcast as CBOR or BSON. |

---

## 🛠️ Build & Run

### Compilation with Free Pascal Compiler (`fpc`)

Compile into a temporary directory so no binaries or object files pollute the repository:

```bash
mkdir -p /tmp/zenith_ws_demo
cd demo/03-websocket

fpc -MObjFPC -Scghi -O2 \
  -FE/tmp/zenith_ws_demo \
  -FU/tmp/zenith_ws_demo \
  -Fu../../src \
  -Fu../../src/deltamodel/src \
  -Fu../../src/swagger4laz \
  -Fu. \
  websocket_demo.lpr
```

### Execution

```bash
/tmp/zenith_ws_demo/websocket_demo
```

By default, the server starts in multi-threaded mode on port `8088`.

---

## 📡 Usage Examples

### 1. Issue a Demo CWT Token

```bash
curl -s http://localhost:8088/auth/cwt
```

Sample response:
```json
{"token":"...","type":"CWT"}
```

### 2. Connect to the Public Chat WebSocket (`/ws/chat`)

Using `websocat` or `wscat`:

```bash
websocat ws://localhost:8088/ws/chat
```

Upon connection, the server sends a welcome event:
```json
{"event":"connected","id":"..."}
```
Any text or CBOR message sent by a client is broadcast in real time to all other connected peers in `ChatHub`.

### 3. Connect to the Authenticated Telemetry Stream (`/ws/telemetry`)

Pass the CWT token obtained from `/auth/cwt` in the `Authorization: Bearer <token>` header (or `access_token` query parameter) and negotiate either `telemetry.cbor` or `telemetry.bson`:

```bash
TOKEN=$(curl -s http://localhost:8088/auth/cwt | sed -E 's/.*"token":"([^"]+)".*/\1/')
websocat --protocol telemetry.cbor \
  -H "Authorization: Bearer $TOKEN" \
  ws://localhost:8088/ws/telemetry
```

---

## 🛡️ License

Part of the **Zenith Framework** ecosystem under the MIT License.
