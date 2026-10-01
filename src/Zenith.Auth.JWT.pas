unit Zenith.Auth.JWT;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, base64, fpjson, StrUtils, DateUtils, fgl,
  Zenith.Hash, Zenith.Env, Zenith.Exceptions;

type

  TDictionay = specialize TFPGMap<string, Variant>;

  { TPayLoad }

  TPayLoad = class
  private
    Fexp: Int64;
    fiat: Int64;
    Values: TDictionay;
    function GetCustomValues(const Name: string): Variant;
    function Getexp: Int64;
    function Getiat: Int64;
    procedure SetCustomValues(Name: string; AValue: Variant);
  public
    property exp: Int64 read Getexp write Fexp;
    property iat: Int64 read Getiat write fiat;
    property CustomValues[Name: string]: Variant read GetCustomValues write SetCustomValues;

    function ToJson: string;
    procedure FromJson(const JsonStr: string);

    procedure Refresh;

    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

  { TJWT }

  TJWT = class
  public
    class function GenerateToken(Payload: TPayLoad): string;
    class function GenerateJson(Payload: TPayLoad): RawByteString;
    class function OpenAPISchema: string;
    class function ValidadeToken(Token: string): TPayLoad;
  end;


  { TJWTAuthentication }

  TJWTAuthentication = class
  private
    FPayload: TPayLoad;
    FAuth: string;
    procedure SetPayload(AValue: TPayLoad);
  public
    property Payload: TPayLoad read FPayload write SetPayload;
    procedure Validate;
    constructor Create(Auth: string);
    destructor Destroy; override;
  end;

implementation

const
  JWT_ENV_VARIABLE = 'ZENITH_JWT_SECRET';
  JWT_EXPIRATION_VARIABLE = 'ZENITH_JWT_EXPIRATION';

function JwtSecret: string;
begin
  Result := Zenith.Env.GetEnvVariable(JWT_ENV_VARIABLE);
  if Result.IsEmpty then
    raise EServerError.Create('JWT signing secret is not configured');
end;

function ConstantTimeEquals(const A, B: string): Boolean;
var
  I: Integer;
  Difference: Byte;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  Difference := 0;
  for I := 1 to Length(A) do
    Difference := Difference or (Byte(Ord(A[I])) xor Byte(Ord(B[I])));
  Result := Difference = 0;
end;

function EncodeStringBase64UrlSafe(const AStr: string): string;
begin
  Result := EncodeStringBase64(AStr);
  Result := StringReplace(Result, '=', '', [rfReplaceAll]);
  Result := StringReplace(Result, '+', '-', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '_', [rfReplaceAll]);
end;

function DecodeStringBase64UrlSafe(const AStr: string): string;
var
  TempStr: string;
begin
  TempStr := AStr;
  TempStr := StringReplace(TempStr, '-', '+', [rfReplaceAll]);
  TempStr := StringReplace(TempStr, '_', '/', [rfReplaceAll]);
  while (Length(TempStr) mod 4) <> 0 do
    TempStr := TempStr + '=';
  Result := DecodeStringBase64(TempStr);
end;

{ TPayLoad }

function TPayLoad.GetCustomValues(const Name: string): Variant;
begin
  Result := Values.KeyData[Name];
end;

function TPayLoad.Getexp: Int64;
var
  vExp, vIat: TDateTime;
  Minutes: Integer;
begin
  if Fexp = 0 then
  begin
    Minutes := GetEnvVariable(JWT_EXPIRATION_VARIABLE, '30').ToInteger;

    vIat := UnixToDateTime(Getiat, True);
    vExp := IncMinute(vIat, Minutes);
    Fexp := DateTimeToUnix(vExp);
  end;

  Result := Fexp;
end;

function TPayLoad.Getiat: Int64;
begin
  if fiat = 0 then
  begin
    fiat := DateTimeToUnix(Now, False);
  end;
  result := fiat
end;

procedure TPayLoad.SetCustomValues(Name: string; AValue: Variant);
begin
  Values.KeyData[Name] := AValue;
