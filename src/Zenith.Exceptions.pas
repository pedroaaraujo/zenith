unit Zenith.Exceptions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Zenith.Constants;

type
  { Structured field-level error item (used in HTTP 422 Unprocessable Entity) }
  TZenithFieldError = record
    Field: string;
    Code: string;
    Message: string;
  end;

  TZenithFieldErrorArray = array of TZenithFieldError;

  { ========================================================================= }
  { EZenithException: Base exception directly mappable to RFC 9457            }
  { Problem Details for HTTP APIs (application/problem+json and +cbor).       }
  { ========================================================================= }
  EZenithException = class(Exception)
  private
    FStatusCode: Integer;
    FErrorType: string;
    FTitle: string;
    FDetail: string;
    FInstance: string;
    FExtensions: TJSONObject;
    function GetExtensions: TJSONObject;
    function HasExtensions: Boolean; inline;
  protected
    procedure PopulateExtensions(AProblemObj: TJSONObject); virtual;
  public
    constructor Create(const ADetail: string;
      AStatusCode: Integer = HTTP_STATUS_INTERNAL_SERVER_ERROR;
      const ATitle: string = '';
      const AErrorType: string = '';
      const AInstance: string = '');
    constructor CreateFmt(const AFormat: string; const AArgs: array of const);
    constructor CreateProblem(AStatusCode: Integer;
      const AErrorType, ATitle, ADetail: string;
      const AInstance: string = '');
    destructor Destroy; override;

    { RFC 9457 extensions (fluent interface) }
    function AddExtension(const AKey, AValue: string): EZenithException; overload;
    function AddExtension(const AKey: string; AValue: Int64): EZenithException; overload;
    function AddExtension(const AKey: string; AValue: Double): EZenithException; overload;
    function AddExtension(const AKey: string; AValue: Boolean): EZenithException; overload;
    function AddExtension(const AKey: string; AData: TJSONData): EZenithException; overload;
    function WithInstance(const AInstance: string): EZenithException;
    function WithErrorType(const AErrorType: string): EZenithException;
    function WithTitle(const ATitle: string): EZenithException;

    { RFC 9457 serialization }
    function ToProblemJsonObject: TJSONObject; virtual;
    function ToProblemJson: string; virtual;
    function ToProblemCbor: TBytes; virtual;

    property StatusCode: Integer read FStatusCode;
    property ErrorType: string read FErrorType write FErrorType;
    property Title: string read FTitle write FTitle;
    property Detail: string read FDetail write FDetail;
    property Instance: string read FInstance write FInstance;
    property Extensions: TJSONObject read GetExtensions;
  end;

  { ========================================================================= }
  { HTTP RFC 9457 Subclasses                                                  }
  { ========================================================================= }

  { 400 Bad Request }
  EZenithBadRequest = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { 401 Unauthorized }
  EZenithUnauthorized = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { 403 Forbidden }
  EZenithForbidden = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { 404 Not Found }
  EZenithNotFound = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { 405 Method Not Allowed }
  EZenithMethodNotAllowed = class(EZenithException)
  private
    FAllowedMethods: string;
  protected
    procedure PopulateExtensions(AProblemObj: TJSONObject); override;
  public
    constructor Create(const ADetail: string = ''; const AAllowedMethods: string = '';
      const AInstance: string = '');
    property AllowedMethods: string read FAllowedMethods write FAllowedMethods;
  end;

  { 409 Conflict }
  EZenithConflict = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { 412 Precondition Failed }
  EZenithPreconditionFailed = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { 413 Payload Too Large }
  EZenithPayloadTooLarge = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { 415 Unsupported Media Type }
  EZenithUnsupportedMediaType = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { 422 Unprocessable Entity (with field-level error array support) }
  EZenithUnprocessableEntity = class(EZenithException)
  private
    FErrors: TZenithFieldErrorArray;
    function GetErrorCount: Integer; inline;
  protected
    procedure PopulateExtensions(AProblemObj: TJSONObject); override;
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = ''); overload;
    constructor Create(const ADetail: string; const AErrors: array of TZenithFieldError;
      const AInstance: string = ''); overload;
    function AddFieldError(const AField, AMessage: string;
      const ACode: string = ''): EZenithUnprocessableEntity;
    property Errors: TZenithFieldErrorArray read FErrors;
    property ErrorCount: Integer read GetErrorCount;
  end;

  { 429 Too Many Requests (with RetryAfter support in seconds) }
  EZenithTooManyRequests = class(EZenithException)
  private
    FRetryAfter: Integer;
  protected
    procedure PopulateExtensions(AProblemObj: TJSONObject); override;
  public
    constructor Create(const ADetail: string = ''; ARetryAfter: Integer = 0;
      const AInstance: string = '');
    property RetryAfter: Integer read FRetryAfter write FRetryAfter;
  end;

  { 500 Internal Server Error }
  EZenithInternalError = class(EZenithException)
  public
    constructor Create(const ADetail: string = ''; const AInstance: string = '');
  end;

  { ========================================================================= }
  { Backward Compatibility Layer (preserves legacy exception signatures)      }
  { ========================================================================= }
  HTTPException = class(EZenithException)
  public
    constructor Create(const AMsg: string);
    constructor CreateFmt(const AFormat: string; const AArgs: array of const);
  end;

  EValidation = class(HTTPException);
  EConflict = class(HTTPException);
  EMissingRequiredField = class(HTTPException);
  EUnknownError = class(HTTPException);
  EUnknowError = EUnknownError; { Legacy backward compatibility alias }
  EUnauthorized = class(HTTPException);
  EForbidden = class(HTTPException);
  EResourceNotFound = class(HTTPException);
  ETooManyRequests = class(HTTPException);
  EServerError = class(HTTPException);
  EBadRequest = class(HTTPException);
  ENotFound = class(HTTPException);
  EUnprocessableEntity = class(HTTPException);

