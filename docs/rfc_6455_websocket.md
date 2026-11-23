# Zenith WebSocket — Servidor Nativo RFC 6455 + RFC 7692 (`permessage-deflate`)

O módulo **`Zenith.WebSocket`** (com extensão **`Zenith.WebSocket.Deflate`**) implementa um servidor WebSocket nativo, zero-dependências externas, diretamente integrado ao roteador HTTP do framework **Zenith** em Free Pascal.

---

## 1. Conformidade com Padrões

| Especificação | Escopo Implementado |
|---|---|
| **RFC 6455** | Handshake HTTP Upgrade (`101 Switching Protocols`), cálculo `Sec-WebSocket-Accept` (`Base64(SHA-1(Key + GUID))` via `sha1`/`base64` da FCL), framing completo (7-bit, 16-bit BE, 64-bit BE), masking/unmasking XOR de 4 bytes otimizado em blocos de 32 bits, fragmentação multi-frame (`FIN=0` -> `Continuation` -> `FIN=1`) com controle intercalado, `Ping`/`Pong` automático e `Close` com status code big-endian + razão UTF-8. |
| **RFC 7692** | Extensão `permessage-deflate` com negociação via `Sec-WebSocket-Extensions`, bit `RSV1=1`, compressão raw DEFLATE (`-MAX_WBITS`) via `paszlib`/`zstream` nativos do FPC com `Z_SYNC_FLUSH` e remoção/adição do trailer `00 00 FF FF` (Seções 7.2.1 e 7.2.2), além de proteção anti-zip-bomb (`AMaxOutputSize`). |
| **RFC 8949 & BSON v1.1** | Transporte nativo de entidades `TDeltaModel` e listas em frames binários (`Opcode $02`) utilizando `TDeltaCborCodec` e `TDeltaBsonCodec` (Zero-DOM). |
| **RFC 8392 (CWT)** | Autenticação de conexões WebSocket com CBOR Web Tokens no handshake (`Authorization: Bearer`, `Sec-WebSocket-Protocol: cwt.<token>`, ou query `?token=`) ou no primeiro frame binário/texto (`RunLoop(True)`). |

---

## 2. Arquitetura dos Componentes

### `Zenith.WebSocket.Deflate`
- `TZWebSocketDeflate.IsPermessageDeflateRequested(AExtensionsHeader)`
- `TZWebSocketDeflate.Negotiate(AClientHeader, out AResponseHeader)`
- `TZWebSocketDeflate.Compress(AData, ALevel)` — gera bloco raw DEFLATE com `Z_SYNC_FLUSH` e remove o trailer `00 00 FF FF`.
- `TZWebSocketDeflate.Decompress(AData, AMaxOutputSize)` — anexa `00 00 FF FF`, descomprime via raw INFLATE e interrompe com `EZWebSocketDeflateLimitExceeded` caso o tamanho descomprimido ultrapasse `AMaxOutputSize` (padrão: 16 MB).

### `Zenith.WebSocket`
- **`TZWebSocketHandshake`**: validação rigorosa do cabeçalho HTTP de upgrade (`Upgrade: websocket`, `Connection: Upgrade`, `Sec-WebSocket-Version: 13`, nonce Base64 de 16 bytes em `Sec-WebSocket-Key`) e geração de resposta `101 Switching Protocols`.
- **`TZWebSocketFrameCodec`**: codificação e decodificação de frames RFC 6455 com rejeição obrigatória de frames `client -> server` não mascarados (`WS_CLOSE_PROTOCOL_ERROR = 1002`), validação de bits `RSV1..3`, opcodes, regras de frames de controle (`FIN=1`, payload `<= 125` bytes) e checagem anti-OOM **antes** de alocar memória (`WS_CLOSE_MESSAGE_TOO_BIG = 1009`).
- **`TZWebSocketAuth`**: extração e validação de CWT (RFC 8392) para `TZSecurityContext` no handshake ou na primeira mensagem binária/texto.
- **`TZWebSocketConnection`**: gerencia leitura com reassembly de fragmentos, resposta automática a `Ping`, handshake de fechamento `Close`, escrita thread-safe (`TCriticalSection`) e helpers `SendModelCbor`, `SendModelBson`, `DecodeBytesToModel`.
- **`TZWebSocketHub`**: registro thread-safe de conexões ativas com broadcast (`BroadcastText`, `BroadcastBinary`, `BroadcastModelCbor`, `BroadcastModelBson`).
- **`TZWebSocketUpgrade`**: ponte direta entre rotas HTTP do Zenith (`TRequest`/`TResponse` sobre `TFPHTTPConnection`) e sessões `TZWebSocketConnection`, preservando bytes residuais do buffer HTTP via `TZBufferedTransportStream`.

