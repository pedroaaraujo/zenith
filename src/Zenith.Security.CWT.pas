unit Zenith.Security.CWT;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, DateUtils, HTTPDefs, fgl, base64, Variants, StrUtils,
  Zenith.Hash, Zenith.Env, Zenith.Exceptions, Zenith.Security;

const
  CWT_ENV_VARIABLE = 'ZENITH_CWT_SECRET';
  CWT_JWT_ENV_VARIABLE = 'ZENITH_JWT_SECRET';
  CWT_EXPIRATION_VARIABLE = 'ZENITH_JWT_EXPIRATION';

  { RFC 8392 Standard Claims }
  CWT_CLAIM_ISS = 1; { Issuer }
  CWT_CLAIM_SUB = 2; { Subject }
  CWT_CLAIM_AUD = 3; { Audience }
  CWT_CLAIM_EXP = 4; { Expiration Time (epoch seconds) }
  CWT_CLAIM_NBF = 5; { Not Before (epoch seconds) }
  CWT_CLAIM_IAT = 6; { Issued At (epoch seconds) }
  CWT_CLAIM_CTI = 7; { CWT ID }

  { COSE Header Labels (RFC 8152 / RFC 9052) }
  COSE_HEADER_ALG = 1;
  COSE_HEADER_CRIT = 2;
  COSE_HEADER_CONTENT_TYPE = 3;
  COSE_HEADER_KID = 4;
  COSE_HEADER_IV = 5;

  { COSE Algorithm IDs }
  COSE_ALG_ES256_OR_HMAC = -7; { RFC 8392 / Prompt canonical alg: -7 }
  COSE_ALG_HMAC_256_256 = 5;   { RFC 8152 Table 7 HMAC 256/256 }
  COSE_ALG_HS256_STR = 'HS256';

  { COSE Tags }
  COSE_TAG_SIGN1 = 18; { RFC 8152 Tag 18 }
  CWT_TAG = 61;        { RFC 8392 Tag 61 }

  { Limits against Resource Exhaustion (Anti-OOM / DoS) }
  MAX_CWT_STRING_LEN = 1024 * 1024; // 1 MB
  MAX_CWT_DEPTH = 32;

type
  { Exceptions }
  ECWTException = class(EUnauthorized);
  ECWTExpired = class(ECWTException);
  ECWTSignatureInvalid = class(ECWTException);
  ECWTMalformed = class(ECWTException);
  ECWTAlgorithmNotSupported = class(ECWTException);

  { Custom Claims Dictionary }
  TCWTDictionay = specialize TFPGMap<string, Variant>;

  { TCWTPayload }
  TCWTPayload = class
  private
    Fiss: string;
    Fsub: string;
    Faud: string;
    Fexp: Int64;
    Fiat: Int64;
    Fnbf: Int64;
    Fcti: string;
    Frole: string;
    Forg_id: Int64;
    Fent_id: Int64;
    FRoles: TStringList;
    FPermissions: TStringList;
    FCustomValues: TCWTDictionay;

    function GetExp: Int64;
    function GetIat: Int64;
    function GetCustomValues(const Name: string): Variant;
    procedure SetCustomValues(const Name: string; const AValue: Variant);
  public
    property iss: string read Fiss write Fiss;
    property sub: string read Fsub write Fsub;
    property aud: string read Faud write Faud;
    property exp: Int64 read GetExp write Fexp;
    property iat: Int64 read GetIat write Fiat;
    property nbf: Int64 read Fnbf write Fnbf;
    property cti: string read Fcti write Fcti;
    property role: string read Frole write Frole;
    property org_id: Int64 read Forg_id write Forg_id;
    property ent_id: Int64 read Fent_id write Fent_id;
    property Roles: TStringList read FRoles;
    property Permissions: TStringList read FPermissions;
    property CustomValues[const Name: string]: Variant read GetCustomValues write SetCustomValues;

    procedure SetCustomClaim(const AName: string; const AValue: Variant);
    function GetCustomClaim(const AName: string; const ADef: Variant): Variant;
    function HasCustomClaim(const AName: string): Boolean;

    function HasRole(const ARole: string): Boolean;
    function HasPermission(const APermission: string): Boolean;

    function ToSecurityContext: TZSecurityContext;
    procedure FromSecurityContext(const ASec: TZSecurityContext);

    procedure Refresh;
    function CountStandardPairs: Integer;

    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

  { TCWT: CBOR Web Token (RFC 8392 / RFC 8152) Manager }
  TCWT = class
  public
    class procedure SetSecret(const ASecret: string);
    class procedure AddFallbackSecret(const ASecret: string);
    class procedure ClearFallbackSecrets;
    class function GetSecret: string;
    class procedure ObterTodosSegredosValidos(AList: TStrings);

    { Generation }
    class function GenerateToken(Payload: TCWTPayload): TBytes; overload;
    class function GenerateToken(Payload: TCWTPayload; AsBase64Url: Boolean): string; overload;
    class function GenerateTokenRaw(Payload: TCWTPayload): RawByteString;
    class function GenerateTokenBase64Url(Payload: TCWTPayload): string;
    class function GenerateTokenHex(Payload: TCWTPayload): string;

    { Validation }
    class function ValidateToken(const Token: TBytes; AllowExpiredWithinGrace: Boolean = False; MaxGraceSeconds: Int64 = 604800): TCWTPayload; overload;
    class function ValidateToken(const Token: RawByteString; AllowExpiredWithinGrace: Boolean = False; MaxGraceSeconds: Int64 = 604800): TCWTPayload; overload;
    class function ValidateToken(const TokenStr: string; AllowExpiredWithinGrace: Boolean = False; MaxGraceSeconds: Int64 = 604800): TCWTPayload; overload;

    { Fast Direct Context Validation (Zero JSON, Zero DOM) }
    class function ValidateToContext(const Token: TBytes; AllowExpiredWithinGrace: Boolean = False; MaxGraceSeconds: Int64 = 604800): TZSecurityContext; overload;
    class function ValidateToContext(const Token: RawByteString; AllowExpiredWithinGrace: Boolean = False; MaxGraceSeconds: Int64 = 604800): TZSecurityContext; overload;
    class function ValidateToContext(const TokenStr: string; AllowExpiredWithinGrace: Boolean = False; MaxGraceSeconds: Int64 = 604800): TZSecurityContext; overload;

    { Size Benchmark Comparison (CWT Binary vs JWT Base64) }
    class function CompareTokenSizes(Payload: TCWTPayload; out ACwtBytes, AJwtBytes: Integer; out AReductionPct: Double): string;
  end;

  { TZCWTBearerResolver: Resolves Authorization: Bearer <cwt_or_jwt> into TZSecurityContext }
  TZCWTBearerResolver = class(TInterfacedObject, IZenithSecurityResolver)
  private
    FAllowJWTFallback: Boolean;
  public
    constructor Create(AAllowJWTFallback: Boolean = True);
    function Resolve(ARequest: TRequest): TZSecurityContext;
  end;

  { TCWTAuthentication }
  TCWTAuthentication = class
  private
    FPayload: TCWTPayload;
    FAuth: string;
    FAllowGracePeriod: Boolean;
    FMaxGraceSeconds: Int64;
    procedure SetPayload(AValue: TCWTPayload);
  public
    property Payload: TCWTPayload read FPayload write SetPayload;
    property AllowGracePeriod: Boolean read FAllowGracePeriod write FAllowGracePeriod;
    property MaxGraceSeconds: Int64 read FMaxGraceSeconds write FMaxGraceSeconds;
    procedure Validate;
    constructor Create(const Auth: string; AAllowGracePeriod: Boolean = False; AMaxGraceSeconds: Int64 = 604800); overload;
    constructor Create(const AuthBytes: TBytes; AAllowGracePeriod: Boolean = False; AMaxGraceSeconds: Int64 = 604800); overload;
    destructor Destroy; override;
  end;

{ Helper Encoding Utilities }
function EncodeBytesBase64UrlSafe(const ABytes: TBytes): string; overload;
function EncodeBytesBase64UrlSafe(const AStr: RawByteString): string; overload;
function DecodeBytesBase64UrlSafe(const AStr: string): TBytes;
function DecodeStringToRawBytes(const AStr: string): RawByteString;
function StringToTokenBytes(const AStr: string): TBytes;
function ConstantTimeEquals(const A, B: string): Boolean;

