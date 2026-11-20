# Zenith

[![Lazarus](https://img.shields.io/badge/Lazarus-2.2%2B-blue.svg)](https://www.lazarus-ide.org/)
[![FreePascal](https://img.shields.io/badge/FPC-3.2.2%2B-green.svg)](https://www.freepascal.org/)
[![OpenAPI](https://img.shields.io/badge/OpenAPI-3.0.3-brightgreen.svg)](https://swagger.io/specification/)
[![RFC 7807](https://img.shields.io/badge/RFC-7807%20Compliant-orange.svg)](https://datatracker.ietf.org/doc/html/rfc7807)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Zenith** é um framework web moderno, elegante e de alta performance para **Free Pascal / Lazarus (FPC)**. Projetado para proporcionar uma experiência de desenvolvimento ágil e contemporânea, o Zenith reúne documentação interativa automática **OpenAPI / Swagger UI**, modelagem e validação com **Micro-ORM Multi-SGDB**, autenticação **JWT / Basic**, logging estruturado e tratamento padronizado de erros no padrão **RFC 7807**.

---

## 🚀 Principais Recursos

- ⚡ **Alta Performance & Concorrência**: Servidor HTTP embutido com suporte nativo a multi-threading (`fphttpapp`), modo FastCGI (`fpfcgi`) e arquitetura Zero-DOM.
- 🚀 **Roteador CRUD Automático (`Zenith.Crud`)**: Registro em 1 linha de 5 endpoints REST completos (`GET`, `GET :id`, `POST`, `PUT :id`, `DELETE :id`) fortemente tipados com validação, pool de conexões e documentação OpenAPI.
- 🌐 **Internacionalização (i18n) e Mensagens Configuráveis**: Suporte unificado a múltiplos idiomas (`en-US`, `pt-BR`, `es-ES`) via `Zenith.Messages`, `DeltaModel.Messages` e `Swagger4Laz` (`ZENITH_LOCALE`, `SetZenithLocale`).
- 🚀 **Streaming JSON Direto & Zero-DOM**: Serialização ultrarrápida via `TDeltaFastJsonStreamer` e streaming HTTP chunked em lotes (`TDeltaQuery<T>.StreamJsonTo`), eliminando consumo excessivo de memória em grandes volumes.
- ⚡ **ORM com Binding Tipado Direto**: Mapeamento pré-alocado de colunas com `TColumnBindingMap`, Eager Loading 1:N com `Include` e cache de reflexão `TRTTICache`.
- 📖 **Documentação OpenAPI 3.1 & Swagger UI**: Integração nativa com o [Swagger4Laz](src/swagger4laz), servindo documentação interativa com registro centralizado de schemas em `components.schemas` e referências canônicas `$ref` em `/docs`.
- 🧩 **Modelagem, Validação & ORM com DeltaModel**: Integração direta com o [DeltaModel](src/deltamodel) para modelos fortemente tipados, validação fluente e persistência multi-SGDB.
- 🛡️ **Erros Padronizados (RFC 7807)**: Respostas de erro ricas em JSON seguindo o padrão internacional *Problem Details for HTTP APIs*.
- 🔐 **Autenticação Embutida**:
  - Suporte completo a **JWT (JSON Web Token)** com geração, assinatura HMAC-SHA256, expiração e validação.
  - Autenticação **HTTP Basic**.
- ⚙️ **Configuração por `.env`**: Leitura transparente de variáveis de ambiente do sistema e arquivos `.env` locais.
- 📝 **Logging Estruturado**: Sistema de logs com registro automático de requisições, erros e níveis de severidade (`INFO`, `WARN`, `ERROR`).
- 🌐 **CORS Automático**: Tratamento configurável de pre-flight `OPTIONS` e cabeçalhos de CORS.
- 🔄 **Pronto para Reverse Proxies**: Compatível com Nginx, Traefik, Apache e Caddy (incluindo `X-Forwarded-Prefix`).

---

## 🏛️ Arquitetura do Framework

```
Zenith/
├── src/
│   ├── Zenith.App.pas         # Singleton da aplicação (TZenithApp) e inicialização
│   ├── Zenith.Crud.pas        # Roteador e controlador CRUD REST automático com Generics
│   ├── Zenith.Messages.pas    # Mensagens de erro e internacionalização RFC 7807 (i18n)
│   ├── Zenith.Core.pas        # Pipeline de tratamento de exceções e middlewares
│   ├── Zenith.Consts.pas      # Constantes HTTP, status codes e MIME types
│   ├── Zenith.Types.pas       # Tipos base e formatador RFC 7807 (TJsonError)
│   ├── Zenith.Exceptions.pas  # Hierarquia de exceções semânticas HTTP
│   ├── Zenith.Auth.JWT.pas    # Criação e validação de tokens JWT
│   ├── Zenith.Auth.Basic.pas  # Autenticação HTTP Basic
│   ├── Zenith.Hash.pas        # Funções criptográficas (HMAC-SHA256, SHA256, MD5)
│   ├── Zenith.Env.pas         # Leitor de variáveis (.env / OS environment)
│   ├── Zenith.Log.pas         # Logger thread-safe em arquivo e console
│   ├── swagger4laz/           # Submódulo: Swagger UI e OpenAPI 3.1
│   └── deltamodel/            # Submódulo: Modelagem, Validação e Micro-ORM Generics
└── demo/
    └── 00-todolist/           # Exemplo prático de API REST completa com TZenithCrud
```

---

## 🏁 Quick Start: Construindo sua Primeira API

### 1. Estrutura do Programa Principal (`.lpr`)

```pascal
program MyApi;

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  Classes, SysUtils, fphttpapp,
  Zenith.App,
  // Suas rotas e modelos
  User.Model, User.Route;

begin
  ZenithApp
    .SetTitle('Minha API REST')
    .SetVersion('1.0.0')
    .SetDescription('API desenvolvida com Zenith e Lazarus')
    .SetPort(8080)
    .SetThreaded(True)
    .SetDocRoute('/docs')
    .Run;
end.
```

---

### 2. Definindo o Modelo com DeltaModel

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
    .RuleFor(name.Value, 'Nome')
      .MinLength(3)
    .RuleFor(email.Value, 'E-mail')
      .ValidEmail;
end;

end.
```

---

### 3. Criando e Documentando as Rotas

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
    raise EBadRequest.Create('ID de usuário inválido.');

  if UserId = 99 then
    raise EResourceNotFound.Create('Usuário não localizado no sistema.');

  User := TUserResponse.Create;
  try
    // Acesso tipado direto sem boxing de Variant
    User.id.AsInteger := UserId;
    User.name.AsText := 'Carlos Eduardo';
    User.email.AsText := 'carlos@empresa.com';

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
    InputData.Validate; // Dispara EDeltaValidation em caso de erro

    // Atribuição tipada direta sem boxing de Variant
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
  // Documentação e vinculação GET /users/:id utilizando referência canônica $ref
  Router
    .Get('/users/:id', @GetUser)
    .SetSummary('Buscar usuário por ID')
    .AddTags('Usuários')
    .AddPathParam('id', True, 'integer', '1', 'ID do usuário')
    .AddResponseRef(StatusOK, 'UserResponse', 'Usuário localizado')
    .AddResponse(StatusBadRequest, 'Requisição inválida')
    .AddResponse(StatusNotFound, 'Usuário não encontrado');

  // Documentação e vinculação POST /users com payload e resposta referenciando components.schemas
  Router
    .Post('/users', @CreateUser)
    .SetSummary('Cadastrar novo usuário')
    .AddTags('Usuários')
    .SetBodyContentRef('UserInsert', True, ApplicationJson, 'Dados de cadastro')
    .AddResponseRef(StatusCreated, 'UserResponse', 'Usuário criado com sucesso')
    .AddResponse(StatusBadRequest, 'Falha na validação dos campos');
end;

initialization
  TUserRouter.Register;
end.
```

---

## 📖 Documentação OpenAPI 3.1 & Registro Canônico de Schemas

O Zenith possui integração profunda e nativa entre o pipeline HTTP, o motor de documentação [Swagger4Laz](src/swagger4laz) e os modelos fortemente tipados do [DeltaModel](src/deltamodel).

### 1. Registro Automático em `components.schemas`
Na inicialização da aplicação, o Zenith registra automaticamente um canal bidirecional entre o DeltaModel e o Router:

```pascal
// Executado automaticamente na unit Zenith.App:
SetDeltaModelRegisterSchemaProc(@ZenithRegisterModelProc);
```

Dessa forma, sempre que um modelo for referenciado em qualquer rota da API, ele é registrado automaticamente no dicionário `components.schemas` do OpenAPI 3.1 de forma idempotente e thread-safe.

### 2. Métodos Semânticos de Schema no DeltaModel
Evite o uso do método legado `SwaggerSchema()`. Utilize os métodos explícitos e fortemente tipados:

| Método | Tipo no Schema | Formato OpenAPI |
| :--- | :--- | :--- |
| `TModel.SwaggerSchemaObject(AddExamples)` | `object` | Schema inline completo do objeto |
| `TModel.SwaggerSchemaArray(AddExamples)` | `array` | Schema inline de lista (`items: { type: object }`) |
| `TModel.SwaggerSchemaPaginated(AddExamples)` | `object` | Envelope paginado (`items`, `page`, `page_size`, `total_records`, `total_pages`) |
| `TModel.SwaggerSchemaRefObject` | `$ref` | `{"$ref": "#/components/schemas/ModelName"}` |
| `TModel.SwaggerSchemaRefArray` | `array` | `{"type": "array", "items": {"$ref": "#/components/schemas/ModelName"}}` |
| `TModel.SwaggerSchemaRefPaginated` | `object` | Envelope paginado contendo referências `$ref` em `items` |

### 3. Exemplo Prático em Rotas Corporativas

```pascal
procedure RegisterProductRoutes;
begin
  // GET /produtos - Lista paginada referenciando components.schemas
  Router
    .Get('/produtos', @ListProducts)
    .SetSummary('Listar produtos com paginação')
    .AddTags('Produtos')
    .AddQueryParam('page', False, 'integer', '1', 'Página atual')
    .AddQueryParam('page_size', False, 'integer', '20', 'Registros por página')
    .AddResponse(StatusOK, 'Lista paginada', TProductResponse.SwaggerSchemaRefPaginated);

  // POST /produtos - Cadastro com Request Body e Response tipados
  Router
    .Post('/produtos', @CreateProduct)
    .SetSummary('Criar novo produto')
    .AddTags('Produtos')
    .SetBodyContent(TProductInsert.SwaggerSchemaObject(), True, ApplicationJson, 'Dados do produto')
    .AddResponse(StatusCreated, 'Produto criado', TProductResponse.SwaggerSchemaRefObject)
    .AddResponse(StatusBadRequest, 'Erro de validação');
end;
```

---

## ⚡ Arquitetura de Alta Performance do Zenith

Para suportar ambientes corporativos de alta demanda e múltiplos tenants concorrentes, o ecossistema Zenith incorpora inovações de baixo nível que eliminam os gargalos tradicionais do Free Pascal:

### 1. `TDeltaFastJsonStreamer`: Streaming JSON Direto (Zero-DOM)
Ao contrário das abordagens tradicionais (`fpjson`) que instanciam árvores de objetos `TJSONObject` e `TJSONData` em heap para cada registro retornado, o Zenith utiliza streaming contíguo de bytes:
- **Zero Alocação DOM**: O payload JSON é gerado diretamente para buffers `RawByteString`, reduzindo substancialmente o uso de memória e a fragmentação de heap.
- **Formatação de Ponto Fixo (`ffFixed`) sem Notação Científica**: O `fpjson` padrão do FPC formata valores numéricos flutuantes grandes ou pequenos em notação científica (ex.: `1.5E+06` ou `1.0E-04`), quebrando parsers de clientes JavaScript e mobile. O `TDeltaFastJsonStreamer` formata floats estritamente em ponto fixo (`FloatToStrF` com `ffFixed`) com remoção inteligente de zeros supérfluos, garantindo compatibilidade contábil e fiscal de alta precisão.

### 2. `TColumnBindingMap`: Binding Direto ORM sem Variant Boxing
A extração de dados do `TDataSet` convencional para objetos de negócio tradicionalmente envolve chamadas a propriedades do tipo `Variant` (`Field.Value`), gerando overhead de despacho e boxing OLE.

Com o `TColumnBindingMap`:
- O mapeamento entre colunas SQL e propriedades do modelo é pré-calculado uma única vez na primeira linha do dataset.
- A leitura dos dados é realizada diretamente através dos métodos tipados nativos do driver (`ADS.Fields[I].AsLargeInt`, `ADS.Fields[I].AsString`, `ADS.Fields[I].AsFloat`, etc.).
- Elimina completamente o uso de Variants em consultas com milhares de registros.

### 3. `TRTTICache` & `TModelMetadata`: Reflexão Estática em Tempo de Execução
A inspeção repetida de RTTI (`TypInfo`) durante serialização, validação e DDL do ORM é evitada através de cache thread-safe em memória:
- As propriedades publicadas de cada classe `TDeltaModel` são inspecionadas e indexadas apenas uma vez.
- As buscas de metadados durante a execução das requisições ocorrem com custo $O(1)$.

---

## 🛡️ Tratamento de Exceções & RFC 7807

Quando uma exceção semântica é lançada em qualquer rota, o Zenith intercepta o erro automaticamente e responde com uma estrutura padronizada **RFC 7807**:

```json
{
  "type": "urn:zenith:problem:validation-error",
  "title": "Falha na validação de regras de negócio.",
  "status": 400,
  "detail": "Field TUserInsert.email is invalid: E-mail format is invalid",
  "instance": ""
}
```

### Exceções Semânticas Disponíveis (`Zenith.Exceptions`):

| Classe de Exceção | Código HTTP | Código no JSON (`type`) |
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

## 🔐 Autenticação JWT

O Zenith inclui suporte nativo a tokens JWT com assinatura HMAC-SHA256 (`Zenith.Auth.JWT`):

### Gerando um Token

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

    // exp e iat são gerenciados automaticamente ou podem ser customizados
    Token := TJWT.GenerateToken(Payload);
  finally
    Payload.Free;
  end;
end;
```

### Validando um Token no Handler

```pascal
var
  AuthHeader, Token: string;
  Payload: TPayLoad;
begin
  AuthHeader := ARequest.Authorization; // "Bearer eyJhbGciOi..."
  Token := StringReplace(AuthHeader, 'Bearer ', '', [rfIgnoreCase]).Trim;

  // Lança EUnauthorized automaticamente se expirado ou inválido
  Payload := TJWT.ValidadeToken(Token);
  try
    WriteLn('Usuário autenticado: ', Payload.CustomValues['email']);
  finally
    Payload.Free;
  end;
end;
```

---

## ⚙️ Configuração via `.env`

Crie um arquivo `.env` no mesmo diretório do executável:

```env
ZENITH_PORT=8080
ZENITH_ALLOW_CORS=Y
ZENITH_CORS_ORIGIN=https://app.empresa.com
ZENITH_CORS_ALLOW_CREDENTIALS=N
ZENITH_LOGFILE=zenith.log
ZENITH_JWT_SECRET=sua-chave-secreta-super-segura-aqui
ZENITH_JWT_EXPIRATION=30
ZENITH_TODO_DATABASE=/var/lib/minha-api/todo.sqlite
```

Variáveis exportadas pelo processo têm precedência sobre o arquivo `.env`. Para
cookies ou autenticação enviada pelo navegador, configure uma origem específica
em `ZENITH_CORS_ORIGIN` e habilite credenciais explicitamente. A origem `*` não
é combinada com credenciais.

As variáveis podem ser consultadas diretamente no código:

```pascal
uses Zenith.Env;

var
  MeuValor: string;
begin
  MeuValor := GetEnvVariable('MINHA_VARIAVEL', 'ValorPadrao');
end;
```

---

## 🌐 Deploy em Produção

### Modo Standalone Daemon (Padrão)
Execute o binário compilado diretamente como um serviço `systemd`:

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
Para compilar em modo FastCGI com pooling de conexões, ative a flag de compilação `-dFCGI`:

```bash
lazbuild -B -dFCGI myapi.lpi
```

Exemplo de configuração no **Nginx**:
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

## 📁 Demonstração Incluída

Consulte [`demo/00-todolist`](demo/00-todolist) para uma API persistente em SQLite:
- `Zenith.App` e `SwaggerRouter`
- `DeltaModel`, migrations automáticas e pool de conexões
- Rotas REST para listar, criar, buscar e remover tarefas.

O arquivo SQLite é criado junto ao executável por padrão. Configure
`ZENITH_TODO_DATABASE` com outro caminho ou use `ZENITH_TODO_DATABASE_URL` para
informar uma URL de conexão completa.

---

## 📄 Licença

Distribuído sob a licença MIT. Consulte `LICENSE` para detalhes.
