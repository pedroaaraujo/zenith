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
    class procedure SetSecret(const ASecret: string);
    class procedure AddFallbackSecret(const ASecret: string);
    class function GenerateToken(Payload: TPayLoad): string;
    class function GenerateJson(Payload: TPayLoad): RawByteString;
    class function OpenAPISchema: string;
    class function ValidadeToken(Token: string; AllowExpiredWithinGrace: Boolean = False; MaxGraceSeconds: Int64 = 604800): TPayLoad;
  end;


  { TJWTAuthentication }

  TJWTAuthentication = class
  private
    FPayload: TPayLoad;
    FAuth: string;
    FAllowGracePeriod: Boolean;
    FMaxGraceSeconds: Int64;
    procedure SetPayload(AValue: TPayLoad);
  public
    property Payload: TPayLoad read FPayload write SetPayload;
    property AllowGracePeriod: Boolean read FAllowGracePeriod write FAllowGracePeriod;
    property MaxGraceSeconds: Int64 read FMaxGraceSeconds write FMaxGraceSeconds;
    procedure Validate;
    constructor Create(Auth: string; AAllowGracePeriod: Boolean = False; AMaxGraceSeconds: Int64 = 604800);
    destructor Destroy; override;
  end;

implementation

const
  JWT_ENV_VARIABLE = 'ZENITH_JWT_SECRET';
  JWT_EXPIRATION_VARIABLE = 'ZENITH_JWT_EXPIRATION';

var
  GPrimaryCustomSecret: string = '';
  GFallbackCustomSecrets: TStringList = nil;

class procedure TJWT.SetSecret(const ASecret: string);
begin
  GPrimaryCustomSecret := Trim(ASecret);
end;

class procedure TJWT.AddFallbackSecret(const ASecret: string);
begin
  if not Assigned(GFallbackCustomSecrets) then
    GFallbackCustomSecrets := TStringList.Create;
  if (Trim(ASecret) <> '') and (GFallbackCustomSecrets.IndexOf(Trim(ASecret)) < 0) then
    GFallbackCustomSecrets.Add(Trim(ASecret));
end;

function JwtSecret: string;
var
  RawEnv: string;
  P: SizeInt;
begin
  if not GPrimaryCustomSecret.IsEmpty then
    Exit(GPrimaryCustomSecret);

  RawEnv := Zenith.Env.GetEnvVariable(JWT_ENV_VARIABLE);
  if RawEnv.IsEmpty then
    raise EServerError.Create('JWT signing secret is not configured');

  P := Pos(',', RawEnv);
  if P > 0 then
    Result := Trim(Copy(RawEnv, 1, P - 1))
  else
    Result := Trim(RawEnv);
end;

procedure ObterTodosSegredosValidos(AList: TStrings);
var
  RawEnv, S: string;
  P: SizeInt;
begin
  AList.Clear;
  if not GPrimaryCustomSecret.IsEmpty then
    AList.Add(GPrimaryCustomSecret);

  RawEnv := Zenith.Env.GetEnvVariable(JWT_ENV_VARIABLE);
  while not RawEnv.IsEmpty do
  begin
    P := Pos(',', RawEnv);
    if P > 0 then
    begin
      S := Trim(Copy(RawEnv, 1, P - 1));
      Delete(RawEnv, 1, P);
    end
    else
    begin
      S := Trim(RawEnv);
      RawEnv := '';
    end;

    if (not S.IsEmpty) and (AList.IndexOf(S) < 0) then
      AList.Add(S);
  end;

  if Assigned(GFallbackCustomSecrets) then
  begin
    for S in GFallbackCustomSecrets do
    begin
      if (not S.IsEmpty) and (AList.IndexOf(S) < 0) then
        AList.Add(S);
    end;
  end;
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
    Minutes := GetEnvVariable(JWT_EXPIRATION_VARIABLE, '1440').ToInteger;

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
  { The timestamp returned in this example is the moment this block was written.
    I was at the farm on a Carnival Sunday, having a beer while waiting for lunch.

    If you are reading this comment, I wish you all happiness and a warm hug.
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

class function TJWT.ValidadeToken(Token: string; AllowExpiredWithinGrace: Boolean = False; MaxGraceSeconds: Int64 = 604800): TPayLoad;
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
  SignatureMatches: Boolean;
  SecretList: TStringList;
begin
  Result := nil;
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

    /// Check signature across primary and rotated/fallback keys
    SignatureMatches := False;
    SecretList := TStringList.Create;
    try
      ObterTodosSegredosValidos(SecretList);
      for Key in SecretList do
      begin
        SignatureDecoded := EncodeStringBase64UrlSafe(HMACSHA256(Key, HeaderEncoded + '.' + PayLoadEncoded));
        if ConstantTimeEquals(SignatureDecoded, SignatureEncoded) then
        begin
          SignatureMatches := True;
          Break;
        end;
      end;
    finally
      SecretList.Free;
    end;

    if not SignatureMatches then
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
      begin
        if not (AllowExpiredWithinGrace and (Claim.AsInt64 + MaxGraceSeconds >= DateTimeToUnix(Now, False))) then
          raise Exception.Create('Token expired');
      end;
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
  FPayload := TJWT.ValidadeToken(FAuth, FAllowGracePeriod, FMaxGraceSeconds);

  if FPayload = nil then
  begin
    raise EUnauthorized.Create('Invalid Token');
  end;

  Exp := UnixToDateTime(Payload.exp, False);
  ANow := Now;
  if Exp < ANow then
  begin
    if not (FAllowGracePeriod and (Payload.exp + FMaxGraceSeconds >= DateTimeToUnix(ANow, False))) then
    begin
      raise EUnauthorized.Create('Expired Token');
    end;
  end;
end;

constructor TJWTAuthentication.Create(Auth: string; AAllowGracePeriod: Boolean; AMaxGraceSeconds: Int64);
begin
  FAuth := Auth.Trim;
  if FAuth.StartsWith('Bearer ', True) then
    FAuth := FAuth.Substring(7).Trim;
  FAllowGracePeriod := AAllowGracePeriod;
  FMaxGraceSeconds := AMaxGraceSeconds;
end;

destructor TJWTAuthentication.Destroy;
begin
  if FPayload <> nil then
    FPayload.Free;

  inherited Destroy;
end;

finalization
  if Assigned(GFallbackCustomSecrets) then
    FreeAndNil(GFallbackCustomSecrets);

end.
