{
    Zenith Framework - Testes de segurança e configuração
    - TBasicAuthorization (RFC 7617)
    - Zenith.Env: cache e parser de .env, GetEnvBool
    - TJWT: iss/aud configuráveis e expiração tolerante
    - ZenithSanitizeSort / ZenithCrudMaxPageSize (ORDER BY vindo do cliente)
    - TZWebSocketHandshake.IsOriginAllowed (CSWSH)
    - Leitura de requisição no TFPHttpServer: 413, 431 e corpo além do Content-Length
}

{$mode objfpc}{$H+}

unit test_zenith_security;

interface

uses
  Classes, SysUtils, fpcunit, testregistry, base64, httpdefs, ssockets,
  fphttpserver,
  DeltaModel, DeltaModel.Fields, DeltaModel.Metadata,
  Zenith.Env, Zenith.Exceptions, Zenith.Auth.Basic, Zenith.Auth.JWT,
  Zenith.Crud, Zenith.WebSocket;

type
  TSortProbe = class(TDeltaModel)
  private
    FId: TDFIntRequired;
    FDescription: TDFStringRequired;
  published
    property id: TDFIntRequired read FId write FId;
    property description: TDFStringRequired read FDescription write FDescription;
  end;

  { TTestZenithSecurity }
  TTestZenithSecurity = class(TTestCase)
  private
    procedure DoBasicNoColon;
    procedure DoBasicBadBase64;
    procedure DoSortInjection;
    procedure DoSortSubquery;
    procedure DoSortBadDirection;
    procedure DoSortUnknownField;
  published
    procedure TestBasicPasswordWithColon;
    procedure TestBasicInvalidCredentialsAreUnauthorized;
    procedure TestEnvFileParserAndBool;
    procedure TestJwtIssuerAndAudience;
    procedure TestJwtInvalidExpirationFallsBack;
    procedure TestSortWhitelist;
    procedure TestSortRejectsInjection;
    procedure TestMaxPageSize;
    procedure TestWebSocketOrigin;
    procedure TestServerRejectsOversizedBody;
    procedure TestServerRejectsOversizedHeaders;
    procedure TestServerBodyLargerThanContentLength;
  end;

implementation

{ Servidor HTTP mínimo em thread para testes de leitura de requisição }
type
  TEchoServer = class(TFPHttpServer)
  public
    procedure HandleRequest(var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse); override;
  end;

  TServerThread = class(TThread)
  public
    Server: TEchoServer;
    procedure Execute; override;
  end;

