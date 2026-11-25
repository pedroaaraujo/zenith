{
    Zenith Framework - Testes HTTP Ponta a Ponta (E2E)
    Sobe o servidor HTTP real (ZenithApp + HTTPRouter + TZenithCrud<T> + SQLite)
    e executa chamadas reais via TFPHTTPClient:
    - CRUD completo (POST 201, GET list, GET :id, PUT :id preservando PK, DELETE 204)
    - Validação de sort (400 em SQL injection), RFC 9457 em 404
    - CORS opt-in desligado por padrão
    - Compressão GZIP respeitando tamanho mínimo e Accept-Encoding
    - Rota protegida por JWT (401 sem token, 200 com Bearer válido)
    - Swagger UI (/docs) pré-comprimido
}

{$mode objfpc}{$H+}

unit test_zenith_e2e;

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fphttpclient, fpjson, jsonparser,
  sqlite3conn, HTTPDefs, httproute, fphttpapp,
  DeltaModel, DeltaModel.Fields, DeltaModel.ORM.Interfaces,
  DeltaModel.ORM.Registry, DeltaModel.ORM.Dialects, DeltaModel.ORM.Driver.SQLDB,
  DeltaModel.ORM.Pool, DeltaModel.ORM.Schema,
  Zenith.App, Zenith.Crud, Zenith.Auth.JWT, Zenith.Security, Zenith.Gzip, Zenith.Exceptions;

type
  TE2EItem = class(TDeltaModel)
  private
    FId: TDFIntRequired;
    FName: TDFStringRequired;
    FNotes: TDFStringNull;
  published
    property id: TDFIntRequired read FId write FId;
    property name: TDFStringRequired read FName write FName;
    property notes: TDFStringNull read FNotes write FNotes;
  public
    procedure AfterConstruction; override;
    class procedure ConfigureSchema(ASchema: TDeltaModelSchema); override;
  end;

  { TTestZenithE2E }
  TTestZenithE2E = class(TTestCase)
  published
    procedure TestCrudAndSecurityEndToEnd;
    procedure TestProtectedJwtAndSwaggerGzip;
  end;

implementation

type
  TAppServerThread = class(TThread)
  public
    procedure Execute; override;
  end;

var
  GDbPath: string = '';
  GPool: TDeltaConnectionPool = nil;
  GCrud: specialize TZenithCrud<TE2EItem> = nil;
  GPort: Word = 0;
  GServerThread: TAppServerThread = nil;

procedure TE2EItem.AfterConstruction;
begin
  inherited AfterConstruction;
  TableName := 'e2e_items';
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
  name.DBOptions := [dboInsert, dboUpdate];
  notes.DBOptions := [dboInsert, dboUpdate];
end;

class procedure TE2EItem.ConfigureSchema(ASchema: TDeltaModelSchema);
begin
  inherited ConfigureSchema(ASchema);
  ASchema.Table('e2e_items');
  ASchema.Field('id').AsPK.AutoInc;
  ASchema.Field('name').MinLength(2);
end;

procedure ProtectedEchoHandler(ARequest: TRequest; AResponse: TResponse);
var
  Sec: TZSecurityContext;
begin
  Sec := GetZenithSecurityResolver.Resolve(ARequest);
  try
    if not Sec.IsAuthenticated then
      raise EUnauthorized.Create('Bearer required');
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := '{"sub":"' + Sec.Subject + '"}';
  finally
    Sec.FreeInternalObjects;
  end;
end;

procedure LargeJsonHandler(ARequest: TRequest; AResponse: TResponse);
begin
  AResponse.Code := 200;
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.Content := '{"payload":"' + StringOfChar('x', 1024) + '"}';
end;

procedure TAppServerThread.Execute;
begin
  try
    Application.Initialize;
    Application.Run;
  except
  end;
end;

procedure EnsureE2EServer;
var
  DbUrl: string;
  Conn: IDeltaConnection;
  Schema: TDeltaORMSchema;
begin
  if GServerThread <> nil then
    Exit;

  GDbPath := GetTempFileName('', 'ze2e') + '.sqlite';
  DbUrl := 'sqlite://' + ExpandFileName(GDbPath);

  Conn := TDeltaORM.Connect(DbUrl);
  try
    Schema := TDeltaORMSchema.Create(Conn);
    try
      Schema.RegisterModel(TE2EItem);
      Schema.PrepareDB(True);
    finally
      Schema.Free;
    end;
  finally
    Conn.Disconnect;
    Conn := nil;
  end;

  GPool := TDeltaConnectionPool.Create(DbUrl, 1, 5);
  GCrud := specialize TZenithCrud<TE2EItem>.Create('/e2e/items', GPool);
  GCrud.WithTag('E2E').Register;

  HTTPRouter.RegisterRoute('/e2e/protected', rmGet, @ProtectedEchoHandler);
  HTTPRouter.RegisterRoute('/e2e/large', rmGet, @LargeJsonHandler);

  GPort := 20000 + Random(4000);
  ZenithApp
    .SetTitle('Zenith E2E')
    .SetPort(GPort)
    .SetThreaded(True)
    .SetSecurityResolver(TZJWTBearerResolver.Create);
  Application.AcceptIdleTimeout := 50;

  GServerThread := TAppServerThread.Create(True);
  GServerThread.FreeOnTerminate := False;
  GServerThread.Start;
  Sleep(350);
end;

function BaseUrl: string;
begin
  EnsureE2EServer;
  Result := 'http://127.0.0.1:' + IntToStr(GPort);
end;

procedure TTestZenithE2E.TestCrudAndSecurityEndToEnd;
var
  Client: TFPHTTPClient;
  Body, CreatedIdStr: string;
  Json: TJSONData;
  CreatedId: Int64;
