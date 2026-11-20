<p align="right">
  <b>Language / Idioma:</b>
  <a href="README.md">English</a> |
  <a href="README.pt-BR.md">Português (Brasil)</a> |
  <a href="README.es-ES.md">Español</a>
</p>

# Zenith

[![Lazarus](https://img.shields.io/badge/Lazarus-2.2%2B-blue.svg)](https://www.lazarus-ide.org/)
[![FreePascal](https://img.shields.io/badge/FPC-3.2.2%2B-green.svg)](https://www.freepascal.org/)
[![OpenAPI](https://img.shields.io/badge/OpenAPI-3.1-brightgreen.svg)](https://swagger.io/specification/)
[![RFC 7807](https://img.shields.io/badge/RFC-7807%20Compliant-orange.svg)](https://datatracker.ietf.org/doc/html/rfc7807)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Zenith** is a modern, elegant, and high-performance web framework for **Free Pascal / Lazarus (FPC)**. Engineered to deliver an agile and contemporary backend development experience, Zenith unifies interactive **OpenAPI 3.1 / Swagger UI** documentation, **Multi-DBMS Micro-ORM** data modeling and validation, **JWT / Basic** authentication, structured logging, and standardized **RFC 7807** problem detail error handling.

---

## 🚀 Key Features

- ⚡ **High Performance & Concurrency**: Embedded HTTP server with native multi-threading (`fphttpapp`), FastCGI mode (`fpfcgi`), and Zero-DOM byte streaming architecture.
- 🚀 **Automatic CRUD Router (`Zenith.Crud`)**: 1-line registration of 5 full REST endpoints (`GET`, `GET :id`, `POST`, `PUT :id`, `DELETE :id`) strongly typed with validation, connection pooling, and OpenAPI documentation.
- 🌐 **Internationalization (i18n) & Multi-Language Support**: Unified multilingual error and validation messages (`en-US`, `pt-BR`, `es-ES`) via `Zenith.Messages`, `DeltaModel.Messages`, and `Swagger4Laz` (`ZENITH_LOCALE`, `SetZenithLocale`).
- 🚀 **Direct JSON Streaming & Zero-DOM**: High-throughput serialization via `TDeltaFastJsonStreamer` and chunked HTTP batch streaming (`TDeltaQuery<T>.StreamJsonTo`), eliminating heap overhead on large datasets.
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
│   ├── Zenith.Consts.pas      # HTTP constants, status codes, and MIME types
│   ├── Zenith.Types.pas       # Base types and RFC 7807 JSON formatter (TJsonError)
│   ├── Zenith.Exceptions.pas  # Semantic HTTP exception hierarchy
│   ├── Zenith.Auth.JWT.pas    # JWT token generation, signature, and verification
│   ├── Zenith.Auth.Basic.pas  # HTTP Basic authentication provider
│   ├── Zenith.Hash.pas        # Cryptographic utilities (HMAC-SHA256, SHA256, MD5)
│   ├── Zenith.Env.pas         # Configuration loader (.env / OS environment)
│   ├── Zenith.Log.pas         # Thread-safe console and file logger
│   ├── swagger4laz/           # Submodule: Swagger UI and OpenAPI 3.1
│   └── deltamodel/            # Submodule: Data Modeling, Validation, and Generics Micro-ORM
└── demo/
    └── 00-todolist/           # End-to-end REST API demo with SQLite and TZenithCrud
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
  // Your models and routes
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
  Zenith.App, Zenith.Consts, Zenith.Exceptions,
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
    // Direct typed access without Variant boxing
    User.id.AsInteger := UserId;
    User.name.AsText := 'John Doe';
    User.email.AsText := 'john.doe@company.com';

    AResponse.Code := StatusOK;
    AResponse.ContentType := ApplicationJson;
    AResponse.Content := User.ToJson;
  finally
    User.Free;
  end;
end;

// Handler: POST /users
procedure CreateUser(ARequest: TRequest; AResponse: TResponse);
var
  InputData: TUserInsert;
  NewUser: TUserResponse;
begin
  InputData := TUserInsert.Create;
  NewUser := TUserResponse.Create;
  try
    InputData.FromJson(ARequest.Content);
    InputData.Validate; // Raises EDeltaValidation on error

    // Direct typed assignment without Variant boxing
    NewUser.id.AsInteger := 101;
    NewUser.name.AsText := InputData.name.AsString;
    NewUser.email.AsText := InputData.email.AsString;

    AResponse.Code := StatusCreated;
    AResponse.ContentType := ApplicationJson;
    AResponse.Content := NewUser.ToJson;
  finally
    NewUser.Free;
    InputData.Free;
  end;
end;

class procedure TUserRouter.Register;
begin
  // Route registration with canonical OpenAPI $ref schema linking
  Router
    .Get('/users/:id', @GetUser)
    .SetSummary('Fetch user by ID')
    .AddTags('Users')
    .AddPathParam('id', True, 'integer', '1', 'Unique user identifier')
    .AddResponseRef(StatusOK, 'UserResponse', 'User located')
    .AddResponse(StatusBadRequest, 'Invalid request parameter')
    .AddResponse(StatusNotFound, 'User not found');

  // POST /users with typed payload and response registered in components.schemas
  Router
    .Post('/users', @CreateUser)
    .SetSummary('Register new user')
    .AddTags('Users')
    .SetBodyContentRef('UserInsert', True, ApplicationJson, 'User registration payload')
    .AddResponseRef(StatusCreated, 'UserResponse', 'User created successfully')
    .AddResponse(StatusBadRequest, 'Field validation failure');
end;

initialization
  TUserRouter.Register;
end.
```

---

## 📖 OpenAPI 3.1 & Canonical Schema Registration

Zenith features native, deep coupling between its HTTP router, the [Swagger4Laz](src/swagger4laz) documentation engine, and [DeltaModel](src/deltamodel) strongly typed models.

### 1. Automatic Registration in `components.schemas`
During application startup, Zenith automatically binds a bidirectional schema handler:

```pascal
// Automatically registered in unit Zenith.App:
SetDeltaModelRegisterSchemaProc(@ZenithRegisterModelProc);
```

Whenever a model is referenced in an API route, it is automatically and idempotently registered into OpenAPI 3.1 `components.schemas` in a thread-safe manner.

### 2. Semantic Schema Generation Methods in DeltaModel
Avoid legacy untyped methods. Use the explicit, strongly typed generators:

| Method | Schema Type | OpenAPI Format |
| :--- | :--- | :--- |
| `TModel.SwaggerSchemaObject(AddExamples)` | `object` | Full inline object schema |
| `TModel.SwaggerSchemaArray(AddExamples)` | `array` | Inline array schema (`items: { type: object }`) |
| `TModel.SwaggerSchemaPaginated(AddExamples)` | `object` | Paginated envelope (`items`, `page`, `page_size`, `total_records`, `total_pages`) |
| `TModel.SwaggerSchemaRefObject` | `$ref` | `{"$ref": "#/components/schemas/ModelName"}` |
| `TModel.SwaggerSchemaRefArray` | `array` | `{"type": "array", "items": {"$ref": "#/components/schemas/ModelName"}}` |
| `TModel.SwaggerSchemaRefPaginated` | `object` | Paginated envelope with `$ref` inside `items` |

### 3. Practical Example in Enterprise Endpoints

```pascal
procedure RegisterProductRoutes;
begin
  // GET /products - Paginated list referencing components.schemas
  Router
    .Get('/products', @ListProducts)
    .SetSummary('List products with pagination')
    .AddTags('Products')
    .AddQueryParam('page', False, 'integer', '1', 'Current page')
    .AddQueryParam('page_size', False, 'integer', '20', 'Records per page')
    .AddResponse(StatusOK, 'Paginated product list', TProductResponse.SwaggerSchemaRefPaginated);

  // POST /products - Registration with typed Request Body and Response
  Router
    .Post('/products', @CreateProduct)
    .SetSummary('Create new product')
    .AddTags('Products')
    .SetBodyContent(TProductInsert.SwaggerSchemaObject(), True, ApplicationJson, 'Product payload')
    .AddResponse(StatusCreated, 'Product created', TProductResponse.SwaggerSchemaRefObject)
    .AddResponse(StatusBadRequest, 'Validation error');
end;
```

---

## ⚡ Zenith High-Performance Architecture

To handle high concurrency and multi-tenant workloads with minimal resource consumption, Zenith eliminates Free Pascal bottlenecks with low-level optimizations:

### 1. `TDeltaFastJsonStreamer`: Zero-DOM JSON Streaming
Traditional approaches (`fpjson`) instantiate hundreds of intermediate DOM heap nodes (`TJSONObject`, `TJSONData`, `TJSONFloat`) for every single returned record, causing memory fragmentation and GC overhead.

Zenith streams raw bytes directly into contiguous `RawByteString` buffers:
- **Zero DOM Allocation**: Generates JSON payloads directly without creating node trees.
- **Fixed-Point Float Formatting (`ffFixed`)**: Standard `fpjson` formats large or small floating numbers using scientific exponent notation (`1.5E+06` or `1.0E-04`), breaking JavaScript and mobile client parsers. `TDeltaFastJsonStreamer` formats floats strictly in fixed-point decimal (`FloatToStrF` with `ffFixed`) with intelligent trimming of trailing zeroes, ensuring fiscal and financial accuracy.

### 2. `TColumnBindingMap`: Direct Typed ORM Binding Without Variant Boxing
Conventional `TDataSet` extraction relies on `Variant` calls (`Field.Value`), incurring COM/OLE dispatch overhead.

With `TColumnBindingMap`:
- Field-to-property offsets are resolved once on the first row of the query.
- Data is read directly via native driver typed methods (`ADS.Fields[I].AsLargeInt`, `ADS.Fields[I].AsString`, `ADS.Fields[I].AsFloat`).
- Completely eliminates Variant boxing over tens of thousands of records.

### 3. `TRTTICache` & `TModelMetadata`: Thread-Safe Static RTTI Cache
Repeated RTTI reflection calls (`TypInfo.GetPropList`) during serialization, validation, and migrations are avoided through thread-safe caching:
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

### Available Semantic Exceptions (`Zenith.Exceptions`):

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

### Generating a Token

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

    // exp and iat are managed automatically or can be explicitly defined
    Token := TJWT.GenerateToken(Payload);
  finally
    Payload.Free;
  end;
end;
```

### Validating a Token Inside a Route Handler

```pascal
var
  AuthHeader, Token: string;
  Payload: TPayLoad;
begin
  AuthHeader := ARequest.Authorization; // "Bearer eyJhbGciOi..."
  Token := StringReplace(AuthHeader, 'Bearer ', '', [rfIgnoreCase]).Trim;

  // Automatically raises EUnauthorized if expired, malformed, or invalid
  Payload := TJWT.ValidadeToken(Token);
  try
    WriteLn('Authenticated user: ', Payload.CustomValues['email']);
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

Operating system environment variables take precedence over `.env` entries. For browser cookies or credentialed CORS requests, set an explicit origin in `ZENITH_CORS_ORIGIN` and enable credentials. Wildcard `*` cannot be combined with credentials.

Access environment variables directly in Pascal code:

```pascal
uses Zenith.Env;

var
  MyVal: string;
begin
  MyVal := GetEnvVariable('MY_CONFIG_VAR', 'DefaultFallback');
end;
```

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
To build in FastCGI mode with connection pooling, compile with the `-dFCGI` compiler directive:

```bash
lazbuild -B -dFCGI myapi.lpi
```

Example **Nginx** configuration:
```nginx
server {
    listen 80;
    server_name api.company.com;

    location / {
        fastcgi_pass 127.0.0.1:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_NAME "";
        fastcgi_param HTTP_X_FORWARDED_PREFIX "";
    }
}
```

---

## 📁 Included Demonstrations

1. [`demo/00-todolist`](demo/00-todolist) — Basic SQLite REST API (Tasks CRUD with OpenAPI 3.1 & Swagger UI).
2. [`demo/01-order-management`](demo/01-order-management) — Enterprise Retail & Order Management (RMS Starter) REST API:
   - Domain modeling: `TProduct`, `TCustomer`, `TSaleOrder`, `TSaleOrderItem` with 1:N relational mapping (`Include('items')`).
   - Declarative RBAC with `TZRBACPolicy<TProduct>` protecting mutations for `admin` role.
   - Fluent route grouping with `SwaggerRouter.Group('/api/v1/orders')`.
   - Atomic business transactions: customer credit check, real-time stock reservation, and automated stock reversal upon cancellation.
   - Multilingual documentation ([English](demo/01-order-management/README.md), [Português](demo/01-order-management/README.pt-BR.md), [Español](demo/01-order-management/README.es-ES.md)).

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.
