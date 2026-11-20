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

**Zenith** es un framework web moderno, elegante y de alto rendimiento para **Free Pascal / Lazarus (FPC)**. Diseñado para proporcionar una experiencia de desarrollo backend ágil y contemporánea, Zenith integra documentación interactiva **OpenAPI 3.1 / Swagger UI**, modelado y validación con **Micro-ORM Multi-SGBD**, autenticación **JWT / Basic**, registro de logs estructurado y gestión estandarizada de errores bajo el estándar **RFC 7807**.

---

## 🚀 Características Principales

- ⚡ **Alto Rendimiento y Concurrencia**: Servidor HTTP integrado con soporte nativo para múltiples subprocesos (`fphttpapp`), modo FastCGI (`fpfcgi`) y arquitectura de flujo de bytes Zero-DOM.
- 🚀 **Enrutador CRUD Automático (`Zenith.Crud`)**: Registro en 1 sola línea de 5 endpoints REST completos (`GET`, `GET :id`, `POST`, `PUT :id`, `DELETE :id`) fuertemente tipados con validación, pool de conexiones y documentación OpenAPI.
- 🌐 **Internacionalización (i18n) y Mensajes Configurables**: Soporte multilingüe unificado (`en-US`, `pt-BR`, `es-ES`) mediante `Zenith.Messages`, `DeltaModel.Messages` y `Swagger4Laz` (`ZENITH_LOCALE`, `SetZenithLocale`).
- 🚀 **Streaming JSON Directo y Zero-DOM**: Serialización de alto rendimiento con `TDeltaFastJsonStreamer` y transmisión HTTP fragmentada por lotes (`TDeltaQuery<T>.StreamJsonTo`), eliminando el consumo excesivo de heap en grandes volúmenes de datos.
- ⚡ **ORM con Vinculación Tipada Directa**: Asignación de columnas precalculada con `TColumnBindingMap`, Eager Loading 1:N mediante `Include` y caché de reflexión estática segura para hilos `TRTTICache`.
- 📖 **Documentación OpenAPI 3.1 y Swagger UI**: Integración nativa con [Swagger4Laz](src/swagger4laz), sirviendo documentación interactiva con registro centralizado de esquemas en `components.schemas` y referencias canónicas `$ref` en `/docs`.
- 🧩 **Modelado, Validación y ORM con DeltaModel**: Integración directa con [DeltaModel](src/deltamodel) para modelos fuertemente tipados, reglas de validación fluidas y persistencia multi-SGBD (PostgreSQL, MariaDB/MySQL, SQLite, Firebird, MSSQL, Oracle).
- 🛡️ **Errores Estandarizados (RFC 7807)**: Respuestas JSON ricas en detalles conforme a la especificación *Problem Details for HTTP APIs*.
- 🔐 **Autenticación Integrada**:
  - Soporte completo para **JWT (JSON Web Token)** con creación, firma HMAC-SHA256, expiración y validación automática.
  - Autenticación estándar **HTTP Basic**.
- ⚙️ **Configuración mediante `.env`**: Carga transparente de variables de entorno del sistema operativo y archivos `.env` locales.
- 📝 **Logging Estructurado y Seguro**: Registro automático de peticiones, trazas de error y niveles configurables de severidad (`INFO`, `WARN`, `ERROR`).
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
│   ├── Zenith.Consts.pas      # Constantes HTTP, códigos de estado y tipos MIME
│   ├── Zenith.Types.pas       # Tipos base y formateador JSON RFC 7807 (TJsonError)
│   ├── Zenith.Exceptions.pas  # Jerarquía de excepciones semánticas HTTP
│   ├── Zenith.Auth.JWT.pas    # Creación, firma y validación de tokens JWT
│   ├── Zenith.Auth.Basic.pas  # Proveedor de autenticación HTTP Basic
│   ├── Zenith.Hash.pas        # Utilidades criptográficas (HMAC-SHA256, SHA256, MD5)
│   ├── Zenith.Env.pas         # Cargador de configuración (.env / entorno del SO)
│   ├── Zenith.Log.pas         # Logger seguro para subprocesos en archivo y consola
│   ├── swagger4laz/           # Submódulo: Swagger UI y OpenAPI 3.1
│   └── deltamodel/            # Submódulo: Modelado, Validación y Micro-ORM con Genéricos
└── demo/
    └── 00-todolist/           # Ejemplo práctico de API REST completa con SQLite y TZenithCrud
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
  // Sus modelos y rutas
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
  Zenith.App, Zenith.Consts, Zenith.Exceptions,
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
    // Acceso tipado directo sin conversión Variant
    User.id.AsInteger := UserId;
    User.name.AsText := 'Juan Pérez';
    User.email.AsText := 'juan.perez@empresa.com';

    AResponse.Code := StatusOK;
    AResponse.ContentType := ApplicationJson;
    AResponse.Content := User.ToJson;
  finally
    User.Free;
  end;
