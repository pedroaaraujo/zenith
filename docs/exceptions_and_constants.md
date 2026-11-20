# Constantes HTTP e Hierarquia de Exceções (RFC 9457) — Zenith & DeltaModel

Este documento descreve a arquitetura de constantes HTTP tipadas (`Zenith.Constants`), a hierarquia de exceções HTTP mapeáveis diretamente para **RFC 9457 Problem Details** (`Zenith.Exceptions`) e a hierarquia de exceções de domínio/ORM do **DeltaModel** (`DeltaModel.Exceptions`).

---

## 1. Constantes HTTP (`Zenith.Constants`)

A unit `Zenith.Constants` centraliza códigos de status, media types, cabeçalhos padrão, métodos HTTP e codificações em formato plano (`HTTP_STATUS_*`, `MIME_*`, `HEADER_*`) e em namespaces tipados via *advanced records* (`THttpStatus`, `TMediaType`, `THttpHeader`, `THttpMethod`).

### 1.1 Códigos de Status HTTP (1xx a 5xx)

| Faixa | Exemplos de Constantes Planas | Namespace Tipado |
|---|---|---|
| **1xx Informational** | `HTTP_STATUS_CONTINUE` (100), `HTTP_STATUS_SWITCHING_PROTOCOLS` (101), `HTTP_STATUS_EARLY_HINTS` (103) | `THttpStatus.Continue`, `THttpStatus.EarlyHints` |
| **2xx Success** | `HTTP_STATUS_OK` (200), `HTTP_STATUS_CREATED` (201), `HTTP_STATUS_ACCEPTED` (202), `HTTP_STATUS_NO_CONTENT` (204), `HTTP_STATUS_PARTIAL_CONTENT` (206) | `THttpStatus.OK`, `THttpStatus.Created`, `THttpStatus.NoContent` |
| **3xx Redirection** | `HTTP_STATUS_MOVED_PERMANENTLY` (301), `HTTP_STATUS_NOT_MODIFIED` (304), `HTTP_STATUS_TEMPORARY_REDIRECT` (307), `HTTP_STATUS_PERMANENT_REDIRECT` (308) | `THttpStatus.NotModified`, `THttpStatus.PermanentRedirect` |
| **4xx Client Error** | `HTTP_STATUS_BAD_REQUEST` (400), `HTTP_STATUS_UNAUTHORIZED` (401), `HTTP_STATUS_FORBIDDEN` (403), `HTTP_STATUS_NOT_FOUND` (404), `HTTP_STATUS_METHOD_NOT_ALLOWED` (405), `HTTP_STATUS_CONFLICT` (409), `HTTP_STATUS_PRECONDITION_FAILED` (412), `HTTP_STATUS_PAYLOAD_TOO_LARGE` (413), `HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE` (415), `HTTP_STATUS_UNPROCESSABLE_ENTITY` (422), `HTTP_STATUS_TOO_MANY_REQUESTS` (429) | `THttpStatus.PreconditionFailed`, `THttpStatus.UnprocessableEntity`, `THttpStatus.TooManyRequests` |
| **5xx Server Error** | `HTTP_STATUS_INTERNAL_SERVER_ERROR` (500), `HTTP_STATUS_NOT_IMPLEMENTED` (501), `HTTP_STATUS_BAD_GATEWAY` (502), `HTTP_STATUS_SERVICE_UNAVAILABLE` (503), `HTTP_STATUS_GATEWAY_TIMEOUT` (504) | `THttpStatus.InternalServerError`, `THttpStatus.ServiceUnavailable` |

Utilitários inclusos:
- `HttpStatusReasonPhrase(AStatusCode: Integer): string`
- `IsHttpStatusInformational`, `IsHttpStatusSuccess`, `IsHttpStatusRedirection`, `IsHttpStatusClientError`, `IsHttpStatusServerError`

### 1.2 Media Types

