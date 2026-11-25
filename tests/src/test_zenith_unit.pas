{
    Zenith Framework - Suíte de Testes Unitários Consolidada
    - Zenith.Hash (SHA-256 NIST / HMAC-SHA256 RFC 4231 via fpsha256)
    - Zenith.Auth.JWT (ValidateToken, cache de segredos, rotação e aliases deprecated)
    - httproute (Radix tree, prioridade Static > Param > Wildcard, rmPatch, 405)
    - Zenith.Idempotency (TZenithMemoryIdempotencyStore, conflito, mismatch, LRU)
    - Zenith.Preconditions (RFC 7232 If-Match, If-None-Match, HTTP-date)
    - Zenith.MergePatch (RFC 7396 media type, ApplyToModel, proteção de PK)
    - Zenith.WebSocket (handshake RFC 6455, ComputeAcceptKey, EncodeFrame/DecodeFrame)
    - Zenith.Gzip (round-trip, ShouldGzipCompress com tamanho mínimo e MIME)
    - Zenith.Log (formato JSON estruturado e escrita assíncrona com Flush)
}

{$mode objfpc}{$H+}

unit test_zenith_unit;

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
  HTTPDefs, httproute,
  DeltaModel, DeltaModel.Fields,
  Zenith.Hash, Zenith.Env, Zenith.Exceptions, Zenith.Auth.JWT,
  Zenith.Idempotency, Zenith.Preconditions, Zenith.MergePatch,
  Zenith.WebSocket, Zenith.Gzip, Zenith.Log;

type
  TPatchProbe = class(TDeltaModel)
  private
    FId: TDFIntRequired;
    FTitle: TDFStringRequired;
    FNotes: TDFStringNull;
  published
    property id: TDFIntRequired read FId write FId;
    property title: TDFStringRequired read FTitle write FTitle;
    property notes: TDFStringNull read FNotes write FNotes;
  public
    procedure AfterConstruction; override;
  end;

  { TTestZenithUnit }
  TTestZenithUnit = class(TTestCase)
  private
    procedure DummyHandler(ARequest: TRequest; AResponse: TResponse);
    procedure DoRequireMergePatchInvalid;
  published
    procedure TestHashSHA256AndHMACVectors;
    procedure TestJwtSecretCacheAndDeprecatedAlias;
    procedure TestRadixRouterPriorityAndMethods;
    procedure TestIdempotencyStoreLifecycleAndLRU;
    procedure TestPreconditionsRFC7232;
    procedure TestMergePatchModelAndMediaType;
    procedure TestWebSocketHandshakeAndFrames;
    procedure TestGzipThresholdAndMimeFilter;
    procedure TestLoggerStructuredJsonAndAsyncFile;
  end;

implementation

procedure TPatchProbe.AfterConstruction;
begin
  inherited AfterConstruction;
  TableName := 'patch_probe';
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
  title.DBOptions := [dboInsert, dboUpdate];
  notes.DBOptions := [dboInsert, dboUpdate];
end;

procedure TTestZenithUnit.DummyHandler(ARequest: TRequest; AResponse: TResponse);
begin
  AResponse.Code := 200;
end;

procedure TTestZenithUnit.TestHashSHA256AndHMACVectors;
var
  Key, Data, DigestHex: string;
  RawDigest: string;
  I: Integer;