{ Helper for ergonomic construction of TZenithFieldError }
function MakeZenithFieldError(const AField, AMessage: string;
  const ACode: string = ''): TZenithFieldError;

implementation

{ =========================================================================== }
{ Lightweight internal RFC 8949 CBOR encoder (zero external dependencies)     }
{ =========================================================================== }

procedure CborWriteHeader(AStream: TStream; AMajor: Byte; AValue: UInt64);
var
  B: Byte;
  U8: Byte;
  U16: Word;
  U32: Cardinal;
  U64: UInt64;
begin
  if AValue < 24 then
  begin
    B := (AMajor shl 5) or Byte(AValue);
    AStream.WriteBuffer(B, 1);
  end
  else if AValue <= $FF then
  begin
    B := (AMajor shl 5) or 24;
    AStream.WriteBuffer(B, 1);
    U8 := Byte(AValue);
    AStream.WriteBuffer(U8, 1);
  end
  else if AValue <= $FFFF then
  begin
    B := (AMajor shl 5) or 25;
    AStream.WriteBuffer(B, 1);
    U16 := NtoBE(Word(AValue));
    AStream.WriteBuffer(U16, 2);
  end
  else if AValue <= $FFFFFFFF then
  begin
    B := (AMajor shl 5) or 26;
    AStream.WriteBuffer(B, 1);
    U32 := NtoBE(Cardinal(AValue));
    AStream.WriteBuffer(U32, 4);
  end
  else
  begin
    B := (AMajor shl 5) or 27;
    AStream.WriteBuffer(B, 1);
    U64 := NtoBE(AValue);
    AStream.WriteBuffer(U64, 8);
  end;
end;

procedure CborWriteInt64(AStream: TStream; AValue: Int64);
begin
  if AValue >= 0 then
    CborWriteHeader(AStream, 0, UInt64(AValue))
  else
    CborWriteHeader(AStream, 1, UInt64(-(AValue + 1)));
end;

procedure CborWriteDouble(AStream: TStream; AValue: Double);
var
  B: Byte;
  RawBits: UInt64;
begin
  B := $FB; { Major 7, Additional 27 = IEEE 754 float64 }
  AStream.WriteBuffer(B, 1);
  Move(AValue, RawBits, SizeOf(RawBits));
  RawBits := NtoBE(RawBits);
  AStream.WriteBuffer(RawBits, 8);
end;

procedure CborWriteText(AStream: TStream; const AText: string);
var
  Utf8Str: RawByteString;
  Len: SizeInt;
begin
  Utf8Str := UTF8Encode(UnicodeString(AText));
  Len := Length(Utf8Str);
  CborWriteHeader(AStream, 3, UInt64(Len));
  if Len > 0 then
    AStream.WriteBuffer(Utf8Str[1], Len);