| Constante | Valor | Namespace |
|---|---|---|
| `MIME_APPLICATION_JSON` | `application/json` | `TMediaType.Json` |
| `MIME_APPLICATION_CBOR` | `application/cbor` | `TMediaType.Cbor` |
| `MIME_APPLICATION_BSON` | `application/bson` | `TMediaType.Bson` |
| `MIME_APPLICATION_XML` | `application/xml` | `TMediaType.Xml` |
| `MIME_TEXT_CSV` | `text/csv` | `TMediaType.Csv` |
| `MIME_APPLICATION_MERGE_PATCH` | `application/merge-patch+json` | `TMediaType.MergePatch` |
| `MIME_APPLICATION_PROBLEM_JSON` | `application/problem+json` | `TMediaType.ProblemJson` |
| `MIME_APPLICATION_PROBLEM_CBOR` | `application/problem+cbor` | `TMediaType.ProblemCbor` |
| `MIME_TEXT_EVENT_STREAM` | `text/event-stream` | `TMediaType.EventStream` |

### 1.3 Cabeçalhos HTTP Padrão

Incluem suporte a autenticação, cache condicional, idempotência, SSE, compressão e rastreamento distribuído (W3C Trace Context):
- `HEADER_AUTHORIZATION` (`Authorization`)
- `HEADER_ETAG` (`ETag`), `HEADER_IF_MATCH` (`If-Match`), `HEADER_IF_NONE_MATCH` (`If-None-Match`)
- `HEADER_IDEMPOTENCY_KEY` (`Idempotency-Key`), `HEADER_IDEMPOTENT_REPLAYED` (`Idempotent-Replayed`)
- `HEADER_ACCEPT_ENCODING` (`Accept-Encoding`), `HEADER_CONTENT_ENCODING` (`Content-Encoding`)
- `HEADER_LAST_EVENT_ID` (`Last-Event-ID`)
- `HEADER_TRACEPARENT` (`Traceparent`), `HEADER_TRACESTATE` (`Tracestate`)
- `HEADER_RETRY_AFTER` (`Retry-After`), `HEADER_ALLOW` (`Allow`)

---

## 2. Hierarquia de Exceções HTTP — RFC 9457 (`Zenith.Exceptions`)

A classe base `EZenithException` encapsula todos os membros canônicos da **RFC 9457 (Problem Details for HTTP APIs)**:

| Propriedade | Membro RFC 9457 | Descrição |
|---|---|---|
| `ErrorType` | `type` | URI de referência do tipo de problema (padrão `about:blank` ou `urn:zenith:problem:<slug>`). |
| `Title` | `title` | Resumo curto e legível do problema. |
| `StatusCode` | `status` | Código de status HTTP numérico. |
| `Detail` | `detail` | Explicação específica desta ocorrência do problema. |
| `Instance` | `instance` | URI que identifica a ocorrência específica (opcional). |
| `Extensions` | *(membros extras)* | Objeto `TJSONObject` lazy-allocated para extensões arbitrárias. |

### 2.1 Subclasses Disponíveis

| Classe | HTTP Status | Recursos Específicos |
|---|---|---|
| `EZenithBadRequest` | `400` | Erro de sintaxe ou requisição malformada. |
| `EZenithUnauthorized` | `401` | Credenciais ausentes ou inválidas. |
| `EZenithForbidden` | `403` | Autenticado, porém sem permissão para o recurso. |
| `EZenithNotFound` | `404` | Recurso inexistente. |
| `EZenithMethodNotAllowed` | `405` | Propriedade `AllowedMethods` exportada em `allowedMethods`. |
| `EZenithConflict` | `409` | Conflito de estado ou unicidade. |
| `EZenithPreconditionFailed` | `412` | Falha em pré-condições (`If-Match` / `ETag`). |
| `EZenithPayloadTooLarge` | `413` | Corpo da requisição acima do limite permitido. |
| `EZenithUnsupportedMediaType` | `415` | `Content-Type` não suportado pelo endpoint. |
| `EZenithUnprocessableEntity` | `422` | Array tipado `Errors: TZenithFieldErrorArray` e método fluente `AddFieldError`. |
| `EZenithTooManyRequests` | `429` | Propriedade `RetryAfter: Integer` (segundos) exportada em `retryAfter`. |
| `EZenithInternalError` | `500` | Falha interna inesperada do servidor. |

