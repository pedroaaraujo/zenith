<p align="right">
  [ English ](README.md) | [ Português (Brasil) ](README.pt-BR.md) | [ Español ](README.es-ES.md)
</p>

# Zenith

[![Lazarus](https://img.shields.io/badge/Lazarus-%3E%3D%202.2-blue.svg)](https://www.lazarus-ide.org/)
[![FreePascal](https://img.shields.io/badge/FPC-%3E%3D%203.2.2-green.svg)](https://www.freepascal.org/)
[![OpenAPI](https://img.shields.io/badge/OpenAPI-3.1-brightgreen.svg)](https://swagger.io/specification/)
[![Formatos](https://img.shields.io/badge/Formatos-JSON%20%7C%20CBOR%20%7C%20BSON%20%7C%20XML%20%7C%20CSV-orange.svg)](https://github.com/pedroaaraujo/zenith)
[![RFC 7807](https://img.shields.io/badge/RFC-7807%20Compliant-orange.svg)](https://datatracker.ietf.org/doc/html/rfc7807)
[![Licencia](https://img.shields.io/badge/Licencia-MIT-blue.svg)](LICENSE)

**Zenith** es un framework web de alto rendimiento para **Free Pascal / Lazarus (FPC)**. Diseñado para proporcionar una experiencia de desarrollo backend ágil y contemporánea, Zenith integra documentación interactiva **OpenAPI 3.1 / Swagger UI**, modelado con **Micro-ORM Multi-SGBD**, **Serialización Multiformato** (JSON, CBOR, BSON, XML, CSV), autenticación **JWT / Basic**, registro de logs estructurado y gestión estandarizada de errores bajo el estándar **RFC 7807**.

---

## 🚀 Características Principales

- ⚡ **Alta Concurrencia y Baja Latencia**: Servidor HTTP integrado con soporte nativo para múltiples subprocesos (`fphttpapp`), modo FastCGI (`fpfcgi`) y arquitectura de flujo de bytes Zero-DOM.
- 📦 **Serialización Multiformato**: Códecs Zero-DOM para 5 formatos canónicos: JSON, CBOR (binario RFC 8949), BSON (binario v1.1), XML y CSV (RFC 4180).
- 🚀 **Enrutador CRUD Automático (`Zenith.Crud`)**: Registro en 1 sola línea de 5 endpoints REST completos (`GET`, `GET :id`, `POST`, `PUT :id`, `DELETE :id`) fuertemente tipados con validación, pool de conexiones y documentación OpenAPI.
- 🌐 **Internacionalización (i18n) y Mensajes Configurables**: Soporte multilingüe unificado (`en-US`, `pt-BR`, `es-ES`) mediante `Zenith.Messages`, `DeltaModel.Messages` y `Swagger4Laz` (`ZENITH_LOCALE`, `SetZenithLocale`).
- 🚀 **Streaming Directo y Zero-DOM**: Serialización de alto rendimiento con `TDeltaFastJsonStreamer`, `TDeltaCborCodec`, `TDeltaBsonCodec`, `TDeltaXmlCodec`, `TDeltaCsvCodec` y transmisión HTTP fragmentada por lotes (`TDeltaQuery<T>.StreamJsonTo`).
- ⚡ **ORM con Vinculación Tipada Directa**: Asignación de columnas precalculada con `TColumnBindingMap`, Eager Loading 1:N mediante `Include` y caché de reflexión estática `TRTTICache`.
- 📖 **Documentación OpenAPI 3.1 y Swagger UI**: Integración nativa con [Swagger4Laz](src/swagger4laz), sirviendo documentación interactiva con registro centralizado de esquemas en `components.schemas` y referencias canónicas `$ref` en `/docs`.
- 🧩 **Modelado, Validación y ORM con DeltaModel**: Integración directa con [DeltaModel](src/deltamodel) para modelos fuertemente tipados, reglas de validación fluidas y persistencia multi-SGBD (PostgreSQL, MariaDB/MySQL, SQLite, Firebird, MSSQL, Oracle).
- 🛡️ **Errores Estandarizados (RFC 7807)**: Respuestas JSON ricas en detalles conforme a la especificación *Problem Details for HTTP APIs*.
- 🔐 **Autenticación Integrada**:
  - Soporte completo para **JWT (JSON Web Token)** con creación, firma HMAC-SHA256, expiración y validación automática.
  - Autenticación estándar **HTTP Basic**.
- ⚙️ **Configuración mediante `.env`**: Carga transparente de variables de entorno del sistema operativo y archivos `.env` locales.
- 📝 **Logging Estructurado Thread-Safe**: Registro automático de peticiones, trazas de error y niveles configurables de severidad (`INFO`, `WARN`, `ERROR`).
- 🌐 **CORS Automático**: Gestión configurable de solicitudes preliminares `OPTIONS` y encabezados CORS detallados.
- 🔄 **Listo para Proxies Inversos**: Compatibilidad nativa con Nginx, Traefik, Apache y Caddy (incluyendo `X-Forwarded-Prefix`).

---

## 🏛️ Arquitectura del Framework

```
Zenith/
├── src/
│   ├── Zenith.App.pas         # Singleton de la aplicación (TZenithApp) y ciclo de vida
│   ├── Zenith.Crud.pas        # Enrutador y controlador CRUD REST genérico automático
│   ├── Zenith.Messages.pas    # Mensajes de error e internacionalización RFC 7807 (i18n)
│   ├── Zenith.Core.pas        # Pipeline de middleware y despachador centralizado de excepciones
│   ├── Zenith.Constants.pas   # Media types canónicos, códigos de estado y encabezados HTTP
│   ├── Zenith.Consts.pas      # Constantes HTTP, códigos de estado y tipos MIME heredados
│   ├── Zenith.Types.pas       # Tipos base y formateador JSON RFC 7807 (TJsonError)
│   ├── Zenith.Exceptions.pas  # Jerarquía de excepciones semánticas HTTP
│   ├── Zenith.Auth.JWT.pas    # Creación, firma y validación de tokens JWT
│   ├── Zenith.Auth.Basic.pas  # Proveedor de autenticación HTTP Basic
│   ├── Zenith.Hash.pas        # Utilidades criptográficas (HMAC-SHA256, SHA256, MD5)
│   ├── Zenith.Env.pas         # Cargador de configuración (.env / entorno del SO)
│   ├── Zenith.Log.pas         # Logger seguro para subprocesos en archivo y consola
│   ├── swagger4laz/           # Submódulo: Swagger UI y OpenAPI 3.1
│   └── deltamodel/            # Submódulo: Modelado, Códecs Multiformato y Micro-ORM Genérico
└── demo/
    ├── 00-todolist/           # Ejemplo práctico de API REST con SQLite y TZenithCrud
    └── 01-order-management/   # RMS Starter completo con productos, pedidos, RBAC y multiformato
```

---

## 🏁 Inicio Rápido: Construyendo su Primera API REST

### 1. Archivo del Programa Principal (`.lpr`)

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
    .SetTitle('API REST Empresarial')
    .SetVersion('1.0.0')
    .SetDescription('API de alto rendimiento desarrollada con Zenith y Lazarus')
    .SetPort(8080)
    .SetThreaded(True)
    .SetDocRoute('/docs')
    .Run;
end.
```

---

### 2. Definiendo Modelos con DeltaModel

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
    .RuleFor(name.Value, 'Nombre')
      .MinLength(3)
    .RuleFor(email.Value, 'E-mail')
      .ValidEmail;
end;

end.
```

---

### 3. Creando y Documentando las Rutas

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

// Controlador: GET /users/:id
procedure GetUser(ARequest: TRequest; AResponse: TResponse);
var
  User: TUserResponse;
  UserId: Integer;
begin
  UserId := StrToIntDef(ARequest.RouteParams['id'], 0);
  if UserId <= 0 then
    raise EBadRequest.Create('ID de usuario inválido.');

  if UserId = 99 then
    raise EResourceNotFound.Create('Usuario no encontrado en el sistema.');

  User := TUserResponse.Create;
  try
    User.id.AsInteger := UserId;
    User.name.AsText := 'Juan Pérez';
    User.email.AsText := 'juan.perez@empresa.com';

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
    .SetSummary('Buscar usuario por ID')
    .AddTags('Usuarios')
    .AddPathParam('id', True, 'integer', '1', 'Identificador único del usuario')
    .AddResponseRef(HTTP_STATUS_OK, 'UserResponse', 'Usuario localizado', MIME_APPLICATION_JSON)
    .AddResponseRef(HTTP_STATUS_OK, 'UserResponse', 'Payload binario CBOR', MIME_APPLICATION_CBOR)
    .AddResponse(HTTP_STATUS_BAD_REQUEST, 'Parámetro de solicitud inválido')
    .AddResponse(HTTP_STATUS_NOT_FOUND, 'Usuario no encontrado');
end;

initialization
  TUserRouter.Register;
end.
```

---

## 📦 Negociación de Contenido Multiformato (JSON, CBOR, BSON, XML, CSV)

Zenith utiliza la arquitectura de códecs Zero-DOM de DeltaModel (`IDeltaCodec` y `TDeltaCodecRegistry`) para serializar respuestas dinámicamente según la cabecera `Accept` o la configuración del endpoint.

### Formatos y Media Types Compatibles

| Formato | Clase del Códec | Media Types Canónicos | Estándar |
| :--- | :--- | :--- | :--- |
| **JSON** | `TDeltaJsonCodec` | `application/json` | RFC 8259 |
| **CBOR** | `TDeltaCborCodec` | `application/cbor` | RFC 8949 (Binario) |
| **BSON** | `TDeltaBsonCodec` | `application/bson` | BSON v1.1 (Binario) |
| **XML**  | `TDeltaXmlCodec`  | `application/xml`, `text/xml` | W3C XML 1.0 (Zero-DOM) |
| **CSV**  | `TDeltaCsvCodec`  | `text/csv` | RFC 4180 |

### Matriz de Tradeoffs Técnicos

- **CBOR (`application/cbor`)**:
  - *Tamaño del payload*: ~40-60% menor que JSON.
  - *Características*: Coma flotante IEEE 754 directa, empaquetado de enteros (0..23 inline), cero coste de conversión a texto.
  - *Ideal para*: Dispositivos IoT, aplicaciones móviles (Flutter), comunicación inter-microservicios de alto rendimiento.
- **BSON (`application/bson`)**:
  - *Tamaño del payload*: Similar a JSON; prefijado con el tamaño total en 32 bits.
  - *Características*: Tipado binario enriquecido (UTC datetime en ms, enteros de 64 bits, BLOBs binarios).
  - *Ideal para*: Bases de datos documentales, analítica, interoperabilidad con MongoDB.
- **CSV (`text/csv`)**:
  - *Tamaño del payload*: Muy compacto para tablas planas.
  - *Características*: Conforme con RFC 4180, cabecera automática, escape de comillas dobles, marcas de tiempo ISO-8601.
  - *Ideal para*: Exportaciones masivas, informes financieros, hojas de cálculo.
- **XML (`application/xml`)**:
  - *Tamaño del payload*: ~20-40% mayor que JSON por etiquetas de cierre.
  - *Características*: Declaración UTF-8 estándar, escape estricto de entidades, etiquetas autocerradas para valores nulos.
  - *Ideal para*: Integraciones corporativas enterprise, cumplimiento bancario/fiscal, sistemas SOAP/XML heredados.
- **JSON (`application/json`)**:
  - *Tamaño del payload*: Línea de base estándar.
  - *Características*: Compatibilidad universal en navegadores y SPAs, números en coma fija decimal (`ffFixed`).
  - *Ideal para*: APIs públicas REST y aplicaciones web JavaScript.

### Protecciones de Seguridad (RFC 8949 Sección 10 y BSON Anti-DoS)

Los decodificadores binarios incorporan defensas activas:
- **Anti-OOM (Prevención de Agotamiento de Memoria)**: Validación rigurosa de longitud antes de alocar búferes con `SetLength`. Si la longitud supera los bytes restantes del stream o excede `16 MB`, se interrumpe de inmediato con `EDeltaDeserializationException`.
- **Límite Estricto de Recursión**: El techo de `MAX_NESTING_DEPTH = 64` previene ataques de desbordamiento de pila por estructuras maliciosas profundamente anidadas.
- **Control de CStrings Nulas**: `MAX_BSON_CSTRING_LENGTH = 1024` evita bucles infinitos ante documentos BSON sin terminador `0x00`.

---

## 📖 Documentación OpenAPI 3.1 y Registro Canónico de Esquemas

Zenith presenta integración nativa entre su enrutador HTTP, [Swagger4Laz](src/swagger4laz) y los modelos de [DeltaModel](src/deltamodel).

### 1. Registro Automático en `components.schemas`
Durante el inicio de la aplicación, Zenith vincula automáticamente un manejador de esquemas bidireccional:

```pascal
SetDeltaModelRegisterSchemaProc(@ZenithRegisterModelProc);
```

Cada vez que un modelo se referencia en una ruta de la API, se registra de manera automática, idempotente y segura para hilos en el diccionario `components.schemas` de OpenAPI 3.1.

### 2. Métodos de Generación Semántica de Esquemas en DeltaModel

| Método | Tipo en el Esquema | Formato OpenAPI |
| :--- | :--- | :--- |
| `TModel.SwaggerSchemaObject(AddExamples)` | `object` | Esquema inline completo del objeto |
| `TModel.SwaggerSchemaArray(AddExamples)` | `array` | Esquema inline de array (`items: { type: object }`) |
| `TModel.SwaggerSchemaPaginated(AddExamples)` | `object` | Envoltorio paginado (`items`, `page`, `page_size`, `total_records`, `total_pages`) |
| `TModel.SwaggerSchemaRefObject` | `$ref` | `{"$ref": "#/components/schemas/ModelName"}` |
| `TModel.SwaggerSchemaRefArray` | `array` | `{"type": "array", "items": {"$ref": "#/components/schemas/ModelName"}}` |
| `TModel.SwaggerSchemaRefPaginated` | `object` | Envoltorio paginado con `$ref` en `items` |

---

## ⚡ Arquitectura de Alto Rendimiento de Zenith

### 1. `TDeltaFastJsonStreamer`: Transmisión JSON Directa (Zero-DOM)
Zenith transmite bytes directamente a búferes `RawByteString` contiguos sin instanciar árboles de objetos en el heap:
- **Cero Asignación DOM**: Genera cargas útiles JSON directamente sin crear nodos intermedios.
- **Formateo de Punto Fijo (`ffFixed`) sin Notación Científica**: El `fpjson` estándar formatea valores numéricos en notación exponencial (`1.5E+06`), rompiendo analizadores móviles y JavaScript. `TDeltaFastJsonStreamer` formatea estrictamente en coma fija decimal (`ffFixed`) eliminando ceros superfluos.

### 2. `TColumnBindingMap`: Vinculación ORM Tipada Directa Sin Conversión Variant
- Las correspondencias entre columnas y propiedades se resuelven una sola vez en la primera fila de la consulta.
- Los datos se leen directamente con métodos nativos tipados (`ADS.Fields[I].AsLargeInt`, `ADS.Fields[I].AsString`, `ADS.Fields[I].AsFloat`).
- Elimina totalmente las conversiones de Variant en consultas con decenas de miles de registros.

### 3. `TRTTICache` & `TModelMetadata`: Caché RTTI Estática Segura para Hilos
- Las propiedades publicadas de cada clase se inspeccionan e indexan solo una vez.
- Las consultas en tiempo de ejecución se realizan en tiempo constante $O(1)$.

---

## 🛡️ Gestión de Excepciones y RFC 7807

Cuando se produce una excepción semántica en cualquier controlador, Zenith la intercepta automáticamente y responde con un formato estructurado conforme a **RFC 7807** Problem Details:

```json
{
  "type": "urn:zenith:problem:validation-error",
  "title": "Fallo en la validación de reglas de negocio.",
  "status": 400,
  "detail": "Field TUserInsert.email is invalid: Email format is invalid",
  "instance": ""
}
```

### Excepciones Semánticas Disponibles (`Zenith.Exceptions`):

| Clase de Excepción | Código HTTP | Identificador JSON (`type`) |
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

## 🔐 Autenticación JWT

Zenith incluye soporte nativo para tokens JSON Web Tokens firmados con HMAC-SHA256 (`Zenith.Auth.JWT`):

```pascal
uses Zenith.Auth.JWT;

var
  Payload: TPayLoad;
  Token: string;
begin
  Payload := TPayLoad.Create;
  try
    Payload.CustomValues['userId'] := 42;
    Payload.CustomValues['email'] := 'usuario@empresa.com';
    Payload.CustomValues['role'] := 'admin';

    Token := TJWT.GenerateToken(Payload);
  finally
    Payload.Free;
  end;
end;
```

---

## ⚙️ Configuración del Entorno (`.env`)

Cree un archivo `.env` en el mismo directorio del ejecutable:

```env
ZENITH_PORT=8080
ZENITH_ALLOW_CORS=Y
ZENITH_CORS_ORIGIN=https://app.empresa.com
ZENITH_CORS_ALLOW_CREDENTIALS=N
ZENITH_LOGFILE=zenith.log
ZENITH_JWT_SECRET=su-clave-secreta-jwt-muy-segura-aqui
ZENITH_JWT_EXPIRATION=30
ZENITH_TODO_DATABASE=/var/lib/myapi/todo.sqlite
```

---

## 🌐 Despliegue en Producción

### Modo Demonio Independiente (Predeterminado)
Ejecute el binario compilado como un servicio estándar de `systemd`:

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

### Modo FastCGI (Nginx / Apache)
Compile con la directiva `-dFCGI`:

```bash
lazbuild -B -dFCGI myapi.lpi
```

---

## 📁 Demostraciones Incluidas

- [`demo/00-todolist`](demo/00-todolist): API REST SQLite minimalista con `Zenith.App`, `TZenithCrud` y Swagger UI.
- [`demo/01-order-management`](demo/01-order-management): RMS Starter corporativo completo que abarca Productos, Clientes, Pedidos, relaciones 1:N (`Include`), RBAC, respuestas multiformato y Swagger UI interactivo.

---

## 📄 Licencia

Distribuido bajo la Licencia MIT. Consulte `LICENSE` para más información.