implementation

uses
  Zenith.Auth.JWT, fpjson, jsonparser;

var
  GPrimaryCwtSecret: string = '';
  GFallbackCwtSecrets: TStringList = nil;

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

function EncodeBytesBase64UrlSafe(const ABytes: TBytes): string;
var
  S: string;
begin
  if Length(ABytes) = 0 then Exit('');
  SetString(S, PAnsiChar(@ABytes[0]), Length(ABytes));
  Result := EncodeBytesBase64UrlSafe(RawByteString(S));
end;

function EncodeBytesBase64UrlSafe(const AStr: RawByteString): string;
begin
  if Length(AStr) = 0 then Exit('');
  Result := EncodeStringBase64(String(AStr));
  Result := StringReplace(Result, '=', '', [rfReplaceAll]);
  Result := StringReplace(Result, '+', '-', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '_', [rfReplaceAll]);
end;

function DecodeBytesBase64UrlSafe(const AStr: string): TBytes;
var
  TempStr, Decoded: string;
begin
  if AStr.IsEmpty then Exit(nil);
  TempStr := AStr;
  TempStr := StringReplace(TempStr, '-', '+', [rfReplaceAll]);
  TempStr := StringReplace(TempStr, '_', '/', [rfReplaceAll]);
  while (Length(TempStr) mod 4) <> 0 do
    TempStr := TempStr + '=';
  Decoded := DecodeStringBase64(TempStr);
  SetLength(Result, Length(Decoded));
  if Length(Decoded) > 0 then
    Move(Decoded[1], Result[0], Length(Decoded));
end;

function DecodeStringToRawBytes(const AStr: string): RawByteString;
var
  Bytes: TBytes;
begin
  Bytes := StringToTokenBytes(AStr);
  if Length(Bytes) = 0 then Exit('');
  SetLength(Result, Length(Bytes));
  Move(Bytes[0], Result[1], Length(Bytes));
end;

function StringToTokenBytes(const AStr: string): TBytes;
var
  S: string;
  I: Integer;
  IsHex: Boolean;
begin
  S := Trim(AStr);
  if S.IsEmpty then Exit(nil);

  // 1. Raw binary check (CBOR Array $84 or COSE Tag $D2, $D8)
  if (Length(S) >= 4) and (Byte(S[1]) in [$84, $D2, $D8]) then
  begin
    SetLength(Result, Length(S));
    Move(S[1], Result[0], Length(S));
    Exit;
  end;

  // 2. Hex check
  if (Length(S) >= 8) and ((Length(S) mod 2) = 0) then
  begin
    IsHex := True;
    for I := 1 to Length(S) do
    begin
      if not (S[I] in ['0'..'9', 'a'..'f', 'A'..'F']) then
      begin
        IsHex := False;
        Break;
      end;
    end;
    if IsHex and (IndexStr(UpperCase(Copy(S, 1, 2)), ['84', 'D2', 'D8']) >= 0) then
    begin
      SetLength(Result, Length(S) div 2);
      for I := 0 to High(Result) do
        Result[I] := StrToInt('$' + Copy(S, I * 2 + 1, 2));
      Exit;
    end;
  end;

  // 3. Base64Url / Base64 decoded
  Result := DecodeBytesBase64UrlSafe(S);
end;

{ Zero-DOM CBOR Writer }
type
  TCborWriter = record
    Data: RawByteString;
    procedure Init;
    procedure WriteByte(B: Byte);
    procedure WriteBuffer(const P; Count: Integer);
    procedure WriteHeader(AMajor: Byte; AVal: UInt64);
    procedure WriteUInt(AVal: UInt64);
    procedure WriteNInt(AVal: Int64);
    procedure WriteInt(AVal: Int64);
    procedure WriteTextString(const S: string);
    procedure WriteByteString(const B: RawByteString); overload;
    procedure WriteByteString(const B: TBytes); overload;
    procedure WriteArrayHeader(ACount: UInt64);
    procedure WriteMapHeader(APairCount: UInt64);
    procedure WriteTag(ATag: UInt64);
    procedure WriteBoolean(AValue: Boolean);
    procedure WriteNull;
    procedure WriteDouble(AValue: Double);
    procedure WriteVariant(const V: Variant);
    function ToBytes: TBytes;
  end;

procedure TCborWriter.Init;
begin
  Data := '';
end;

procedure TCborWriter.WriteByte(B: Byte);
var
  L: Integer;
begin
  L := Length(Data);
  SetLength(Data, L + 1);
  Data[L + 1] := AnsiChar(B);
end;

procedure TCborWriter.WriteBuffer(const P; Count: Integer);
var
  L: Integer;
begin
  if Count <= 0 then Exit;
  L := Length(Data);
  SetLength(Data, L + Count);
  Move(P, Data[L + 1], Count);
end;

procedure TCborWriter.WriteHeader(AMajor: Byte; AVal: UInt64);
var
  InitialByte: Byte;
  U8: UInt8;
  U16: Word;
  U32: UInt32;
  U64: UInt64;
begin
  if AVal < 24 then
  begin
    InitialByte := (AMajor shl 5) or Byte(AVal);
    WriteByte(InitialByte);
  end
  else if AVal <= $FF then
  begin
    InitialByte := (AMajor shl 5) or 24;
    WriteByte(InitialByte);
    U8 := UInt8(AVal);
    WriteByte(U8);
  end
  else if AVal <= $FFFF then
  begin
    InitialByte := (AMajor shl 5) or 25;
    WriteByte(InitialByte);
    U16 := NtoBE(Word(AVal));
    WriteBuffer(U16, 2);
  end
  else if AVal <= $FFFFFFFF then
  begin
    InitialByte := (AMajor shl 5) or 26;
    WriteByte(InitialByte);
    U32 := NtoBE(UInt32(AVal));
    WriteBuffer(U32, 4);
  end
  else
  begin
    InitialByte := (AMajor shl 5) or 27;
    WriteByte(InitialByte);
    U64 := NtoBE(AVal);
    WriteBuffer(U64, 8);
  end;
end;

procedure TCborWriter.WriteUInt(AVal: UInt64);
begin
  WriteHeader(0, AVal);
end;

procedure TCborWriter.WriteNInt(AVal: Int64);
begin
  WriteHeader(1, UInt64(-1 - AVal));
end;

procedure TCborWriter.WriteInt(AVal: Int64);
begin
  if AVal >= 0 then
    WriteUInt(UInt64(AVal))
  else
    WriteNInt(AVal);
end;

procedure TCborWriter.WriteTextString(const S: string);
var
  Raw: RawByteString;
begin
  Raw := UTF8Encode(S);
  WriteHeader(3, Length(Raw));
  if Length(Raw) > 0 then
    WriteBuffer(Raw[1], Length(Raw));
end;

procedure TCborWriter.WriteByteString(const B: RawByteString);
begin
  WriteHeader(2, Length(B));
  if Length(B) > 0 then
    WriteBuffer(B[1], Length(B));
end;

procedure TCborWriter.WriteByteString(const B: TBytes);
begin
  WriteHeader(2, Length(B));
  if Length(B) > 0 then
    WriteBuffer(B[0], Length(B));
end;

procedure TCborWriter.WriteArrayHeader(ACount: UInt64);
begin
  WriteHeader(4, ACount);
end;

procedure TCborWriter.WriteMapHeader(APairCount: UInt64);
begin
  WriteHeader(5, APairCount);
end;

procedure TCborWriter.WriteTag(ATag: UInt64);
begin
  WriteHeader(6, ATag);
end;

procedure TCborWriter.WriteBoolean(AValue: Boolean);
begin
  if AValue then
    WriteByte($F5)
  else
    WriteByte($F4);
end;

procedure TCborWriter.WriteNull;
begin
  WriteByte($F6);
end;

procedure TCborWriter.WriteDouble(AValue: Double);
var
  U64, BE: UInt64;
begin
  WriteByte($FB);
  Move(AValue, U64, 8);
  BE := NtoBE(U64);
  WriteBuffer(BE, 8);