procedure TEchoServer.HandleRequest(var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
begin
  AResponse.Code := 200;
  AResponse.Content := 'len=' + IntToStr(Length(ARequest.Content));
end;

procedure TServerThread.Execute;
begin
  try
    Server.Active := True;
  except
  end;
end;

var
  GPort: Word = 0;
  GServerThread: TServerThread = nil;

procedure EnsureServer;
begin
  if GServerThread <> nil then
    Exit;
  GPort := 18000 + Random(2000);
  GServerThread := TServerThread.Create(True);
  GServerThread.FreeOnTerminate := False;
  GServerThread.Server := TEchoServer.Create(nil);
  GServerThread.Server.Port := GPort;
  GServerThread.Server.Threaded := True;
  GServerThread.Server.MaxRequestBodySize := 1024;
  GServerThread.Server.MaxHeaderSize := 2048;
  GServerThread.Server.ReadTimeout := 2000;
  GServerThread.Server.AcceptIdleTimeout := 50;
  GServerThread.Start;
  Sleep(300);
end;

function RawExchange(const ARequest: AnsiString): AnsiString;
var
  Sock: TInetSocket;
  Buf: array[0..4095] of AnsiChar;
  R: Integer;
begin
  Result := '';
  EnsureServer;
  Sock := TInetSocket.Create('127.0.0.1', GPort);
  try
    Sock.IOTimeout := 3000;
    if ARequest <> '' then
      Sock.WriteBuffer(ARequest[1], Length(ARequest));
    repeat
      try
        R := Sock.Read(Buf, SizeOf(Buf));
      except
        R := 0;
      end;
      if R > 0 then
        Result := Result + Copy(Buf, 0, R);
    until R <= 0;
  finally
    Sock.Free;
  end;
end;

{ Basic }

procedure TTestZenithSecurity.TestBasicPasswordWithColon;
var
  B: TBasicAuthorization;
begin
  B := TBasicAuthorization.Create('Basic ' + EncodeStringBase64('alice:pa:ss:wd'));
  try
    AssertEquals('alice', B.User);
    AssertEquals('pa:ss:wd', B.Password);
  finally
    B.Free;
  end;
end;

procedure TTestZenithSecurity.DoBasicNoColon;
begin
  TBasicAuthorization.Create('Basic ' + EncodeStringBase64('semseparador')).Free;
end;

procedure TTestZenithSecurity.DoBasicBadBase64;
begin
  TBasicAuthorization.Create('Basic !!!@@@').Free;
end;

procedure TTestZenithSecurity.TestBasicInvalidCredentialsAreUnauthorized;
begin
  AssertException(EUnauthorized, @DoBasicNoColon);
  AssertException(EUnauthorized, @DoBasicBadBase64);
end;

{ Env }

procedure TTestZenithSecurity.TestEnvFileParserAndBool;
var
  F: string;
  SL: TStringList;
begin
  F := GetTempFileName('', 'zenv');
  SL := TStringList.Create;
  try
    SL.Add('# comentário');
    SL.Add('');
    SL.Add('export ZT_EXPORTED=abc');
    SL.Add('ZT_QUOTED="valor com # e espaço"');
    SL.Add('ZT_SINGLE=''x=y''');
    SL.Add('ZT_INLINE=42 # comentário inline');
    SL.Add('ZT_FLAG_S=S');
    SL.Add('ZT_FLAG_TRUE=true');
    SL.Add('ZT_FLAG_OFF=off');
    SL.SaveToFile(F);
  finally
    SL.Free;
  end;
  try
    ReloadEnvFile(F);
    AssertEquals('abc', GetEnvVariable('ZT_EXPORTED'));
    AssertEquals('valor com # e espaço', GetEnvVariable('ZT_QUOTED'));
    AssertEquals('x=y', GetEnvVariable('ZT_SINGLE'));
    AssertEquals('42', GetEnvVariable('ZT_INLINE'));
    AssertEquals('padrao', GetEnvVariable('ZT_MISSING', 'padrao'));
    AssertTrue(GetEnvBool('ZT_FLAG_S'));
    AssertTrue(GetEnvBool('ZT_FLAG_TRUE'));
    AssertFalse(GetEnvBool('ZT_FLAG_OFF', True));
    AssertTrue(GetEnvBool('ZT_MISSING', True));
  finally
    DeleteFile(F);
    ReloadEnvFile('');
  end;
end;

{ JWT }

procedure TTestZenithSecurity.TestJwtIssuerAndAudience;
var
  P, V: TPayLoad;
  Token: string;
  Raised: Boolean;
begin
  TJWT.SetSecret('0123456789abcdef0123456789abcdef');
  SetEnvVariable('ZENITH_JWT_ISSUER', 'zenith-test');
  SetEnvVariable('ZENITH_JWT_AUDIENCE', 'api');
  try
    P := TPayLoad.Create;
    try
      P.CustomValues['sub'] := 'u1';
      Token := TJWT.GenerateToken(P);
    finally
      P.Free;
    end;
    V := TJWT.ValidadeToken(Token);
    try
      AssertEquals('u1', string(V.CustomValues['sub']));
      AssertEquals('zenith-test', string(V.CustomValues['iss']));
    finally
      V.Free;
    end;

    SetEnvVariable('ZENITH_JWT_ISSUER', 'outro-emissor');
    Raised := False;
    try
      TJWT.ValidadeToken(Token).Free;
    except
      on E: EUnauthorized do Raised := True;
    end;
    AssertTrue('iss divergente deve ser rejeitado', Raised);

    SetEnvVariable('ZENITH_JWT_ISSUER', 'zenith-test');
    SetEnvVariable('ZENITH_JWT_AUDIENCE', 'outra-api');
    Raised := False;
    try
      TJWT.ValidadeToken(Token).Free;
    except
      on E: EUnauthorized do Raised := True;
    end;
    AssertTrue('aud divergente deve ser rejeitado', Raised);
  finally
    SetEnvVariable('ZENITH_JWT_ISSUER', '');
    SetEnvVariable('ZENITH_JWT_AUDIENCE', '');
  end;
end;

procedure TTestZenithSecurity.TestJwtInvalidExpirationFallsBack;
var
  P: TPayLoad;
begin
  SetEnvVariable('ZENITH_JWT_EXPIRATION', 'abc');
  P := TPayLoad.Create;
  try
    AssertEquals(Int64(1440 * 60), P.exp - P.iat);
  finally
    P.Free;
    SetEnvVariable('ZENITH_JWT_EXPIRATION', '');
  end;
end;

{ Sort }

function SortMeta: TModelMetadata;
begin
  Result := TRTTICache.GetModelMetadata(TSortProbe);
end;

procedure TTestZenithSecurity.TestSortWhitelist;
begin
  AssertEquals('', ZenithSanitizeSort('', SortMeta));
  AssertEquals('id ASC', ZenithSanitizeSort('id', SortMeta));
  AssertEquals('id DESC, description ASC', ZenithSanitizeSort('-id, description', SortMeta));
  AssertEquals('description DESC', ZenithSanitizeSort('description desc', SortMeta));
  AssertEquals('id ASC', ZenithSanitizeSort('ID:asc', SortMeta));
end;

procedure TTestZenithSecurity.DoSortInjection;
begin
  ZenithSanitizeSort('id;DROP TABLE x', SortMeta);
end;

procedure TTestZenithSecurity.DoSortSubquery;
begin
  ZenithSanitizeSort('(CASE WHEN (SELECT 1)=1 THEN id ELSE description END)', SortMeta);
end;

procedure TTestZenithSecurity.DoSortBadDirection;
begin
  ZenithSanitizeSort('id desc, 1', SortMeta);
end;

procedure TTestZenithSecurity.DoSortUnknownField;
begin
  ZenithSanitizeSort('password', SortMeta);
end;

procedure TTestZenithSecurity.TestSortRejectsInjection;
begin
  AssertException(EBadRequest, @DoSortInjection);
  AssertException(EBadRequest, @DoSortSubquery);
  AssertException(EBadRequest, @DoSortBadDirection);
  AssertException(EBadRequest, @DoSortUnknownField);
end;

procedure TTestZenithSecurity.TestMaxPageSize;
begin
  AssertEquals(ZENITH_CRUD_DEFAULT_MAX_PAGE_SIZE, ZenithCrudMaxPageSize);
  SetEnvVariable('ZENITH_CRUD_MAX_PAGE_SIZE', '250');
  try
    AssertEquals(250, ZenithCrudMaxPageSize);
  finally
    SetEnvVariable('ZENITH_CRUD_MAX_PAGE_SIZE', '');
  end;
end;

{ WebSocket }

procedure TTestZenithSecurity.TestWebSocketOrigin;
var
  Req: TRequest;
begin
  Req := TRequest.Create;
  try
    Req.Host := 'api.local:8080';
    AssertTrue('sem Origin (cliente nativo)', TZWebSocketHandshake.IsOriginAllowed(Req));
    Req.SetCustomHeader('Origin', 'http://api.local:8080');
    AssertTrue('mesma origem', TZWebSocketHandshake.IsOriginAllowed(Req));
    Req.SetCustomHeader('Origin', 'https://evil.example');
    AssertFalse('origem cruzada', TZWebSocketHandshake.IsOriginAllowed(Req));
    SetEnvVariable('ZENITH_WS_ALLOWED_ORIGINS', 'https://app.example, https://evil.example');
    AssertTrue('origem em allowlist', TZWebSocketHandshake.IsOriginAllowed(Req));
  finally
    SetEnvVariable('ZENITH_WS_ALLOWED_ORIGINS', '');
    Req.Free;
  end;
end;

{ Servidor HTTP }

procedure TTestZenithSecurity.TestServerRejectsOversizedBody;
var
  R: AnsiString;
begin
  R := RawExchange('POST /x HTTP/1.1'#13#10'Host: t'#13#10 +
    'Content-Length: 2000000000'#13#10#13#10);
  AssertTrue('esperado 413, obtido: ' + Copy(R, 1, 40), Pos('HTTP/1.1 413', R) = 1);
end;

procedure TTestZenithSecurity.TestServerRejectsOversizedHeaders;
var
  R: AnsiString;
begin
  R := RawExchange('GET /x HTTP/1.1'#13#10'Host: t'#13#10 +
    'X-Big: ' + StringOfChar('a', 4096) + #13#10#13#10);
  AssertTrue('esperado 431, obtido: ' + Copy(R, 1, 40), Pos('HTTP/1.1 431', R) = 1);
end;

procedure TTestZenithSecurity.TestServerBodyLargerThanContentLength;
var
  R: AnsiString;
begin
  { O cliente envia 600 bytes declarando 10: só 10 podem virar o corpo. }
  R := RawExchange('POST /x HTTP/1.1'#13#10'Host: t'#13#10 +
    'Content-Length: 10'#13#10#13#10 + StringOfChar('b', 600));
  AssertTrue('resposta 200 esperada, obtido: ' + Copy(R, 1, 40), Pos('HTTP/1.1 200', R) = 1);
  AssertTrue('corpo limitado ao Content-Length', Pos('len=10', R) > 0);
end;

initialization
  Randomize;
  RegisterTest(TTestZenithSecurity);

finalization
  if GServerThread <> nil then
  begin
    GServerThread.Server.Active := False;
    GServerThread.WaitFor;
    GServerThread.Server.Free;
    GServerThread.Free;
  end;

end.
