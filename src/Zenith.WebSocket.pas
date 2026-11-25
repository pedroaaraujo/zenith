unit Zenith.WebSocket;

{
  Zenith High-Performance Native WebSocket Server Suite
  - RFC 6455: The WebSocket Protocol (Handshake, Framing, Masking, Fragmentation, Control Frames)
  - RFC 7692: Compression Extensions for WebSocket (permessage-deflate, RSV1, 00 00 FF FF trailer)
  - RFC 8949 / BSON v1.1: Native Binary Payload Transport for DeltaModel entities
  - RFC 8392: CBOR Web Token (CWT) Authentication at Handshake or Initial Frame
  Zero external dependencies (uses native FPC FCL sha1, base64, zstream/paszlib).
}

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, StrUtils, SyncObjs, sha1, base64, HTTPDefs,
  fphttpserver, Zenith.Env,
  DeltaModel,
  DeltaModel.Codec.Cbor,
  DeltaModel.Codec.Bson,
  Zenith.Security,
  Zenith.Security.CWT,
  Zenith.WebSocket.Deflate;

const
  { RFC 6455 Constants }
  WS_GUID    = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
  WS_VERSION = '13';

  { RFC 6455 Opcodes (Section 5.2) }
  WS_OP_CONTINUATION = $00;
  WS_OP_TEXT         = $01;
  WS_OP_BINARY       = $02;
  WS_OP_CLOSE        = $08;
  WS_OP_PING         = $09;
  WS_OP_PONG         = $0A;

  { RFC 6455 Close Status Codes (Section 7.4.1) }
  WS_CLOSE_NORMAL           = 1000;
  WS_CLOSE_GOING_AWAY       = 1001;
  WS_CLOSE_PROTOCOL_ERROR   = 1002;
  WS_CLOSE_UNSUPPORTED_DATA = 1003;
  WS_CLOSE_NO_STATUS        = 1005;
  WS_CLOSE_ABNORMAL         = 1006;
  WS_CLOSE_INVALID_PAYLOAD  = 1007;
  WS_CLOSE_POLICY_VIOLATION = 1008;
  WS_CLOSE_MESSAGE_TOO_BIG  = 1009;
  WS_CLOSE_MANDATORY_EXT    = 1010;
  WS_CLOSE_INTERNAL_ERROR   = 1011;

  { Anti-OOM / DoS Default Limits }
  WS_DEFAULT_MAX_FRAME_SIZE   = 1024 * 1024;      // 1 MB per frame
  WS_DEFAULT_MAX_MESSAGE_SIZE = 4 * 1024 * 1024;  // 4 MB per assembled message
  WS_MAX_CONTROL_PAYLOAD      = 125;              // RFC 6455 Section 5.5