end;

// Controlador: POST /users
procedure CreateUser(ARequest: TRequest; AResponse: TResponse);
var
  InputData: TUserInsert;
  NewUser: TUserResponse;
begin
  InputData := TUserInsert.Create;
  NewUser := TUserResponse.Create;
  try
    InputData.FromJson(ARequest.Content);
    InputData.Validate; // Lanza EDeltaValidation ante errores de validación

    // Asignación tipada directa sin conversión Variant
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
  // Registro de ruta vinculando referencia canónica $ref de OpenAPI
  Router
    .Get('/users/:id', @GetUser)
    .SetSummary('Buscar usuario por ID')
    .AddTags('Usuarios')
    .AddPathParam('id', True, 'integer', '1', 'Identificador único del usuario')
    .AddResponseRef(StatusOK, 'UserResponse', 'Usuario localizado')
    .AddResponse(StatusBadRequest, 'Parámetro de solicitud inválido')
    .AddResponse(StatusNotFound, 'Usuario no encontrado');

  // POST /users con carga útil y respuesta tipadas registradas en components.schemas
  Router
    .Post('/users', @CreateUser)
    .SetSummary('Registrar nuevo usuario')
    .AddTags('Usuarios')
    .SetBodyContentRef('UserInsert', True, ApplicationJson, 'Datos de registro del usuario')
    .AddResponseRef(StatusCreated, 'UserResponse', 'Usuario creado exitosamente')
    .AddResponse(StatusBadRequest, 'Fallo en la validación de campos');
end;

initialization
  TUserRouter.Register;
end.
```

---

## 📖 Documentación OpenAPI 3.1 y Registro Canónico de Esquemas

Zenith presenta una profunda integración nativa entre su enrutador HTTP, el motor de documentación [Swagger4Laz](src/swagger4laz) y los modelos fuertemente tipados de [DeltaModel](src/deltamodel).

### 1. Registro Automático en `components.schemas`
Durante el inicio de la aplicación, Zenith vincula automáticamente un manejador de esquemas bidireccional:

```pascal
// Registrado automáticamente en la unidad Zenith.App:
SetDeltaModelRegisterSchemaProc(@ZenithRegisterModelProc);
```

Cada vez que un modelo se referencia en una ruta de la API, se registra de manera automática, idempotente y segura para hilos en el diccionario `components.schemas` de OpenAPI 3.1.

### 2. Métodos de Generación Semántica de Esquemas en DeltaModel
Evite métodos heredados no tipados. Utilice los generadores explícitos:

| Método | Tipo en el Esquema | Formato OpenAPI |
| :--- | :--- | :--- |
| `TModel.SwaggerSchemaObject(AddExamples)` | `object` | Esquema inline completo del objeto |
| `TModel.SwaggerSchemaArray(AddExamples)` | `array` | Esquema inline de array (`items: { type: object }`) |
| `TModel.SwaggerSchemaPaginated(AddExamples)` | `object` | Envoltorio paginado (`items`, `page`, `page_size`, `total_records`, `total_pages`) |
| `TModel.SwaggerSchemaRefObject` | `$ref` | `{"$ref": "#/components/schemas/ModelName"}` |
| `TModel.SwaggerSchemaRefArray` | `array` | `{"type": "array", "items": {"$ref": "#/components/schemas/ModelName"}}` |
| `TModel.SwaggerSchemaRefPaginated` | `object` | Envoltorio paginado con `$ref` en `items` |

### 3. Ejemplo Práctico en Endpoints Empresariales

```pascal
procedure RegisterProductRoutes;
begin
  // GET /productos - Lista paginada referenciando components.schemas
  Router
    .Get('/productos', @ListProducts)
    .SetSummary('Listar productos con paginación')
    .AddTags('Productos')
    .AddQueryParam('page', False, 'integer', '1', 'Página actual')
    .AddQueryParam('page_size', False, 'integer', '20', 'Registros por página')
    .AddResponse(StatusOK, 'Lista paginada de productos', TProductResponse.SwaggerSchemaRefPaginated);

  // POST /productos - Registro con cuerpo de solicitud y respuesta tipados
  Router
    .Post('/productos', @CreateProduct)
    .SetSummary('Crear nuevo producto')
    .AddTags('Productos')
    .SetBodyContent(TProductInsert.SwaggerSchemaObject(), True, ApplicationJson, 'Datos del producto')
    .AddResponse(StatusCreated, 'Producto creado', TProductResponse.SwaggerSchemaRefObject)
    .AddResponse(StatusBadRequest, 'Error de validación');
