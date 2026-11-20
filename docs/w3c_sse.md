# W3C Server-Sent Events (SSE) no Zenith

O módulo `Zenith.SSE` oferece suporte nativo, thread-safe e sem dependências externas ao padrão **W3C Server-Sent Events (HTML Living Standard — Section 9.2)** sobre `text/event-stream`.

## Recursos Principais

- **100% RTL/FCL puro**: nenhuma dependência de bibliotecas de terceiros.
- **Cabeçalhos canônicos obrigatórios**:
  - `Content-Type: text/event-stream; charset=utf-8`
  - `Cache-Control: no-cache, no-transform`
  - `Connection: keep-alive`
  - `X-Accel-Buffering: no` (evita buffering em Nginx e proxies reversos)
- **Formatação estrita W3C**:
  - Campos `id:`, `event:`, `retry:` e `data:` terminados com `\n\n`.
  - Quebra automática de payloads multi-linha (`\r\n`, `\n` e `\r`) em múltiplas linhas `data: ...`.
  - Sanitização de caracteres de controle (`CR`, `LF`, `NUL`) em `id` e `event`.
  - Preservação integral de UTF-8 (acentuação, símbolos e emojis).
  - Comentários SSE (`SendComment('ping')` -> `: ping\n\n`) para heartbeat/keep-alive.
- **Reconexão resiliente (`Last-Event-ID`)**:
  - Extração automática do cabeçalho `Last-Event-ID` (com fallback opcional para query string `lastEventId`).
  - Ring-buffer configurável no `TZSSEBroker` com `ReplaySince` para reenvio ordenado de eventos perdidos.
- **Broker multi-tópico lock-free em I/O (`TZSSEBroker`)**:
  - Assinatura em tópicos nomeados (`notifications`, `progress`, `metrics`) ou wildcard (`*`).
  - Nenhum lock global mantido durante escritas de rede, evitando que clientes lentos bloqueiem os demais.
- **Heartbeat automático e Zero Thread-Leak**:
  - `TZSSEConnection.WaitLoop` utiliza `TEvent` (0% de CPU ocioso) com detecção imediata de desconexão via `MSG_PEEK | MSG_DONTWAIT` (Linux/Unix) ou `select`/`MSG_PEEK` (Windows).
  - Ao detectar queda do cliente, o worker do `TZenithThreadPool` é imediatamente liberado e reciclado sem vazamento de threads ou memória.

---

## Uso no Servidor (Free Pascal / Zenith)

### Exemplo 1: Endpoint SSE com `TZSSEBroker` (Multi-Tópico + Replay + Heartbeat)

```pascal
unit Notifications.Route;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, httpdefs, httproute, Zenith.SSE;

procedure RegisterNotificationRoutes;

var
  EventBroker: TZSSEBroker;

implementation

procedure StreamNotifications(ARequest: TRequest; AResponse: TResponse);
begin
  // Abre o stream W3C, envia headers canônicos, faz replay a partir de Last-Event-ID,
  // mantém heartbeat a cada 15s e encerra limpamente ao desconectar.
  EventBroker.ServeConnection(
    ARequest,
    AResponse,
    'notifications',
    15000, // Heartbeat a cada 15s (: ping)
    True   // Reenvia eventos perdidos com base em Last-Event-ID
  );
end;

procedure PublishSampleNotification(ARequest: TRequest; AResponse: TResponse);
var
  Delivered: Integer;
begin
  Delivered := EventBroker.Publish(
    'notifications',
    '{"title":"Relatório pronto","severity":"info"}',
    'TNotification',
    IntToStr(GetTickCount64),
    3000 // Sugere reconexão em 3s
  );
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.Content := Format('{"delivered":%d}', [Delivered]);
end;

procedure RegisterNotificationRoutes;
begin
  EventBroker := TZSSEBroker.Create(200); // Ring-buffer com últimos 200 eventos
  HTTPRouter.RegisterRoute('/events/notifications', rmGet, @StreamNotifications);
  HTTPRouter.RegisterRoute('/events/notifications/publish', rmPost, @PublishSampleNotification);
end;

finalization
  FreeAndNil(EventBroker);

end.
```