type
  { Exceptions }
  EZWebSocketError = class(Exception)
  private
    FCloseCode: Word;
  public
    constructor CreateWithCode(ACode: Word; const AMsg: string);
    property CloseCode: Word read FCloseCode;
  end;

  EZWebSocketHandshakeError = class(EZWebSocketError);
  EZWebSocketProtocolError  = class(EZWebSocketError);
  EZWebSocketMessageTooBig  = class(EZWebSocketError);
  EZWebSocketAuthError      = class(EZWebSocketError);

  TZWebSocketState = (wsStateOpen, wsStateClosing, wsStateClosed);
  TZWebSocketMessageType = (wsMsgText, wsMsgBinary);
  TZWebSocketBinaryFormat = (wsBinRaw, wsBinCbor, wsBinBson);

  { TZWebSocketFrame }
  TZWebSocketFrame = record
    Fin: Boolean;
    Rsv1: Boolean;
    Rsv2: Boolean;
    Rsv3: Boolean;
    Opcode: Byte;
    Masked: Boolean;
    MaskKey: array[0..3] of Byte;
    Payload: TBytes;
    function IsControlFrame: Boolean;
    function PayloadAsText: string;
  end;

  { TZWebSocketMessage: Reassembled WebSocket Message }
  TZWebSocketMessage = record
    MessageType: TZWebSocketMessageType;
    Compressed: Boolean;
    Payload: TBytes;
    function AsText: string;
    function AsRawByteString: RawByteString;
  end;

  { TZWebSocketHandshake: RFC 6455 Section 4 }
  TZWebSocketHandshake = class
  private
    class function HeaderContainsToken(const AHeaderValue, AToken: string): Boolean; static;
    class function GetRequestHeaderCI(ARequest: TRequest; const AName: string): string; static;
  public
    class function ComputeAcceptKey(const ASecWebSocketKey: string): string; static;
    { Proteção contra Cross-Site WebSocket Hijacking. Sem header Origin
      (clientes não-navegador) aceita; com Origin, aceita se for a mesma
      origem do Host ou estiver em ZENITH_WS_ALLOWED_ORIGINS (lista separada
      por vírgula; "*" libera qualquer origem). }
    class function IsOriginAllowed(ARequest: TRequest): Boolean; static;
    class function ValidateRequest(
      ARequest: TRequest;
      out AAcceptKey: string;
      out AExtensionsResponse: string;
      out ASelectedProtocol: string;
      const ASupportedProtocols: string = '';
      AAllowDeflate: Boolean = True
    ): Boolean; static;
    class function BuildUpgradeResponseRaw(
      const AAcceptKey: string;
      const AExtensionsResponse: string = '';
      const ASelectedProtocol: string = ''
    ): RawByteString; static;
  end;

  { TZWebSocketFrameCodec: RFC 6455 Section 5 }
  TZWebSocketFrameCodec = class
  public
    class procedure GenerateMaskKey(out AMaskKey: array of Byte); static;
    class procedure ApplyMask(var AData: TBytes; const AMaskKey: array of Byte); overload; static;
    class procedure ApplyMask(AData: PByte; ALen: SizeInt; const AMaskKey: array of Byte); overload; static;

    class function EncodeFrame(const AFrame: TZWebSocketFrame): TBytes; static;
    class function DecodeFrame(
      AStream: TStream;
      out AFrame: TZWebSocketFrame;
      ARequireMask: Boolean = True;
      AMaxFrameSize: Int64 = WS_DEFAULT_MAX_FRAME_SIZE;
      AAllowRsv1: Boolean = False
    ): Boolean; static;

    class function CreateTextFrame(
      const AText: string;
      AMasked: Boolean = False;
      ACompress: Boolean = False;
      AFin: Boolean = True
    ): TZWebSocketFrame; static;

    class function CreateBinaryFrame(
      const AData: TBytes;
      AMasked: Boolean = False;
      ACompress: Boolean = False;
      AFin: Boolean = True
    ): TZWebSocketFrame; static;

    class function CreateContinuationFrame(
      const AData: TBytes;
      AFin: Boolean;
      AMasked: Boolean = False
    ): TZWebSocketFrame; static;

    class function CreateCloseFrame(
      ACode: Word = WS_CLOSE_NORMAL;
      const AReason: string = '';
      AMasked: Boolean = False
    ): TZWebSocketFrame; static;

    class function CreatePingFrame(
      const AData: TBytes = nil;
      AMasked: Boolean = False
    ): TZWebSocketFrame; static;

    class function CreatePongFrame(
      const AData: TBytes = nil;
      AMasked: Boolean = False
    ): TZWebSocketFrame; static;

    class procedure ParseClosePayload(
      const APayload: TBytes;
      out ACode: Word;
      out AReason: string
    ); static;
  end;

  { TZWebSocketAuth: RFC 8392 CWT Authentication Helpers }
  TZWebSocketAuth = class
  public
    class function ExtractTokenFromRequest(ARequest: TRequest; AAllowQueryParam: Boolean = True): string; static;
    class function AuthenticateHandshake(
      ARequest: TRequest;
      out ASecurityContext: TZSecurityContext;
      AAllowQueryParam: Boolean = True
    ): Boolean; static;
    class function AuthenticateBinaryMessage(
      const APayload: TBytes;
      out ASecurityContext: TZSecurityContext
    ): Boolean; static;
    class function AuthenticateTextMessage(
      const AMessage: string;
      out ASecurityContext: TZSecurityContext
    ): Boolean; static;
  end;

  { TZBufferedTransportStream: Prepends residual HTTP connection buffer before reading socket }
  TZBufferedTransportStream = class(TStream)
  private
    FInnerStream: TStream;
    FPreBuffer: RawByteString;
    FPrePos: SizeInt;
    FOwnsInner: Boolean;
  public
    constructor Create(AInnerStream: TStream; const AInitialBuffer: RawByteString = ''; AOwnsInner: Boolean = False);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  TZWebSocketConnection = class;

  TZWebSocketOpenEvent = procedure(AConn: TZWebSocketConnection) of object;
  TZWebSocketTextEvent = procedure(AConn: TZWebSocketConnection; const AText: string) of object;
  TZWebSocketBinaryEvent = procedure(AConn: TZWebSocketConnection; const AData: TBytes) of object;
  TZWebSocketControlEvent = procedure(AConn: TZWebSocketConnection; const AData: TBytes) of object;
  TZWebSocketCloseEvent = procedure(AConn: TZWebSocketConnection; ACode: Word; const AReason: string) of object;
  TZWebSocketErrorEvent = procedure(AConn: TZWebSocketConnection; E: Exception) of object;

  { TZWebSocketConnection }
  TZWebSocketConnection = class
  private
    FId: string;
    FStream: TStream;
    FOwnsStream: Boolean;
    FWriteLock: TCriticalSection;
    FState: TZWebSocketState;
    FRemoteAddress: string;
    FSubProtocol: string;
    FDeflateEnabled: Boolean;
    FDeflateThreshold: Integer;
    FMaxFrameSize: Int64;
    FMaxMessageSize: Int64;
    FRequireClientMask: Boolean;
    FIsClientMode: Boolean;
    FAutoPong: Boolean;
    FCloseCode: Word;
    FCloseReason: string;
    FAuthenticated: Boolean;
    FSecurityContext: TZSecurityContext;

    FOnOpen: TZWebSocketOpenEvent;
    FOnTextMessage: TZWebSocketTextEvent;
    FOnBinaryMessage: TZWebSocketBinaryEvent;
    FOnPing: TZWebSocketControlEvent;
    FOnPong: TZWebSocketControlEvent;
    FOnClose: TZWebSocketCloseEvent;
    FOnError: TZWebSocketErrorEvent;

    procedure WriteRawBytes(const ABytes: TBytes);
    procedure SendFrameInternal(const AFrame: TZWebSocketFrame);
  public
    constructor Create(AStream: TStream; AOwnsStream: Boolean = False);
    destructor Destroy; override;

    { Low-level & High-level Send }
    procedure SendFrame(const AFrame: TZWebSocketFrame);
    procedure SendText(const AText: string; ACompress: Boolean = False);
    procedure SendBinary(const AData: TBytes; ACompress: Boolean = False);
    procedure SendPing(const AData: TBytes = nil);
    procedure SendPong(const AData: TBytes = nil);
    procedure Close(ACode: Word = WS_CLOSE_NORMAL; const AReason: string = '');

    { CBOR / BSON DeltaModel Helpers }
    procedure SendModelCbor(AModel: TDeltaModel; ACompress: Boolean = False);
    procedure SendModelBson(AModel: TDeltaModel; ACompress: Boolean = False);
    procedure SendListCbor(AList: TObject; ACompress: Boolean = False);
    procedure SendListBson(AList: TObject; ACompress: Boolean = False);
    class function EncodeModelToBytes(AModel: TDeltaModel; AFormat: TZWebSocketBinaryFormat): TBytes; static;
    class procedure DecodeBytesToModel(const AData: TBytes; AModel: TDeltaModel; AFormat: TZWebSocketBinaryFormat); static;

    { Authentication (CWT RFC 8392) }
    procedure SetSecurityContext(const ACtx: TZSecurityContext);
    function AuthenticateWithBinaryCWT(const APayload: TBytes): Boolean;
    function AuthenticateWithTextCWT(const ATokenStr: string): Boolean;

    { Receive & Reassembly }
    function ReadMessage(out AMessage: TZWebSocketMessage): Boolean;
    procedure RunLoop(ARequireFirstMessageAuth: Boolean = False);

    property Id: string read FId write FId;
    property State: TZWebSocketState read FState;
    property RemoteAddress: string read FRemoteAddress write FRemoteAddress;
    property SubProtocol: string read FSubProtocol write FSubProtocol;
    property DeflateEnabled: Boolean read FDeflateEnabled write FDeflateEnabled;
    property DeflateThreshold: Integer read FDeflateThreshold write FDeflateThreshold;
    property MaxFrameSize: Int64 read FMaxFrameSize write FMaxFrameSize;
    property MaxMessageSize: Int64 read FMaxMessageSize write FMaxMessageSize;
    property RequireClientMask: Boolean read FRequireClientMask write FRequireClientMask;
    property IsClientMode: Boolean read FIsClientMode write FIsClientMode;
    property AutoPong: Boolean read FAutoPong write FAutoPong;
    property CloseCode: Word read FCloseCode;
    property CloseReason: string read FCloseReason;
    property Authenticated: Boolean read FAuthenticated;
    property SecurityContext: TZSecurityContext read FSecurityContext;

    property OnOpen: TZWebSocketOpenEvent read FOnOpen write FOnOpen;
    property OnTextMessage: TZWebSocketTextEvent read FOnTextMessage write FOnTextMessage;
    property OnBinaryMessage: TZWebSocketBinaryEvent read FOnBinaryMessage write FOnBinaryMessage;
    property OnPing: TZWebSocketControlEvent read FOnPing write FOnPing;
    property OnPong: TZWebSocketControlEvent read FOnPong write FOnPong;
    property OnClose: TZWebSocketCloseEvent read FOnClose write FOnClose;
    property OnError: TZWebSocketErrorEvent read FOnError write FOnError;
  end;

  { TZWebSocketHub: Thread-Safe Connection Registry & Broadcaster }
  TZWebSocketHub = class
  private
    FLock: TCriticalSection;
    FConnections: TList;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterConnection(AConn: TZWebSocketConnection);
    procedure UnregisterConnection(AConn: TZWebSocketConnection);
    function Count: Integer;

    procedure BroadcastText(const AText: string; AExclude: TZWebSocketConnection = nil);
    procedure BroadcastBinary(const AData: TBytes; AExclude: TZWebSocketConnection = nil);
    procedure BroadcastModelCbor(AModel: TDeltaModel; AExclude: TZWebSocketConnection = nil);
    procedure BroadcastModelBson(AModel: TDeltaModel; AExclude: TZWebSocketConnection = nil);
  end;

  TZWebSocketSessionProc = procedure(AConn: TZWebSocketConnection);
  TZWebSocketSessionMethod = procedure(AConn: TZWebSocketConnection) of object;

  { TZWebSocketUpgrade: Integrates WebSocket Upgrade into Zenith HTTP Routes }
  TZWebSocketUpgrade = class
  public
    class function Accept(
      ARequest: TRequest;
      AResponse: TResponse;
      ASessionProc: TZWebSocketSessionProc;
      const ASupportedProtocols: string = '';
      AAllowDeflate: Boolean = True;
      ARequireHandshakeCWT: Boolean = False;
      AMaxFrameSize: Int64 = WS_DEFAULT_MAX_FRAME_SIZE;
      AMaxMessageSize: Int64 = WS_DEFAULT_MAX_MESSAGE_SIZE
    ): Boolean; overload; static;

    class function Accept(
      ARequest: TRequest;
      AResponse: TResponse;
      ASessionMethod: TZWebSocketSessionMethod;
      const ASupportedProtocols: string = '';
      AAllowDeflate: Boolean = True;
      ARequireHandshakeCWT: Boolean = False;
      AMaxFrameSize: Int64 = WS_DEFAULT_MAX_FRAME_SIZE;
      AMaxMessageSize: Int64 = WS_DEFAULT_MAX_MESSAGE_SIZE
    ): Boolean; overload; static;
  end;

implementation

{ Internal Helpers }

function ReadExact(AStream: TStream; var ABuf; ACount: SizeInt): Boolean;
var
  TotalRead, Chunk: SizeInt;
  P: PByte;
begin
  if ACount = 0 then
    Exit(True);

  TotalRead := 0;
  P := @ABuf;
  while TotalRead < ACount do
  begin
    Chunk := AStream.Read(P[TotalRead], ACount - TotalRead);
    if Chunk <= 0 then
    begin
      if TotalRead = 0 then
        Exit(False);
      raise EZWebSocketProtocolError.CreateWithCode(
        WS_CLOSE_ABNORMAL,
        Format('Unexpected EOF while reading WebSocket frame (%d/%d bytes)', [TotalRead, ACount])
      );
    end;
    Inc(TotalRead, Chunk);
  end;
  Result := True;
end;