end;
```

---

## ⚡ Arquitectura de Alto Rendimiento de Zenith

Para responder a entornos empresariales de alta demanda y múltiples inquilinos con un consumo mínimo de recursos, Zenith elimina los cuellos de botella clásicos de Free Pascal:

### 1. `TDeltaFastJsonStreamer`: Transmisión JSON Directa (Zero-DOM)
Los métodos convencionales (`fpjson`) instancian cientos de nodos DOM intermedios (`TJSONObject`, `TJSONData`, `TJSONFloat`) en el heap para cada registro retornado, generando fragmentación de memoria y sobrecarga en el recolector de basura.

Zenith transmite bytes crudos directamente a búferes continuos `RawByteString`:
- **Cero Asignación DOM**: Genera cargas útiles JSON directamente sin crear árboles de objetos.
- **Formateo de Punto Fijo (`ffFixed`) sin Notación Científica**: El `fpjson` estándar de FPC formatea números en coma flotante grandes o pequeños con notación exponencial (`1.5E+06` o `1.0E-04`), rompiendo parsers en clientes JavaScript y móviles. `TDeltaFastJsonStreamer` formatea estrictamente en punto fijo decimal (`FloatToStrF` con `ffFixed`) con eliminación inteligente de ceros superfluos, garantizando precisión contable y fiscal.

### 2. `TColumnBindingMap`: Vinculación ORM Tipada Directa Sin Conversión Variant
La extracción tradicional de `TDataSet` utiliza propiedades `Variant` (`Field.Value`), incurriendo en costos de empaquetado y despacho OLE/COM.

Con `TColumnBindingMap`:
- Las correspondencias entre columnas y propiedades se resuelven una sola vez en la primera fila de la consulta.
- Los datos se leen directamente con métodos nativos tipados (`ADS.Fields[I].AsLargeInt`, `ADS.Fields[I].AsString`, `ADS.Fields[I].AsFloat`).
- Elimina totalmente las conversiones de Variant en consultas con decenas de miles de registros.

### 3. `TRTTICache` & `TModelMetadata`: Caché RTTI Estática Segura para Hilos
La inspección repetitiva de RTTI (`TypInfo.GetPropList`) durante la serialización, validación y migraciones se evita mediante una caché en memoria protegida por secciones críticas:
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

### Generación de un Token

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

    // exp e iat se gestionan automáticamente o pueden definirse manualmente
    Token := TJWT.GenerateToken(Payload);
  finally
    Payload.Free;
  end;
end;
```

### Validación de un Token en el Controlador de Ruta

```pascal
var
  AuthHeader, Token: string;
  Payload: TPayLoad;
begin
  AuthHeader := ARequest.Authorization; // "Bearer eyJhbGciOi..."
  Token := StringReplace(AuthHeader, 'Bearer ', '', [rfIgnoreCase]).Trim;

  // Lanza EUnauthorized automáticamente si ha expirado, está malformado o es inválido
  Payload := TJWT.ValidadeToken(Token);
  try
    WriteLn('Usuario autenticado: ', Payload.CustomValues['email']);
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

Las variables de entorno del sistema operativo tienen prioridad sobre las entradas de `.env`. Para cookies del navegador o peticiones CORS con credenciales, defina un origen explícito en `ZENITH_CORS_ORIGIN` y active credenciales. El comodín `*` no puede combinarse con credenciales.

Consulte variables de entorno directamente en Pascal:

```pascal
uses Zenith.Env;

var
  MiValor: string;
begin
  MiValor := GetEnvVariable('MI_VARIABLE', 'ValorPorDefecto');
end;
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
Para compilar en modo FastCGI con pool de conexiones, use la directiva de compilación `-dFCGI`:

```bash
lazbuild -B -dFCGI myapi.lpi
```

Ejemplo de configuración en **Nginx**:
```nginx
server {
    listen 80;
    server_name api.empresa.com;

    location / {
        fastcgi_pass 127.0.0.1:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_NAME "";
        fastcgi_param HTTP_X_FORWARDED_PREFIX "";
    }
}
```

---

## 📁 Demostraciones Incluidas

1. [`demo/00-todolist`](demo/00-todolist) — API básica de tareas con SQLite (CRUD completo con OpenAPI 3.1 y Swagger UI).
2. [`demo/01-order-management`](demo/01-order-management) — API empresarial de Comercio y Gestión de Pedidos (RMS Starter):
   - Modelado de dominio: `TProduct`, `TCustomer`, `TSaleOrder` y `TSaleOrderItem` con mapeo relacional 1:N (`Include('items')`).
   - RBAC declarativo con `TZRBACPolicy<TProduct>` para restringir mutaciones al rol `admin`.
   - Agrupación fluida de rutas con `SwaggerRouter.Group('/api/v1/orders')`.
   - Transacciones atómicas: validación de límite de crédito, reserva de inventario en tiempo real y cancelación con reposición de stock.
   - Documentación en tres idiomas ([Español](demo/01-order-management/README.es-ES.md), [English](demo/01-order-management/README.md), [Português](demo/01-order-management/README.pt-BR.md)).

---

## 📄 Licencia

Distribuido bajo la Licencia MIT. Consulte `LICENSE` para más información.
