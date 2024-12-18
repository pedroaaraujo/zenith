unit Zenith.Auth;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, server.funcoes, server.classes, base64, ufuncoes,
  fpjson, StrUtils, server.exceptions, DateUtils;

type
  { TBasicAuthorization }

  TBasicAuthorization = class
  private
    FAuth: string;
    FPassword: string;
    FUser: string;
    procedure Extract;
  public
    property User: string read FUser;
    property Password: string read FPassword;
    constructor Create(Auth: string);
  end;

  { TPayLoad }

  TPayLoad = class(TCadastro)
  private
    Fexp: Int64;
    fiat: Int64;
    FIdEmpresa: Integer;
    FIdPerfilUsuario: Integer;
    FIdUsuario: Integer;
    function Getiat: Int64;
  published
    property exp: Int64 read Fexp write Fexp;
    property iat: Int64 read Getiat write fiat;
    property IdEmpresa: Integer read FIdEmpresa write FIdEmpresa;
    property IdUsuario: Integer read FIdUsuario write FIdUsuario;
    property IdPerfilUsuario: Integer read FIdPerfilUsuario write FIdPerfilUsuario;
  end;

  { TJWT }

  TJWT = class
  public
    class function GenerateToken(Payload: TPayLoad): string;
    class function GenerateJson(Payload: TPayLoad): string;
    class function ValidadeToken(Token: string): TPayLoad;
  end;

  { TBearerAuthentication }

  TBearerAuthentication = class
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

{ TBasicAuthorization }

procedure TBasicAuthorization.Extract;
var
  SL: TStringList;
begin
  if FAuth.IsEmpty then
    Exit;

  SL := TStringList.Create;
  try
    SL.Delimiter := ':';
    SL.StrictDelimiter := True;
    SL.DelimitedText := DecodeStringBase64(FAuth);
    FUser := Sl.Strings[0];
    FPassword := Sl.Strings[1];
  finally
    SL.Free;
  end;
end;

constructor TBasicAuthorization.Create(Auth: string);
begin
  FAuth := Auth.Replace('Basic ', EmptyStr, [rfIgnoreCase]);
  Extract;
end;

{ TPayLoad }

function TPayLoad.Getiat: Int64;
begin
  if fiat = 0 then
  begin
    fiat := DateTimeToUnix(Now, False);
  end;
  result := fiat
end;

{ TJWT }

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

class function TJWT.GenerateToken(Payload: TPayLoad): string;
var
  Body, Key: string;
begin
  Key := Configuracao('CRYPT_PWD');

  Body :=
    EncodeStringBase64UrlSafe('{"alg": "HS256", "typ": "JWT"}')  + '.' +
    EncodeStringBase64UrlSafe(Payload.ToJson);
  Result :=
    Body + '.' +
    EncodeStringBase64UrlSafe(HMAC_SHA256(Key, Body));
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
  Key := Configuracao('CRYPT_PWD');
  try
    /// Segments
    HeaderEncoded := ExtractWord(1, Token, ['.']);
    PayLoadEncoded := ExtractWord(2, Token, ['.']);
    SignatureEncoded := ExtractWord(3, Token, ['.']);

    /// Check signature
    SignatureDecoded := EncodeStringBase64UrlSafe(HMAC_SHA256(Key, HeaderEncoded + '.' + PayLoadEncoded));
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

{ TBearerAuthentication }

procedure TBearerAuthentication.SetPayload(AValue: TPayLoad);
begin
  if FPayload = AValue then Exit;
  FPayload := AValue;
end;

procedure TBearerAuthentication.Validate;
var
  Exp, ANow: TDateTime;
begin
  FPayload := TJWT.ValidadeToken(FAuth);

  if FPayload = nil then
  begin
    raise EUnauthorized.Create('Token inválido');
  end;

  Exp := UnixToDateTime(Payload.exp, False);
  ANow := Now;
  if Exp < ANow then
  begin
    raise EUnauthorized.Create('Token expirado');
  end;
end;

constructor TBearerAuthentication.Create(Auth: string);
begin
  FAuth := Auth.Replace('Bearer ', EmptyStr, [rfIgnoreCase]);
end;

destructor TBearerAuthentication.Destroy;
begin
  FPayload.Free;
  inherited Destroy;
end;


end.