end;

procedure TCborWriter.WriteVariant(const V: Variant);
var
  VarT: TVarType;
begin
  VarT := VarType(V);
  case VarT of
    varEmpty, varNull:
      WriteNull;
    varBoolean:
      WriteBoolean(Boolean(V));
    varSmallInt, varInteger, varShortInt, varByte, varWord, varLongWord, varInt64, varQWord:
      WriteInt(Int64(V));
    varSingle, varDouble, varCurrency:
      WriteDouble(Double(V));
    varOleStr, varString, varUString:
      WriteTextString(String(V));
  else
    WriteTextString(VarToStr(V));
  end;
end;

function TCborWriter.ToBytes: TBytes;
begin
  if Length(Data) = 0 then Exit(nil);
  SetLength(Result, Length(Data));
  Move(Data[1], Result[0], Length(Data));
end;

{ Zero-DOM CBOR Reader }
type
  TCborReader = record
  private
    FBuffer: PByte;
    FSize: Integer;
    FPos: Integer;
  public
    procedure Init(P: PByte; ASize: Integer); overload;
    procedure Init(const S: RawByteString); overload;
    procedure Init(const B: TBytes); overload;
    function AtEnd: Boolean;
    function Position: Integer;
    function Remaining: Integer;
    function PeekByte: Byte;
    function ReadByte: Byte;
    function ReadRawSlice(StartPos, Len: Integer): RawByteString;
    function ReadBytesSlice(StartPos, Len: Integer): TBytes;
    function ReadHeader(out AMajor: Byte; out AVal: UInt64; out AAddInfo: Byte): Boolean;
    function ReadInt64(out AVal: Int64): Boolean;
    function ReadUInt64(out AVal: UInt64): Boolean;
    function ReadTextString(out S: string): Boolean;
    function ReadByteStringRaw(out B: RawByteString): Boolean;
    function ReadByteString(out B: TBytes): Boolean;
    function ReadArrayHeader(out ACount: UInt64): Boolean;
    function ReadMapHeader(out APairCount: UInt64): Boolean;
    function ReadBoolean(out B: Boolean): Boolean;
    function ReadVariant(out V: Variant): Boolean;
    procedure SkipValue(ADepth: Integer = 0);
  end;

procedure TCborReader.Init(P: PByte; ASize: Integer);
begin
  FBuffer := P;
  FSize := ASize;
  FPos := 0;
end;

procedure TCborReader.Init(const S: RawByteString);
begin
  if Length(S) > 0 then
    Init(PByte(@S[1]), Length(S))
  else
    Init(nil, 0);
end;

procedure TCborReader.Init(const B: TBytes);
begin
  if Length(B) > 0 then
    Init(PByte(@B[0]), Length(B))
  else
    Init(nil, 0);
end;

function TCborReader.AtEnd: Boolean;
begin
  Result := (FPos >= FSize) or (FBuffer = nil);
end;

function TCborReader.Position: Integer;
begin
  Result := FPos;
end;

function TCborReader.Remaining: Integer;
begin
  if FPos >= FSize then
    Result := 0
  else
    Result := FSize - FPos;
end;

function TCborReader.PeekByte: Byte;
begin
  if FPos < FSize then
    Result := FBuffer[FPos]
  else
    Result := 0;
end;

function TCborReader.ReadByte: Byte;
begin
  if FPos < FSize then
  begin
    Result := FBuffer[FPos];
    Inc(FPos);
  end
  else
    Result := 0;
end;

function TCborReader.ReadRawSlice(StartPos, Len: Integer): RawByteString;
begin
  if Len <= 0 then Exit('');
  SetLength(Result, Len);
  Move(FBuffer[StartPos], Result[1], Len);
end;

function TCborReader.ReadBytesSlice(StartPos, Len: Integer): TBytes;
begin
  if Len <= 0 then Exit(nil);
  SetLength(Result, Len);
  Move(FBuffer[StartPos], Result[0], Len);
end;

function TCborReader.ReadHeader(out AMajor: Byte; out AVal: UInt64; out AAddInfo: Byte): Boolean;
var
  InitialByte: Byte;
  U8: UInt8;
  U16: Word;
  U32: UInt32;
  U64: UInt64;
begin
  Result := False;
  AMajor := 0;
  AVal := 0;
  AAddInfo := 0;
  if FPos >= FSize then Exit;

  InitialByte := FBuffer[FPos];
  Inc(FPos);
  AMajor := InitialByte shr 5;
  AAddInfo := InitialByte and $1F;

  if AAddInfo < 24 then
  begin
    AVal := AAddInfo;
    Result := True;
  end
  else if AAddInfo = 24 then
  begin
    if FPos + 1 > FSize then Exit;
    U8 := FBuffer[FPos];
    Inc(FPos);
    AVal := U8;
    Result := True;
  end
  else if AAddInfo = 25 then
  begin
    if FPos + 2 > FSize then Exit;
    Move(FBuffer[FPos], U16, 2);
    Inc(FPos, 2);
    AVal := BEtoN(U16);
    Result := True;
  end
  else if AAddInfo = 26 then
  begin
    if FPos + 4 > FSize then Exit;
    Move(FBuffer[FPos], U32, 4);
    Inc(FPos, 4);
    AVal := BEtoN(U32);
    Result := True;
  end
  else if AAddInfo = 27 then
  begin
    if FPos + 8 > FSize then Exit;
    Move(FBuffer[FPos], U64, 8);
    Inc(FPos, 8);
    AVal := BEtoN(U64);
    Result := True;
  end;
end;

function TCborReader.ReadInt64(out AVal: Int64): Boolean;
var
  Major, AddInfo: Byte;
  UVal: UInt64;
begin
  Result := False;
  AVal := 0;
  if not ReadHeader(Major, UVal, AddInfo) then Exit;
  if Major = 0 then
  begin
    AVal := Int64(UVal);
    Result := True;
  end
  else if Major = 1 then
  begin
    AVal := -1 - Int64(UVal);
    Result := True;
  end;
end;

function TCborReader.ReadUInt64(out AVal: UInt64): Boolean;
var
  Major, AddInfo: Byte;
begin
  Result := False;
  AVal := 0;
  if not ReadHeader(Major, AVal, AddInfo) then Exit;
  Result := (Major = 0);
end;

function TCborReader.ReadTextString(out S: string): Boolean;
var
  Major, AddInfo: Byte;
  UVal: UInt64;
  Raw: RawByteString;
begin
  Result := False;
  S := '';
  if not ReadHeader(Major, UVal, AddInfo) then Exit;
  if Major <> 3 then Exit;
  if UVal > UInt64(Remaining) then Exit;
  if UVal = 0 then
  begin
    S := '';
    Exit(True);
  end;
  SetLength(Raw, UVal);
  Move(FBuffer[FPos], Raw[1], UVal);
  Inc(FPos, UVal);
  S := String(Raw);
  Result := True;
end;

function TCborReader.ReadByteStringRaw(out B: RawByteString): Boolean;
var
  Major, AddInfo: Byte;
  UVal: UInt64;
begin
  Result := False;
  B := '';
  if not ReadHeader(Major, UVal, AddInfo) then Exit;
  if Major <> 2 then Exit;
  if UVal > UInt64(Remaining) then Exit;
  if UVal = 0 then
  begin
    B := '';
    Exit(True);
  end;
  SetLength(B, UVal);
  Move(FBuffer[FPos], B[1], UVal);
  Inc(FPos, UVal);
  Result := True;
end;

function TCborReader.ReadByteString(out B: TBytes): Boolean;
var
  Raw: RawByteString;
begin
  Result := ReadByteStringRaw(Raw);
  if Result then
  begin
    SetLength(B, Length(Raw));
    if Length(Raw) > 0 then
      Move(Raw[1], B[0], Length(Raw));
  end
  else
    B := nil;
end;

function TCborReader.ReadArrayHeader(out ACount: UInt64): Boolean;
var
  Major, AddInfo: Byte;
begin
  Result := False;
  ACount := 0;
  if not ReadHeader(Major, ACount, AddInfo) then Exit;
  Result := (Major = 4);