end;

function TPayLoad.ToJson: string;
var
  Json: TJSONObject;
  I: Integer;
begin
  Json := TJSONObject.Create;
  try
    Json.Add('exp', Exp);
    Json.Add('iat', Iat);

    for I := 0 to Pred(Values.Count) do
    begin
      Json.Add(Values.Keys[I], Values.Data[I]);
    end;

    Result := Json.AsJSON;
  finally
    Json.Free;
  end;
end;

procedure TPayLoad.FromJson(const JsonStr: string);
var
  Json: TJSONObject;
  I: Integer;
  Key: string;
begin
  Json := GetJSON(JsonStr) as TJSONObject;
  try
    if Json.Find('exp') <> nil then
      Fexp := Json.Integers['exp'];

    if Json.Find('iat') <> nil then
      fiat := Json.Integers['iat'];

    Values.Clear;
    for I := 0 to Pred(Json.Count) do
    begin
      Key := Json.Names[I];

      if (Key <> 'exp') and (Key <> 'iat') then
      begin
        Values.Add(Key, Json.Get(Key));
      end;
    end;
  finally
    Json.Free;
  end;
end;

procedure TPayLoad.Refresh;
begin
  Fexp := 0;
  fiat := 0;

  Getexp;
end;

procedure TPayLoad.AfterConstruction;
begin
  inherited AfterConstruction;
  Values := TDictionay.Create;
end;

procedure TPayLoad.BeforeDestruction;
begin
  inherited BeforeDestruction;
  Values.Free;
end;

{ TJWT }

class function TJWT.GenerateToken(Payload: TPayLoad): string;
var
  Body, Key: string;
begin
  Key := JwtSecret;

  Body :=
    EncodeStringBase64UrlSafe('{"alg": "HS256", "typ": "JWT"}')  + '.' +
    EncodeStringBase64UrlSafe(Payload.ToJson);
  Result :=
    Body + '.' +
    EncodeStringBase64UrlSafe(HMACSHA256(Key, Body));
end;

class function TJWT.GenerateJson(Payload: TPayLoad): RawByteString;
var
  Json: TJSONObject;
  vExp, vIat: string;
begin
  Json := TJSONObject.Create;
  try
    vExp := DateToISO8601(UnixToDateTime(Payload.exp));
    vIat := DateToISO8601(UnixToDateTime(Payload.iat));

    Json.Add('expiresIn', vExp);
    Json.Add('created', vIat);
    Json.add('token', GenerateToken(Payload));
    Result := Json.AsJSON;
  finally
    Json.Free;
  end;
end;

class function TJWT.OpenAPISchema: string;
begin
  {A data retornada no exemplo é o momento em que este bloco foi escrito.
   Eu estava na fazenda, em um domingo de carnaval, bebendo uma cerveja
   enquanto aguardava o almoço.

   Se você estiver lendo este comentário, lhe desejo toda felicidade e um fraterno abraço.
  }
  Result :=
    '{' +
    '  "type": "object",' +
    '  "properties": {' +
    '    "expiresIn": {' +
    '      "type": "string",' +
    '      "format": "date-time",' +
    '      "example": "2025-03-02T13:39:42.000Z"' +
    '    },' +
    '    "created": {' +
    '      "type": "string",' +
    '      "format": "date-time",' +
    '      "example": "2025-03-02T13:09:42.000Z"' +
    '    },' +
    '    "token": {' +
    '      "type": "string",' +
    '      "example": "eyJhbGciOiJIUzI1NiIsInR..."' +
    '    }' +
    '  },' +
    '  "required": ["expiresIn", "created", "token"]' +
    '}';
end;

class function TJWT.ValidadeToken(Token: string): TPayLoad;
var
  HeaderEncoded: string;
  PayLoadEncoded: string;
  SignatureEncoded: string;
  HeaderDecoded: string;
  PayLoadDecoded: string;
  SignatureDecoded: string;
  HeaderJson: TJSONData;
  PayloadJson: TJSONData;
  Claim: TJSONData;
  Key: string;
  FirstDot, SecondDot: SizeInt;
