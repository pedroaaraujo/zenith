# Zenith

[![Lazarus](https://img.shields.io/badge/Lazarus-2.2%2B-blue.svg)](https://www.lazarus-ide.org/)
[![FreePascal](https://img.shields.io/badge/FPC-3.2.2%2B-green.svg)](https://www.freepascal.org/)
[![OpenAPI](https://img.shields.io/badge/OpenAPI-3.0.3-brightgreen.svg)](https://swagger.io/specification/)
[![RFC 7807](https://img.shields.io/badge/RFC-7807%20Compliant-orange.svg)](https://datatracker.ietf.org/doc/html/rfc7807)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Zenith** é um framework web moderno, elegante e de alta performance para **Free Pascal / Lazarus (FPC)**. Projetado para proporcionar uma experiência de desenvolvimento ágil e contemporânea, o Zenith reúne documentação interativa automática **OpenAPI / Swagger UI**, modelagem e validação com **Micro-ORM Multi-SGDB**, autenticação **JWT / Basic**, logging estruturado e tratamento padronizado de erros no padrão **RFC 7807**.

---

## 🚀 Principais Recursos

- ⚡ **Alta Performance & Concorrência**: Servidor HTTP embutido com suporte nativo a multi-threading (`fphttpapp`) e modo FastCGI (`fpfcgi`).
- 📖 **Documentação Swagger UI Integrada**: Integração nativa com o [Swagger4Laz](src/swagger4laz), servindo documentação interativa OpenAPI 3.0 em `/docs`.
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
│   ├── Zenith.Core.pas        # Pipeline de tratamento de exceções e middlewares
│   ├── Zenith.Consts.pas      # Constantes HTTP, status codes e MIME types
│   ├── Zenith.Types.pas       # Tipos base e formatador RFC 7807 (TJsonError)
│   ├── Zenith.Exceptions.pas  # Hierarquia de exceções semânticas HTTP
│   ├── Zenith.Auth.JWT.pas    # Criação e validação de tokens JWT
│   ├── Zenith.Auth.Basic.pas  # Autenticação HTTP Basic
│   ├── Zenith.Hash.pas        # Funções criptográficas (HMAC-SHA256, SHA256, MD5)
│   ├── Zenith.Env.pas         # Leitor de variáveis (.env / OS environment)
│   ├── Zenith.Log.pas         # Logger thread-safe em arquivo e console
│   ├── swagger4laz/           # Submódulo: Swagger UI e OpenAPI 3.0
│   └── deltamodel/            # Submódulo: Modelagem, Validação e Micro-ORM
└── demo/
    └── 00-todolist/           # Exemplo prático de API REST completa
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
    User.id.Value := UserId;
    User.name.Value := 'Carlos Eduardo';
    User.email.Value := 'carlos@empresa.com';

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

    NewUser.id.Value := 101;
    NewUser.name.Value := InputData.name.Value;
    NewUser.email.Value := InputData.email.Value;

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
  // Documentação e vinculação GET /users/:id
  Router
    .Get('/users/:id', @GetUser)
    .SetSummary('Buscar usuário por ID')
    .AddTags('Usuários')
    .AddPathParam('id', True, 'integer', '1', 'ID do usuário')
    .AddResponse(StatusOK, 'Usuário localizado', TUserResponse.SwaggerSchema())
    .AddResponse(StatusBadRequest, 'Requisição inválida')
    .AddResponse(StatusNotFound, 'Usuário não encontrado');

  // Documentação e vinculação POST /users
  Router
    .Post('/users', @CreateUser)
    .SetSummary('Cadastrar novo usuário')
    .AddTags('Usuários')
    .SetBodyContent(TUserInsert.SwaggerSchema(), True, ApplicationJson, 'Dados de cadastro')
    .AddResponse(StatusCreated, 'Usuário criado com sucesso', TUserResponse.SwaggerSchema())
    .AddResponse(StatusBadRequest, 'Falha na validação dos campos');
end;

initialization
  TUserRouter.Register;
end.
```

---

## 🛡️ Tratamento de Exceções & RFC 7807

Quando uma exceção semântica é lançada em qualquer rota, o Zenith intercepta o erro automaticamente e responde com uma estrutura padronizada **RFC 7807**:

```json
{
  "type": "VALIDATION_ERROR",
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
ZENITH_LOGFILE=zenith.log
ZENITH_JWT_SECRET=sua-chave-secreta-super-segura-aqui
```

As variáveis são consumidas automaticamente pelo framework ou diretamente no seu código:

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

Consulte o projeto completo em [`demo/00-todolist`](demo/00-todolist) para ver a integração prática entre:
- `Zenith.App` e `SwaggerRouter`
- `DeltaModel` e `TDeltaModelList`
- Rotas REST com paginação, criação e busca por ID.

---

## 📄 Licença

Distribuído sob a licença MIT. Consulte `LICENSE` para detalhes.