end;

function TCborReader.ReadMapHeader(out APairCount: UInt64): Boolean;
var
  Major, AddInfo: Byte;
begin
  Result := False;
  APairCount := 0;
  if not ReadHeader(Major, APairCount, AddInfo) then Exit;
  Result := (Major = 5);
end;

function TCborReader.ReadBoolean(out B: Boolean): Boolean;
var
  Major, AddInfo: Byte;
  UVal: UInt64;
begin
  Result := False;
  B := False;
  if not ReadHeader(Major, UVal, AddInfo) then Exit;
  if Major = 7 then
  begin
    if AddInfo = 20 then
    begin
      B := False;
      Result := True;
    end
    else if AddInfo = 21 then
    begin
      B := True;
      Result := True;
    end;
  end;
end;

function TCborReader.ReadVariant(out V: Variant): Boolean;
var
  SavePos: Integer;
  Major, AddInfo: Byte;
  UVal: UInt64;
  I64: Int64;
  S: string;
  RawBytes: RawByteString;
  D: Double;
  BE: UInt64;
begin
  Result := False;
  V := Null;
  SavePos := FPos;
  if not ReadHeader(Major, UVal, AddInfo) then Exit;

  case Major of
    0:
    begin
      V := Int64(UVal);
      Result := True;
    end;
    1:
    begin
      I64 := -1 - Int64(UVal);
      V := I64;
      Result := True;
    end;
    2:
    begin
      FPos := SavePos;
      if ReadByteStringRaw(RawBytes) then
      begin
        V := RawBytes;
        Result := True;
      end;
    end;
    3:
    begin
      FPos := SavePos;
      if ReadTextString(S) then
      begin
        V := S;
        Result := True;
      end;
    end;
    7:
    begin
      if AddInfo = 20 then
      begin
        V := False;
        Result := True;
      end
      else if AddInfo = 21 then
      begin
        V := True;
        Result := True;
      end
      else if AddInfo = 22 then
      begin
        V := Null;
        Result := True;
      end
      else if (AddInfo = 27) and (Remaining >= 8) then
      begin
        Move(FBuffer[FPos], BE, 8);
        Inc(FPos, 8);
        BE := BEtoN(BE);
        Move(BE, D, 8);
        V := D;
        Result := True;
      end
      else
      begin
        V := Null;
        Result := True;
      end;
    end;
  else
    FPos := SavePos;
    SkipValue;
    V := Null;
    Result := True;
  end;
end;

procedure TCborReader.SkipValue(ADepth: Integer);
var
  Major, AddInfo: Byte;
  UVal, I: UInt64;
begin
  if ADepth > MAX_CWT_DEPTH then
    raise ECWTMalformed.Create('CBOR maximum nesting depth exceeded');
  if not ReadHeader(Major, UVal, AddInfo) then Exit;

  case Major of
    0, 1: ; // Header consumed value
    2, 3:
    begin
      if UVal > UInt64(Remaining) then
        raise ECWTMalformed.Create('CBOR string length exceeds stream boundaries');
      Inc(FPos, UVal);
    end;
    4:
    begin
      for I := 1 to UVal do
        SkipValue(ADepth + 1);
    end;
    5:
    begin
      for I := 1 to UVal * 2 do
        SkipValue(ADepth + 1);
    end;
    6:
    begin
      SkipValue(ADepth + 1);
    end;
    7:
    begin
      if AddInfo = 24 then Inc(FPos, 1)
      else if AddInfo = 25 then Inc(FPos, 2)
      else if AddInfo = 26 then Inc(FPos, 4)
      else if AddInfo = 27 then Inc(FPos, 8);
    end;
  end;
end;

{ TCWTPayload }

function TCWTPayload.GetExp: Int64;
var
  Minutes: Integer;
  vIat, vExp: TDateTime;
begin
  if Fexp = 0 then
  begin
    Minutes := StrToIntDef(Zenith.Env.GetEnvVariable(CWT_EXPIRATION_VARIABLE, '1440'), 1440);
    vIat := UnixToDateTime(GetIat, False);
    vExp := IncMinute(vIat, Minutes);
    Fexp := DateTimeToUnix(vExp, False);
  end;
  Result := Fexp;
end;

function TCWTPayload.GetIat: Int64;
begin
  if Fiat = 0 then
    Fiat := DateTimeToUnix(Now, False);
  Result := Fiat;
end;

function TCWTPayload.GetCustomValues(const Name: string): Variant;
var
  Idx: Integer;
begin
  Idx := FCustomValues.IndexOf(Name);
  if Idx >= 0 then
    Result := FCustomValues.Data[Idx]
  else
    Result := Null;
end;

procedure TCWTPayload.SetCustomValues(const Name: string; const AValue: Variant);
begin
  FCustomValues.KeyData[Name] := AValue;
end;

procedure TCWTPayload.SetCustomClaim(const AName: string; const AValue: Variant);
begin
  FCustomValues.KeyData[AName] := AValue;
end;

function TCWTPayload.GetCustomClaim(const AName: string; const ADef: Variant): Variant;
var
  Idx: Integer;
begin
  Idx := FCustomValues.IndexOf(AName);
  if Idx >= 0 then
    Result := FCustomValues.Data[Idx]
  else
    Result := ADef;
end;

function TCWTPayload.HasCustomClaim(const AName: string): Boolean;
begin
  Result := FCustomValues.IndexOf(AName) >= 0;
end;

function TCWTPayload.HasRole(const ARole: string): Boolean;
var
  Target: string;
begin
  Target := Trim(ARole);
  if Target.IsEmpty then Exit(False);
  if SameText(Frole, Target) or (Frole = '*') then Exit(True);
  if Assigned(FRoles) then
  begin
    if FRoles.IndexOf('*') >= 0 then Exit(True);
    if FRoles.IndexOf(Target) >= 0 then Exit(True);
  end;
  Result := False;
end;

function TCWTPayload.HasPermission(const APermission: string): Boolean;
var
  Target: string;
begin
  Target := Trim(APermission);
  if Target.IsEmpty then Exit(False);
  if Assigned(FPermissions) then
  begin
    if (FPermissions.IndexOf('*') >= 0) or (FPermissions.IndexOf('ALL') >= 0) then Exit(True);
    if FPermissions.IndexOf(Target) >= 0 then Exit(True);
  end;
  Result := False;
end;

function TCWTPayload.ToSecurityContext: TZSecurityContext;
var
  I: Integer;
  K: string;
begin
  Result := TZSecurityContext.CreateAuthenticated(Fsub);

  if not Frole.IsEmpty then
    Result.Roles.Add(Frole);
  if Assigned(FRoles) then
  begin
    for I := 0 to FRoles.Count - 1 do
      if Result.Roles.IndexOf(FRoles[I]) < 0 then
        Result.Roles.Add(FRoles[I]);
  end;

  if Assigned(FPermissions) then
  begin
    for I := 0 to FPermissions.Count - 1 do
      if Result.Permissions.IndexOf(FPermissions[I]) < 0 then
        Result.Permissions.Add(FPermissions[I]);
  end;

  if Forg_id <> 0 then
    Result.Attributes.Add('org_id', Forg_id);
  if Fent_id <> 0 then
  begin
    Result.Attributes.Add('ent_id', Fent_id);
    Result.Attributes.Add('empresa_id', Fent_id);
  end;
  if not Fiss.IsEmpty then
    Result.Attributes.Add('iss', Fiss);
  if Exp <> 0 then
    Result.Attributes.Add('exp', Exp);
  if Iat <> 0 then
    Result.Attributes.Add('iat', Iat);

  if Assigned(FCustomValues) then
  begin
    for I := 0 to FCustomValues.Count - 1 do
    begin
      K := FCustomValues.Keys[I];
      case VarType(FCustomValues.Data[I]) of
        varBoolean: Result.Attributes.Add(K, Boolean(FCustomValues.Data[I]));
        varSmallInt, varInteger, varShortInt, varByte, varWord, varLongWord, varInt64, varQWord:
          Result.Attributes.Add(K, Int64(FCustomValues.Data[I]));
        varSingle, varDouble, varCurrency:
          Result.Attributes.Add(K, Double(FCustomValues.Data[I]));
      else
        Result.Attributes.Add(K, VarToStr(FCustomValues.Data[I]));
      end;
    end;
  end;
