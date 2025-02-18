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
    function Getiat: Int64;
  public
    property exp: Int64 read Fexp write Fexp;
    property iat: Int64 read Getiat write fiat;
    property CustomValues[Name: string]: Variant read GetCustomValues;

    function ToJson: string;
    procedure FromJson(const JsonStr: string);

    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

  { TJWT }

  TJWT = class
  public
    class function GenerateToken(Payload: TPayLoad): string;
    class function GenerateJson(Payload: TPayLoad): string;
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
  JWT_ENV_VARIABLE = 'JWT_SECRET';

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

function TPayLoad.Getiat: Int64;
begin
  if fiat = 0 then
  begin
    fiat := DateTimeToUnix(Now, False);
  end;
  result := fiat
end;

function TPayLoad.ToJson: string;
var
  Json: TJSONObject;
  I: Integer;
begin
  Json := TJSONObject.Create;
  try
    Json.Add('exp', Fexp);
    Json.Add('iat', Getiat);

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
  Key := Zenith.Env.GetEnvVariable(JWT_ENV_VARIABLE);

  Body :=
    EncodeStringBase64UrlSafe('{"alg": "HS256", "typ": "JWT"}')  + '.' +
    EncodeStringBase64UrlSafe(Payload.ToJson);
  Result :=
    Body + '.' +
    EncodeStringBase64UrlSafe(HMACSHA256(Key, Body));
end;

class function TJWT.GenerateJson(Payload: TPayLoad): string;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.Add('expiresIn', Payload.exp);
    Json.Add('created', Payload.iat);
    Json.add('token', GenerateToken(Payload));
    Result := Json.AsJSON;
  finally
    Json.Free;
  end;
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
  Key: string;
begin
  Result := nil;
  Key := Zenith.Env.GetEnvVariable(JWT_ENV_VARIABLE);
  try
    /// Segments
    HeaderEncoded := ExtractWord(1, Token, ['.']);
    PayLoadEncoded := ExtractWord(2, Token, ['.']);
    SignatureEncoded := ExtractWord(3, Token, ['.']);

    /// Check signature
    SignatureDecoded := EncodeStringBase64UrlSafe(HMACSHA256(Key, HeaderEncoded + '.' + PayLoadEncoded));
    if (SignatureDecoded <> SignatureEncoded) then
    begin
      raise Exception.Create('Signature verification failed');
    end;

    HeaderDecoded := DecodeStringBase64UrlSafe(HeaderEncoded);
    HeaderJson := GetJSON(HeaderDecoded);

    if (HeaderJson.FindPath('.alg').AsString = EmptyStr)
      or (HeaderJson.FindPath('.alg').AsString <> 'HS256') then
    begin
      raise Exception.Create('Algorithm not supported');
    end;

    PayLoadDecoded:= DecodeStringBase64UrlSafe(PayLoadEncoded);

    Result := TPayLoad.Create;
    Result.FromJson(PayLoadDecoded);
  except
    on E: Exception do
    begin
      raise EUnauthorized.CreateFmt('JWT invalid. %s', [E.Message]);
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
  FAuth := Auth.Replace('Bearer ', EmptyStr, [rfIgnoreCase]);
end;

destructor TJWTAuthentication.Destroy;
begin
  if FPayload <> nil then
    FPayload.Free;

  inherited Destroy;
end;

end.