begin
  { NIST FIPS 180-4 / RFC 6234 }
  AssertEquals('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    SHA256Hex(''));
  AssertEquals('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    SHA256Hex('abc'));

  { RFC 4231 Test Case 2: key = "Jefe", data = "what do ya want for nothing?" }
  Key := 'Jefe';
  Data := 'what do ya want for nothing?';
  RawDigest := HMACSHA256(Key, Data);
  AssertEquals(32, Length(RawDigest));
  DigestHex := '';
  for I := 1 to Length(RawDigest) do
    DigestHex := DigestHex + LowerCase(IntToHex(Ord(RawDigest[I]), 2));
  AssertEquals('5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843', DigestHex);

  { Empty data must still produce valid 32-byte HMAC }
  AssertEquals(32, Length(HMACSHA256('secret-key', '')));
  AssertEquals('', HMACSHA256('', 'data'));
end;

procedure TTestZenithUnit.TestJwtSecretCacheAndDeprecatedAlias;
var
  P, V1, V2: TPayLoad;
  Token1, Token2: string;
  Raised: Boolean;
begin
  TJWT.SetSecret('');
  SetEnvVariable('ZENITH_JWT_SECRET', '0123456789abcdef0123456789abcdef');
  try
    P := TPayLoad.Create;
    try
      P.CustomValues['sub'] := 'user-1';
      Token1 := TJWT.GenerateToken(P);
    finally
      P.Free;
    end;

    V1 := TJWT.ValidateToken(Token1);
    try
      AssertEquals('user-1', string(V1.CustomValues['sub']));
    finally
      V1.Free;
    end;

    { Rotaciona segredo via env e verifica que o cache invalida imediatamente }
    SetEnvVariable('ZENITH_JWT_SECRET', 'fedcba9876543210fedcba9876543210,0123456789abcdef0123456789abcdef');
    P := TPayLoad.Create;
    try
      P.CustomValues['sub'] := 'user-2';
      Token2 := TJWT.GenerateToken(P);
    finally
      P.Free;
    end;

    { Token antigo ainda valida pelo segredo rotacionado; alias deprecated funciona }
    {$WARNINGS OFF}
    V1 := TJWT.ValidadeToken(Token1);
    {$WARNINGS ON}
    try
      AssertEquals('user-1', string(V1.CustomValues['sub']));
    finally
      V1.Free;
    end;

    V2 := TJWT.ValidateToken(Token2);
    try
      AssertEquals('user-2', string(V2.CustomValues['sub']));
    finally
      V2.Free;
    end;

    { Remove segredo antigo da env: cache deve rejeitar Token1 }
    SetEnvVariable('ZENITH_JWT_SECRET', 'fedcba9876543210fedcba9876543210');
    Raised := False;
    try
      TJWT.ValidateToken(Token1).Free;
    except
      on E: EUnauthorized do Raised := True;
    end;
    AssertTrue('Segredo removido da env deve invalidar cache imediatamente', Raised);
  finally
    SetEnvVariable('ZENITH_JWT_SECRET', '');
    TJWT.SetSecret('');
  end;
end;

procedure TTestZenithUnit.TestRadixRouterPriorityAndMethods;
var
  R: THTTPRouter;
  Params: TStringList;
  Mismatch: Boolean;
  Matched, RWild, RParam, RStatic, RPatch: THTTPRoute;
begin
  R := THTTPRouter.Create(nil);
  Params := TStringList.Create;
  try
    { Registra na ordem inversa de prioridade: wildcard -> param -> static }
    RWild := R.RegisterRoute('/users/*rest', rmGet, @DummyHandler);
    RParam := R.RegisterRoute('/users/:id', rmGet, @DummyHandler);
    RStatic := R.RegisterRoute('/users/me', rmGet, @DummyHandler);
    RPatch := R.RegisterRoute('/users/:id', rmPatch, @DummyHandler);

    Matched := R.FindHTTPRoute('/users/me', rmGet, Params, Mismatch);
    AssertSame(RStatic, Matched);
    AssertFalse(Mismatch);

    Params.Clear;
    Matched := R.FindHTTPRoute('/users/42', rmGet, Params, Mismatch);
    AssertSame(RParam, Matched);
    AssertEquals('42', Params.Values['id']);

    Params.Clear;
    Matched := R.FindHTTPRoute('/users/42', rmPatch, Params, Mismatch);
    AssertSame(RPatch, Matched);
    AssertEquals('42', Params.Values['id']);

    Params.Clear;
    Matched := R.FindHTTPRoute('/users/a/b/c', rmGet, Params, Mismatch);
    AssertSame(RWild, Matched);

    Params.Clear;
    Matched := R.FindHTTPRoute('/users/42', rmDelete, Params, Mismatch);
    AssertNull(Matched);
    AssertTrue('Método não registrado deve sinalizar MethodMismatch', Mismatch);
  finally
    Params.Free;
    R.Free;
  end;
end;

procedure TTestZenithUnit.TestIdempotencyStoreLifecycleAndLRU;
var
  Store: IZenithIdempotencyStore;
  Existing: TIdempotencyRecord;
  Conflict, Mismatch: Boolean;
  Stats: TIdempotencyStoreStats;
begin
  Store := TZenithMemoryIdempotencyStore.Create(2, 60);

  AssertTrue(Store.TryAcquire('k1', 'hash-a', Existing, Conflict, Mismatch));
  AssertFalse(Conflict);
  AssertFalse(Mismatch);

  { Requisição concorrente com mesma chave ainda em andamento -> Conflict }
  AssertFalse(Store.TryAcquire('k1', 'hash-a', Existing, Conflict, Mismatch));
  AssertTrue(Conflict);
  AssertFalse(Mismatch);

  Store.Complete('k1', 201, 'application/json', '{"id":1}');

  { Replay com mesmo hash -> hit }
  AssertFalse(Store.TryAcquire('k1', 'hash-a', Existing, Conflict, Mismatch));
  AssertFalse(Conflict);
  AssertFalse(Mismatch);
  AssertEquals(201, Existing.ResponseCode);
  AssertEquals('{"id":1}', string(Existing.ResponseBody));

  { Mesma chave com payload diferente -> Mismatch (422) }
  AssertFalse(Store.TryAcquire('k1', 'hash-b', Existing, Conflict, Mismatch));
  AssertTrue(Mismatch);

  { Inserir k2 e k3 com capacidade=2 deve evictar o LRU (k1 ou k2) mantendo Count=2 }
  AssertTrue(Store.TryAcquire('k2', 'h2', Existing, Conflict, Mismatch));
  Store.Complete('k2', 200, 'text/plain', 'ok');
  { Acessa k1 novamente para torná-lo MRU; k2 vira LRU }
  AssertFalse(Store.TryAcquire('k1', 'hash-a', Existing, Conflict, Mismatch));
  AssertTrue(Store.TryAcquire('k3', 'h3', Existing, Conflict, Mismatch));
  Store.Complete('k3', 200, 'text/plain', 'ok3');

  AssertEquals(2, Store.Count);
  AssertTrue('k1 deve permanecer no cache LRU', Store.Get('k1', Existing));
  AssertFalse('k2 deve ter sido evictado como LRU', Store.Get('k2', Existing));
  Stats := Store.GetStats;
  AssertTrue(Stats.Evictions >= 1);
end;

procedure TTestZenithUnit.TestPreconditionsRFC7232;
var
  Eval: TPreconditionEvaluation;
  DT, ParsedDT: TDateTime;
  HttpDate: string;
begin
  DT := EncodeDate(2026, 5, 10) + EncodeTime(14, 30, 0, 0);
  HttpDate := FormatHTTPDate(DT);
  AssertTrue(TryParseHTTPDate(HttpDate, ParsedDT));
  AssertEquals(TruncateToHTTPSeconds(DT), TruncateToHTTPSeconds(ParsedDT));

  { If-Match válido vs divergente }
  Eval := TZenithPreconditions.Evaluate('PUT', '"v1"', '', '', '', '"v1"');
  AssertEquals(Ord(prProceed), Ord(Eval.Outcome));

  Eval := TZenithPreconditions.Evaluate('PUT', '"v2"', '', '', '', '"v1"');
  AssertEquals(Ord(prPreconditionFailed), Ord(Eval.Outcome));
  AssertEquals(412, Eval.StatusCode);

  { If-None-Match em GET -> 304; em PUT -> 412 }
  Eval := TZenithPreconditions.Evaluate('GET', '', '', '"v1"', '', '"v1"');
  AssertEquals(Ord(prNotModified), Ord(Eval.Outcome));
  AssertEquals(304, Eval.StatusCode);

  Eval := TZenithPreconditions.Evaluate('PUT', '', '', '"v1"', '', '"v1"');
  AssertEquals(Ord(prPreconditionFailed), Ord(Eval.Outcome));
  AssertEquals(412, Eval.StatusCode);
end;

procedure TTestZenithUnit.DoRequireMergePatchInvalid;
var
  Req: TRequest;
begin
  Req := TRequest.Create;
  try
    Req.ContentType := 'application/json';
    TZenithMergePatch.RequireMergePatchContentType(Req);
  finally
    Req.Free;
  end;
end;

procedure TTestZenithUnit.TestMergePatchModelAndMediaType;
var
  Req: TRequest;
  M: TPatchProbe;
  Modified: Integer;
begin
  AssertEquals('application/merge-patch+json',
    TZenithMergePatch.ExtractMediaType('application/merge-patch+json; charset=utf-8'));
  AssertTrue(TZenithMergePatch.IsMergePatchContentType('Application/Merge-Patch+Json'));
  AssertException(EUnsupportedMediaType, @DoRequireMergePatchInvalid);

  Req := TRequest.Create;
  M := TPatchProbe.Create;
  try
    M.id.AsLargeInt := 10;
    M.title.AsText := 'Original';
    M.notes.AsText := 'Manter';
    M.ClearAllDirty;

    Req.ContentType := 'application/merge-patch+json; charset=utf-8';
    Req.Content := '{"id":999,"title":"Atualizado","notes":null}';
    Modified := TZenithMergePatch.ApplyToModel(Req, M);

    AssertEquals(2, Modified);
    AssertEquals(Int64(10), M.id.AsLargeInt);
    AssertEquals('Atualizado', M.title.AsString);
    AssertTrue(M.notes.IsNull);
  finally
    M.Free;
    Req.Free;
  end;
end;

procedure TTestZenithUnit.TestWebSocketHandshakeAndFrames;
var
  Req: TRequest;
  Acc, Ext, Proto: string;
  FrameIn, FrameOut: TZWebSocketFrame;
  RawBytes: TBytes;
  MS: TMemoryStream;
  BigText: string;
begin
  { RFC 6455 Section 1.3 vector }
  AssertEquals('s3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
    TZWebSocketHandshake.ComputeAcceptKey('dGhlIHNhbXBsZSBub25jZQ=='));

  Req := TRequest.Create;
  try
    Req.Method := 'GET';
    Req.Host := 'ws.local';
    Req.SetCustomHeader('Upgrade', 'websocket');
    Req.SetCustomHeader('Connection', 'Upgrade');
    Req.SetCustomHeader('Sec-WebSocket-Version', '13');
    AssertFalse('Handshake sem Sec-WebSocket-Key deve retornar False',
      TZWebSocketHandshake.ValidateRequest(Req, Acc, Ext, Proto));

    Req.SetCustomHeader('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
    Req.SetCustomHeader('Origin', 'https://evil.example');
    AssertFalse('Handshake com Origin cruzada deve retornar False',
      TZWebSocketHandshake.ValidateRequest(Req, Acc, Ext, Proto));

    Req.SetCustomHeader('Origin', 'https://ws.local');
    AssertTrue(TZWebSocketHandshake.ValidateRequest(Req, Acc, Ext, Proto));
    AssertEquals('s3pPLMBiTxaQ9kYGzzhZRbK+xOo=', Acc);
  finally
    Req.Free;
  end;

  { Round-trip frame mascarado (> 125 bytes para cobrir payload estendido 16-bit) }
  BigText := StringOfChar('Z', 300);
  FrameIn := TZWebSocketFrameCodec.CreateTextFrame(BigText, True, False, True);
  RawBytes := TZWebSocketFrameCodec.EncodeFrame(FrameIn);
  MS := TMemoryStream.Create;
  try
    MS.WriteBuffer(RawBytes[0], Length(RawBytes));
    MS.Position := 0;
    AssertTrue(TZWebSocketFrameCodec.DecodeFrame(MS, FrameOut, True));
    AssertEquals(WS_OP_TEXT, FrameOut.Opcode);
    AssertTrue(FrameOut.Fin);
    AssertEquals(BigText, FrameOut.PayloadAsText);
  finally
    MS.Free;
  end;
end;

procedure TTestZenithUnit.TestGzipThresholdAndMimeFilter;
var
  Sample, Compressed, Restored: RawByteString;
begin
  Sample := RawByteString(StringOfChar('A', 1024));
  Compressed := GZipCompress(Sample);
  Restored := GZipDecompress(Compressed);
  AssertEquals(string(Sample), string(Restored));

  AssertFalse('Payload menor que mínimo não deve ser comprimido',
    ShouldGzipCompress('application/json', 100, 512));
  AssertTrue('JSON >= 512 bytes deve ser comprimido',
    ShouldGzipCompress('application/json; charset=utf-8', 600, 512));
  AssertTrue('SVG deve ser comprimido',
    ShouldGzipCompress('image/svg+xml', 600, 512));
  AssertFalse('PNG já é comprimido',
    ShouldGzipCompress('image/png', 4096, 512));
  AssertFalse('ZIP já é comprimido',
    ShouldGzipCompress('application/zip', 4096, 512));
  AssertFalse('SSE stream não deve passar por GZIP em bloco',
    ShouldGzipCompress('text/event-stream', 4096, 512));
end;

procedure TTestZenithUnit.TestLoggerStructuredJsonAndAsyncFile;
var
  LogPath: string;
  Logger: TZenithLogger;
  Lines: TStringList;
  JsonObj: TJSONData;
begin
  LogPath := GetTempFileName('', 'zlog') + '.log';
  SetEnvVariable('ZENITH_LOG_FORMAT', 'json');
  Logger := TZenithLogger.Create(LogPath, True);
  Lines := TStringList.Create;
  try
    Logger.Info('mensagem "teste"' + LineEnding + 'linha2');
    Logger.Flush;
    Logger.Free;
    Logger := nil;

    Lines.LoadFromFile(LogPath);
    AssertEquals(1, Lines.Count);
    JsonObj := GetJSON(Lines[0]);
    try
      AssertEquals(Ord(jtObject), Ord(JsonObj.JSONType));
      AssertEquals('INFO', TJSONObject(JsonObj).Strings['level']);
      AssertTrue(Pos('mensagem "teste"', TJSONObject(JsonObj).Strings['message']) = 1);
      AssertTrue(TJSONObject(JsonObj).Find('timestamp') <> nil);
    finally
      JsonObj.Free;
    end;
  finally
    SetEnvVariable('ZENITH_LOG_FORMAT', '');
    if Logger <> nil then Logger.Free;
    Lines.Free;
    if FileExists(LogPath) then DeleteFile(LogPath);
  end;
end;

initialization
  RegisterTest(TTestZenithUnit);

end.
