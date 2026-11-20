<p align="right">
  [ English ](README.md) | [ Português (Brasil) ](README.pt-BR.md) | [ Español ](README.es-ES.md)
</p>

# Zenith

[![Lazarus](https://img.shields.io/badge/Lazarus-%3E%3D%202.2-blue.svg)](https://www.lazarus-ide.org/)
[![FreePascal](https://img.shields.io/badge/FPC-%3E%3D%203.2.2-green.svg)](https://www.freepascal.org/)
[![OpenAPI](https://img.shields.io/badge/OpenAPI-3.1-brightgreen.svg)](https://swagger.io/specification/)
[![Formatos](https://img.shields.io/badge/Formatos-JSON%20%7C%20CBOR%20%7C%20BSON%20%7C%20XML%20%7C%20CSV-orange.svg)](https://github.com/pedroaaraujo/zenith)
[![RFC 7807](https://img.shields.io/badge/RFC-7807%20Compliant-orange.svg)](https://datatracker.ietf.org/doc/html/rfc7807)
[![Licença](https://img.shields.io/badge/Licenca-MIT-blue.svg)](LICENSE)

**Zenith** é um framework web de alta performance para **Free Pascal / Lazarus (FPC)**. Projetado para proporcionar uma experiência de desenvolvimento ágil e contemporânea, o Zenith reúne documentação interativa **OpenAPI 3.1 / Swagger UI**, modelagem de dados com **Micro-ORM Multi-SGBD**, **Serialização Multi-Formato** (JSON, CBOR, BSON, XML, CSV), autenticação **JWT / Basic**, logging estruturado e tratamento padronizado de erros no padrão **RFC 7807**.

---

## 🚀 Principais Recursos

- ⚡ **Alta Concorrência & Baixa Latência**: Servidor HTTP embutido com suporte nativo a multi-threading (`fphttpapp`), modo FastCGI (`fpfcgi`) e arquitetura Zero-DOM.
- 📦 **Serialização Multi-Formato**: Codecs Zero-DOM para 5 formatos canônicos: JSON, CBOR (binário RFC 8949), BSON (binário v1.1), XML e CSV (RFC 4180).
- 🚀 **Roteador CRUD Automático (`Zenith.Crud`)**: Registro em 1 linha de 5 endpoints REST completos (`GET`, `GET :id`, `POST`, `PUT :id`, `DELETE :id`) fortemente tipados com validação, pool de conexões e documentação OpenAPI.
- 🌐 **Internacionalização (i18n) e Mensagens Configuráveis**: Suporte unificado a múltiplos idiomas (`en-US`, `pt-BR`, `es-ES`) via `Zenith.Messages`, `DeltaModel.Messages` e `Swagger4Laz` (`ZENITH_LOCALE`, `SetZenithLocale`).
- 🚀 **Streaming Direto & Zero-DOM**: Serialização ultrarrápida via `TDeltaFastJsonStreamer`, `TDeltaCborCodec`, `TDeltaBsonCodec`, `TDeltaXmlCodec`, `TDeltaCsvCodec` e streaming HTTP chunked em lotes (`TDeltaQuery<T>.StreamJsonTo`).
- ⚡ **ORM com Binding Tipado Direto**: Mapeamento pré-alocado de colunas com `TColumnBindingMap`, Eager Loading 1:N com `Include` e cache de reflexão estático `TRTTICache`.
- 📖 **Documentação OpenAPI 3.1 & Swagger UI**: Integração nativa com o [Swagger4Laz](src/swagger4laz), servindo documentação interativa com registro centralizado de schemas em `components.schemas` e referências canônicas `$ref` em `/docs`.
- 🧩 **Modelagem, Validação & ORM com DeltaModel**: Integração direta com o [DeltaModel](src/deltamodel) para modelos fortemente tipados, validação fluente e persistência multi-SGBD (PostgreSQL, MariaDB/MySQL, SQLite, Firebird, MSSQL, Oracle).
- 🛡️ **Erros Padronizados (RFC 7807)**: Respostas de erro ricas em JSON seguindo o padrão internacional *Problem Details for HTTP APIs*.
- 🔐 **Autenticação Embutida**:
  - Suporte completo a **JWT (JSON Web Token)** com geração, assinatura HMAC-SHA256, expiração e validação.
  - Autenticação **HTTP Basic**.
- ⚙️ **Configuração por `.env`**: Leitura transparente de variáveis de ambiente do sistema e arquivos `.env` locais.
- 📝 **Logging Estruturado Thread-Safe**: Sistema de logs com registro automático de requisições, erros e níveis de severidade (`INFO`, `WARN`, `ERROR`).
- 🌐 **CORS Automático**: Tratamento configurável de pre-flight `OPTIONS` e cabeçalhos de CORS.
- 🔄 **Pronto para Reverse Proxies**: Compatível com Nginx, Traefik, Apache e Caddy (incluindo `X-Forwarded-Prefix`).

---

## 🏛️ Arquitetura do Framework

```
Zenith/
├── src/
│   ├── Zenith.App.pas         # Singleton da aplicação (TZenithApp) e ciclo de vida
│   ├── Zenith.Crud.pas        # Roteador e controlador CRUD REST automático com Generics
│   ├── Zenith.Messages.pas    # Mensagens de erro e internacionalização RFC 7807 (i18n)
│   ├── Zenith.Core.pas        # Pipeline de tratamento de exceções e middlewares
│   ├── Zenith.Constants.pas   # MIME types canônicos, status codes e cabeçalhos HTTP
│   ├── Zenith.Consts.pas      # Constantes HTTP, status codes e MIME types legados
│   ├── Zenith.Types.pas       # Tipos base e formatador RFC 7807 (TJsonError)
│   ├── Zenith.Exceptions.pas  # Hierarquia de exceções semânticas HTTP
│   ├── Zenith.Auth.JWT.pas    # Criação e validação de tokens JWT
│   ├── Zenith.Auth.Basic.pas  # Autenticação HTTP Basic
│   ├── Zenith.Hash.pas        # Funções criptográficas (HMAC-SHA256, SHA256, MD5)
│   ├── Zenith.Env.pas         # Leitor de variáveis (.env / OS environment)
│   ├── Zenith.Log.pas         # Logger thread-safe em arquivo e console
│   ├── swagger4laz/           # Submódulo: Swagger UI e OpenAPI 3.1
│   └── deltamodel/            # Submódulo: Modelagem, Codecs Multi-Formato e Micro-ORM Generics
└── demo/
    ├── 00-todolist/           # Exemplo prático de API REST com SQLite e TZenithCrud
    └── 01-order-management/   # RMS Starter completo com produtos, pedidos, RBAC e multi-formato
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
    raise EBadRequest.Create('ID de usuário inválido.');

  if UserId = 99 then
    raise EResourceNotFound.Create('Usuário não localizado no sistema.');

  User := TUserResponse.Create;
  try
    User.id.AsInteger := UserId;
    User.name.AsText := 'Carlos Eduardo';
    User.email.AsText := 'carlos@empresa.com';

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
    .SetSummary('Buscar usuário por ID')
    .AddTags('Usuários')
    .AddPathParam('id', True, 'integer', '1', 'ID do usuário')
    .AddResponseRef(HTTP_STATUS_OK, 'UserResponse', 'Usuário localizado', MIME_APPLICATION_JSON)
    .AddResponseRef(HTTP_STATUS_OK, 'UserResponse', 'Payload binário CBOR', MIME_APPLICATION_CBOR)
    .AddResponse(HTTP_STATUS_BAD_REQUEST, 'Requisição inválida')
    .AddResponse(HTTP_STATUS_NOT_FOUND, 'Usuário não encontrado');
end;

initialization
  TUserRouter.Register;
end.
```

---

## 📦 Negociação de Conteúdo Multi-Formato (JSON, CBOR, BSON, XML, CSV)

O Zenith utiliza o pipeline de codecs Zero-DOM do DeltaModel (`IDeltaCodec` e `TDeltaCodecRegistry`) para serializar respostas dinamicamente com base no cabeçalho `Accept` da requisição HTTP ou nas necessidades da rota.

### Formatos e Media Types Suportados

| Formato | Classe do Codec | Media Types Canônicos | Padrão |
| :--- | :--- | :--- | :--- |
| **JSON** | `TDeltaJsonCodec` | `application/json` | RFC 8259 |
| **CBOR** | `TDeltaCborCodec` | `application/cbor` | RFC 8949 (Binário) |
| **BSON** | `TDeltaBsonCodec` | `application/bson` | BSON v1.1 (Binário) |
| **XML**  | `TDeltaXmlCodec`  | `application/xml`, `text/xml` | W3C XML 1.0 (Zero-DOM) |
| **CSV**  | `TDeltaCsvCodec`  | `text/csv` | RFC 4180 |

### Matriz de Tradeoffs Técnicos

- **CBOR (`application/cbor`)**:
  - *Tamanho do payload*: ~40-60% menor que JSON.
  - *Características*: Ponto flutuante IEEE 754 direto, compactação de inteiros (0..23 inline), zero overhead de conversão a texto.
  - *Ideal para*: Dispositivos IoT, aplicativos móveis (Flutter), comunicação inter-microsserviços onde largura de banda e latência são críticas.
- **BSON (`application/bson`)**:
  - *Tamanho do payload*: Similar ao JSON; prefixado com o tamanho do documento em 32 bits.
  - *Características*: Tipagem binária rica (UTC datetime em ms, inteiros de 64 bits, BLOBs binários).
  - *Ideal para*: Bancos documentais, workers de analytics, interoperabilidade com MongoDB.
- **CSV (`text/csv`)**:
  - *Tamanho do payload*: Extremamente compacto para conjuntos de dados tabulares planos.
  - *Características*: Conformidade com RFC 4180, cabeçalho automático, escape de aspas duplas, timestamps ISO-8601.
  - *Ideal para*: Exportações em lote, relatórios contábeis/fiscais, planilhas analíticas.
- **XML (`application/xml`)**:
  - *Tamanho do payload*: ~20-40% maior que JSON devido às tags de fechamento.
  - *Características*: Declaração UTF-8 padrão, escape estrito de entidades, tags auto-fechadas para valores nulos.
  - *Ideal para*: Integrações corporativas enterprise, conformidade bancária/fiscal, sistemas SOAP/XML legados.
- **JSON (`application/json`)**:
  - *Tamanho do payload*: Linha de base padrão.
  - *Características*: Compatibilidade universal com navegadores e SPAs, números em ponto fixo (`ffFixed`).
  - *Ideal para*: APIs públicas REST e clientes web JavaScript.

### Blindagens de Segurança (RFC 8949 Seção 10 & BSON Anti-DoS)

Os decodificadores binários implementam proteções ativas:
- **Anti-OOM (Prevenção de Esgotamento de Memória)**: Validação estrita do tamanho do stream antes de alocações com `SetLength`. Comprimentos declarados que excedam o restante do stream ou ultrapassem `16 MB` disparam imediatamente `EDeltaDeserializationException`.
- **Limite Rígido de Recursão**: O limite de `MAX_NESTING_DEPTH = 64` previne ataques de estouro de pilha por documentos maliciosos profundamente aninhados.
- **Controle de CStrings Nulas**: `MAX_BSON_CSTRING_LENGTH = 1024` impede loops infinitos de leitura em documentos BSON sem terminador nulo `0x00`.

---

## 📖 Documentação OpenAPI 3.1 & Registro Canônico de Schemas

O Zenith possui integração nativa entre o pipeline HTTP, o motor [Swagger4Laz](src/swagger4laz) e os modelos do [DeltaModel](src/deltamodel).

### 1. Registro Automático em `components.schemas`
Na inicialização da aplicação, o Zenith registra automaticamente um canal bidirecional entre o DeltaModel e o Router:

```pascal
SetDeltaModelRegisterSchemaProc(@ZenithRegisterModelProc);
```

Dessa forma, sempre que um modelo for referenciado em qualquer rota da API, ele é registrado automaticamente no dicionário `components.schemas` do OpenAPI 3.1 de forma idempotente e thread-safe.

### 2. Métodos Semânticos de Schema no DeltaModel

| Método | Tipo no Schema | Formato OpenAPI |
| :--- | :--- | :--- |
| `TModel.SwaggerSchemaObject(AddExamples)` | `object` | Schema inline completo do objeto |
| `TModel.SwaggerSchemaArray(AddExamples)` | `array` | Schema inline de lista (`items: { type: object }`) |
| `TModel.SwaggerSchemaPaginated(AddExamples)` | `object` | Envelope paginado (`items`, `page`, `page_size`, `total_records`, `total_pages`) |
| `TModel.SwaggerSchemaRefObject` | `$ref` | `{"$ref": "#/components/schemas/ModelName"}` |
| `TModel.SwaggerSchemaRefArray` | `array` | `{"type": "array", "items": {"$ref": "#/components/schemas/ModelName"}}` |
| `TModel.SwaggerSchemaRefPaginated` | `object` | Envelope paginado contendo referências `$ref` em `items` |

---

## ⚡ Arquitetura de Alta Performance do Zenith

### 1. `TDeltaFastJsonStreamer`: Streaming JSON Direto (Zero-DOM)
O Zenith transmite bytes diretamente para buffers `RawByteString` contíguos sem instanciar árvores de objetos no heap:
- **Zero Alocação DOM**: Gera o payload diretamente sem construir nós intermediários.
- **Formatação de Ponto Fixo (`ffFixed`) sem Notação Científica**: O `fpjson` padrão formata valores flutuantes grandes em notação exponencial (`1.5E+06`), quebrando parsers mobile e JavaScript. O `TDeltaFastJsonStreamer` formata floats estritamente em ponto fixo (`ffFixed`) com remoção inteligente de zeros supérfluos.

### 2. `TColumnBindingMap`: Binding Direto ORM sem Variant Boxing
- Mapeamento de colunas para propriedades resolvido uma única vez na primeira linha do dataset.
- Leitura direta via métodos tipados nativos do driver (`ADS.Fields[I].AsLargeInt`, `ADS.Fields[I].AsString`, `ADS.Fields[I].AsFloat`).
- Elimina completamente o overhead de Variants em consultas de alto volume.

### 3. `TRTTICache` & `TModelMetadata`: Reflexão Estática em Tempo de Execução
- Propriedades publicadas inspecionadas e indexadas apenas uma vez por classe.
- Consultas de metadados durante a execução ocorrem em tempo constante $O(1)$.

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
Compile com a diretiva `-dFCGI`:

```bash
lazbuild -B -dFCGI myapi.lpi
```

---

## 📁 Demonstrações Incluídas

- [`demo/00-todolist`](demo/00-todolist): API REST SQLite minimalista com `Zenith.App`, `TZenithCrud` e Swagger UI.
- [`demo/01-order-management`](demo/01-order-management): RMS Starter corporativo completo cobrindo Produtos, Clientes, Pedidos, relações 1:N (`Include`), RBAC, respostas multi-formato e Swagger UI interativo.

---

## 📄 Licença

Distribuído sob a licença MIT. Consulte `LICENSE` para detalhes.