### Exemplo 2: Progresso de Tarefa Direto com `TZSSEConnection`

```pascal
procedure StreamJobProgress(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TZSSEConnection;
  Step: Integer;
begin
  Conn := TZSSEConnection.Create(ARequest, AResponse);
  try
    Conn.SendRetry(2000);
    for Step := 1 to 10 do
    begin
      if Conn.CheckDisconnected then
        Break;

      if not Conn.SendEvent(
        Format('{"step":%d,"total":10,"percent":%d}', [Step, Step * 10]),
        'TProgress',
        'job-42-step-' + IntToStr(Step)
      ) then
        Break;

      Sleep(500);
    end;
    Conn.SendComment('completed');
  finally
    Conn.Free;
  end;
end;
```

---

## Exemplos de Cliente

### Navegador (JavaScript / TypeScript — `EventSource`)

```typescript
const source = new EventSource('/api/v1/events/notifications', {
  withCredentials: true,
});

source.addEventListener('TNotification', (ev: MessageEvent) => {
  const payload = JSON.parse(ev.data);
  console.log(`[id=${ev.lastEventId}]`, payload.title);
});

source.addEventListener('TProgress', (ev: MessageEvent) => {
  const progress = JSON.parse(ev.data);
  console.log(`Progresso: ${progress.percent}%`);
});

source.addEventListener('TMetric', (ev: MessageEvent) => {
  const metric = JSON.parse(ev.data);
  console.log('Métrica em tempo real:', metric);
});

source.onerror = () => {
  // O navegador reconecta automaticamente enviando o header Last-Event-ID
  console.warn('Conexão SSE interrompida; aguardando reconexão automática...');
};
```

### Teste rápido com `curl`

```bash
# Assinar stream de métricas em tempo real (sem buffer no curl)
curl -N -H "Accept: text/event-stream" \
  http://127.0.0.1:8080/events/metrics

# Simular reconexão retomando a partir do evento m-101
curl -N -H "Accept: text/event-stream" \
  -H "Last-Event-ID: m-101" \
  http://127.0.0.1:8080/events/metrics
```

---

## Configuração Recomendada de Proxy Reverso (Nginx)

Para garantir entrega imediata de eventos SSE sem buffering e sem quedas prematuras por timeout de leitura:

```nginx
location /api/v1/events/ {
    proxy_pass http://zenith_backend;

    # HTTP/1.1 sem Connection: close para manter keep-alive com upstream
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Desabilita buffering e compressão gzip em streams SSE
    proxy_buffering off;
    proxy_cache off;
    gzip off;
    chunked_transfer_encoding on;

    # Timeouts estendidos (alinhados com heartbeat de 15s do Zenith.SSE)
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}
```

> **Nota**: O próprio `Zenith.SSE` envia `X-Accel-Buffering: no` e `Cache-Control: no-cache, no-transform` em toda resposta SSE, instruindo o Nginx e CDNs intermediárias a repassarem cada frame imediatamente.

---

## Executando a Suíte de Testes e Benchmark

Compile e execute o runner standalone em diretório temporário (preservando artefatos do repositório):

```bash
mkdir -p /tmp/zenith_sse_build
fpc -MObjFPC -Scghi -O2 -gl -gh \
  -Fu/home/araujo/Desenvolvimento/Source/zenith/src \
  -Fu/home/araujo/Desenvolvimento/Source/zenith/tests/src \
  -FE/tmp/zenith_sse_build \
  -FU/tmp/zenith_sse_build \
  /home/araujo/Desenvolvimento/Source/zenith/tests/src/test_sse_runner.lpr

/tmp/zenith_sse_build/test_sse_runner --all --format=plain
```

A flag `-gh` (HeapTrc) valida automaticamente **0 blocos de memória vazados** ao final da execução.