end;

procedure TCWTPayload.FromSecurityContext(const ASec: TZSecurityContext);
var
  I: Integer;
begin
  Fsub := ASec.Subject;
  if Assigned(ASec.Roles) and (ASec.Roles.Count > 0) then
  begin
    Frole := ASec.Roles[0];
    for I := 0 to ASec.Roles.Count - 1 do
      if FRoles.IndexOf(ASec.Roles[I]) < 0 then
        FRoles.Add(ASec.Roles[I]);
  end;

  if Assigned(ASec.Permissions) then
  begin
    for I := 0 to ASec.Permissions.Count - 1 do
      if FPermissions.IndexOf(ASec.Permissions[I]) < 0 then
        FPermissions.Add(ASec.Permissions[I]);
  end;

  Forg_id := ASec.GetAttributeInt64('org_id', 0);
  Fent_id := ASec.GetAttributeInt64('ent_id', 0);
  if Fent_id = 0 then
    Fent_id := ASec.GetAttributeInt64('empresa_id', 0);
  Fiss := ASec.GetAttribute('iss', 'Zenith');
end;

procedure TCWTPayload.Refresh;
begin
  Fexp := 0;
  Fiat := 0;
  GetExp;
end;

function TCWTPayload.CountStandardPairs: Integer;
var
  I: Integer;
  K: string;
begin
  Result := 0;
  if not Fiss.IsEmpty then Inc(Result);
  if not Fsub.IsEmpty then Inc(Result);
  if not Faud.IsEmpty then Inc(Result);
  if Exp <> 0 then Inc(Result);
  if Iat <> 0 then Inc(Result);
  if Fnbf <> 0 then Inc(Result);
  if not Fcti.IsEmpty then Inc(Result);
  if not Frole.IsEmpty then Inc(Result);
  if Forg_id <> 0 then Inc(Result);
  if Fent_id <> 0 then Inc(Result);
  if Assigned(FRoles) and (FRoles.Count > 0) then Inc(Result);
  if Assigned(FPermissions) and (FPermissions.Count > 0) then Inc(Result);

  if Assigned(FCustomValues) then
  begin
    for I := 0 to FCustomValues.Count - 1 do
    begin
      K := FCustomValues.Keys[I];
      if SameText(K, 'iss') or SameText(K, 'sub') or SameText(K, 'aud') or
         SameText(K, 'exp') or SameText(K, 'iat') or SameText(K, 'nbf') or
         SameText(K, 'cti') or SameText(K, 'role') or SameText(K, 'org_id') or
         SameText(K, 'ent_id') or SameText(K, 'roles') or SameText(K, 'permissions') then
        Continue;
      Inc(Result);
    end;
  end;
end;

procedure TCWTPayload.AfterConstruction;
begin
  inherited AfterConstruction;
  FRoles := TStringList.Create;
  FRoles.CaseSensitive := False;
  FPermissions := TStringList.Create;
  FPermissions.CaseSensitive := False;
  FCustomValues := TCWTDictionay.Create;
end;

procedure TCWTPayload.BeforeDestruction;
begin
  FRoles.Free;
  FPermissions.Free;
  FCustomValues.Free;
  inherited BeforeDestruction;
end;

{ TCWT }

class procedure TCWT.SetSecret(const ASecret: string);
begin
  GPrimaryCwtSecret := Trim(ASecret);
end;

class procedure TCWT.AddFallbackSecret(const ASecret: string);
begin
  if not Assigned(GFallbackCwtSecrets) then
    GFallbackCwtSecrets := TStringList.Create;
  if (Trim(ASecret) <> '') and (GFallbackCwtSecrets.IndexOf(Trim(ASecret)) < 0) then
    GFallbackCwtSecrets.Add(Trim(ASecret));
end;

class procedure TCWT.ClearFallbackSecrets;
begin
  if Assigned(GFallbackCwtSecrets) then
    GFallbackCwtSecrets.Clear;
end;

class function TCWT.GetSecret: string;
var
  RawEnv: string;
  P: SizeInt;
begin
  if not GPrimaryCwtSecret.IsEmpty then
    Exit(GPrimaryCwtSecret);

  RawEnv := Zenith.Env.GetEnvVariable(CWT_ENV_VARIABLE);
  if RawEnv.IsEmpty then
    RawEnv := Zenith.Env.GetEnvVariable(CWT_JWT_ENV_VARIABLE);

  if RawEnv.IsEmpty then
    raise EServerError.Create('CWT signing secret is not configured');

  P := Pos(',', RawEnv);
  if P > 0 then
    Result := Trim(Copy(RawEnv, 1, P - 1))
  else
    Result := Trim(RawEnv);
end;

class procedure TCWT.ObterTodosSegredosValidos(AList: TStrings);
var
  RawEnv, S: string;
  P: SizeInt;
begin
  AList.Clear;
  if not GPrimaryCwtSecret.IsEmpty then
    AList.Add(GPrimaryCwtSecret);

  RawEnv := Zenith.Env.GetEnvVariable(CWT_ENV_VARIABLE);
  if RawEnv.IsEmpty then
    RawEnv := Zenith.Env.GetEnvVariable(CWT_JWT_ENV_VARIABLE);

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

  if Assigned(GFallbackCwtSecrets) then
  begin
    for S in GFallbackCwtSecrets do
      if (not S.IsEmpty) and (AList.IndexOf(S) < 0) then
        AList.Add(S);
  end;
end;

function EncodeCwtPayloadBytes(Payload: TCWTPayload): RawByteString;
var
  Writer: TCborWriter;
  PairCount, I: Integer;
  K: string;
begin
  Writer.Init;
  PairCount := Payload.CountStandardPairs;
  Writer.WriteMapHeader(PairCount);

  // 1. Standard Claims (RFC 8392)
  if not Payload.iss.IsEmpty then
  begin
    Writer.WriteUInt(CWT_CLAIM_ISS);
    Writer.WriteTextString(Payload.iss);
  end;

  if not Payload.sub.IsEmpty then
  begin
    Writer.WriteUInt(CWT_CLAIM_SUB);
    Writer.WriteTextString(Payload.sub);
  end;

  if not Payload.aud.IsEmpty then
  begin
    Writer.WriteUInt(CWT_CLAIM_AUD);
    Writer.WriteTextString(Payload.aud);
  end;

  if Payload.exp <> 0 then
  begin
    Writer.WriteUInt(CWT_CLAIM_EXP);
    Writer.WriteInt(Payload.exp);
  end;

  if Payload.nbf <> 0 then
  begin
    Writer.WriteUInt(CWT_CLAIM_NBF);
    Writer.WriteInt(Payload.nbf);
  end;

  if Payload.iat <> 0 then
  begin
    Writer.WriteUInt(CWT_CLAIM_IAT);
    Writer.WriteInt(Payload.iat);
  end;

  if not Payload.cti.IsEmpty then
  begin
    Writer.WriteUInt(CWT_CLAIM_CTI);
    Writer.WriteTextString(Payload.cti);
  end;

  // 2. Corporate Claims
  if not Payload.role.IsEmpty then
  begin
    Writer.WriteTextString('role');
    Writer.WriteTextString(Payload.role);
  end;

  if Payload.org_id <> 0 then
  begin
    Writer.WriteTextString('org_id');
    Writer.WriteInt(Payload.org_id);
  end;

  if Payload.ent_id <> 0 then
  begin
    Writer.WriteTextString('ent_id');
    Writer.WriteInt(Payload.ent_id);
  end;

  if Assigned(Payload.Roles) and (Payload.Roles.Count > 0) then
  begin
    Writer.WriteTextString('roles');
    Writer.WriteArrayHeader(Payload.Roles.Count);
    for I := 0 to Payload.Roles.Count - 1 do
      Writer.WriteTextString(Payload.Roles[I]);
  end;

  if Assigned(Payload.Permissions) and (Payload.Permissions.Count > 0) then
  begin
    Writer.WriteTextString('permissions');
    Writer.WriteArrayHeader(Payload.Permissions.Count);
    for I := 0 to Payload.Permissions.Count - 1 do
      Writer.WriteTextString(Payload.Permissions[I]);
  end;

  // 3. Custom Claims
  if Assigned(Payload.FCustomValues) then
  begin
    for I := 0 to Payload.FCustomValues.Count - 1 do
    begin
      K := Payload.FCustomValues.Keys[I];
      if SameText(K, 'iss') or SameText(K, 'sub') or SameText(K, 'aud') or
         SameText(K, 'exp') or SameText(K, 'iat') or SameText(K, 'nbf') or
         SameText(K, 'cti') or SameText(K, 'role') or SameText(K, 'org_id') or
         SameText(K, 'ent_id') or SameText(K, 'roles') or SameText(K, 'permissions') then
        Continue;
      Writer.WriteTextString(K);
      Writer.WriteVariant(Payload.FCustomValues.Data[I]);
    end;
  end;

  Result := Writer.Data;