end;

procedure CborWriteJsonData(AStream: TStream; AData: TJSONData);
var
  B: Byte;
  I: Integer;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then
  begin
    B := $F6; { CBOR null }
    AStream.WriteBuffer(B, 1);
    Exit;
  end;

  case AData.JSONType of
    jtBoolean:
      begin
        if AData.AsBoolean then
          B := $F5
        else
          B := $F4;
        AStream.WriteBuffer(B, 1);
      end;
    jtNumber:
      begin
        if TJSONNumber(AData).NumberType in [ntInteger, ntInt64] then
          CborWriteInt64(AStream, AData.AsInt64)
        else if TJSONNumber(AData).NumberType = ntQWord then
          CborWriteHeader(AStream, 0, AData.AsQWord)
        else
          CborWriteDouble(AStream, AData.AsFloat);
      end;
    jtString:
      CborWriteText(AStream, AData.AsString);
    jtArray:
      begin
        Arr := TJSONArray(AData);
        CborWriteHeader(AStream, 4, UInt64(Arr.Count));
        for I := 0 to Arr.Count - 1 do
          CborWriteJsonData(AStream, Arr.Items[I]);
      end;
    jtObject:
      begin
        Obj := TJSONObject(AData);
        CborWriteHeader(AStream, 5, UInt64(Obj.Count));
        for I := 0 to Obj.Count - 1 do
        begin
          CborWriteText(AStream, Obj.Names[I]);
          CborWriteJsonData(AStream, Obj.Items[I]);
        end;
      end;
  else
    B := $F6;
    AStream.WriteBuffer(B, 1);
  end;
end;

function MakeZenithFieldError(const AField, AMessage: string;
  const ACode: string): TZenithFieldError;
begin
  Result.Field := AField;
  Result.Code := ACode;
  Result.Message := AMessage;
end;

{ =========================================================================== }
{ EZenithException                                                            }
{ =========================================================================== }

constructor EZenithException.Create(const ADetail: string;
  AStatusCode: Integer; const ATitle, AErrorType, AInstance: string);
var
  EffectiveTitle: string;
  EffectiveType: string;
begin
  EffectiveTitle := ATitle;
  if EffectiveTitle = '' then
    EffectiveTitle := HttpStatusReasonPhrase(AStatusCode);

  EffectiveType := AErrorType;
  if EffectiveType = '' then
    EffectiveType := PROBLEM_TYPE_ABOUT_BLANK;

  if ADetail <> '' then
    inherited Create(ADetail)
  else
    inherited Create(EffectiveTitle);

  FStatusCode := AStatusCode;
  FErrorType := EffectiveType;
  FTitle := EffectiveTitle;
  FDetail := ADetail;
  FInstance := AInstance;
  FExtensions := nil;
end;

constructor EZenithException.CreateFmt(const AFormat: string;
  const AArgs: array of const);
begin
  Create(Format(AFormat, AArgs), HTTP_STATUS_INTERNAL_SERVER_ERROR);
end;

constructor EZenithException.CreateProblem(AStatusCode: Integer;
  const AErrorType, ATitle, ADetail, AInstance: string);
begin
  Create(ADetail, AStatusCode, ATitle, AErrorType, AInstance);
end;

destructor EZenithException.Destroy;
begin
  FreeAndNil(FExtensions);
  inherited Destroy;
end;

function EZenithException.GetExtensions: TJSONObject;
begin
  if FExtensions = nil then
    FExtensions := TJSONObject.Create;
  Result := FExtensions;
end;

function EZenithException.HasExtensions: Boolean;
begin
  Result := (FExtensions <> nil) and (FExtensions.Count > 0);
end;

procedure EZenithException.PopulateExtensions(AProblemObj: TJSONObject);
var
  I: Integer;
  Key: string;
begin
  if not HasExtensions then
    Exit;

  for I := 0 to FExtensions.Count - 1 do
  begin
    Key := FExtensions.Names[I];
    { Do not overwrite standard RFC 9457 members }
    if (Key = 'type') or (Key = 'title') or (Key = 'status') or
       (Key = 'detail') or (Key = 'instance') then
      Continue;
    AProblemObj.Add(Key, FExtensions.Items[I].Clone);
  end;
