# Demo 03 — Zenith WebSocket (RFC 6455 + RFC 7692 + CBOR/BSON + CWT)

Exemplo agnóstico demonstrando um servidor WebSocket nativo com Zenith:

- `GET /auth/cwt` — emite um token CWT (RFC 8392) em Base64URL para autenticar sessões WebSocket.
- `GET /ws/chat` — sala de chat em tempo real com suporte a frames de texto, frames binários CBOR (`TChatMessage`) e compressão `permessage-deflate` (RFC 7692).
- `GET /ws/telemetry` — stream de telemetria IoT (`TSensorTelemetry`) autenticado via CWT no handshake, suportando subprotocolos `telemetry.cbor` e `telemetry.bson`.

## Compilação

```bash
mkdir -p /tmp/zenith_ws_demo
fpc -MObjFPC -Sh -O2 \
  -FE/tmp/zenith_ws_demo -FU/tmp/zenith_ws_demo \
  -Fu../../src -Fu../../src/deltamodel/src -Fu../../src/swagger4laz \
  websocket_demo.lpr
```

## Execução

```bash
/tmp/zenith_ws_demo/websocket_demo
```

Para obter um token CWT de demonstração:

```bash
curl -s http://localhost:8088/auth/cwt
```

Para conectar ao WebSocket de chat (ex: via `websocat` ou `wscat`):

```bash
websocat ws://localhost:8088/ws/chat
```
