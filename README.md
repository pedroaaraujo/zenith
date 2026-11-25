<p align="right">
  [ English ](README.md) | [ Português (Brasil) ](README.pt-BR.md) | [ Español ](README.es-ES.md)
</p>

# Zenith

[![Lazarus](https://img.shields.io/badge/Lazarus-%3E%3D%202.2-blue.svg)](https://www.lazarus-ide.org/)
[![FreePascal](https://img.shields.io/badge/FPC-%3E%3D%203.2.2-green.svg)](https://www.freepascal.org/)
[![OpenAPI](https://img.shields.io/badge/OpenAPI-3.1-brightgreen.svg)](https://swagger.io/specification/)
[![Formats](https://img.shields.io/badge/Formats-JSON%20%7C%20CBOR%20%7C%20BSON%20%7C%20XML%20%7C%20CSV-orange.svg)](https://github.com/pedroaaraujo/zenith)
[![RFC 7807](https://img.shields.io/badge/RFC-7807%20Compliant-orange.svg)](https://datatracker.ietf.org/doc/html/rfc7807)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Zenith** is a high-performance web framework for **Free Pascal / Lazarus (FPC)**. Engineered to deliver an agile and contemporary backend development experience, Zenith unifies interactive **OpenAPI 3.1 / Swagger UI** documentation, **Multi-DBMS Micro-ORM** data modeling, **Multi-Format Serialization** (JSON, CBOR, BSON, XML, CSV), **JWT / Basic** authentication, structured logging, and standardized **RFC 7807** problem detail error handling.

---

## 🚀 Key Features

- ⚡ **High Concurrency & Low Latency**: Embedded HTTP server with native multi-threading (`fphttpapp`), FastCGI mode (`fpfcgi`), and Zero-DOM byte streaming architecture.
- 📦 **Multi-Format Serialization**: Zero-DOM codecs for 5 canonical formats: JSON, CBOR (RFC 8949 binary), BSON (v1.1 binary), XML, and CSV (RFC 4180).
- 🚀 **Automatic CRUD Router (`Zenith.Crud`)**: 1-line registration of 5 full REST endpoints (`GET`, `GET :id`, `POST`, `PUT :id`, `DELETE :id`) strongly typed with validation, connection pooling, and OpenAPI documentation.
- 🌐 **Internationalization (i18n) & Multi-Language Support**: Unified multilingual error and validation messages (`en-US`, `pt-BR`, `es-ES`) via `Zenith.Messages`, `DeltaModel.Messages`, and `Swagger4Laz` (`ZENITH_LOCALE`, `SetZenithLocale`).
- 🚀 **Direct Streaming & Zero-DOM**: High-throughput serialization via `TDeltaFastJsonStreamer`, `TDeltaCborCodec`, `TDeltaBsonCodec`, `TDeltaXmlCodec`, `TDeltaCsvCodec`, and chunked HTTP batch streaming (`TDeltaQuery<T>.StreamJsonTo`).
- ⚡ **Direct Typed ORM Binding**: Pre-allocated column mapping with `TColumnBindingMap`, 1:N Eager Loading via `Include`, and thread-safe static reflection cache `TRTTICache`.
- 📖 **OpenAPI 3.1 & Swagger UI**: Native integration with [Swagger4Laz](src/swagger4laz), serving interactive API documentation with centralized schema registration in `components.schemas` and canonical `$ref` references at `/docs`.
- 🧩 **Modeling, Validation & ORM with DeltaModel**: Direct integration with [DeltaModel](src/deltamodel) for strongly typed models, fluent validation rules, and multi-database persistence (PostgreSQL, MariaDB/MySQL, SQLite, Firebird, MSSQL, Oracle).
- 🛡️ **Standardized Error Handling (RFC 7807)**: Detailed, structured JSON problem responses adhering to the *Problem Details for HTTP APIs* specification.
- 🔐 **Built-in Authentication**:
  - Full **JWT (JSON Web Token)** support with creation, HMAC-SHA256 signature, expiration, and automated validation.
  - Standard **HTTP Basic** authentication.
- ⚙️ **`.env` Configuration**: Seamless reading of operating system environment variables and local `.env` files.
- 📝 **Structured Thread-Safe Logging**: Automated request logging, error traces, and configurable severity levels (`INFO`, `WARN`, `ERROR`).
- 🌐 **Automatic CORS**: Configurable pre-flight `OPTIONS` handling and granular CORS response headers.
- 🔄 **Reverse Proxy Ready**: Native compatibility with Nginx, Traefik, Apache, and Caddy (including `X-Forwarded-Prefix`).

---

## 🏛️ Framework Architecture

```
Zenith/
├── src/
│   ├── Zenith.App.pas         # Application singleton (TZenithApp) and runtime lifecycle
│   ├── Zenith.Crud.pas        # Automated generic REST CRUD router and controller
│   ├── Zenith.Messages.pas    # Error messages and RFC 7807 internationalization (i18n)
│   ├── Zenith.Core.pas        # Middleware pipeline and centralized exception dispatcher
│   ├── Zenith.Constants.pas   # Canonical MIME types, status codes, and HTTP headers
│   ├── Zenith.Consts.pas      # HTTP constants, status codes, and MIME types
│   ├── Zenith.Types.pas       # Base types and RFC 7807 JSON formatter (TJsonError)
│   ├── Zenith.Exceptions.pas  # Semantic HTTP exception hierarchy
│   ├── Zenith.Auth.JWT.pas    # JWT token generation, signature, and verification
│   ├── Zenith.Auth.Basic.pas  # HTTP Basic authentication provider
│   ├── Zenith.Hash.pas        # Cryptographic utilities (HMAC-SHA256, SHA256, MD5)
│   ├── Zenith.Env.pas         # Configuration loader (.env / OS environment)
│   ├── Zenith.Log.pas         # Thread-safe console and file logger
│   ├── swagger4laz/           # Submodule: Swagger UI and OpenAPI 3.1
│   └── deltamodel/            # Submodule: Data Modeling, Multi-Format Codecs, and Generics Micro-ORM
└── demo/
    ├── 00-todolist/           # Minimal REST API demo with SQLite and TZenithCrud
    └── 01-order-management/   # Enterprise RMS Starter with multi-format endpoints and Swagger UI
```

---

## 🏁 Quick Start: Building Your First REST API

### 1. Main Program File (`.lpr`)

```pascal
program MyApi;

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  Classes, SysUtils, fphttpapp,
  Zenith.App,
  User.Model, User.Route;

begin
  ZenithApp
    .SetTitle('Enterprise REST API')
    .SetVersion('1.0.0')
    .SetDescription('High-performance API built with Zenith and Lazarus')
    .SetPort(8080)
    .SetThreaded(True)
    .SetDocRoute('/docs')
    .Run;
end.
```

---

### 2. Defining Models with DeltaModel

```pascal
unit User.Model;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DeltaModel, DeltaModel.Fields;

type
  { TUserResponse }
  TUserResponse = class(TDeltaModel)
  private
    Fid: TDFIntRequired;
    Fname: TDFStringRequired;
    Femail: TDFStringRequired;
  published
    property id: TDFIntRequired read Fid write Fid;
    property name: TDFStringRequired read Fname write Fname;
    property email: TDFStringRequired read Femail write Femail;
  end;

  { TUserInsert }
  TUserInsert = class(TDeltaModel)
  private
    Fname: TDFStringRequired;
    Femail: TDFStringRequired;
  published
    property name: TDFStringRequired read Fname write Fname;
    property email: TDFStringRequired read Femail write Femail;
  public
    procedure Validate; override;
  end;

implementation

procedure TUserInsert.Validate;
begin
  inherited Validate;
  Validator
    .RuleFor(name.Value, 'Name')
      .MinLength(3)
    .RuleFor(email.Value, 'Email')
      .ValidEmail;
end;

end.
```

---

### 3. Creating and Documenting Routes

```pascal
unit User.Route;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs,
  Zenith.App, Zenith.Constants, Zenith.Exceptions,
  User.Model, DeltaModel;

type
  TUserRouter = class
  public
    class procedure Register;
  end;

implementation

// Handler: GET /users/:id
procedure GetUser(ARequest: TRequest; AResponse: TResponse);
var
  User: TUserResponse;
  UserId: Integer;
begin
  UserId := StrToIntDef(ARequest.RouteParams['id'], 0);
  if UserId <= 0 then
    raise EBadRequest.Create('Invalid user ID.');

  if UserId = 99 then
    raise EResourceNotFound.Create('User not found in the system.');

  User := TUserResponse.Create;
  try
    User.id.AsInteger := UserId;
    User.name.AsText := 'John Doe';
    User.email.AsText := 'john.doe@company.com';

    AResponse.Code := HTTP_STATUS_OK;
    AResponse.ContentType := MIME_APPLICATION_JSON;
    AResponse.Content := User.ToJson;
  finally
    User.Free;
  end;
end;

class procedure TUserRouter.Register;
begin
  Router
    .Get('/users/:id', @GetUser)
    .SetSummary('Fetch user by ID')
    .AddTags('Users')
    .AddPathParam('id', True, 'integer', '1', 'Unique user identifier')
    .AddResponseRef(HTTP_STATUS_OK, 'UserResponse', 'User located', MIME_APPLICATION_JSON)
    .AddResponseRef(HTTP_STATUS_OK, 'UserResponse', 'Binary CBOR payload', MIME_APPLICATION_CBOR)
    .AddResponse(HTTP_STATUS_BAD_REQUEST, 'Invalid request parameter')
    .AddResponse(HTTP_STATUS_NOT_FOUND, 'User not found');
end;

initialization
  TUserRouter.Register;
end.
```

---

## 📦 Multi-Format Content Negotiation (JSON, CBOR, BSON, XML, CSV)

Zenith leverages DeltaModel's zero-DOM codec pipeline (`IDeltaCodec` and `TDeltaCodecRegistry`) to serialize responses dynamically according to the client's `Accept` HTTP header or route requirements.

### Supported Media Types & Codecs

| Format | Codec Class | Canonical Media Types | Standard |
| :--- | :--- | :--- | :--- |
| **JSON** | `TDeltaJsonCodec` | `application/json` | RFC 8259 |
| **CBOR** | `TDeltaCborCodec` | `application/cbor` | RFC 8949 (Binary) |
| **BSON** | `TDeltaBsonCodec` | `application/bson` | BSON v1.1 (Binary) |
| **XML**  | `TDeltaXmlCodec`  | `application/xml`, `text/xml` | W3C XML 1.0 (Zero-DOM) |
| **CSV**  | `TDeltaCsvCodec`  | `text/csv` | RFC 4180 |

### Technical Tradeoffs Matrix

- **CBOR (`application/cbor`)**:
  - *Payload size*: ~40-60% smaller than JSON.
  - *Characteristics*: Direct IEEE 754 floats, integer packing (0..23 inline), zero text parsing overhead.
  - *Ideal for*: IoT devices, mobile apps (Flutter), high-throughput internal microservice IPC.
- **BSON (`application/bson`)**:
  - *Payload size*: Comparable to JSON; prefixed with 32-bit document length.
  - *Characteristics*: Rich types (UTC datetime ms, 64-bit integers, binary BLOBs).
  - *Ideal for*: Document indexing, analytical workers, MongoDB interoperability.
- **CSV (`text/csv`)**:
  - *Payload size*: Extremely compact for tabular datasets.
  - *Characteristics*: RFC 4180 compliant, automatic header row, double-quote escaping, ISO-8601 timestamps.
  - *Ideal for*: Bulk exports, financial statements, spreadsheet analysis.
- **XML (`application/xml`)**:
  - *Payload size*: ~20-40% larger than JSON due to closing tags.
  - *Characteristics*: Standard UTF-8 declaration, strict entity escaping, self-closing NULL tags.
  - *Ideal for*: Enterprise integrations, banking/fiscal compliance, legacy SOAP/XML systems.
- **JSON (`application/json`)**:
  - *Payload size*: Baseline standard.
  - *Characteristics*: Universal browser/SPA support, fixed-point float formatting (`ffFixed`).
  - *Ideal for*: Public web REST APIs and web browsers.

### Security Protections (RFC 8949 §10 & BSON Anti-DoS)

The binary decoders enforce defense-in-depth protections:
- **Anti-OOM**: Strict stream length bounds checking before `SetLength` memory allocation. Claimed lengths larger than the stream or exceeding `16 MB` immediately raise `EDeltaDeserializationException`.
- **Recursion Depth Ceiling**: `MAX_NESTING_DEPTH = 64` prevents stack exhaustion from deeply nested malicious structures.
- **CString Boundary**: `MAX_BSON_CSTRING_LENGTH = 1024` prevents infinite byte scanning on malformed documents missing null terminators.

---

## 📖 OpenAPI 3.1 & Canonical Schema Registration

Zenith features native coupling between its HTTP router, [Swagger4Laz](src/swagger4laz), and [DeltaModel](src/deltamodel).

### 1. Automatic Registration in `components.schemas`
During application startup, Zenith automatically binds a bidirectional schema handler:

```pascal
SetDeltaModelRegisterSchemaProc(@ZenithRegisterModelProc);
```

Whenever a model is referenced in an API route, it is registered idempotently into OpenAPI 3.1 `components.schemas`.

### 2. Semantic Schema Generation Methods in DeltaModel

| Method | Schema Type | OpenAPI Format |
| :--- | :--- | :--- |
| `TModel.SwaggerSchemaObject(AddExamples)` | `object` | Full inline object schema |
| `TModel.SwaggerSchemaArray(AddExamples)` | `array` | Inline array schema (`items: { type: object }`) |
| `TModel.SwaggerSchemaPaginated(AddExamples)` | `object` | Paginated envelope (`items`, `page`, `page_size`, `total_records`, `total_pages`) |
| `TModel.SwaggerSchemaRefObject` | `$ref` | `{"$ref": "#/components/schemas/ModelName"}` |
| `TModel.SwaggerSchemaRefArray` | `array` | `{"type": "array", "items": {"$ref": "#/components/schemas/ModelName"}}` |
| `TModel.SwaggerSchemaRefPaginated` | `object` | Paginated envelope with `$ref` inside `items` |

---

## ⚡ Zenith High-Performance Architecture

### 1. `TDeltaFastJsonStreamer`: Zero-DOM JSON Streaming
Zenith streams raw bytes directly into contiguous `RawByteString` buffers without instantiating DOM trees:
- **Zero DOM Allocation**: Generates JSON payloads directly without creating node trees.
- **Fixed-Point Float Formatting (`ffFixed`)**: Standard `fpjson` formats large or small floating numbers using scientific exponent notation (`1.5E+06`), breaking JavaScript and mobile parsers. `TDeltaFastJsonStreamer` formats floats strictly in fixed-point decimal (`ffFixed`) with intelligent trimming of trailing zeroes.

### 2. `TColumnBindingMap`: Direct Typed ORM Binding Without Variant Boxing
- Field-to-property offsets are resolved once on the first row of the query.
- Data is read directly via native driver typed methods (`ADS.Fields[I].AsLargeInt`, `ADS.Fields[I].AsString`, `ADS.Fields[I].AsFloat`).
- Completely eliminates Variant boxing over tens of thousands of records.

### 3. `TRTTICache` & `TModelMetadata`: Thread-Safe Static RTTI Cache
- Published properties are inspected and indexed once per class.
- Subsequent request-time lookups operate in $O(1)$ constant time.

---

## 🛡️ Exception Handling & RFC 7807

When a semantic exception is raised in any handler, Zenith intercepts it and returns a standardized **RFC 7807** Problem Details payload:

```json
{
  "type": "urn:zenith:problem:validation-error",
  "title": "Business rule validation failure.",
  "status": 400,
  "detail": "Field TUserInsert.email is invalid: Email format is invalid",
  "instance": ""
}
```

### Semantic Exceptions (`Zenith.Exceptions`):

| Exception Class | HTTP Code | JSON `type` Identifier |
| :--- | :--- | :--- |
| `EBadRequest` | 400 | `VALIDATION_ERROR` |
| `EValidation` | 400 | `VALIDATION_ERROR` |
| `EMissingRequiredField` | 400 | `MISSING_REQUIRED_FIELD_ERROR` |
| `EUnauthorized` | 401 | `UNAUTHORIZED` |
| `EForbidden` | 403 | `FORBIDDEN` |
| `ENotFound` / `EResourceNotFound` | 404 | `RESOURCE_NOT_FOUND` |
| `EConflict` | 409 | `CONFLICT` |
| `ETooManyRequests` | 429 | `TOO_MANY_REQUESTS` |
| `EServerError` | 500 | `SERVER_ERROR` |

---

## 🔐 JWT Authentication

Zenith includes native support for JSON Web Tokens signed with HMAC-SHA256 (`Zenith.Auth.JWT`):

```pascal
uses Zenith.Auth.JWT;

var
  Payload: TPayLoad;
  Token: string;
begin
  Payload := TPayLoad.Create;
  try
    Payload.CustomValues['userId'] := 42;
    Payload.CustomValues['email'] := 'user@company.com';
    Payload.CustomValues['role'] := 'admin';

    Token := TJWT.GenerateToken(Payload);
  finally
    Payload.Free;
  end;
end;
```

---

## ⚙️ Environment Configuration (`.env`)

Create a `.env` file in the same directory as the compiled executable:

```env
ZENITH_PORT=8080
ZENITH_ALLOW_CORS=Y
ZENITH_CORS_ORIGIN=https://app.company.com
ZENITH_CORS_ALLOW_CREDENTIALS=N
ZENITH_LOGFILE=zenith.log
ZENITH_JWT_SECRET=your-super-secure-jwt-secret-key-here
ZENITH_JWT_EXPIRATION=30
ZENITH_TODO_DATABASE=/var/lib/myapi/todo.sqlite
```

Resolution order: `SetEnvVariable` > OS environment > `.env` (read once at startup; `ReloadEnvFile` reloads it) > default. The `.env` parser accepts `#` comments, `export VAR=...` and single/double quotes. Boolean flags accept `Y/YES/S/SIM/TRUE/ON/1` (and their negatives) through `GetEnvBool`.

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `ZENITH_ALLOW_CORS` | `N` | CORS is **opt-in**. With `Y`, CORS headers are emitted per request. |
| `ZENITH_CORS_ORIGIN` | *(empty)* | Comma-separated allowlist. The request `Origin` is echoed only when listed (plus `Vary: Origin`); `*` allows any origin and never sends credentials. |
| `ZENITH_CORS_ALLOW_CREDENTIALS` | `N` | Sends `Access-Control-Allow-Credentials: true` for allowlisted origins. |
| `ZENITH_MAX_BODY_SIZE` | `10485760` | Maximum request body in bytes; larger `Content-Length` returns `413`. |
| `ZENITH_MAX_HEADER_SIZE` | `65536` | Maximum size of the request line plus headers; larger returns `431`. |
| `ZENITH_READ_TIMEOUT_MS` | `30000` | Per-read socket timeout and total deadline to receive the headers (`408`). Applies only while reading the request; SSE/WebSocket are not affected. `0` disables. |
| `ZENITH_CRUD_MAX_PAGE_SIZE` | `100` | Upper bound for `limit`/`page_size` in `TZenithCrud` listings. |
| `ZENITH_JWT_ISSUER` / `ZENITH_JWT_AUDIENCE` | *(empty)* | When set, tokens are issued with `iss`/`aud` and validation requires them to match. |
| `ZENITH_WS_ALLOWED_ORIGINS` | *(empty)* | WebSocket handshakes with an `Origin` header must be same-origin (`Host`) or listed here; `*` allows any. Clients without `Origin` are accepted. |
| `ZENITH_LOG_DEBUG` | `N` | Enables the `DEBUG` log level. |
| `ZENITH_LOGFILE` | *(empty)* | Also appends log lines to this file. |

> **Security notes:** `TZenithCrud` validates `sort`/`order_by` against the model fields (`?sort=-id,name` or `?sort=name desc`); anything else returns `400`. Use `ZENITH_JWT_SECRET` with at least 32 bytes (RFC 7518); shorter secrets log a warning. Create the connection pool **before** registering `TZenithCrud` routes (the constructor rejects a `nil` pool).

---

## 🌐 Production Deployment

### Standalone Daemon Mode (Default)
Run the compiled binary as a standard `systemd` service:

```ini
[Unit]
Description=Zenith Web Service
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/myapi
ExecStart=/opt/myapi/myapi
Restart=always

[Install]
WantedBy=multi-user.target
```

### FastCGI Mode (Nginx / Apache)
Compile with the `-dFCGI` compiler directive:

```bash
lazbuild -B -dFCGI myapi.lpi
```

---

## 📁 Included Demos

- [`demo/00-todolist`](demo/00-todolist): Minimal SQLite REST API with `Zenith.App`, `TZenithCrud`, and Swagger UI.
- [`demo/01-order-management`](demo/01-order-management): Complete RMS Starter REST API covering Products, Customers, Orders, 1:N relations (`Include`), RBAC, multi-format responses, and interactive OpenAPI documentation.

---

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