end;

function EZenithException.AddExtension(const AKey, AValue: string): EZenithException;
begin
  Extensions.Delete(AKey);
  Extensions.Add(AKey, AValue);
  Result := Self;
end;

function EZenithException.AddExtension(const AKey: string; AValue: Int64): EZenithException;
begin
  Extensions.Delete(AKey);
  Extensions.Add(AKey, AValue);
  Result := Self;
end;

function EZenithException.AddExtension(const AKey: string; AValue: Double): EZenithException;
begin
  Extensions.Delete(AKey);
  Extensions.Add(AKey, AValue);
  Result := Self;
end;

function EZenithException.AddExtension(const AKey: string; AValue: Boolean): EZenithException;
begin
  Extensions.Delete(AKey);
  Extensions.Add(AKey, AValue);
  Result := Self;
end;

function EZenithException.AddExtension(const AKey: string; AData: TJSONData): EZenithException;
begin
  Extensions.Delete(AKey);
  if AData <> nil then
    Extensions.Add(AKey, AData)
  else
    Extensions.Add(AKey, TJSONNull.Create);
  Result := Self;
end;

function EZenithException.WithInstance(const AInstance: string): EZenithException;
begin
  FInstance := AInstance;
  Result := Self;
end;

function EZenithException.WithErrorType(const AErrorType: string): EZenithException;
begin
  FErrorType := AErrorType;
  Result := Self;
end;

function EZenithException.WithTitle(const ATitle: string): EZenithException;
begin
  FTitle := ATitle;
  Result := Self;
end;

function EZenithException.ToProblemJsonObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    if FErrorType <> '' then
      Result.Add('type', FErrorType)
    else
      Result.Add('type', PROBLEM_TYPE_ABOUT_BLANK);

    if FTitle <> '' then
      Result.Add('title', FTitle)
    else
      Result.Add('title', HttpStatusReasonPhrase(FStatusCode));

    Result.Add('status', FStatusCode);

    if FDetail <> '' then
      Result.Add('detail', FDetail)
    else if Message <> '' then
      Result.Add('detail', Message);

    if FInstance <> '' then
      Result.Add('instance', FInstance);

    PopulateExtensions(Result);
  except
    Result.Free;
    raise;
  end;
end;

function EZenithException.ToProblemJson: string;
var
  Obj: TJSONObject;
begin
  Obj := ToProblemJsonObject;
  try
    Result := Obj.AsJSON;
  finally
    Obj.Free;
  end;
end;

function EZenithException.ToProblemCbor: TBytes;
var
  Obj: TJSONObject;
  Stream: TMemoryStream;
begin
  Result := nil;
  Obj := ToProblemJsonObject;
  try
    Stream := TMemoryStream.Create;
    try
      CborWriteJsonData(Stream, Obj);
      SetLength(Result, Stream.Size);
      if Stream.Size > 0 then
        Move(Stream.Memory^, Result[0], Stream.Size);
    finally
      Stream.Free;
    end;
  finally
    Obj.Free;
  end;
end;

{ =========================================================================== }
{ HTTP RFC 9457 Subclasses                                                    }
{ =========================================================================== }

constructor EZenithBadRequest.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_BAD_REQUEST, 'Bad Request',
    PROBLEM_TYPE_PREFIX + 'bad-request', AInstance);
end;

constructor EZenithUnauthorized.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_UNAUTHORIZED, 'Unauthorized',
    PROBLEM_TYPE_PREFIX + 'unauthorized', AInstance);
end;

constructor EZenithForbidden.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_FORBIDDEN, 'Forbidden',
    PROBLEM_TYPE_PREFIX + 'forbidden', AInstance);
end;

constructor EZenithNotFound.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_NOT_FOUND, 'Not Found',
    PROBLEM_TYPE_PREFIX + 'not-found', AInstance);
end;

constructor EZenithMethodNotAllowed.Create(const ADetail,
  AAllowedMethods, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_METHOD_NOT_ALLOWED, 'Method Not Allowed',
    PROBLEM_TYPE_PREFIX + 'method-not-allowed', AInstance);
  FAllowedMethods := AAllowedMethods;
end;

procedure EZenithMethodNotAllowed.PopulateExtensions(AProblemObj: TJSONObject);
begin
  if FAllowedMethods <> '' then
    AProblemObj.Add('allowedMethods', FAllowedMethods);
  inherited PopulateExtensions(AProblemObj);