begin
  Result := nil;
  Key := JwtSecret;
  try
    if Token.IsEmpty then
    begin
      raise Exception.Create('Token is empty');
    end;

    FirstDot := Pos('.', Token);
    SecondDot := PosEx('.', Token, FirstDot + 1);
    if (FirstDot <= 1) or (SecondDot <= FirstDot + 1) or
       (SecondDot >= Length(Token)) or (PosEx('.', Token, SecondDot + 1) > 0) then
      raise Exception.Create('Malformed token');
    HeaderEncoded := Copy(Token, 1, FirstDot - 1);
    PayLoadEncoded := Copy(Token, FirstDot + 1, SecondDot - FirstDot - 1);
    SignatureEncoded := Copy(Token, SecondDot + 1, MaxInt);

    /// Check signature
    SignatureDecoded := EncodeStringBase64UrlSafe(HMACSHA256(Key, HeaderEncoded + '.' + PayLoadEncoded));
    if not ConstantTimeEquals(SignatureDecoded, SignatureEncoded) then
    begin
      raise Exception.Create('Signature verification failed');
    end;

    HeaderJson := nil;
    PayloadJson := nil;
    try
      HeaderDecoded := DecodeStringBase64UrlSafe(HeaderEncoded);
      HeaderJson := GetJSON(HeaderDecoded);
      if (HeaderJson = nil) or (HeaderJson.JSONType <> jtObject) then
        raise Exception.Create('Cannot read header');

      Claim := TJSONObject(HeaderJson).Find('alg');
      if (Claim = nil) or (Claim.AsString <> 'HS256') then
        raise Exception.Create('Algorithm not supported');

      PayLoadDecoded := DecodeStringBase64UrlSafe(PayLoadEncoded);
      PayloadJson := GetJSON(PayLoadDecoded);
      if (PayloadJson = nil) or (PayloadJson.JSONType <> jtObject) then
        raise Exception.Create('Cannot read payload');
      Claim := TJSONObject(PayloadJson).Find('exp');
      if Claim = nil then
        raise Exception.Create('Expiration claim is required');
      if Claim.AsInt64 <= DateTimeToUnix(Now, False) then
        raise Exception.Create('Token expired');
      Claim := TJSONObject(PayloadJson).Find('nbf');
      if (Claim <> nil) and (Claim.AsInt64 > DateTimeToUnix(Now, False)) then
        raise Exception.Create('Token is not active');

      Result := TPayLoad.Create;
      Result.FromJson(PayLoadDecoded);
    finally
      if HeaderJson <> nil then HeaderJson.Free;
      if PayloadJson <> nil then PayloadJson.Free;
    end;
  except
    on E: Exception do
    begin
      if Result <> nil then
      begin
        Result.Free;
        Result := nil;
      end;
      raise EUnauthorized.CreateFmt('Invalid JWT - %s', [E.Message]);
    end;
  end;
end;

{ TJWTAuthentication }

procedure TJWTAuthentication.SetPayload(AValue: TPayLoad);
begin
  if FPayload = AValue then Exit;
  FPayload := AValue;
end;

procedure TJWTAuthentication.Validate;
var
  Exp, ANow: TDateTime;
begin
  FreeAndNil(FPayload);
  FPayload := TJWT.ValidadeToken(FAuth);

  if FPayload = nil then
  begin
    raise EUnauthorized.Create('Invalid Token');
  end;

  Exp := UnixToDateTime(Payload.exp, False);
  ANow := Now;
  if Exp < ANow then
  begin
    raise EUnauthorized.Create('Expired Token');
  end;
end;

constructor TJWTAuthentication.Create(Auth: string);
begin
  FAuth := Auth.Trim;
  if FAuth.StartsWith('Bearer ', True) then
    FAuth := FAuth.Substring(7).Trim;
end;

destructor TJWTAuthentication.Destroy;
begin
  if FPayload <> nil then
    FPayload.Free;

  inherited Destroy;
end;

end.