---

## 3. Exemplo de Uso

### 3.1 Upgrade de Rota HTTP para WebSocket com CWT e CBOR

```pascal
procedure HandleTelemetrySession(AConn: TZWebSocketConnection);
var
  Msg: TZWebSocketMessage;
  Telemetry: TSensorTelemetry;
begin
  TelemetryHub.RegisterConnection(AConn);
  try
    while AConn.ReadMessage(Msg) do
    begin
      if Msg.MessageType = wsMsgBinary then
      begin
        Telemetry := TSensorTelemetry.Create;
        try
          TZWebSocketConnection.DecodeBytesToModel(Msg.Payload, Telemetry, wsBinCbor);
          TelemetryHub.BroadcastModelCbor(Telemetry, AConn);
        finally
          Telemetry.Free;
        end;
      end;
    end;
  finally
    TelemetryHub.UnregisterConnection(AConn);
  end;
end;

procedure TelemetryWsRoute(ARequest: TRequest; AResponse: TResponse);
begin
  TZWebSocketUpgrade.Accept(
    ARequest,
    AResponse,
    @HandleTelemetrySession,
    'telemetry.cbor', // Sec-WebSocket-Protocol
    True,             // Enable RFC 7692 permessage-deflate
    True              // Require valid CWT token on handshake
  );
end;
```

### 3.2 Autenticação CWT na Primeira Mensagem Binária

```pascal
procedure HandleProtectedChat(AConn: TZWebSocketConnection);
begin
  AConn.OnTextMessage := @OnChatText;
  // Require CWT token as the very first message (binary or text);
  // closes with 1008 Policy Violation if invalid.
  AConn.RunLoop(True);
end;
```

---

## 4. Proteções de Segurança (Anti-OOM / DoS)

1. **Limite de Frame (`MaxFrameSize`, padrão 1 MB)**: validado imediatamente após a leitura do comprimento do cabeçalho (7/16/64-bit), antes de qualquer alocação `SetLength`. Frames acima do limite encerram a conexão com `1009 Message Too Big`.
2. **Limite de Mensagem Fragmentada (`MaxMessageSize`, padrão 4 MB)**: validado cumulativamente durante o reassembly de frames `Continuation`.
3. **Proteção Anti-Zip-Bomb (`permessage-deflate`)**: `TZWebSocketDeflate.Decompress` monitora o total de bytes descomprimidos a cada chunk de 16 KB, abortando imediatamente com `EZWebSocketDeflateLimitExceeded` se exceder `MaxMessageSize`.
4. **Enforce de Máscara Cliente (`RequireClientMask = True`)**: conforme RFC 6455 §5.1, qualquer frame recebido de um cliente sem bit `MASK=1` é rejeitado com `1002 Protocol Error`.
5. **Regras de Frames de Controle**: frames `Close`/`Ping`/`Pong` fragmentados (`FIN=0`), comprimidos (`RSV1=1`) ou com payload > 125 bytes são rejeitados com `1002 Protocol Error`.

---

## 5. Exemplo Completo

Consulte o projeto agnóstico em `demo/03-websocket/`, que demonstra chat em tempo real (`TChatMessage`), telemetria binária CBOR/BSON (`TSensorTelemetry`), `permessage-deflate` e emissão/validação de tokens CWT.