end;

class function TCWT.GenerateTokenRaw(Payload: TCWTPayload): RawByteString;
var
  ProtMapWriter, ProtBstrWriter, PayloadBstrWriter: TCborWriter;
  SigWriter, OuterWriter: TCborWriter;
  ProtMapBytes, ProtBstrBytes, PayloadRawBytes, PayloadBstrBytes: RawByteString;
  SigStructureBytes, SigBytes: RawByteString;
  Key: string;
begin
  Key := GetSecret;

  // 1. Protected Header Map: {1: -7} (alg: -7 HMAC-SHA256)
  ProtMapWriter.Init;
  ProtMapWriter.WriteMapHeader(1);
  ProtMapWriter.WriteUInt(COSE_HEADER_ALG);
  ProtMapWriter.WriteInt(COSE_ALG_ES256_OR_HMAC);
  ProtMapBytes := ProtMapWriter.Data;

  // Protected Header as bstr
  ProtBstrWriter.Init;
  ProtBstrWriter.WriteByteString(ProtMapBytes);
  ProtBstrBytes := ProtBstrWriter.Data;

  // 2. Payload Map as bstr
  PayloadRawBytes := EncodeCwtPayloadBytes(Payload);
  PayloadBstrWriter.Init;
  PayloadBstrWriter.WriteByteString(PayloadRawBytes);
  PayloadBstrBytes := PayloadBstrWriter.Data;

  // 3. COSE Sig_structure for COSE_Sign1 (RFC 8152 Section 4.4):
  // [ context: "Signature1", body_protected: bstr, external_aad: bstr, payload: bstr ]
  SigWriter.Init;
  SigWriter.WriteArrayHeader(4);
  SigWriter.WriteTextString('Signature1');
  SigWriter.WriteBuffer(ProtBstrBytes[1], Length(ProtBstrBytes));
  SigWriter.WriteByteString(''); // external_aad: empty bstr ($40)
  SigWriter.WriteBuffer(PayloadBstrBytes[1], Length(PayloadBstrBytes));
  SigStructureBytes := SigWriter.Data;

  // Calculate HMAC-SHA256 signature
  SigBytes := RawByteString(HMACSHA256(Key, String(SigStructureBytes)));

  // 4. Outer COSE_Sign1 structure:
  // [ protected: bstr, unprotected: map, payload: bstr, signature: bstr ]
  OuterWriter.Init;
  OuterWriter.WriteArrayHeader(4);
  OuterWriter.WriteBuffer(ProtBstrBytes[1], Length(ProtBstrBytes)); // item 0: protected bstr
  OuterWriter.WriteMapHeader(0);                                   // item 1: unprotected empty map ($A0)
  OuterWriter.WriteBuffer(PayloadBstrBytes[1], Length(PayloadBstrBytes)); // item 2: payload bstr
  OuterWriter.WriteByteString(SigBytes);                           // item 3: signature bstr

  Result := OuterWriter.Data;
end;

class function TCWT.GenerateToken(Payload: TCWTPayload): TBytes;
var
  Raw: RawByteString;
begin
  Raw := GenerateTokenRaw(Payload);
  if Length(Raw) = 0 then Exit(nil);
  SetLength(Result, Length(Raw));
  Move(Raw[1], Result[0], Length(Raw));
end;

class function TCWT.GenerateToken(Payload: TCWTPayload; AsBase64Url: Boolean): string;
begin
  if AsBase64Url then
    Result := GenerateTokenBase64Url(Payload)
  else
    Result := String(GenerateTokenRaw(Payload));
end;

class function TCWT.GenerateTokenBase64Url(Payload: TCWTPayload): string;
begin
  Result := EncodeBytesBase64UrlSafe(GenerateTokenRaw(Payload));
end;

class function TCWT.GenerateTokenHex(Payload: TCWTPayload): string;
var
  Raw: RawByteString;
  I: Integer;
begin
  Raw := GenerateTokenRaw(Payload);
  Result := '';
  for I := 1 to Length(Raw) do
    Result := Result + IntToHex(Byte(Raw[I]), 2);
end;

class function TCWT.ValidateToken(const Token: RawByteString; AllowExpiredWithinGrace: Boolean; MaxGraceSeconds: Int64): TCWTPayload;
var
  Reader: TCborReader;
  FirstByte: Byte;
  TagVal, ArrayCount, PairCount, ItemCount, I, J: UInt64;
  ProtStart, ProtLen, PayloadStart, PayloadLen: Integer;
  ProtBstrSlice, PayloadBstrSlice: RawByteString;
  ProtBytes, PayloadBytes, SignatureRaw: RawByteString;
  ProtReader, PayloadReader: TCborReader;
  Major, AddInfo: Byte;
  AlgIsOk, SigMatches: Boolean;
  AlgInt: Int64;
  AlgStr, KeyStr: string;
  IntKey: Int64;
  StrVal: string;
  VariantVal: Variant;
  SigStructureWriter: TCborWriter;
  SigStructureBytes, ComputedSig: RawByteString;
  SecretList: TStringList;
  SecretKey: string;
  NowUnix: Int64;