function BytesFromRawString(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then
    Move(S[1], Result[0], Length(S));
end;

function RawStringFromBytes(const B: TBytes): RawByteString;
begin
  SetLength(Result, Length(B));
  if Length(B) > 0 then
    Move(B[0], Result[1], Length(B));
end;

function GenerateConnectionId: string;
var
  G: TGuid;
begin
  if CreateGUID(G) = 0 then
    Result := LowerCase(StringReplace(StringReplace(GUIDToString(G), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]))
  else
    Result := IntToHex(GetTickCount64, 16);
end;

{ EZWebSocketError }

constructor EZWebSocketError.CreateWithCode(ACode: Word; const AMsg: string);
begin
  inherited Create(AMsg);
  FCloseCode := ACode;
end;

{ TZWebSocketFrame }

function TZWebSocketFrame.IsControlFrame: Boolean;
begin
  Result := (Opcode and $08) <> 0;
end;

function TZWebSocketFrame.PayloadAsText: string;
begin
  Result := '';
  if Length(Payload) > 0 then
    SetString(Result, PAnsiChar(@Payload[0]), Length(Payload));
end;

{ TZWebSocketMessage }

function TZWebSocketMessage.AsText: string;
begin
  Result := '';
  if Length(Payload) > 0 then
    SetString(Result, PAnsiChar(@Payload[0]), Length(Payload));
end;

function TZWebSocketMessage.AsRawByteString: RawByteString;
begin
  Result := RawStringFromBytes(Payload);
end;

{ TZWebSocketHandshake }

class function TZWebSocketHandshake.HeaderContainsToken(const AHeaderValue, AToken: string): Boolean;
var
  Parts: TStringArray;
  I: Integer;
  Target: string;
begin
  Result := False;
  Target := LowerCase(Trim(AToken));
  if Target = '' then
    Exit;

  Parts := SplitString(AHeaderValue, ',');
  for I := 0 to High(Parts) do
  begin
    if LowerCase(Trim(Parts[I])) = Target then
      Exit(True);
  end;
end;

class function TZWebSocketHandshake.GetRequestHeaderCI(ARequest: TRequest; const AName: string): string;
var
  I: Integer;
  Line, Key, LowerName: string;
  ColonPos: SizeInt;
begin
  Result := ARequest.GetCustomHeader(AName);
  if Result <> '' then
    Exit;

  LowerName := LowerCase(AName);
  if LowerName = 'connection' then
  begin
    Result := ARequest.Connection;
    if Result <> '' then Exit;
  end
  else if LowerName = 'authorization' then
  begin
    Result := ARequest.Authorization;
    if Result <> '' then Exit;
  end;

  for I := 0 to ARequest.CustomHeaders.Count - 1 do
  begin
    Line := ARequest.CustomHeaders[I];
    ColonPos := Pos('=', Line);
    if ColonPos = 0 then
      ColonPos := Pos(':', Line);
    if ColonPos > 1 then
    begin
      Key := LowerCase(Trim(Copy(Line, 1, ColonPos - 1)));
      if Key = LowerName then
        Exit(Trim(Copy(Line, ColonPos + 1, MaxInt)));
    end;
  end;
end;

class function TZWebSocketHandshake.ComputeAcceptKey(const ASecWebSocketKey: string): string;
var
  Combined: RawByteString;
  Digest: TSHA1Digest;
  DigestStr: RawByteString;
begin
  Combined := RawByteString(Trim(ASecWebSocketKey) + WS_GUID);
  Digest := SHA1String(Combined);
  SetLength(DigestStr, SizeOf(TSHA1Digest));
  Move(Digest[0], DigestStr[1], SizeOf(TSHA1Digest));
  Result := EncodeStringBase64(string(DigestStr));
end;

class function TZWebSocketHandshake.IsOriginAllowed(ARequest: TRequest): Boolean;
var
  Origin, HostHdr, OriginHost, Allowed, Item: string;
  P: SizeInt;
begin
  Origin := Trim(GetRequestHeaderCI(ARequest, 'Origin'));
  if Origin = '' then
    Exit(True);
  Origin := Origin.TrimRight(['/']);

  Allowed := Trim(GetEnvVariable('ZENITH_WS_ALLOWED_ORIGINS', ''));
  if Allowed <> '' then
    for Item in Allowed.Split([',']) do
      if (Trim(Item) = '*') or SameText(Trim(Item).TrimRight(['/']), Origin) then
        Exit(True);

  HostHdr := Trim(ARequest.Host);
  if HostHdr = '' then
    HostHdr := Trim(GetRequestHeaderCI(ARequest, 'Host'));
  P := Pos('://', Origin);
  if P > 0 then
    OriginHost := Copy(Origin, P + 3, MaxInt)
  else
    OriginHost := Origin;
  Result := (HostHdr <> '') and SameText(OriginHost, HostHdr);
end;

class function TZWebSocketHandshake.ValidateRequest(
  ARequest: TRequest;
  out AAcceptKey: string;
  out AExtensionsResponse: string;
  out ASelectedProtocol: string;
  const ASupportedProtocols: string;
  AAllowDeflate: Boolean
): Boolean;
var
  UpgradeHdr, ConnectionHdr, VersionHdr, KeyHdr, ExtHdr, ProtoHdr: string;
  DecodedKey: string;
  ClientProtos, ServerProtos: TStringArray;
  I, J: Integer;
begin
  Result := False;
  AAcceptKey := '';
  AExtensionsResponse := '';
  ASelectedProtocol := '';

  if not Assigned(ARequest) then
    Exit;

  if (ARequest.Method <> '') and (UpperCase(ARequest.Method) <> 'GET') then
    Exit;

  UpgradeHdr := GetRequestHeaderCI(ARequest, 'Upgrade');
  ConnectionHdr := GetRequestHeaderCI(ARequest, 'Connection');
  VersionHdr := Trim(GetRequestHeaderCI(ARequest, 'Sec-WebSocket-Version'));
  KeyHdr := Trim(GetRequestHeaderCI(ARequest, 'Sec-WebSocket-Key'));

  if not HeaderContainsToken(UpgradeHdr, 'websocket') then
    Exit;
  if not HeaderContainsToken(ConnectionHdr, 'upgrade') then
    Exit;
  if VersionHdr <> WS_VERSION then
    Exit;
  if KeyHdr = '' then
    Exit;
  if not IsOriginAllowed(ARequest) then
    Exit;

  // RFC 6455 Section 4.1: Sec-WebSocket-Key must be a base64-encoded 16-byte nonce
  try
    DecodedKey := DecodeStringBase64(KeyHdr);
    if Length(DecodedKey) <> 16 then
      Exit;
  except
    Exit;
  end;

  AAcceptKey := ComputeAcceptKey(KeyHdr);

  // RFC 7692 permessage-deflate negotiation
  if AAllowDeflate then
  begin
    ExtHdr := GetRequestHeaderCI(ARequest, 'Sec-WebSocket-Extensions');
    if ExtHdr <> '' then
      AExtensionsResponse := TZWebSocketDeflate.BuildResponseExtensionHeader(ExtHdr);
  end;

  // Optional Sec-WebSocket-Protocol negotiation
  ProtoHdr := GetRequestHeaderCI(ARequest, 'Sec-WebSocket-Protocol');
  if (ProtoHdr <> '') and (Trim(ASupportedProtocols) <> '') then
  begin
    ClientProtos := SplitString(ProtoHdr, ',');
    ServerProtos := SplitString(ASupportedProtocols, ',');
    for I := 0 to High(ClientProtos) do
    begin
      for J := 0 to High(ServerProtos) do
      begin
        if LowerCase(Trim(ClientProtos[I])) = LowerCase(Trim(ServerProtos[J])) then
        begin
          ASelectedProtocol := Trim(ServerProtos[J]);
          Break;
        end;
      end;
      if ASelectedProtocol <> '' then
        Break;
    end;
  end;

  Result := True;
end;

class function TZWebSocketHandshake.BuildUpgradeResponseRaw(
  const AAcceptKey: string;
  const AExtensionsResponse: string;
  const ASelectedProtocol: string
): RawByteString;
var
  S: string;
begin
  S := 'HTTP/1.1 101 Switching Protocols'#13#10 +
       'Upgrade: websocket'#13#10 +
       'Connection: Upgrade'#13#10 +
       'Sec-WebSocket-Accept: ' + AAcceptKey + #13#10;

  if Trim(AExtensionsResponse) <> '' then
    S := S + 'Sec-WebSocket-Extensions: ' + Trim(AExtensionsResponse) + #13#10;

  if Trim(ASelectedProtocol) <> '' then
    S := S + 'Sec-WebSocket-Protocol: ' + Trim(ASelectedProtocol) + #13#10;

  S := S + #13#10;
  Result := RawByteString(S);
end;

{ TZWebSocketFrameCodec }

class procedure TZWebSocketFrameCodec.GenerateMaskKey(out AMaskKey: array of Byte);
var
  I: Integer;
begin
  for I := 0 to 3 do
    AMaskKey[I] := Byte(Random(256));
end;

class procedure TZWebSocketFrameCodec.ApplyMask(AData: PByte; ALen: SizeInt; const AMaskKey: array of Byte);
var
  I: SizeInt;
  Mask32: UInt32;
  P32: PUInt32;
  Blocks: SizeInt;
begin
  if (AData = nil) or (ALen <= 0) then
    Exit;

  // Fast 32-bit word-aligned XOR loop (4 bytes per iteration)
  Mask32 := UInt32(AMaskKey[0]) or
            (UInt32(AMaskKey[1]) shl 8) or
            (UInt32(AMaskKey[2]) shl 16) or
            (UInt32(AMaskKey[3]) shl 24);

  Blocks := ALen div 4;
  P32 := PUInt32(AData);
  for I := 0 to Blocks - 1 do
  begin
    P32^ := P32^ xor Mask32;
    Inc(P32);
  end;

  // Remaining 0..3 tail bytes
  for I := Blocks * 4 to ALen - 1 do
    AData[I] := AData[I] xor AMaskKey[I and 3];
end;

class procedure TZWebSocketFrameCodec.ApplyMask(var AData: TBytes; const AMaskKey: array of Byte);
begin
  if Length(AData) > 0 then
    ApplyMask(@AData[0], Length(AData), AMaskKey);
end;

class function TZWebSocketFrameCodec.EncodeFrame(const AFrame: TZWebSocketFrame): TBytes;
var
  PayloadLen: QWord;
  HeaderLen: SizeInt;
  B0, B1: Byte;
  PosIdx: SizeInt;
  Len16: Word;
  Len64: QWord;
begin
  PayloadLen := QWord(Length(AFrame.Payload));

  if PayloadLen < 126 then
    HeaderLen := 2
  else if PayloadLen <= $FFFF then
    HeaderLen := 4
  else
    HeaderLen := 10;

  if AFrame.Masked then
    Inc(HeaderLen, 4);

  Result := nil;
  SetLength(Result, HeaderLen + SizeInt(PayloadLen));

  B0 := AFrame.Opcode and $0F;
  if AFrame.Fin then  B0 := B0 or $80;
  if AFrame.Rsv1 then B0 := B0 or $40;
  if AFrame.Rsv2 then B0 := B0 or $20;
  if AFrame.Rsv3 then B0 := B0 or $10;

  if PayloadLen < 126 then
    B1 := Byte(PayloadLen)
  else if PayloadLen <= $FFFF then
    B1 := 126
  else
    B1 := 127;

  if AFrame.Masked then
    B1 := B1 or $80;

  Result[0] := B0;
  Result[1] := B1;
  PosIdx := 2;

  if PayloadLen >= 126 then
  begin
    if PayloadLen <= $FFFF then
    begin
      Len16 := NtoBE(Word(PayloadLen));
      Move(Len16, Result[PosIdx], 2);
      Inc(PosIdx, 2);
    end
    else
    begin
      Len64 := NtoBE(PayloadLen);
      Move(Len64, Result[PosIdx], 8);
      Inc(PosIdx, 8);
    end;
  end;

  if AFrame.Masked then
  begin
    Move(AFrame.MaskKey[0], Result[PosIdx], 4);
    Inc(PosIdx, 4);
  end;

  if PayloadLen > 0 then
  begin
    Move(AFrame.Payload[0], Result[PosIdx], SizeInt(PayloadLen));
    if AFrame.Masked then
      ApplyMask(@Result[PosIdx], SizeInt(PayloadLen), AFrame.MaskKey);
  end;
end;

class function TZWebSocketFrameCodec.DecodeFrame(
  AStream: TStream;
  out AFrame: TZWebSocketFrame;
  ARequireMask: Boolean;
  AMaxFrameSize: Int64;
  AAllowRsv1: Boolean
): Boolean;
var
  Hdr: array[0..1] of Byte;
  LenCode: Byte;
  Len16: Word;
  Len64: QWord;
  PayloadLen: QWord;
begin
  Result := False;
  FillChar(AFrame, SizeOf(AFrame), 0);

  if not Assigned(AStream) then
    Exit(False);

  if not ReadExact(AStream, Hdr[0], 2) then
    Exit(False);

  AFrame.Fin    := (Hdr[0] and $80) <> 0;
  AFrame.Rsv1   := (Hdr[0] and $40) <> 0;
  AFrame.Rsv2   := (Hdr[0] and $20) <> 0;
  AFrame.Rsv3   := (Hdr[0] and $10) <> 0;
  AFrame.Opcode := Hdr[0] and $0F;

  AFrame.Masked := (Hdr[1] and $80) <> 0;
  LenCode       := Hdr[1] and $7F;

  // RFC 6455 Section 5.2: RSV bits must be 0 unless negotiated (RSV1 allowed when permessage-deflate active)
  if AFrame.Rsv2 or AFrame.Rsv3 or (AFrame.Rsv1 and (not AAllowRsv1)) then
    raise EZWebSocketProtocolError.CreateWithCode(
      WS_CLOSE_PROTOCOL_ERROR,
      'Non-zero RSV bits received without negotiated extension'
    );

  // Validate known opcodes
  if not (AFrame.Opcode in [WS_OP_CONTINUATION, WS_OP_TEXT, WS_OP_BINARY,
                            WS_OP_CLOSE, WS_OP_PING, WS_OP_PONG]) then
    raise EZWebSocketProtocolError.CreateWithCode(
      WS_CLOSE_PROTOCOL_ERROR,
      Format('Unknown WebSocket opcode: $%x', [AFrame.Opcode])
    );

  // RFC 6455 Section 5.1: All client->server frames MUST be masked
  if ARequireMask and (not AFrame.Masked) then
    raise EZWebSocketProtocolError.CreateWithCode(
      WS_CLOSE_PROTOCOL_ERROR,
      'Client-to-server WebSocket frame must be masked (RFC 6455 Section 5.1)'
    );

  // Determine payload length
  if LenCode < 126 then
    PayloadLen := LenCode
  else if LenCode = 126 then
  begin
    if not ReadExact(AStream, Len16, 2) then
      raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Truncated 16-bit payload length');
    PayloadLen := BEtoN(Len16);
  end
  else
  begin
    if not ReadExact(AStream, Len64, 8) then
      raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Truncated 64-bit payload length');
    PayloadLen := BEtoN(Len64);
    // RFC 6455 Section 5.2: Most significant bit of 64-bit length MUST be 0
    if (PayloadLen and QWord($8000000000000000)) <> 0 then
      raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Invalid 64-bit payload length (MSB set)');
  end;

  // RFC 6455 Section 5.5: Control frames must not be fragmented and payload <= 125 bytes
  if AFrame.IsControlFrame then
  begin
    if not AFrame.Fin then
      raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Control frames must not be fragmented');
    if PayloadLen > WS_MAX_CONTROL_PAYLOAD then
      raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Control frame payload exceeds 125 bytes');
    if AFrame.Rsv1 then
      raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Control frames must not be compressed (RSV1=1)');
  end;

  // Anti-OOM protection BEFORE allocating buffer
  if (AMaxFrameSize > 0) and (PayloadLen > QWord(AMaxFrameSize)) then
    raise EZWebSocketMessageTooBig.CreateWithCode(
      WS_CLOSE_MESSAGE_TOO_BIG,
      Format('WebSocket frame payload (%u bytes) exceeds maximum limit (%d bytes)', [PayloadLen, AMaxFrameSize])
    );

  // Read masking key if present
  if AFrame.Masked then
  begin
    if not ReadExact(AStream, AFrame.MaskKey[0], 4) then
      raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Truncated masking key');
  end;

  // Read payload
  if PayloadLen > 0 then
  begin
    SetLength(AFrame.Payload, SizeInt(PayloadLen));
    if not ReadExact(AStream, AFrame.Payload[0], SizeInt(PayloadLen)) then
      raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Truncated frame payload');

    if AFrame.Masked then
      ApplyMask(AFrame.Payload, AFrame.MaskKey);
  end;

  Result := True;
end;

class function TZWebSocketFrameCodec.CreateTextFrame(
  const AText: string;
  AMasked: Boolean;
  ACompress: Boolean;
  AFin: Boolean
): TZWebSocketFrame;
var
  Raw: RawByteString;
begin
  Result := Default(TZWebSocketFrame);
  Result.Fin := AFin;
  Result.Opcode := WS_OP_TEXT;
  Result.Masked := AMasked;
  if AMasked then
    GenerateMaskKey(Result.MaskKey);

  Raw := RawByteString(AText);
  if ACompress and (Length(Raw) > 0) then
  begin
    Result.Rsv1 := True;
    Raw := TZWebSocketDeflate.Compress(Raw);
  end;
  Result.Payload := BytesFromRawString(Raw);
end;

class function TZWebSocketFrameCodec.CreateBinaryFrame(
  const AData: TBytes;
  AMasked: Boolean;
  ACompress: Boolean;
  AFin: Boolean
): TZWebSocketFrame;
begin
  Result := Default(TZWebSocketFrame);
  Result.Fin := AFin;
  Result.Opcode := WS_OP_BINARY;
  Result.Masked := AMasked;
  if AMasked then
    GenerateMaskKey(Result.MaskKey);

  if ACompress and (Length(AData) > 0) then
  begin
    Result.Rsv1 := True;
    Result.Payload := TZWebSocketDeflate.Compress(AData);
  end
  else
    Result.Payload := Copy(AData, 0, Length(AData));
end;

class function TZWebSocketFrameCodec.CreateContinuationFrame(
  const AData: TBytes;
  AFin: Boolean;
  AMasked: Boolean
): TZWebSocketFrame;
begin
  Result := Default(TZWebSocketFrame);
  Result.Fin := AFin;
  Result.Opcode := WS_OP_CONTINUATION;
  Result.Masked := AMasked;
  if AMasked then
    GenerateMaskKey(Result.MaskKey);
  Result.Payload := Copy(AData, 0, Length(AData));
end;

class function TZWebSocketFrameCodec.CreateCloseFrame(
  ACode: Word;
  const AReason: string;
  AMasked: Boolean
): TZWebSocketFrame;
var
  ReasonRaw: RawByteString;
  CodeBE: Word;
  ReasonLen: SizeInt;
begin
  Result := Default(TZWebSocketFrame);
  Result.Fin := True;
  Result.Opcode := WS_OP_CLOSE;
  Result.Masked := AMasked;
  if AMasked then
    GenerateMaskKey(Result.MaskKey);

  if ACode > 0 then
  begin
    ReasonRaw := RawByteString(AReason);
    // RFC 6455 Section 5.5: Control frame max 125 bytes (2 bytes status + max 123 bytes reason)
    ReasonLen := Length(ReasonRaw);
    if ReasonLen > 123 then
      ReasonLen := 123;

    SetLength(Result.Payload, 2 + ReasonLen);
    CodeBE := NtoBE(ACode);
    Move(CodeBE, Result.Payload[0], 2);
    if ReasonLen > 0 then
      Move(ReasonRaw[1], Result.Payload[2], ReasonLen);
  end;
end;

class function TZWebSocketFrameCodec.CreatePingFrame(const AData: TBytes; AMasked: Boolean): TZWebSocketFrame;
var
  Len: SizeInt;
begin
  Result := Default(TZWebSocketFrame);
  Result.Fin := True;
  Result.Opcode := WS_OP_PING;
  Result.Masked := AMasked;
  if AMasked then
    GenerateMaskKey(Result.MaskKey);

  Len := Length(AData);
  if Len > WS_MAX_CONTROL_PAYLOAD then
    Len := WS_MAX_CONTROL_PAYLOAD;
  if Len > 0 then
    Result.Payload := Copy(AData, 0, Len);
end;

class function TZWebSocketFrameCodec.CreatePongFrame(const AData: TBytes; AMasked: Boolean): TZWebSocketFrame;
var
  Len: SizeInt;
begin
  Result := Default(TZWebSocketFrame);
  Result.Fin := True;
  Result.Opcode := WS_OP_PONG;
  Result.Masked := AMasked;
  if AMasked then
    GenerateMaskKey(Result.MaskKey);

  Len := Length(AData);
  if Len > WS_MAX_CONTROL_PAYLOAD then
    Len := WS_MAX_CONTROL_PAYLOAD;
  if Len > 0 then
    Result.Payload := Copy(AData, 0, Len);
end;

class procedure TZWebSocketFrameCodec.ParseClosePayload(
  const APayload: TBytes;
  out ACode: Word;
  out AReason: string
);
var
  CodeBE: Word;
begin
  ACode := WS_CLOSE_NO_STATUS;
  AReason := '';

  if Length(APayload) = 0 then
    Exit;

  if Length(APayload) = 1 then
    raise EZWebSocketProtocolError.CreateWithCode(WS_CLOSE_PROTOCOL_ERROR, 'Invalid 1-byte close payload');

  Move(APayload[0], CodeBE, 2);
  ACode := BEtoN(CodeBE);

  if Length(APayload) > 2 then
    SetString(AReason, PAnsiChar(@APayload[2]), Length(APayload) - 2);
end;

{ TZWebSocketAuth }

class function TZWebSocketAuth.ExtractTokenFromRequest(ARequest: TRequest; AAllowQueryParam: Boolean): string;
var
  AuthHdr, ProtoHdr: string;
  Parts: TStringArray;
  I: Integer;
  Item: string;
begin
  Result := '';
  if not Assigned(ARequest) then
    Exit;

  // 1. Authorization: Bearer <cwt_token>
  AuthHdr := Trim(TZWebSocketHandshake.GetRequestHeaderCI(ARequest, 'Authorization'));
  if AuthHdr <> '' then
  begin
    if SameText(Copy(AuthHdr, 1, 7), 'Bearer ') then
      Exit(Trim(Copy(AuthHdr, 8, MaxInt)))
    else if SameText(Copy(AuthHdr, 1, 4), 'CWT ') then
      Exit(Trim(Copy(AuthHdr, 5, MaxInt)));
  end;

  // 2. Sec-WebSocket-Protocol: cwt.<token> or bearer.<token>
  ProtoHdr := TZWebSocketHandshake.GetRequestHeaderCI(ARequest, 'Sec-WebSocket-Protocol');
  if ProtoHdr <> '' then
  begin
    Parts := SplitString(ProtoHdr, ',');
    for I := 0 to High(Parts) do
    begin
      Item := Trim(Parts[I]);
      if SameText(Copy(Item, 1, 4), 'cwt.') then
        Exit(Copy(Item, 5, MaxInt))
      else if SameText(Copy(Item, 1, 7), 'bearer.') then
        Exit(Copy(Item, 8, MaxInt));
    end;
  end;

  // 3. Query parameter ?token=... or ?access_token=...
  if AAllowQueryParam then
  begin
    Result := Trim(ARequest.QueryFields.Values['token']);
    if Result <> '' then
      Exit;
    Result := Trim(ARequest.QueryFields.Values['access_token']);
  end;
end;

class function TZWebSocketAuth.AuthenticateHandshake(
  ARequest: TRequest;
  out ASecurityContext: TZSecurityContext;
  AAllowQueryParam: Boolean
): Boolean;
var
  TokenStr: string;
begin
  Result := False;
  ASecurityContext := TZSecurityContext.CreateAnonymous;
  TokenStr := ExtractTokenFromRequest(ARequest, AAllowQueryParam);
  if TokenStr = '' then
    Exit(False);

  try
    ASecurityContext := TCWT.ValidateToContext(TokenStr);
    Result := ASecurityContext.IsAuthenticated;
  except
    ASecurityContext.FreeInternalObjects;
    ASecurityContext := TZSecurityContext.CreateAnonymous;
    Result := False;
  end;
end;

class function TZWebSocketAuth.AuthenticateBinaryMessage(
  const APayload: TBytes;
  out ASecurityContext: TZSecurityContext
): Boolean;
begin
  Result := False;
  ASecurityContext := TZSecurityContext.CreateAnonymous;
  if Length(APayload) = 0 then
    Exit(False);

  try
    ASecurityContext := TCWT.ValidateToContext(APayload);
    Result := ASecurityContext.IsAuthenticated;
  except
    ASecurityContext.FreeInternalObjects;
    ASecurityContext := TZSecurityContext.CreateAnonymous;
    Result := False;
  end;
end;

class function TZWebSocketAuth.AuthenticateTextMessage(
  const AMessage: string;
  out ASecurityContext: TZSecurityContext
): Boolean;
var
  TokenStr: string;
begin
  Result := False;
  ASecurityContext := TZSecurityContext.CreateAnonymous;
  TokenStr := Trim(AMessage);
  if TokenStr = '' then
    Exit(False);

  if SameText(Copy(TokenStr, 1, 5), 'AUTH ') then
    TokenStr := Trim(Copy(TokenStr, 6, MaxInt))
  else if SameText(Copy(TokenStr, 1, 7), 'Bearer ') then
    TokenStr := Trim(Copy(TokenStr, 8, MaxInt));

  try
    ASecurityContext := TCWT.ValidateToContext(TokenStr);
    Result := ASecurityContext.IsAuthenticated;
  except
    ASecurityContext.FreeInternalObjects;
    ASecurityContext := TZSecurityContext.CreateAnonymous;
    Result := False;
  end;
end;

{ TZBufferedTransportStream }

constructor TZBufferedTransportStream.Create(
  AInnerStream: TStream;
  const AInitialBuffer: RawByteString;
  AOwnsInner: Boolean
);
begin
  inherited Create;
  FInnerStream := AInnerStream;
  FPreBuffer := AInitialBuffer;
  FPrePos := 1;
  FOwnsInner := AOwnsInner;
end;

destructor TZBufferedTransportStream.Destroy;
begin
  if FOwnsInner then
    FreeAndNil(FInnerStream);
  inherited Destroy;
end;

function TZBufferedTransportStream.Read(var Buffer; Count: Longint): Longint;
var
  Remaining, ToCopy, FromInner: SizeInt;
  P: PByte;
begin
  Result := 0;
  if Count <= 0 then
    Exit;

  P := @Buffer;
  Remaining := Length(FPreBuffer) - FPrePos + 1;
  if Remaining > 0 then
  begin
    ToCopy := Count;
    if ToCopy > Remaining then
      ToCopy := Remaining;
    Move(FPreBuffer[FPrePos], P^, ToCopy);
    Inc(FPrePos, ToCopy);
    Result := ToCopy;
    if FPrePos > Length(FPreBuffer) then
    begin
      FPreBuffer := '';
      FPrePos := 1;
    end;
    if Result = Count then
      Exit;
  end;

  if Assigned(FInnerStream) then
  begin
    FromInner := FInnerStream.Read(P[Result], Count - Result);
    if FromInner > 0 then
      Inc(Result, FromInner);
  end;
end;

function TZBufferedTransportStream.Write(const Buffer; Count: Longint): Longint;
begin
  if Assigned(FInnerStream) then
    Result := FInnerStream.Write(Buffer, Count)
  else
    Result := 0;
end;

function TZBufferedTransportStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  if Assigned(FInnerStream) then
    Result := FInnerStream.Seek(Offset, Origin)
  else
    Result := 0;
end;

{ TZWebSocketConnection }

constructor TZWebSocketConnection.Create(AStream: TStream; AOwnsStream: Boolean);
begin
  inherited Create;
  FId := GenerateConnectionId;
  FStream := AStream;
  FOwnsStream := AOwnsStream;
  FWriteLock := TCriticalSection.Create;
  FState := wsStateOpen;
  FDeflateEnabled := False;
  FDeflateThreshold := 128;
  FMaxFrameSize := WS_DEFAULT_MAX_FRAME_SIZE;
  FMaxMessageSize := WS_DEFAULT_MAX_MESSAGE_SIZE;
  FRequireClientMask := True;
  FIsClientMode := False;
  FAutoPong := True;
  FCloseCode := WS_CLOSE_NO_STATUS;
  FCloseReason := '';
  FAuthenticated := False;
  FSecurityContext := TZSecurityContext.CreateAnonymous;
end;

destructor TZWebSocketConnection.Destroy;
begin
  FSecurityContext.FreeInternalObjects;
  if FOwnsStream then
    FreeAndNil(FStream);
  FWriteLock.Free;
  inherited Destroy;
end;

procedure TZWebSocketConnection.WriteRawBytes(const ABytes: TBytes);
begin
  if (not Assigned(FStream)) or (Length(ABytes) = 0) then
    Exit;

  FWriteLock.Acquire;
  try
    FStream.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    FWriteLock.Release;
  end;
end;

procedure TZWebSocketConnection.SendFrameInternal(const AFrame: TZWebSocketFrame);
var
  Encoded: TBytes;
begin
  Encoded := TZWebSocketFrameCodec.EncodeFrame(AFrame);
  WriteRawBytes(Encoded);
end;

procedure TZWebSocketConnection.SendFrame(const AFrame: TZWebSocketFrame);
begin
  if FState = wsStateClosed then
    Exit;
  SendFrameInternal(AFrame);
end;

procedure TZWebSocketConnection.SendText(const AText: string; ACompress: Boolean);
var
  ShouldCompress: Boolean;
  Frame: TZWebSocketFrame;
begin
  if FState <> wsStateOpen then
    Exit;

  ShouldCompress := FDeflateEnabled and (ACompress or (Length(AText) >= FDeflateThreshold));
  Frame := TZWebSocketFrameCodec.CreateTextFrame(AText, FIsClientMode, ShouldCompress, True);
  SendFrameInternal(Frame);
end;

procedure TZWebSocketConnection.SendBinary(const AData: TBytes; ACompress: Boolean);
var
  ShouldCompress: Boolean;
  Frame: TZWebSocketFrame;
begin
  if FState <> wsStateOpen then
    Exit;

  ShouldCompress := FDeflateEnabled and (ACompress or (Length(AData) >= FDeflateThreshold));
  Frame := TZWebSocketFrameCodec.CreateBinaryFrame(AData, FIsClientMode, ShouldCompress, True);
  SendFrameInternal(Frame);
end;

procedure TZWebSocketConnection.SendPing(const AData: TBytes);
begin
  if FState <> wsStateOpen then
    Exit;
  SendFrameInternal(TZWebSocketFrameCodec.CreatePingFrame(AData, FIsClientMode));
end;

procedure TZWebSocketConnection.SendPong(const AData: TBytes);
begin
  if FState = wsStateClosed then
    Exit;
  SendFrameInternal(TZWebSocketFrameCodec.CreatePongFrame(AData, FIsClientMode));
end;

procedure TZWebSocketConnection.Close(ACode: Word; const AReason: string);
begin
  if FState = wsStateClosed then
    Exit;

  FCloseCode := ACode;
  FCloseReason := AReason;
  FState := wsStateClosing;
  try
    SendFrameInternal(TZWebSocketFrameCodec.CreateCloseFrame(ACode, AReason, FIsClientMode));
  except
    // Ignore socket errors during close handshake
  end;
  FState := wsStateClosed;
end;

class function TZWebSocketConnection.EncodeModelToBytes(AModel: TDeltaModel; AFormat: TZWebSocketBinaryFormat): TBytes;
var
  MS: TMemoryStream;
  CborCodec: TDeltaCborCodec;
  BsonCodec: TDeltaBsonCodec;
begin
  Result := nil;
  if not Assigned(AModel) then
    Exit;

  MS := TMemoryStream.Create;
  try
    case AFormat of
      wsBinCbor:
        begin
          CborCodec := TDeltaCborCodec.Create;
          try
            CborCodec.EncodeModel(AModel, MS);
          finally
            CborCodec.Free;
          end;
        end;
      wsBinBson:
        begin
          BsonCodec := TDeltaBsonCodec.Create;
          try
            BsonCodec.EncodeModel(AModel, MS);
          finally
            BsonCodec.Free;
          end;
        end;
    else
      raise EZWebSocketError.CreateWithCode(WS_CLOSE_UNSUPPORTED_DATA, 'Unsupported binary model format');
    end;

    SetLength(Result, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Result[0], MS.Size);
  finally
    MS.Free;
  end;
end;

class procedure TZWebSocketConnection.DecodeBytesToModel(
  const AData: TBytes;
  AModel: TDeltaModel;
  AFormat: TZWebSocketBinaryFormat
);
var
  MS: TMemoryStream;
  CborCodec: TDeltaCborCodec;
  BsonCodec: TDeltaBsonCodec;
begin
  if (not Assigned(AModel)) or (Length(AData) = 0) then
    Exit;

  MS := TMemoryStream.Create;
  try
    MS.WriteBuffer(AData[0], Length(AData));
    MS.Position := 0;

    case AFormat of
      wsBinCbor:
        begin
          CborCodec := TDeltaCborCodec.Create;
          try
            CborCodec.DecodeModel(MS, AModel);
          finally
            CborCodec.Free;
          end;
        end;
      wsBinBson:
        begin
          BsonCodec := TDeltaBsonCodec.Create;
          try
            BsonCodec.DecodeModel(MS, AModel);
          finally
            BsonCodec.Free;
          end;
        end;
    else
      raise EZWebSocketError.CreateWithCode(WS_CLOSE_UNSUPPORTED_DATA, 'Unsupported binary model format');
    end;
  finally
    MS.Free;
  end;
end;

procedure TZWebSocketConnection.SendModelCbor(AModel: TDeltaModel; ACompress: Boolean);
begin
  SendBinary(EncodeModelToBytes(AModel, wsBinCbor), ACompress);
end;

procedure TZWebSocketConnection.SendModelBson(AModel: TDeltaModel; ACompress: Boolean);
begin
  SendBinary(EncodeModelToBytes(AModel, wsBinBson), ACompress);
end;

procedure TZWebSocketConnection.SendListCbor(AList: TObject; ACompress: Boolean);
var
  MS: TMemoryStream;
  Codec: TDeltaCborCodec;
  Buf: TBytes;
begin
  if not Assigned(AList) then
    Exit;

  MS := TMemoryStream.Create;
  Codec := TDeltaCborCodec.Create;
  try
    Codec.EncodeList(AList, MS);
    SetLength(Buf, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Buf[0], MS.Size);
    SendBinary(Buf, ACompress);
  finally
    Codec.Free;
    MS.Free;
  end;
end;

procedure TZWebSocketConnection.SendListBson(AList: TObject; ACompress: Boolean);
var
  MS: TMemoryStream;
  Codec: TDeltaBsonCodec;
  Buf: TBytes;
begin
  if not Assigned(AList) then
    Exit;

  MS := TMemoryStream.Create;
  Codec := TDeltaBsonCodec.Create;
  try
    Codec.EncodeList(AList, MS);
    SetLength(Buf, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Buf[0], MS.Size);
    SendBinary(Buf, ACompress);
  finally
    Codec.Free;
    MS.Free;
  end;
end;

procedure TZWebSocketConnection.SetSecurityContext(const ACtx: TZSecurityContext);
begin
  FSecurityContext.FreeInternalObjects;
  FSecurityContext := ACtx;
  FAuthenticated := ACtx.IsAuthenticated;
end;

function TZWebSocketConnection.AuthenticateWithBinaryCWT(const APayload: TBytes): Boolean;
var
  Ctx: TZSecurityContext;
begin
  Result := TZWebSocketAuth.AuthenticateBinaryMessage(APayload, Ctx);
  if Result then
    SetSecurityContext(Ctx);
end;

function TZWebSocketConnection.AuthenticateWithTextCWT(const ATokenStr: string): Boolean;
var
  Ctx: TZSecurityContext;
begin
  Result := TZWebSocketAuth.AuthenticateTextMessage(ATokenStr, Ctx);
  if Result then
    SetSecurityContext(Ctx);
end;

function TZWebSocketConnection.ReadMessage(out AMessage: TZWebSocketMessage): Boolean;
var
  Frame: TZWebSocketFrame;
  Assembling: Boolean;
  FirstOpcode: Byte;
  MessageCompressed: Boolean;
  BufferStream: TMemoryStream;
  CloseCodeVal: Word;
  CloseReasonVal: string;
  RawPayload: TBytes;
begin
  Result := False;
  FillChar(AMessage, SizeOf(AMessage), 0);

  if FState = wsStateClosed then
    Exit(False);

  Assembling := False;
  FirstOpcode := WS_OP_CONTINUATION;
  MessageCompressed := False;
  BufferStream := TMemoryStream.Create;
  try
    while FState = wsStateOpen do
    begin
      if not TZWebSocketFrameCodec.DecodeFrame(
        FStream, Frame, FRequireClientMask, FMaxFrameSize, FDeflateEnabled
      ) then
      begin
        FState := wsStateClosed;
        Exit(False);
      end;

      // Control frames may be interleaved inside fragmented messages (RFC 6455 Section 5.4)
      if Frame.IsControlFrame then
      begin
        case Frame.Opcode of
          WS_OP_PING:
            begin
              if Assigned(FOnPing) then
                FOnPing(Self, Frame.Payload);
              if FAutoPong then
                SendPong(Frame.Payload);
            end;
          WS_OP_PONG:
            begin
              if Assigned(FOnPong) then
                FOnPong(Self, Frame.Payload);
            end;
          WS_OP_CLOSE:
            begin
              TZWebSocketFrameCodec.ParseClosePayload(Frame.Payload, CloseCodeVal, CloseReasonVal);
              FCloseCode := CloseCodeVal;
              FCloseReason := CloseReasonVal;
              if FState = wsStateOpen then
                Close(CloseCodeVal, CloseReasonVal);
              if Assigned(FOnClose) then
                FOnClose(Self, CloseCodeVal, CloseReasonVal);
              Exit(False);
            end;
        end;
        Continue;
      end;

      // Data frames (Text, Binary, Continuation)
      if Frame.Opcode = WS_OP_CONTINUATION then
      begin
        if not Assembling then
          raise EZWebSocketProtocolError.CreateWithCode(
            WS_CLOSE_PROTOCOL_ERROR,
            'Unexpected continuation frame without initial data frame'
          );
        if Frame.Rsv1 then
          raise EZWebSocketProtocolError.CreateWithCode(
            WS_CLOSE_PROTOCOL_ERROR,
            'RSV1 bit must not be set on continuation frames (RFC 7692 Section 6.1)'
          );
      end
      else
      begin
        if Assembling then
          raise EZWebSocketProtocolError.CreateWithCode(
            WS_CLOSE_PROTOCOL_ERROR,
            'New data frame received before previous fragmented message finished'
          );
        FirstOpcode := Frame.Opcode;
        MessageCompressed := Frame.Rsv1;
        Assembling := True;
      end;

      // Anti-OOM check across accumulated fragments
      if (FMaxMessageSize > 0) and (BufferStream.Size + Length(Frame.Payload) > FMaxMessageSize) then
        raise EZWebSocketMessageTooBig.CreateWithCode(
          WS_CLOSE_MESSAGE_TOO_BIG,
          Format('Assembled WebSocket message exceeds maximum limit (%d bytes)', [FMaxMessageSize])
        );

      if Length(Frame.Payload) > 0 then
        BufferStream.WriteBuffer(Frame.Payload[0], Length(Frame.Payload));

      if Frame.Fin then
      begin
        SetLength(RawPayload, BufferStream.Size);
        if BufferStream.Size > 0 then
          Move(BufferStream.Memory^, RawPayload[0], BufferStream.Size);

        if MessageCompressed then
          RawPayload := TZWebSocketDeflate.Decompress(RawPayload, FMaxMessageSize);

        if FirstOpcode = WS_OP_TEXT then
          AMessage.MessageType := wsMsgText
        else
          AMessage.MessageType := wsMsgBinary;

        AMessage.Compressed := MessageCompressed;
        AMessage.Payload := RawPayload;
        Exit(True);
      end;
    end;
  finally
    BufferStream.Free;
  end;
end;

procedure TZWebSocketConnection.RunLoop(ARequireFirstMessageAuth: Boolean);
var
  Msg: TZWebSocketMessage;
  AuthOK: Boolean;
begin
  try
    if Assigned(FOnOpen) then
      FOnOpen(Self);

    while (FState = wsStateOpen) and ReadMessage(Msg) do
    begin
      if ARequireFirstMessageAuth and (not FAuthenticated) then
      begin
        if Msg.MessageType = wsMsgBinary then
          AuthOK := AuthenticateWithBinaryCWT(Msg.Payload)
        else
          AuthOK := AuthenticateWithTextCWT(Msg.AsText);

        if not AuthOK then
        begin
          Close(WS_CLOSE_POLICY_VIOLATION, 'Invalid or missing CWT authentication token');
          raise EZWebSocketAuthError.CreateWithCode(
            WS_CLOSE_POLICY_VIOLATION,
            'WebSocket initial CWT authentication failed'
          );
        end;
        Continue;
      end;

      case Msg.MessageType of
        wsMsgText:
          if Assigned(FOnTextMessage) then
            FOnTextMessage(Self, Msg.AsText);
        wsMsgBinary:
          if Assigned(FOnBinaryMessage) then
            FOnBinaryMessage(Self, Msg.Payload);
      end;
    end;
  except
    on E: EZWebSocketError do
    begin
      if FState = wsStateOpen then
        Close(E.CloseCode, E.Message);
      if Assigned(FOnError) then
        FOnError(Self, E);
    end;
    on E: EZWebSocketDeflateLimitExceeded do
    begin
      if FState = wsStateOpen then
        Close(WS_CLOSE_MESSAGE_TOO_BIG, E.Message);
      if Assigned(FOnError) then
        FOnError(Self, E);
    end;
    on E: EZWebSocketDeflateError do
    begin
      if FState = wsStateOpen then
        Close(WS_CLOSE_INVALID_PAYLOAD, E.Message);
      if Assigned(FOnError) then
        FOnError(Self, E);
    end;
    on E: Exception do
    begin
      if FState = wsStateOpen then
        Close(WS_CLOSE_INTERNAL_ERROR, E.Message);
      if Assigned(FOnError) then
        FOnError(Self, E);
    end;
  end;
end;

{ TZWebSocketHub }

constructor TZWebSocketHub.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FConnections := TList.Create;
end;

destructor TZWebSocketHub.Destroy;
begin
  FConnections.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TZWebSocketHub.RegisterConnection(AConn: TZWebSocketConnection);
begin
  if not Assigned(AConn) then
    Exit;
  FLock.Acquire;
  try
    if FConnections.IndexOf(AConn) < 0 then
      FConnections.Add(AConn);
  finally
    FLock.Release;
  end;
end;

procedure TZWebSocketHub.UnregisterConnection(AConn: TZWebSocketConnection);
begin
  if not Assigned(AConn) then
    Exit;
  FLock.Acquire;
  try
    FConnections.Remove(AConn);
  finally
    FLock.Release;
  end;
end;

function TZWebSocketHub.Count: Integer;
begin
  FLock.Acquire;
  try
    Result := FConnections.Count;
  finally
    FLock.Release;
  end;
end;

procedure TZWebSocketHub.BroadcastText(const AText: string; AExclude: TZWebSocketConnection);
var
  Snapshot: array of TZWebSocketConnection;
  I: Integer;
begin
  FLock.Acquire;
  try
    SetLength(Snapshot, FConnections.Count);
    for I := 0 to FConnections.Count - 1 do
      Snapshot[I] := TZWebSocketConnection(FConnections[I]);
  finally
    FLock.Release;
  end;

  for I := 0 to High(Snapshot) do
  begin
    if (Snapshot[I] <> AExclude) and (Snapshot[I].State = wsStateOpen) then
    begin
      try
        Snapshot[I].SendText(AText);
      except
      end;
    end;
  end;
end;

procedure TZWebSocketHub.BroadcastBinary(const AData: TBytes; AExclude: TZWebSocketConnection);
var
  Snapshot: array of TZWebSocketConnection;
  I: Integer;
begin
  FLock.Acquire;
  try
    SetLength(Snapshot, FConnections.Count);
    for I := 0 to FConnections.Count - 1 do
      Snapshot[I] := TZWebSocketConnection(FConnections[I]);
  finally
    FLock.Release;
  end;

  for I := 0 to High(Snapshot) do
  begin
    if (Snapshot[I] <> AExclude) and (Snapshot[I].State = wsStateOpen) then
    begin
      try
        Snapshot[I].SendBinary(AData);
      except
      end;
    end;
  end;
end;

procedure TZWebSocketHub.BroadcastModelCbor(AModel: TDeltaModel; AExclude: TZWebSocketConnection);
var
  Encoded: TBytes;
begin
  Encoded := TZWebSocketConnection.EncodeModelToBytes(AModel, wsBinCbor);
  BroadcastBinary(Encoded, AExclude);
end;

procedure TZWebSocketHub.BroadcastModelBson(AModel: TDeltaModel; AExclude: TZWebSocketConnection);
var
  Encoded: TBytes;
begin
  Encoded := TZWebSocketConnection.EncodeModelToBytes(AModel, wsBinBson);
  BroadcastBinary(Encoded, AExclude);
end;

{ TZWebSocketUpgrade }

class function TZWebSocketUpgrade.Accept(
  ARequest: TRequest;
  AResponse: TResponse;
  ASessionProc: TZWebSocketSessionProc;
  const ASupportedProtocols: string;
  AAllowDeflate: Boolean;
  ARequireHandshakeCWT: Boolean;
  AMaxFrameSize: Int64;
  AMaxMessageSize: Int64
): Boolean;
var
  AcceptKey, ExtResp, SelectedProto: string;
  SecCtx: TZSecurityContext;
  HasAuth: Boolean;
  HttpConn: TFPHTTPConnection;
  ResidualBuf: RawByteString;
  Transport: TZBufferedTransportStream;
  WsConn: TZWebSocketConnection;
begin
  Result := False;
  if not (ARequest is TFPHTTPConnectionRequest) then
  begin
    AResponse.Code := 400;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'WebSocket upgrade requires TFPHTTPConnectionRequest';
    Exit(False);
  end;

  if not TZWebSocketHandshake.ValidateRequest(
    ARequest, AcceptKey, ExtResp, SelectedProto, ASupportedProtocols, AAllowDeflate
  ) then
  begin
    AResponse.Code := 400;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'Invalid WebSocket Upgrade request (RFC 6455)';
    Exit(False);
  end;

  SecCtx := TZSecurityContext.CreateAnonymous;
  HasAuth := TZWebSocketAuth.AuthenticateHandshake(ARequest, SecCtx, True);
  if ARequireHandshakeCWT and (not HasAuth) then
  begin
    SecCtx.FreeInternalObjects;
    AResponse.Code := 401;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'Unauthorized: valid CWT token required for WebSocket upgrade';
    Exit(False);
  end;

  HttpConn := TFPHTTPConnectionRequest(ARequest).Connection;
  if (not Assigned(HttpConn)) or (not Assigned(HttpConn.Socket)) then
  begin
    SecCtx.FreeInternalObjects;
    AResponse.Code := 500;
    AResponse.Content := 'Underlying HTTP socket unavailable';
    Exit(False);
  end;

  // Send 101 Switching Protocols and mark HTTP response sent so fphttpserver won't write after WS closes
  AResponse.Code := 101;
  AResponse.CodeText := 'Switching Protocols';
  AResponse.ContentType := '';
  AResponse.Contents.Clear;
  AResponse.SetCustomHeader('Upgrade', 'websocket');
  AResponse.SetCustomHeader('Connection', 'Upgrade');
  AResponse.SetCustomHeader('Sec-WebSocket-Accept', AcceptKey);
  if ExtResp <> '' then
    AResponse.SetCustomHeader('Sec-WebSocket-Extensions', ExtResp);
  if SelectedProto <> '' then
    AResponse.SetCustomHeader('Sec-WebSocket-Protocol', SelectedProto);
  AResponse.SendHeaders;
  AResponse.SendContent; // Empty body -> sets ContentSent = True cleanly

  ResidualBuf := RawByteString(HttpConn.TakeBuffer);
  Transport := TZBufferedTransportStream.Create(HttpConn.Socket, ResidualBuf, False);
  WsConn := TZWebSocketConnection.Create(Transport, True);
  try
    WsConn.RemoteAddress := ARequest.RemoteAddress;
    WsConn.SubProtocol := SelectedProto;
    WsConn.DeflateEnabled := (ExtResp <> '');
    WsConn.MaxFrameSize := AMaxFrameSize;
    WsConn.MaxMessageSize := AMaxMessageSize;
    if HasAuth then
      WsConn.SetSecurityContext(SecCtx)
    else
      SecCtx.FreeInternalObjects;

    Result := True;
    if Assigned(ASessionProc) then
      ASessionProc(WsConn);
  finally
    WsConn.Free;
  end;
end;

class function TZWebSocketUpgrade.Accept(
  ARequest: TRequest;
  AResponse: TResponse;
  ASessionMethod: TZWebSocketSessionMethod;
  const ASupportedProtocols: string;
  AAllowDeflate: Boolean;
  ARequireHandshakeCWT: Boolean;
  AMaxFrameSize: Int64;
  AMaxMessageSize: Int64
): Boolean;
var
  AcceptKey, ExtResp, SelectedProto: string;
  SecCtx: TZSecurityContext;
  HasAuth: Boolean;
  HttpConn: TFPHTTPConnection;
  ResidualBuf: RawByteString;
  Transport: TZBufferedTransportStream;
  WsConn: TZWebSocketConnection;
begin
  Result := False;
  if not (ARequest is TFPHTTPConnectionRequest) then
  begin
    AResponse.Code := 400;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'WebSocket upgrade requires TFPHTTPConnectionRequest';
    Exit(False);
  end;

  if not TZWebSocketHandshake.ValidateRequest(
    ARequest, AcceptKey, ExtResp, SelectedProto, ASupportedProtocols, AAllowDeflate
  ) then
  begin
    AResponse.Code := 400;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'Invalid WebSocket Upgrade request (RFC 6455)';
    Exit(False);
  end;

  SecCtx := TZSecurityContext.CreateAnonymous;
  HasAuth := TZWebSocketAuth.AuthenticateHandshake(ARequest, SecCtx, True);
  if ARequireHandshakeCWT and (not HasAuth) then
  begin
    SecCtx.FreeInternalObjects;
    AResponse.Code := 401;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'Unauthorized: valid CWT token required for WebSocket upgrade';
    Exit(False);
  end;

  HttpConn := TFPHTTPConnectionRequest(ARequest).Connection;
  if (not Assigned(HttpConn)) or (not Assigned(HttpConn.Socket)) then
  begin
    SecCtx.FreeInternalObjects;
    AResponse.Code := 500;
    AResponse.Content := 'Underlying HTTP socket unavailable';
    Exit(False);
  end;

  AResponse.Code := 101;
  AResponse.CodeText := 'Switching Protocols';
  AResponse.ContentType := '';
  AResponse.Contents.Clear;
  AResponse.SetCustomHeader('Upgrade', 'websocket');
  AResponse.SetCustomHeader('Connection', 'Upgrade');
  AResponse.SetCustomHeader('Sec-WebSocket-Accept', AcceptKey);
  if ExtResp <> '' then
    AResponse.SetCustomHeader('Sec-WebSocket-Extensions', ExtResp);
  if SelectedProto <> '' then
    AResponse.SetCustomHeader('Sec-WebSocket-Protocol', SelectedProto);
  AResponse.SendHeaders;
  AResponse.SendContent;

  ResidualBuf := RawByteString(HttpConn.TakeBuffer);
  Transport := TZBufferedTransportStream.Create(HttpConn.Socket, ResidualBuf, False);
  WsConn := TZWebSocketConnection.Create(Transport, True);
  try
    WsConn.RemoteAddress := ARequest.RemoteAddress;
    WsConn.SubProtocol := SelectedProto;
    WsConn.DeflateEnabled := (ExtResp <> '');
    WsConn.MaxFrameSize := AMaxFrameSize;
    WsConn.MaxMessageSize := AMaxMessageSize;
    if HasAuth then
      WsConn.SetSecurityContext(SecCtx)
    else
      SecCtx.FreeInternalObjects;

    Result := True;
    if Assigned(ASessionMethod) then
      ASessionMethod(WsConn);
  finally
    WsConn.Free;
  end;
end;

end.