end;

constructor EZenithConflict.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_CONFLICT, 'Conflict',
    PROBLEM_TYPE_PREFIX + 'conflict', AInstance);
end;

constructor EZenithPreconditionFailed.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_PRECONDITION_FAILED, 'Precondition Failed',
    PROBLEM_TYPE_PREFIX + 'precondition-failed', AInstance);
end;

constructor EZenithPayloadTooLarge.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_PAYLOAD_TOO_LARGE, 'Payload Too Large',
    PROBLEM_TYPE_PREFIX + 'payload-too-large', AInstance);
end;

constructor EZenithUnsupportedMediaType.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE, 'Unsupported Media Type',
    PROBLEM_TYPE_PREFIX + 'unsupported-media-type', AInstance);
end;

{ EZenithUnprocessableEntity }

constructor EZenithUnprocessableEntity.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_UNPROCESSABLE_ENTITY, 'Unprocessable Entity',
    PROBLEM_TYPE_PREFIX + 'unprocessable-entity', AInstance);
  SetLength(FErrors, 0);
end;

constructor EZenithUnprocessableEntity.Create(const ADetail: string;
  const AErrors: array of TZenithFieldError; const AInstance: string);
var
  I: Integer;
begin
  Create(ADetail, AInstance);
  SetLength(FErrors, Length(AErrors));
  for I := 0 to High(AErrors) do
    FErrors[I] := AErrors[I];
end;

function EZenithUnprocessableEntity.GetErrorCount: Integer;
begin
  Result := Length(FErrors);
end;

function EZenithUnprocessableEntity.AddFieldError(const AField, AMessage,
  ACode: string): EZenithUnprocessableEntity;
var
  Idx: Integer;
begin
  Idx := Length(FErrors);
  SetLength(FErrors, Idx + 1);
  FErrors[Idx].Field := AField;
  FErrors[Idx].Code := ACode;
  FErrors[Idx].Message := AMessage;
  Result := Self;
end;

procedure EZenithUnprocessableEntity.PopulateExtensions(AProblemObj: TJSONObject);
var
  ErrArray: TJSONArray;
  ErrItem: TJSONObject;
  I: Integer;
begin
  if Length(FErrors) > 0 then
  begin
    ErrArray := TJSONArray.Create;
    for I := 0 to High(FErrors) do
    begin
      ErrItem := TJSONObject.Create;
      ErrItem.Add('field', FErrors[I].Field);
      if FErrors[I].Code <> '' then
        ErrItem.Add('code', FErrors[I].Code);
      ErrItem.Add('message', FErrors[I].Message);
      ErrArray.Add(ErrItem);
    end;
    AProblemObj.Add('errors', ErrArray);
  end;
  inherited PopulateExtensions(AProblemObj);
end;

{ EZenithTooManyRequests }

constructor EZenithTooManyRequests.Create(const ADetail: string;
  ARetryAfter: Integer; const AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_TOO_MANY_REQUESTS, 'Too Many Requests',
    PROBLEM_TYPE_PREFIX + 'too-many-requests', AInstance);
  FRetryAfter := ARetryAfter;
end;

procedure EZenithTooManyRequests.PopulateExtensions(AProblemObj: TJSONObject);
begin
  if FRetryAfter > 0 then
    AProblemObj.Add('retryAfter', FRetryAfter);
  inherited PopulateExtensions(AProblemObj);
end;

{ EZenithInternalError }

constructor EZenithInternalError.Create(const ADetail, AInstance: string);
begin
  inherited Create(ADetail, HTTP_STATUS_INTERNAL_SERVER_ERROR, 'Internal Server Error',
    PROBLEM_TYPE_PREFIX + 'internal-error', AInstance);
end;

{ =========================================================================== }
{ HTTPException (Backward Compatibility)                                      }
{ =========================================================================== }

constructor HTTPException.Create(const AMsg: string);
begin
  inherited Create(AMsg, HTTP_STATUS_BAD_REQUEST);
end;

constructor HTTPException.CreateFmt(const AFormat: string;
  const AArgs: array of const);
begin
  inherited Create(Format(AFormat, AArgs), HTTP_STATUS_BAD_REQUEST);
end;

end.