begin
  Result := nil;
  if Length(Token) < 8 then
    raise ECWTMalformed.Create('Token is too short or empty');

  Reader.Init(Token);

  // 1. Unwrap optional COSE Sign1 (18) or CWT (61) tags
  FirstByte := Reader.PeekByte;
  if (FirstByte = $D2) or (FirstByte = $D8) then
  begin
    if Reader.ReadHeader(Major, TagVal, AddInfo) and (Major = 6) then
    begin
      // If tag 61, it might contain tag 18 inside
      if (TagVal = CWT_TAG) and (Reader.PeekByte = $D2) then
        Reader.ReadHeader(Major, TagVal, AddInfo);
    end;
  end;

  // 2. Read outer COSE_Sign1 Array of 4 items
  if (not Reader.ReadArrayHeader(ArrayCount)) or (ArrayCount <> 4) then
    raise ECWTMalformed.Create('Malformed CWT: must be a COSE_Sign1 array of 4 items');

  // Item 0: protected header (bstr)
  ProtStart := Reader.Position;
  if not Reader.ReadByteStringRaw(ProtBytes) then
    raise ECWTMalformed.Create('Malformed CWT: protected header must be a byte string');
  ProtLen := Reader.Position - ProtStart;
  ProtBstrSlice := Reader.ReadRawSlice(ProtStart, ProtLen);

  // Validate algorithm inside protected header
  AlgIsOk := False;
  if Length(ProtBytes) > 0 then
  begin
    ProtReader.Init(ProtBytes);
    if ProtReader.ReadMapHeader(PairCount) then
    begin
      for I := 1 to PairCount do
      begin
        // Check key
        if ProtReader.ReadInt64(IntKey) and (IntKey = COSE_HEADER_ALG) then
        begin
          if ProtReader.ReadInt64(AlgInt) then
          begin
            if (AlgInt = COSE_ALG_ES256_OR_HMAC) or (AlgInt = COSE_ALG_HMAC_256_256) then
              AlgIsOk := True;
          end
          else if ProtReader.ReadTextString(AlgStr) then
          begin
            if SameText(AlgStr, COSE_ALG_HS256_STR) or SameText(AlgStr, 'HMAC-SHA256') then
              AlgIsOk := True;
          end;
        end
        else
          ProtReader.SkipValue;
      end;
    end;
  end;
  if not AlgIsOk then
    raise ECWTAlgorithmNotSupported.Create('Unsupported COSE algorithm in CWT protected header');

  // Item 1: unprotected map
  if not Reader.ReadMapHeader(PairCount) then
    raise ECWTMalformed.Create('Malformed CWT: unprotected header must be a map');
  for I := 1 to PairCount * 2 do
    Reader.SkipValue;

  // Item 2: payload (bstr)
  PayloadStart := Reader.Position;
  if not Reader.ReadByteStringRaw(PayloadBytes) then
    raise ECWTMalformed.Create('Malformed CWT: payload must be a byte string');
  PayloadLen := Reader.Position - PayloadStart;
  PayloadBstrSlice := Reader.ReadRawSlice(PayloadStart, PayloadLen);

  // Item 3: signature (bstr)
  if not Reader.ReadByteStringRaw(SignatureRaw) then
    raise ECWTMalformed.Create('Malformed CWT: signature must be a byte string');
  if Length(SignatureRaw) <> 32 then
    raise ECWTSignatureInvalid.Create('Invalid CWT signature length');

  // 3. Cryptographic Signature Verification over COSE Sig_structure
  SigStructureWriter.Init;
  SigStructureWriter.WriteArrayHeader(4);
  SigStructureWriter.WriteTextString('Signature1');
  SigStructureWriter.WriteBuffer(ProtBstrSlice[1], Length(ProtBstrSlice));
  SigStructureWriter.WriteByteString(''); // external_aad: empty bstr ($40)
  SigStructureWriter.WriteBuffer(PayloadBstrSlice[1], Length(PayloadBstrSlice));
  SigStructureBytes := SigStructureWriter.Data;

  SigMatches := False;
  SecretList := TStringList.Create;
  try
    ObterTodosSegredosValidos(SecretList);
    for SecretKey in SecretList do
    begin
      ComputedSig := RawByteString(HMACSHA256(SecretKey, String(SigStructureBytes)));
      if ConstantTimeEquals(String(ComputedSig), String(SignatureRaw)) then
      begin
        SigMatches := True;
        Break;
      end;
    end;
  finally
    SecretList.Free;
  end;

  if not SigMatches then
    raise ECWTSignatureInvalid.Create('CWT signature verification failed');

  // 4. Decode Claims from PayloadBytes (Zero JSON Parsing)
  Result := TCWTPayload.Create;
  try
    PayloadReader.Init(PayloadBytes);
    if not PayloadReader.ReadMapHeader(PairCount) then
      raise ECWTMalformed.Create('Malformed CWT payload: expected CBOR map');

    for I := 1 to PairCount do
    begin
      FirstByte := PayloadReader.PeekByte;
      Major := FirstByte shr 5;

      if (Major = 0) or (Major = 1) then
      begin
        // Integer key
        PayloadReader.ReadInt64(IntKey);
        case IntKey of
          CWT_CLAIM_ISS: PayloadReader.ReadTextString(Result.Fiss);
          CWT_CLAIM_SUB: PayloadReader.ReadTextString(Result.Fsub);
          CWT_CLAIM_AUD: PayloadReader.ReadTextString(Result.Faud);
          CWT_CLAIM_EXP: PayloadReader.ReadInt64(Result.Fexp);
          CWT_CLAIM_NBF: PayloadReader.ReadInt64(Result.Fnbf);
          CWT_CLAIM_IAT: PayloadReader.ReadInt64(Result.Fiat);
          CWT_CLAIM_CTI: PayloadReader.ReadTextString(Result.Fcti);
        else
          if PayloadReader.ReadVariant(VariantVal) then
            Result.FCustomValues.KeyData[IntToStr(IntKey)] := VariantVal;
        end;
      end
      else if Major = 3 then
      begin
        // Text string key
        PayloadReader.ReadTextString(KeyStr);
        if SameText(KeyStr, 'iss') then
          PayloadReader.ReadTextString(Result.Fiss)
        else if SameText(KeyStr, 'sub') or SameText(KeyStr, 'user') then
          PayloadReader.ReadTextString(Result.Fsub)
        else if SameText(KeyStr, 'aud') then
          PayloadReader.ReadTextString(Result.Faud)
        else if SameText(KeyStr, 'exp') then
          PayloadReader.ReadInt64(Result.Fexp)
        else if SameText(KeyStr, 'iat') then
          PayloadReader.ReadInt64(Result.Fiat)
        else if SameText(KeyStr, 'nbf') then
          PayloadReader.ReadInt64(Result.Fnbf)
        else if SameText(KeyStr, 'cti') then
          PayloadReader.ReadTextString(Result.Fcti)
        else if SameText(KeyStr, 'role') then
        begin
          PayloadReader.ReadTextString(Result.Frole);
          if Result.FRoles.IndexOf(Result.Frole) < 0 then
            Result.FRoles.Add(Result.Frole);
        end
        else if SameText(KeyStr, 'org_id') or SameText(KeyStr, 'orgId') then
          PayloadReader.ReadInt64(Result.Forg_id)
        else if SameText(KeyStr, 'ent_id') or SameText(KeyStr, 'entId') or SameText(KeyStr, 'empresa_id') then
          PayloadReader.ReadInt64(Result.Fent_id)
        else if SameText(KeyStr, 'roles') then
        begin
          if (PayloadReader.PeekByte shr 5) = 4 then
          begin
            PayloadReader.ReadArrayHeader(ItemCount);
            for J := 1 to ItemCount do
            begin
              PayloadReader.ReadTextString(StrVal);
              if Result.FRoles.IndexOf(StrVal) < 0 then
                Result.FRoles.Add(StrVal);
            end;
          end
          else if PayloadReader.ReadTextString(StrVal) then
            Result.FRoles.CommaText := StrVal;
        end
        else if SameText(KeyStr, 'permissions') then
        begin
          if (PayloadReader.PeekByte shr 5) = 4 then
          begin
            PayloadReader.ReadArrayHeader(ItemCount);
            for J := 1 to ItemCount do
            begin
              PayloadReader.ReadTextString(StrVal);
              if Result.FPermissions.IndexOf(StrVal) < 0 then
                Result.FPermissions.Add(StrVal);
            end;
          end
          else if PayloadReader.ReadTextString(StrVal) then
            Result.FPermissions.CommaText := StrVal;
        end
        else
        begin
          if PayloadReader.ReadVariant(VariantVal) then
            Result.FCustomValues.KeyData[KeyStr] := VariantVal;
        end;
      end
      else
      begin
        PayloadReader.SkipValue;
        PayloadReader.SkipValue;
      end;
    end;

    // 5. Expiration & Temporal Validation
    NowUnix := DateTimeToUnix(Now, False);
    if Result.exp <> 0 then
    begin
      if Result.exp <= NowUnix then
      begin
        if not (AllowExpiredWithinGrace and (Result.exp + MaxGraceSeconds >= NowUnix)) then
          raise ECWTExpired.Create('CWT token expired');
      end;
    end;

    if (Result.nbf <> 0) and (Result.nbf > NowUnix) then
      raise ECWTException.Create('CWT token is not active yet (nbf)');

  except
    on E: Exception do
    begin
      Result.Free;
      Result := nil;
      raise;
    end;
  end;
end;

class function TCWT.ValidateToken(const Token: TBytes; AllowExpiredWithinGrace: Boolean; MaxGraceSeconds: Int64): TCWTPayload;
var
  Raw: RawByteString;
begin
  if Length(Token) = 0 then
    raise ECWTMalformed.Create('Token is empty');
  SetLength(Raw, Length(Token));
  Move(Token[0], Raw[1], Length(Token));
  Result := ValidateToken(Raw, AllowExpiredWithinGrace, MaxGraceSeconds);
end;

class function TCWT.ValidateToken(const TokenStr: string; AllowExpiredWithinGrace: Boolean; MaxGraceSeconds: Int64): TCWTPayload;
var
  Bytes: TBytes;