### 2.2 Serialização JSON e CBOR

- `ToProblemJson: string` — gera payload `application/problem+json` válido segundo RFC 9457.
- `ToProblemCbor: TBytes` — codifica o mesmo objeto em **CBOR binário (RFC 8949)** compatível com `application/problem+cbor`, sem dependências externas adicionais.

### 2.3 Exemplo de Uso (HTTP 422 com Erros por Campo)

```pascal
var
  Ex: EZenithUnprocessableEntity;
begin
  Ex := EZenithUnprocessableEntity.Create('Falha de validação nos dados informados.', '/v1/orders');
  Ex.AddFieldError('email', 'Endereço de e-mail inválido.', 'INVALID_EMAIL')
    .AddFieldError('quantity', 'Deve ser maior que zero.', 'MIN_VALUE')
    .AddExtension('traceId', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01');
  raise Ex;
end;
```

Payload `application/problem+json` produzido:

```json
{
  "type": "urn:zenith:problem:unprocessable-entity",
  "title": "Unprocessable Entity",
  "status": 422,
  "detail": "Falha de validação nos dados informados.",
  "instance": "/v1/orders",
  "errors": [
    { "field": "email", "code": "INVALID_EMAIL", "message": "Endereço de e-mail inválido." },
    { "field": "quantity", "code": "MIN_VALUE", "message": "Deve ser maior que zero." }
  ],
  "traceId": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
}
```

### 2.4 Retrocompatibilidade

A classe legada `HTTPException` herda de `EZenithException`, preservando integralmente as subclasses anteriores (`EValidation`, `EConflict`, `EMissingRequiredField`, `EUnauthorized`, `EForbidden`, `EResourceNotFound`, `ENotFound`, `ETooManyRequests`, `EServerError`, `EBadRequest`, `EUnprocessableEntity`, `EUnknownError` / `EUnknowError`).

---

## 3. Hierarquia de Exceções de Domínio e ORM (`DeltaModel.Exceptions`)

A unit `DeltaModel.Exceptions` permanece 100% desacoplada da camada HTTP, fornecendo semântica rica para validação, persistência, concorrência e serialização:

| Classe | Propósito | Propriedades Principais |
|---|---|---|
| `EDeltaModelException` | Classe base do ORM | `ErrorCode`, `ModelName` |
| `EDeltaValidationException` | Violações por campo | `Violations`, `ViolationCount`, `AddViolation`, `HasFieldViolation`, `GetFieldViolations`, `ToJson` |
| `EDeltaNotFoundException` | Registro não encontrado | `ModelName`, `EntityId` |
| `EDeltaConcurrencyException` | Conflito de concorrência otimista | `ModelName`, `EntityId`, `ExpectedVersion`, `ActualVersion` |
| `EDeltaSerializationException` | Erro de parse/encode (JSON/CBOR/BSON/XML/CSV) | `FormatName`, `FieldName`, `ModelName` |
| `EDeltaQueryException` | Erro de construção ou execução SQL | `SqlStatement`, `DialectName`, `ModelName` |

### 3.1 Exemplo de Mapeamento DeltaModel -> Zenith

```pascal
try
  OrderRepository.Save(Order);
except
  on E: EDeltaNotFoundException do
    raise EZenithNotFound.Create(E.Message);
  on E: EDeltaConcurrencyException do
    raise EZenithPreconditionFailed.Create(E.Message);
  on E: EDeltaValidationException do
  begin
    Unproc := EZenithUnprocessableEntity.Create(E.Message);
    for V in E.Violations do
      Unproc.AddFieldError(V.FieldName, V.Message, V.Rule);
    raise Unproc;
  end;
end;
```