begin
  Client := TFPHTTPClient.Create(nil);
  try
    Client.AllowRedirect := False;

    { 1. POST /e2e/items -> 201 + commit persistido }
    Client.RequestHeaders.Clear;
    Client.AddHeader('Content-Type', 'application/json');
    Client.AddHeader('Origin', 'https://evil.example');
    Client.RequestBody := TStringStream.Create('{"name":"Item Alpha","notes":"ok"}');
    try
      Body := Client.Post(BaseUrl + '/e2e/items');
    finally
      Client.RequestBody.Free;
      Client.RequestBody := nil;
    end;
    AssertEquals(201, Client.ResponseStatusCode);
    AssertEquals('CORS desligado por padrão não deve emitir header',
      '', Client.ResponseHeaders.Values['Access-Control-Allow-Origin']);

    Json := GetJSON(Body);
    try
      CreatedId := TJSONObject(Json).Int64s['id'];
      AssertTrue(CreatedId > 0);
      AssertEquals('Item Alpha', TJSONObject(Json).Strings['name']);
    finally
      Json.Free;
    end;
    CreatedIdStr := IntToStr(CreatedId);

    { 2. GET /e2e/items -> 200 com item persistido }
    Body := Client.Get(BaseUrl + '/e2e/items?sort=-id');
    AssertEquals(200, Client.ResponseStatusCode);
    AssertTrue(Pos('Item Alpha', Body) > 0);

    { 3. GET /e2e/items?sort=INVALID -> 400 RFC 9457 }
    try
      Client.Get(BaseUrl + '/e2e/items?sort=(SELECT%201)');
    except
    end;
    AssertEquals(400, Client.ResponseStatusCode);

    { 4. PUT /e2e/items/:id tentando trocar id no corpo -> PK preservado }
    Client.RequestHeaders.Clear;
    Client.AddHeader('Content-Type', 'application/json');
    Client.RequestBody := TStringStream.Create('{"id":9999,"name":"Item Beta"}');
    try
      Body := Client.Put(BaseUrl + '/e2e/items/' + CreatedIdStr);
    finally
      Client.RequestBody.Free;
      Client.RequestBody := nil;
    end;
    AssertEquals(200, Client.ResponseStatusCode);
    Json := GetJSON(Body);
    try
      AssertEquals(CreatedId, TJSONObject(Json).Int64s['id']);
      AssertEquals('Item Beta', TJSONObject(Json).Strings['name']);
    finally
      Json.Free;
    end;

    { 5. DELETE /e2e/items/:id -> 204 e GET seguinte -> 404 problem+json }
    Client.Delete(BaseUrl + '/e2e/items/' + CreatedIdStr);
    AssertEquals(204, Client.ResponseStatusCode);

    try
      Body := Client.Get(BaseUrl + '/e2e/items/' + CreatedIdStr);
    except
    end;
    AssertEquals(404, Client.ResponseStatusCode);
  finally
    Client.Free;
  end;
end;

procedure TTestZenithE2E.TestProtectedJwtAndSwaggerGzip;
var
  Client: TFPHTTPClient;
  P: TPayLoad;
  Token, Body, Decompressed, URLBase: string;
begin
  URLBase := BaseUrl;
  TJWT.SetSecret('0123456789abcdef0123456789abcdef');
  Client := TFPHTTPClient.Create(nil);
  try
    { Sem token -> 401 }
    try
      Client.Get(URLBase + '/e2e/protected');
    except
      on E: EHTTPClient do ;
    end;
    AssertEquals(401, Client.ResponseStatusCode);

    { Com JWT válido -> 200 }
    P := TPayLoad.Create;
    try
      P.CustomValues['sub'] := 'alice';
      Token := TJWT.GenerateToken(P);
    finally
      P.Free;
    end;

    Client.AddHeader('Authorization', 'Bearer ' + Token);
    Body := Client.Get(BaseUrl + '/e2e/protected');
    AssertEquals(200, Client.ResponseStatusCode);
    AssertTrue(Pos('"alice"', Body) > 0);

    { GZIP em payload >= 512 bytes }
    Client.RequestHeaders.Clear;
    Client.AddHeader('Accept-Encoding', 'gzip');
    Body := Client.Get(BaseUrl + '/e2e/large');
    AssertEquals(200, Client.ResponseStatusCode);
    AssertEquals('gzip', LowerCase(Trim(Client.ResponseHeaders.Values['Content-Encoding'])));
    Decompressed := string(GZipDecompress(RawByteString(Body)));
    AssertTrue(Pos('"payload"', Decompressed) > 0);

    { Swagger UI pré-comprimido }
    Client.RequestHeaders.Clear;
    Client.AddHeader('Accept-Encoding', 'gzip');
    Body := Client.Get(BaseUrl + '/docs');
    AssertEquals(200, Client.ResponseStatusCode);
    AssertEquals('gzip', LowerCase(Trim(Client.ResponseHeaders.Values['Content-Encoding'])));
    Decompressed := string(GZipDecompress(RawByteString(Body)));
    AssertTrue(Pos('SwaggerUIBundle', Decompressed) > 0);
  finally
    TJWT.SetSecret('');
    Client.Free;
  end;
end;

initialization
  Randomize;
  RegisterTest(TTestZenithE2E);

finalization
  if GServerThread <> nil then
  begin
    Application.Terminate;
    GServerThread.WaitFor;
    GServerThread.Free;
  end;
  FreeAndNil(GCrud);
  FreeAndNil(GPool);
  if (GDbPath <> '') and FileExists(GDbPath) then
    DeleteFile(GDbPath);

end.