begin
  Bytes := StringToTokenBytes(TokenStr);
  if Length(Bytes) = 0 then
    raise ECWTMalformed.Create('Token is empty or invalid format');
  Result := ValidateToken(Bytes, AllowExpiredWithinGrace, MaxGraceSeconds);
end;

class function TCWT.ValidateToContext(const Token: TBytes; AllowExpiredWithinGrace: Boolean; MaxGraceSeconds: Int64): TZSecurityContext;
var
  Payload: TCWTPayload;
begin
  Payload := ValidateToken(Token, AllowExpiredWithinGrace, MaxGraceSeconds);
  try
    Result := Payload.ToSecurityContext;
  finally
    Payload.Free;
  end;
end;

class function TCWT.ValidateToContext(const Token: RawByteString; AllowExpiredWithinGrace: Boolean; MaxGraceSeconds: Int64): TZSecurityContext;
var
  Payload: TCWTPayload;
begin
  Payload := ValidateToken(Token, AllowExpiredWithinGrace, MaxGraceSeconds);
  try
    Result := Payload.ToSecurityContext;
  finally
    Payload.Free;
  end;
end;

class function TCWT.ValidateToContext(const TokenStr: string; AllowExpiredWithinGrace: Boolean; MaxGraceSeconds: Int64): TZSecurityContext;
var
  Payload: TCWTPayload;
begin
  Payload := ValidateToken(TokenStr, AllowExpiredWithinGrace, MaxGraceSeconds);
  try
    Result := Payload.ToSecurityContext;
  finally
    Payload.Free;
  end;
end;

class function TCWT.CompareTokenSizes(Payload: TCWTPayload; out ACwtBytes, AJwtBytes: Integer; out AReductionPct: Double): string;
var
  CwtRaw: RawByteString;
  JwtPayload: TPayLoad;
  JwtStr: string;
  I: Integer;
begin
  CwtRaw := GenerateTokenRaw(Payload);
  ACwtBytes := Length(CwtRaw);

  JwtPayload := TPayLoad.Create;
  try
    JwtPayload.exp := Payload.exp;
    JwtPayload.iat := Payload.iat;
    if not Payload.sub.IsEmpty then JwtPayload.CustomValues['sub'] := Payload.sub;
    if not Payload.iss.IsEmpty then JwtPayload.CustomValues['iss'] := Payload.iss;
    if not Payload.role.IsEmpty then JwtPayload.CustomValues['role'] := Payload.role;
    if Payload.org_id <> 0 then JwtPayload.CustomValues['org_id'] := Payload.org_id;
    if Payload.ent_id <> 0 then JwtPayload.CustomValues['ent_id'] := Payload.ent_id;
    for I := 0 to Payload.FCustomValues.Count - 1 do
      JwtPayload.CustomValues[Payload.FCustomValues.Keys[I]] := Payload.FCustomValues.Data[I];

    JwtStr := TJWT.GenerateToken(JwtPayload);
    AJwtBytes := Length(JwtStr);
  finally
    JwtPayload.Free;
  end;

  if AJwtBytes > 0 then
    AReductionPct := ((AJwtBytes - ACwtBytes) / AJwtBytes) * 100.0
  else
    AReductionPct := 0.0;

  Result := Format('CWT: %d bytes (binary) vs JWT: %d bytes (Base64). Reduction: %.1f%%',
    [ACwtBytes, AJwtBytes, AReductionPct]);
end;

{ TZCWTBearerResolver }

constructor TZCWTBearerResolver.Create(AAllowJWTFallback: Boolean);
begin
  inherited Create;
  FAllowJWTFallback := AAllowJWTFallback;
end;

function TZCWTBearerResolver.Resolve(ARequest: TRequest): TZSecurityContext;
var
  AuthHeader, Token, SubVal: string;
  Payload: TPayLoad;
  PayloadJson: TJSONObject;
  JsonItem: TJSONData;
  I: Integer;
begin
  Result := TZSecurityContext.CreateAnonymous;

  AuthHeader := ARequest.Authorization;
  if AuthHeader.IsEmpty then
    AuthHeader := ARequest.GetCustomHeader('Authorization');

  AuthHeader := Trim(AuthHeader);
  if not AuthHeader.StartsWith('Bearer ', True) then
    Exit;

  Token := Trim(Copy(AuthHeader, 8, MaxInt));
  if Token.IsEmpty then
    Exit;

  // Try CWT resolution first (zero JSON parsing)
  try
    Result.FreeInternalObjects;
    Result := TCWT.ValidateToContext(Token);
    Exit;
  except
    // Fall through to JWT if allowed
  end;

  // Optional JWT Fallback
  if FAllowJWTFallback and (Pos('.', Token) > 0) then
  begin
    try
      Payload := TJWT.ValidadeToken(Token);
      if Payload = nil then Exit;
      try
        PayloadJson := GetJSON(Payload.ToJson) as TJSONObject;
        try
          if PayloadJson.Find('sub') <> nil then
            SubVal := PayloadJson.Strings['sub']
          else if PayloadJson.Find('user') <> nil then
            SubVal := PayloadJson.Strings['user']
          else
            SubVal := '';

          Result.FreeInternalObjects;
          Result := TZSecurityContext.CreateAuthenticated(SubVal);

          JsonItem := PayloadJson.Find('roles');
          if JsonItem <> nil then
          begin
            if JsonItem.JSONType = jtArray then
            begin
              for I := 0 to TJSONArray(JsonItem).Count - 1 do
                Result.Roles.Add(TJSONArray(JsonItem).Strings[I]);
            end
            else if JsonItem.JSONType = jtString then
              Result.Roles.CommaText := JsonItem.AsString;
          end
          else
          begin
            JsonItem := PayloadJson.Find('role');
            if (JsonItem <> nil) and (JsonItem.JSONType = jtString) then
              Result.Roles.Add(JsonItem.AsString);
          end;

          JsonItem := PayloadJson.Find('permissions');
          if JsonItem <> nil then
          begin
            if JsonItem.JSONType = jtArray then
            begin
              for I := 0 to TJSONArray(JsonItem).Count - 1 do
                Result.Permissions.Add(TJSONArray(JsonItem).Strings[I]);
            end
            else if JsonItem.JSONType = jtString then
              Result.Permissions.CommaText := JsonItem.AsString;
          end;

          Result.Attributes.Free;
          Result.Attributes := PayloadJson.Clone as TJSONObject;
        finally
          PayloadJson.Free;
        end;
      finally
        Payload.Free;
      end;
    except
      Result.FreeInternalObjects;
      Result := TZSecurityContext.CreateAnonymous;
    end;
  end;
end;

{ TCWTAuthentication }

constructor TCWTAuthentication.Create(const Auth: string; AAllowGracePeriod: Boolean; AMaxGraceSeconds: Int64);
begin
  inherited Create;
  FAuth := Auth;
  FAllowGracePeriod := AAllowGracePeriod;
  FMaxGraceSeconds := AMaxGraceSeconds;
  Validate;
end;

constructor TCWTAuthentication.Create(const AuthBytes: TBytes; AAllowGracePeriod: Boolean; AMaxGraceSeconds: Int64);
var
  S: string;
begin
  inherited Create;
  SetLength(S, Length(AuthBytes));
  if Length(AuthBytes) > 0 then
    Move(AuthBytes[0], S[1], Length(AuthBytes));
  FAuth := S;
  FAllowGracePeriod := AAllowGracePeriod;
  FMaxGraceSeconds := AMaxGraceSeconds;
  Validate;
end;

destructor TCWTAuthentication.Destroy;
begin
  if Assigned(FPayload) then
    FPayload.Free;
  inherited Destroy;
end;

procedure TCWTAuthentication.SetPayload(AValue: TCWTPayload);
begin
  if FPayload = AValue then Exit;
  if Assigned(FPayload) then
    FPayload.Free;
  FPayload := AValue;
end;

procedure TCWTAuthentication.Validate;
var
  Token: string;
begin
  Token := Trim(FAuth);
  if Token.StartsWith('Bearer ', True) then
    Token := Trim(Copy(Token, 8, MaxInt));

  FPayload := TCWT.ValidateToken(Token, FAllowGracePeriod, FMaxGraceSeconds);
end;

end.
