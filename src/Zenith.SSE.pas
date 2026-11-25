{
    Zenith High-Performance HTTP Framework
    W3C Server-Sent Events (SSE / text/event-stream) Native Engine

    Implements the HTML Living Standard Section 9.2 (Server-Sent Events):
    - Strict canonical HTTP headers (Content-Type, Cache-Control, Connection, X-Accel-Buffering)
    - Compliant wire formatting (id, event, multi-line data, retry, comments, UTF-8)
    - Last-Event-ID reconnection & ring-buffer event replay
    - Thread-safe multi-topic Pub/Sub broker (TZSSEBroker) with lock-free I/O dispatch
    - Automatic heartbeat comments (: ping) and immediate socket disconnect detection
    - Zero external dependencies (100% pure FPC RTL/FCL) and zero thread/memory leaks
}

{$mode objfpc}{$H+}

unit Zenith.SSE;

interface

uses
  Classes, SysUtils, SyncObjs, DateUtils,
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  {$IFDEF WINDOWS}
  WinSock2,
  {$ENDIF}
  sockets, ssockets, httpdefs, fphttpserver;

const
  SSE_CONTENT_TYPE = 'text/event-stream; charset=utf-8';
  SSE_CACHE_CONTROL = 'no-cache, no-transform';
  SSE_CONNECTION = 'keep-alive';
  SSE_ACCEL_BUFFERING = 'no';

  SSE_DEFAULT_HEARTBEAT_MS = 15000;
  SSE_DEFAULT_POLL_MS = 250;
  SSE_DEFAULT_REPLAY_BUFFER_SIZE = 100;
  SSE_DEFAULT_MAX_CONNECTIONS = 64;

type
  EZSSEError = class(Exception);

  { TZSSEEvent: Immutable W3C SSE event record }
  TZSSEEvent = record
    Id: string;
    EventType: string;
    Data: string;
    RetryMs: Integer; // < 0 omits the retry field
    Topic: string;
    Timestamp: TDateTime;
  end;

  { TZSSEFormatter: Strict wire formatter per HTML Living Standard Section 9.2 }
  TZSSEFormatter = class
  public
    class function SanitizeSingleLine(const AValue: string): string;
    class function FormatEvent(const AData: string; const AEvent: string = '';
      const AId: string = ''; ARetryMs: Integer = -1): RawByteString; overload;
    class function FormatEvent(const AEvent: TZSSEEvent): RawByteString; overload;
    class function FormatComment(const AText: string = 'ping'): RawByteString;
    class function FormatRetry(ARetryMs: Integer): RawByteString;
    class function ExtractLastEventID(ARequest: TRequest): string;
  end;

  { TZSSEStream: Thread-safe SSE stream writer over any TStream or TSocketStream }
  TZSSEStream = class
  private
    FStream: TStream;
    FOwnsStream: Boolean;
    FSocketHandle: LongInt;
    FWriteLock: TCriticalSection;
    FConnected: Boolean;
    FHeadersSent: Boolean;
    FBytesSent: Int64;
    FEventsSent: Int64;
    FLastActivityTick: QWord;
    function GetConnected: Boolean;
    function GetBytesSent: Int64;
    function GetEventsSent: Int64;
  protected
    procedure SetConnected(AValue: Boolean);
    procedure TouchActivity;
    property Stream: TStream read FStream;
    property SocketHandle: LongInt read FSocketHandle;
  public
    constructor Create(AStream: TStream; AOwnsStream: Boolean = False);
    destructor Destroy; override;

    class procedure ApplyHeaders(AResponse: TResponse);

    function SendRaw(const ARaw: RawByteString): Boolean;
    function SendEvent(const AData: string; const AEvent: string = '';
      const AId: string = ''; ARetryMs: Integer = -1): Boolean; overload;
    function SendEvent(const AEvent: TZSSEEvent): Boolean; overload;
    function SendComment(const AText: string = 'ping'): Boolean;
    function SendRetry(ARetryMs: Integer): Boolean;

    function CheckDisconnected: Boolean; virtual;
    procedure Close; virtual;

    property Connected: Boolean read GetConnected;
    property HeadersSent: Boolean read FHeadersSent write FHeadersSent;
    property BytesSent: Int64 read GetBytesSent;
    property EventsSent: Int64 read GetEventsSent;
    property LastActivityTick: QWord read FLastActivityTick;
  end;

  { TZSSEConnection: Active SSE connection with topics, Last-Event-ID, heartbeat and lifecycle }
  TZSSEConnection = class(TZSSEStream)
  private
    FClientID: string;
    FLastEventID: string;
    FCreatedAt: TDateTime;
    FTopicsLock: TCriticalSection;
    FTopics: TStringList;
    FStopEvent: TEvent;
    FDispatchLock: TCriticalSection;
    FDispatchIdleEvent: TEvent;
    FActiveDispatches: LongInt;
    FHeartbeatsSent: Int64;
    class var FNextClientSeq: Int64;
    class function GenerateClientID: string;
  protected
    procedure AcquireDispatch;
    procedure ReleaseDispatch;
    procedure WaitForDispatches;
  public
    constructor Create(ARequest: TRequest; AResponse: TResponse;
      const AClientID: string = ''); overload;
    constructor CreateFromStream(AStream: TStream; const ALastEventID: string = '';
      const AClientID: string = ''; AOwnsStream: Boolean = False); overload;
    destructor Destroy; override;

    procedure AddTopic(const ATopic: string);
    procedure RemoveTopic(const ATopic: string);
    function HasTopic(const ATopic: string): Boolean;
    procedure ClearTopics;

    procedure Close; override;
    procedure WaitLoop(AHeartbeatIntervalMs: Integer = SSE_DEFAULT_HEARTBEAT_MS;
      APollIntervalMs: Integer = SSE_DEFAULT_POLL_MS;
      AMaxDurationMs: Integer = 0);

    property ClientID: string read FClientID;
    property LastEventID: string read FLastEventID;
    property CreatedAt: TDateTime read FCreatedAt;
    property HeartbeatsSent: Int64 read FHeartbeatsSent;
  end;

  { TZSSEBroker: Thread-safe multi-topic manager with replay buffer and lock-free I/O dispatch }
  TZSSEBroker = class
  private
    FLock: TCriticalSection;
    FConnections: TList;
    FHistory: array of TZSSEEvent;
    FHistoryHead: Integer;
    FHistoryCount: Integer;
    FReplayBufferSize: Integer;
    FMaxConnections: Integer;
    FShuttingDown: Boolean;
    FTotalPublished: Int64;
    FTotalDelivered: Int64;
    FTotalDropped: Int64;
    procedure RecordEventLocked(const AEvent: TZSSEEvent);
    function DispatchRaw(const ATopic: string; const ARaw: RawByteString;
      ABroadcastAll: Boolean): Integer;
    function GetTotalPublished: Int64;
    function GetTotalDelivered: Int64;
    function GetTotalDropped: Int64;
    function GetMaxConnections: Integer;
    procedure SetMaxConnections(AValue: Integer);
  public
    constructor Create(AReplayBufferSize: Integer = SSE_DEFAULT_REPLAY_BUFFER_SIZE;
      AMaxConnections: Integer = SSE_DEFAULT_MAX_CONNECTIONS);
    destructor Destroy; override;

    procedure Subscribe(AConn: TZSSEConnection; const ATopic: string = '*'); overload;
    procedure Subscribe(AConn: TZSSEConnection; const ATopics: array of string); overload;
    function TrySubscribe(AConn: TZSSEConnection; const ATopic: string = '*'): Boolean; overload;
    function TrySubscribe(AConn: TZSSEConnection; const ATopics: array of string): Boolean; overload;
    procedure Unsubscribe(AConn: TZSSEConnection);
    procedure UnsubscribeTopic(AConn: TZSSEConnection; const ATopic: string);

    function Publish(const ATopic, AData: string; const AEvent: string = '';
      const AId: string = ''; ARetryMs: Integer = -1): Integer;
    function Broadcast(const AData: string; const AEvent: string = '';
      const AId: string = ''; ARetryMs: Integer = -1): Integer;
    function BroadcastComment(const AText: string = 'ping'): Integer;

    function ReplaySince(AConn: TZSSEConnection; const ATopic: string = '';
      const ALastEventID: string = ''): Integer;
    function PruneDisconnected: Integer;
    procedure Shutdown;

    procedure ServeConnection(ARequest: TRequest; AResponse: TResponse;
      const ATopic: string = '*';
      AHeartbeatIntervalMs: Integer = SSE_DEFAULT_HEARTBEAT_MS;
      AReplayMissed: Boolean = True;
      APollIntervalMs: Integer = SSE_DEFAULT_POLL_MS); overload;
    procedure ServeConnection(ARequest: TRequest; AResponse: TResponse;
      const ATopics: array of string;
      AHeartbeatIntervalMs: Integer = SSE_DEFAULT_HEARTBEAT_MS;
      AReplayMissed: Boolean = True;
      APollIntervalMs: Integer = SSE_DEFAULT_POLL_MS); overload;

    function ConnectionCount: Integer;
    function TopicSubscriberCount(const ATopic: string): Integer;

    property ReplayBufferSize: Integer read FReplayBufferSize;
    property MaxConnections: Integer read GetMaxConnections write SetMaxConnections;
    property TotalPublished: Int64 read GetTotalPublished;
    property TotalDelivered: Int64 read GetTotalDelivered;
    property TotalDropped: Int64 read GetTotalDropped;
  end;

implementation

{ Internal helper for fast RawByteString appending without quadratic reallocations }
type
  TByteBuffer = record
    Data: RawByteString;
    Len: SizeInt;
    Cap: SizeInt;
  end;

procedure BufInit(out ABuf: TByteBuffer; AInitialCap: SizeInt = 256); inline;
begin
  if AInitialCap < 64 then
    AInitialCap := 64;
  ABuf.Len := 0;
  ABuf.Cap := AInitialCap;
  SetLength(ABuf.Data, ABuf.Cap);
end;

procedure BufGrow(var ABuf: TByteBuffer; ANeeded: SizeInt);
var
  NewCap: SizeInt;
begin
  if ABuf.Len + ANeeded <= ABuf.Cap then
    Exit;
  NewCap := ABuf.Cap * 2;
  while NewCap < ABuf.Len + ANeeded do
    NewCap := NewCap * 2;
  SetLength(ABuf.Data, NewCap);
  ABuf.Cap := NewCap;
end;

procedure BufAppendStr(var ABuf: TByteBuffer; const S: RawByteString); inline;
var
  L: SizeInt;
begin
  L := Length(S);
  if L = 0 then Exit;
  BufGrow(ABuf, L);
  Move(S[1], ABuf.Data[ABuf.Len + 1], L);
  Inc(ABuf.Len, L);
end;

procedure BufAppendMem(var ABuf: TByteBuffer; P: PAnsiChar; ALen: SizeInt); inline;
begin
  if ALen <= 0 then Exit;
  BufGrow(ABuf, ALen);
  Move(P^, ABuf.Data[ABuf.Len + 1], ALen);
  Inc(ABuf.Len, ALen);
end;

procedure BufAppendChar(var ABuf: TByteBuffer; C: AnsiChar); inline;
begin
  BufGrow(ABuf, 1);
  Inc(ABuf.Len);
  ABuf.Data[ABuf.Len] := C;
end;

function BufFinish(var ABuf: TByteBuffer): RawByteString; inline;
begin
  SetLength(ABuf.Data, ABuf.Len);
  Result := ABuf.Data;
end;

{$IFNDEF CPU64}
var
  GSSEAtomicLock: TCriticalSection;

function InterLockedIncrement64(var Target: Int64): Int64;
begin
  GSSEAtomicLock.Enter;
  try
    Inc(Target);
    Result := Target;
  finally
    GSSEAtomicLock.Leave;
  end;
end;

function InterLockedExchangeAdd64(var Target: Int64; Source: Int64): Int64;
begin
  GSSEAtomicLock.Enter;
  try
    Result := Target;
    Inc(Target, Source);
  finally
    GSSEAtomicLock.Leave;
  end;
end;
{$ENDIF}

{ TZSSEFormatter }

class function TZSSEFormatter.SanitizeSingleLine(const AValue: string): string;
var
  I, OutLen: SizeInt;
  C: Char;
begin
  if AValue = '' then
    Exit('');
  SetLength(Result, Length(AValue));
  OutLen := 0;
  for I := 1 to Length(AValue) do
  begin
    C := AValue[I];
    if (C <> #0) and (C <> #13) and (C <> #10) then
    begin
      Inc(OutLen);
      Result[OutLen] := C;
    end;
  end;
  SetLength(Result, OutLen);
end;

class function TZSSEFormatter.FormatEvent(const AData: string; const AEvent: string;
  const AId: string; ARetryMs: Integer): RawByteString;
var
  Buf: TByteBuffer;
  CleanId, CleanEvent: string;
  DataLen, LineStart, I: SizeInt;
begin
  BufInit(Buf, Length(AData) + Length(AEvent) + Length(AId) + 64);

  if AId <> '' then
  begin
    CleanId := SanitizeSingleLine(AId);
    if CleanId <> '' then
    begin
      BufAppendStr(Buf, 'id: ');
      BufAppendStr(Buf, RawByteString(CleanId));
      BufAppendChar(Buf, #10);
    end;
  end;

  if AEvent <> '' then
  begin
    CleanEvent := SanitizeSingleLine(AEvent);
    if CleanEvent <> '' then
    begin
      BufAppendStr(Buf, 'event: ');
      BufAppendStr(Buf, RawByteString(CleanEvent));
      BufAppendChar(Buf, #10);
    end;
  end;

  if ARetryMs >= 0 then
  begin
    BufAppendStr(Buf, 'retry: ');
    BufAppendStr(Buf, RawByteString(IntToStr(ARetryMs)));
    BufAppendChar(Buf, #10);
  end;

  // W3C SSE Section 9.2.6: each line break (CRLF, LF, or CR) produces a separate "data: ..." line
  DataLen := Length(AData);
  if DataLen = 0 then
  begin
    BufAppendStr(Buf, 'data: '#10);
  end
  else
  begin
    LineStart := 1;
    I := 1;
    while I <= DataLen do
    begin
      if (AData[I] = #13) or (AData[I] = #10) then
      begin
        BufAppendStr(Buf, 'data: ');
        if I > LineStart then
          BufAppendMem(Buf, @AData[LineStart], I - LineStart);
        BufAppendChar(Buf, #10);

        if (AData[I] = #13) and (I < DataLen) and (AData[I + 1] = #10) then
          Inc(I, 2)
        else
          Inc(I);
        LineStart := I;
      end
      else
        Inc(I);
    end;

    // Final line (or empty line if the payload ended with a line break)
    BufAppendStr(Buf, 'data: ');
    if LineStart <= DataLen then
      BufAppendMem(Buf, @AData[LineStart], DataLen - LineStart + 1);
    BufAppendChar(Buf, #10);
  end;

  // Blank line terminating the event block (\n\n)
  BufAppendChar(Buf, #10);
  Result := BufFinish(Buf);
end;

class function TZSSEFormatter.FormatEvent(const AEvent: TZSSEEvent): RawByteString;
begin
  Result := FormatEvent(AEvent.Data, AEvent.EventType, AEvent.Id, AEvent.RetryMs);
end;

class function TZSSEFormatter.FormatComment(const AText: string): RawByteString;
var
  Buf: TByteBuffer;
  TextLen, LineStart, I: SizeInt;
begin
  TextLen := Length(AText);
  if TextLen = 0 then
    Exit(':'#10#10);

  BufInit(Buf, TextLen + 16);
  LineStart := 1;
  I := 1;
  while I <= TextLen do
  begin
    if (AText[I] = #13) or (AText[I] = #10) then
    begin
      BufAppendStr(Buf, ': ');
      if I > LineStart then
        BufAppendMem(Buf, @AText[LineStart], I - LineStart);
      BufAppendChar(Buf, #10);

      if (AText[I] = #13) and (I < TextLen) and (AText[I + 1] = #10) then
        Inc(I, 2)
      else
        Inc(I);
      LineStart := I;
    end
    else
      Inc(I);
  end;

  if LineStart <= TextLen then
  begin
    BufAppendStr(Buf, ': ');
    BufAppendMem(Buf, @AText[LineStart], TextLen - LineStart + 1);
    BufAppendChar(Buf, #10);
  end;

  BufAppendChar(Buf, #10);
  Result := BufFinish(Buf);
end;

class function TZSSEFormatter.FormatRetry(ARetryMs: Integer): RawByteString;
begin
  if ARetryMs < 0 then
    ARetryMs := 0;
  Result := RawByteString('retry: ' + IntToStr(ARetryMs) + #10#10);
end;

class function TZSSEFormatter.ExtractLastEventID(ARequest: TRequest): string;
var
  I: Integer;
  N, V: string;
begin
  Result := '';
  if not Assigned(ARequest) then
    Exit;

  // 1. Direct lookup via CustomHeaders (standard HTTPDefs behavior)
  Result := Trim(ARequest.GetCustomHeader('Last-Event-ID'));
  if Result <> '' then
    Exit;

  // 2. Case-insensitive scan across CustomHeaders (clients may send last-event-id)
  if Assigned(ARequest.CustomHeaders) then
  begin
    for I := 0 to ARequest.CustomHeaders.Count - 1 do
    begin
      ARequest.CustomHeaders.GetNameValue(I, N, V);
      if SameText(Trim(N), 'Last-Event-ID') then
      begin
        Result := Trim(V);
        if Result <> '' then
          Exit;
      end;
    end;
  end;

  // 3. Optional query string fallback (EventSource polyfills / proxies)
  if Assigned(ARequest.QueryFields) then
    Result := Trim(ARequest.QueryFields.Values['lastEventId']);
end;

{ TZSSEStream }

constructor TZSSEStream.Create(AStream: TStream; AOwnsStream: Boolean);
begin
  inherited Create;
  if not Assigned(AStream) then
    raise EZSSEError.Create('SSE stream cannot be nil');
  FStream := AStream;
  FOwnsStream := AOwnsStream;
  FWriteLock := TCriticalSection.Create;
  FConnected := True;
  FHeadersSent := False;
  FBytesSent := 0;
  FEventsSent := 0;
  FLastActivityTick := GetTickCount64;

  if FStream is TSocketStream then
  begin
    FSocketHandle := TSocketStream(FStream).Handle;
    {$IF DEFINED(Linux) OR DEFINED(FreeBSD)}
    TSocketStream(FStream).WriteFlags := TSocketStream(FStream).WriteFlags or MSG_NOSIGNAL;
    TSocketStream(FStream).ReadFlags := TSocketStream(FStream).ReadFlags or MSG_NOSIGNAL;
    {$ENDIF}
  end
  else
    FSocketHandle := -1;
end;

destructor TZSSEStream.Destroy;
begin
  Close;
  if FOwnsStream then
    FreeAndNil(FStream);
  FreeAndNil(FWriteLock);
  inherited Destroy;
end;

class procedure TZSSEStream.ApplyHeaders(AResponse: TResponse);
begin
  if not Assigned(AResponse) then
    raise EZSSEError.Create('HTTP response cannot be nil');

  AResponse.Code := 200;
  AResponse.CodeText := 'OK';
  AResponse.ContentType := SSE_CONTENT_TYPE;
  AResponse.CacheControl := SSE_CACHE_CONTROL;
  AResponse.SetFieldByName('Connection', SSE_CONNECTION);
  AResponse.SetCustomHeader('X-Accel-Buffering', SSE_ACCEL_BUFFERING);
  AResponse.Contents.Clear;
end;

function TZSSEStream.GetConnected: Boolean;
begin
  FWriteLock.Enter;
  try
    Result := FConnected;
  finally
    FWriteLock.Leave;
  end;
end;

function TZSSEStream.GetBytesSent: Int64;
begin
  FWriteLock.Enter;
  try
    Result := FBytesSent;
  finally
    FWriteLock.Leave;
  end;
end;

function TZSSEStream.GetEventsSent: Int64;
begin
  FWriteLock.Enter;
  try
    Result := FEventsSent;
  finally
    FWriteLock.Leave;
  end;
end;

procedure TZSSEStream.SetConnected(AValue: Boolean);
begin
  FWriteLock.Enter;
  try
    FConnected := AValue;
  finally
    FWriteLock.Leave;
  end;
end;

procedure TZSSEStream.TouchActivity;
begin
  FLastActivityTick := GetTickCount64;
end;

function TZSSEStream.SendRaw(const ARaw: RawByteString): Boolean;
var
  TotalLen, Offset, Written: LongInt;
begin
  Result := False;
  TotalLen := Length(ARaw);
  if TotalLen = 0 then
    Exit(GetConnected);

  FWriteLock.Enter;
  try
    if (not FConnected) or (not Assigned(FStream)) then
      Exit(False);

    Offset := 1;
    try
      while Offset <= TotalLen do
      begin
        Written := FStream.Write(ARaw[Offset], TotalLen - Offset + 1);
        if Written <= 0 then
        begin
          FConnected := False;
          Exit(False);
        end;
        Inc(Offset, Written);
        Inc(FBytesSent, Written);
      end;
      FLastActivityTick := GetTickCount64;
      Result := True;
    except
      // Any socket/stream error (EPIPE, ECONNRESET, etc.) cleanly closes the connection
      FConnected := False;
      Result := False;
    end;
  finally
    FWriteLock.Leave;
  end;
end;

function TZSSEStream.SendEvent(const AData: string; const AEvent: string;
  const AId: string; ARetryMs: Integer): Boolean;
var
  Payload: RawByteString;
begin
  Payload := TZSSEFormatter.FormatEvent(AData, AEvent, AId, ARetryMs);
  Result := SendRaw(Payload);
  if Result then
  begin
    FWriteLock.Enter;
    try
      Inc(FEventsSent);
    finally
      FWriteLock.Leave;
    end;
  end;
end;

function TZSSEStream.SendEvent(const AEvent: TZSSEEvent): Boolean;
begin
  Result := SendEvent(AEvent.Data, AEvent.EventType, AEvent.Id, AEvent.RetryMs);
end;

function TZSSEStream.SendComment(const AText: string): Boolean;
var
  Payload: RawByteString;
begin
  Payload := TZSSEFormatter.FormatComment(AText);
  Result := SendRaw(Payload);
end;

function TZSSEStream.SendRetry(ARetryMs: Integer): Boolean;
var
  Payload: RawByteString;
begin
  Payload := TZSSEFormatter.FormatRetry(ARetryMs);
  Result := SendRaw(Payload);
end;

function TZSSEStream.CheckDisconnected: Boolean;
{$IFDEF UNIX}
var
  PeekBuf: Byte;
  Res: ssize_t;
  Err: LongInt;
{$ENDIF}
{$IFDEF WINDOWS}
var
  ReadSet: TFDSet;
  TV: TTimeVal;
  PeekBuf: Byte;
  Res: LongInt;
{$ENDIF}
begin
  if not GetConnected then
    Exit(True);

  if FSocketHandle < 0 then
    Exit(False);

  {$IFDEF UNIX}
  PeekBuf := 0;
  Res := fpRecv(FSocketHandle, @PeekBuf, 1, MSG_PEEK or MSG_DONTWAIT);
  if Res = 0 then
  begin
    // Peer sent FIN (orderly shutdown)
    SetConnected(False);
    Exit(True);
  end
  else if Res < 0 then
  begin
    Err := socketerror;
    if (Err <> EsockEWOULDBLOCK) and (Err <> ESysEAGAIN) and (Err <> ESysEINTR) then
    begin
      // Fatal socket error (ECONNRESET, EPIPE, EBADF, ENOTCONN, etc.)
      SetConnected(False);
      Exit(True);
    end;
  end;
  Result := False;
  {$ELSE}
  {$IFDEF WINDOWS}
  FD_ZERO(ReadSet);
  FD_SET(FSocketHandle, ReadSet);
  TV.tv_sec := 0;
  TV.tv_usec := 0;
  Res := select(0, @ReadSet, nil, nil, @TV);
  if Res > 0 then
  begin
    PeekBuf := 0;
    Res := recv(FSocketHandle, PeekBuf, 1, MSG_PEEK);
    if Res <= 0 then
    begin
      SetConnected(False);
      Exit(True);
    end;
  end
  else if Res < 0 then
  begin
    SetConnected(False);
    Exit(True);
  end;
  Result := False;
  {$ELSE}
  Result := False;
  {$ENDIF}
  {$ENDIF}
end;

procedure TZSSEStream.Close;
begin
  SetConnected(False);
end;

{ TZSSEConnection }

class function TZSSEConnection.GenerateClientID: string;
var
  Seq: Int64;
begin
  Seq := InterLockedIncrement64(FNextClientSeq);
  Result := 'sse-' + IntToStr(Seq);
end;

constructor TZSSEConnection.Create(ARequest: TRequest; AResponse: TResponse;
  const AClientID: string);
var
  Sock: TSocketStream;
begin
  if not Assigned(ARequest) then
    raise EZSSEError.Create('HTTP request cannot be nil');
  if not Assigned(AResponse) then
    raise EZSSEError.Create('HTTP response cannot be nil');

  Sock := nil;
  if (ARequest is TFPHTTPConnectionRequest) and
     Assigned(TFPHTTPConnectionRequest(ARequest).Connection) then
    Sock := TFPHTTPConnectionRequest(ARequest).Connection.Socket;

  if not Assigned(Sock) then
    raise EZSSEError.Create('Underlying socket stream not available on request');

  inherited Create(Sock, False);

  if AClientID <> '' then
    FClientID := AClientID
  else
    FClientID := GenerateClientID;

  FLastEventID := TZSSEFormatter.ExtractLastEventID(ARequest);
  FCreatedAt := Now;
  FTopicsLock := TCriticalSection.Create;
  FTopics := TStringList.Create;
  FTopics.Sorted := True;
  FTopics.Duplicates := dupIgnore;
  FTopics.CaseSensitive := False;
  FStopEvent := TEvent.Create(nil, True, False, '');
  FDispatchLock := TCriticalSection.Create;
  FDispatchIdleEvent := TEvent.Create(nil, True, True, '');
  FActiveDispatches := 0;
  FHeartbeatsSent := 0;

  // Apply canonical W3C headers and flush immediately to open the event stream
  ApplyHeaders(AResponse);
  if not AResponse.HeadersSent then
    AResponse.SendHeaders;
  HeadersSent := True;
end;

constructor TZSSEConnection.CreateFromStream(AStream: TStream; const ALastEventID: string;
  const AClientID: string; AOwnsStream: Boolean);
begin
  inherited Create(AStream, AOwnsStream);

  if AClientID <> '' then
    FClientID := AClientID
  else
    FClientID := GenerateClientID;

  FLastEventID := Trim(ALastEventID);
  FCreatedAt := Now;
  FTopicsLock := TCriticalSection.Create;
  FTopics := TStringList.Create;
  FTopics.Sorted := True;
  FTopics.Duplicates := dupIgnore;
  FTopics.CaseSensitive := False;
  FStopEvent := TEvent.Create(nil, True, False, '');
  FDispatchLock := TCriticalSection.Create;
  FDispatchIdleEvent := TEvent.Create(nil, True, True, '');
  FActiveDispatches := 0;
  FHeartbeatsSent := 0;
end;

destructor TZSSEConnection.Destroy;
begin
  Close;
  WaitForDispatches;
  FreeAndNil(FDispatchIdleEvent);
  FreeAndNil(FDispatchLock);
  FreeAndNil(FStopEvent);
  FreeAndNil(FTopics);
  FreeAndNil(FTopicsLock);
  inherited Destroy;
end;

procedure TZSSEConnection.AcquireDispatch;
begin
  FDispatchLock.Enter;
  try
    Inc(FActiveDispatches);
    if FActiveDispatches = 1 then
      FDispatchIdleEvent.ResetEvent;
  finally
    FDispatchLock.Leave;
  end;
end;

procedure TZSSEConnection.ReleaseDispatch;
begin
  FDispatchLock.Enter;
  try
    Dec(FActiveDispatches);
    if FActiveDispatches <= 0 then
    begin
      FActiveDispatches := 0;
      FDispatchIdleEvent.SetEvent;
    end;
  finally
    FDispatchLock.Leave;
  end;
end;

procedure TZSSEConnection.WaitForDispatches;
begin
  while True do
  begin
    FDispatchLock.Enter;
    try
      if FActiveDispatches <= 0 then
        Exit;
    finally
      FDispatchLock.Leave;
    end;
    FDispatchIdleEvent.WaitFor(INFINITE);
  end;
end;

procedure TZSSEConnection.AddTopic(const ATopic: string);
var
  T: string;
begin
  T := Trim(ATopic);
  if T = '' then Exit;
  FTopicsLock.Enter;
  try
    FTopics.Add(T);
  finally
    FTopicsLock.Leave;
  end;
end;

procedure TZSSEConnection.RemoveTopic(const ATopic: string);
var
  Idx: Integer;
begin
  FTopicsLock.Enter;
  try
    Idx := FTopics.IndexOf(Trim(ATopic));
    if Idx >= 0 then
      FTopics.Delete(Idx);
  finally
    FTopicsLock.Leave;
  end;
end;

function TZSSEConnection.HasTopic(const ATopic: string): Boolean;
begin
  FTopicsLock.Enter;
  try
    Result := (FTopics.IndexOf('*') >= 0) or (FTopics.IndexOf(Trim(ATopic)) >= 0);
  finally
    FTopicsLock.Leave;
  end;
end;

procedure TZSSEConnection.ClearTopics;
begin
  FTopicsLock.Enter;
  try
    FTopics.Clear;
  finally
    FTopicsLock.Leave;
  end;
end;

procedure TZSSEConnection.Close;
begin
  inherited Close;
  if Assigned(FStopEvent) then
    FStopEvent.SetEvent;
end;

procedure TZSSEConnection.WaitLoop(AHeartbeatIntervalMs: Integer;
  APollIntervalMs: Integer; AMaxDurationMs: Integer);
var
  StartTick, NowTick, SinceActivity, WaitMs, RemainingHeartbeat, RemainingMax: QWord;
  WaitRes: TWaitResult;
begin
  if APollIntervalMs < 10 then
    APollIntervalMs := 10;

  StartTick := GetTickCount64;

  while Connected do
  begin
    if CheckDisconnected then
      Break;

    NowTick := GetTickCount64;

    if (AMaxDurationMs > 0) and (NowTick - StartTick >= QWord(AMaxDurationMs)) then
      Break;

    // Check whether it is time to send a heartbeat comment (: ping\n\n)
    if AHeartbeatIntervalMs > 0 then
    begin
      SinceActivity := NowTick - LastActivityTick;
      if SinceActivity >= QWord(AHeartbeatIntervalMs) then
      begin
        if not SendComment('ping') then
          Break;
        InterLockedIncrement64(FHeartbeatsSent);
        NowTick := GetTickCount64;
      end;
    end;

    // Compute shortest wait interval to wake on the next poll or heartbeat
    WaitMs := QWord(APollIntervalMs);
    if AHeartbeatIntervalMs > 0 then
    begin
      SinceActivity := NowTick - LastActivityTick;
      if SinceActivity < QWord(AHeartbeatIntervalMs) then
        RemainingHeartbeat := QWord(AHeartbeatIntervalMs) - SinceActivity
      else
        RemainingHeartbeat := 1;
      if RemainingHeartbeat < WaitMs then
        WaitMs := RemainingHeartbeat;
    end;

    if AMaxDurationMs > 0 then
    begin
      if NowTick - StartTick < QWord(AMaxDurationMs) then
        RemainingMax := QWord(AMaxDurationMs) - (NowTick - StartTick)
      else
        RemainingMax := 0;
      if RemainingMax = 0 then
        Break;
      if RemainingMax < WaitMs then
        WaitMs := RemainingMax;
    end;

    if WaitMs < 1 then
      WaitMs := 1;

    WaitRes := FStopEvent.WaitFor(Cardinal(WaitMs));
    if WaitRes = wrSignaled then
      Break;
  end;
end;

{ TZSSEBroker }

constructor TZSSEBroker.Create(AReplayBufferSize: Integer; AMaxConnections: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FConnections := TList.Create;
  if AReplayBufferSize < 0 then
    AReplayBufferSize := 0;
  FReplayBufferSize := AReplayBufferSize;
  if AMaxConnections < 0 then
    AMaxConnections := 0;
  FMaxConnections := AMaxConnections;
  if FReplayBufferSize > 0 then
    SetLength(FHistory, FReplayBufferSize)
  else
    SetLength(FHistory, 0);
  FHistoryHead := 0;
  FHistoryCount := 0;
  FShuttingDown := False;
  FTotalPublished := 0;
  FTotalDelivered := 0;
  FTotalDropped := 0;
end;

destructor TZSSEBroker.Destroy;
begin
  Shutdown;
  FLock.Enter;
  try
    FConnections.Clear;
  finally
    FLock.Leave;
  end;
  FreeAndNil(FConnections);
  FreeAndNil(FLock);
  SetLength(FHistory, 0);
  inherited Destroy;
end;

procedure TZSSEBroker.RecordEventLocked(const AEvent: TZSSEEvent);
var
  Slot: Integer;
begin
  if (FReplayBufferSize <= 0) or (AEvent.Id = '') then
    Exit;

  Slot := (FHistoryHead + FHistoryCount) mod FReplayBufferSize;
  FHistory[Slot] := AEvent;
  if FHistoryCount < FReplayBufferSize then
    Inc(FHistoryCount)
  else
    FHistoryHead := (FHistoryHead + 1) mod FReplayBufferSize;
end;

function TZSSEBroker.GetTotalPublished: Int64;
begin
  Result := InterLockedExchangeAdd64(FTotalPublished, 0);
end;

function TZSSEBroker.GetTotalDelivered: Int64;
begin
  Result := InterLockedExchangeAdd64(FTotalDelivered, 0);
end;

function TZSSEBroker.GetTotalDropped: Int64;
begin
  Result := InterLockedExchangeAdd64(FTotalDropped, 0);
end;

function TZSSEBroker.GetMaxConnections: Integer;
begin
  FLock.Enter;
  try
    Result := FMaxConnections;
  finally
    FLock.Leave;
  end;
end;

procedure TZSSEBroker.SetMaxConnections(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  FLock.Enter;
  try
    FMaxConnections := AValue;
  finally
    FLock.Leave;
  end;
end;

function TZSSEBroker.TrySubscribe(AConn: TZSSEConnection; const ATopic: string): Boolean;
begin
  Result := False;
  if not Assigned(AConn) then
    Exit;

  AConn.AddTopic(ATopic);

  FLock.Enter;
  try
    if FShuttingDown then
    begin
      AConn.Close;
      Exit(False);
    end;
    if FConnections.IndexOf(AConn) >= 0 then
      Exit(True);
    if (FMaxConnections > 0) and (FConnections.Count >= FMaxConnections) then
      Exit(False);
    FConnections.Add(AConn);
    Result := True;
  finally
    FLock.Leave;
  end;
end;

function TZSSEBroker.TrySubscribe(AConn: TZSSEConnection; const ATopics: array of string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if not Assigned(AConn) then
    Exit;

  for I := Low(ATopics) to High(ATopics) do
    AConn.AddTopic(ATopics[I]);

  FLock.Enter;
  try
    if FShuttingDown then
    begin
      AConn.Close;
      Exit(False);
    end;
    if FConnections.IndexOf(AConn) >= 0 then
      Exit(True);
    if (FMaxConnections > 0) and (FConnections.Count >= FMaxConnections) then
      Exit(False);
    FConnections.Add(AConn);
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TZSSEBroker.Subscribe(AConn: TZSSEConnection; const ATopic: string);
begin
  TrySubscribe(AConn, ATopic);
end;

procedure TZSSEBroker.Subscribe(AConn: TZSSEConnection; const ATopics: array of string);
begin
  TrySubscribe(AConn, ATopics);
end;

procedure TZSSEBroker.Unsubscribe(AConn: TZSSEConnection);
begin
  if not Assigned(AConn) then
    Exit;

  FLock.Enter;
  try
    FConnections.Remove(AConn);
  finally
    FLock.Leave;
  end;

  // Wait for any in-flight dispatches to complete before caller frees AConn
  AConn.WaitForDispatches;
end;

procedure TZSSEBroker.UnsubscribeTopic(AConn: TZSSEConnection; const ATopic: string);
begin
  if not Assigned(AConn) then
    Exit;
  AConn.RemoveTopic(ATopic);
end;

function TZSSEBroker.DispatchRaw(const ATopic: string; const ARaw: RawByteString;
  ABroadcastAll: Boolean): Integer;
var
  Targets: array of TZSSEConnection;
  Dead: array of TZSSEConnection;
  TargetCount, DeadCount, I: Integer;
  Conn: TZSSEConnection;
begin
  Result := 0;
  TargetCount := 0;
  DeadCount := 0;

  // 1. Fast snapshot under lock, pinning active connections via AcquireDispatch
  FLock.Enter;
  try
    if FConnections.Count = 0 then
      Exit(0);

    SetLength(Targets, FConnections.Count);
    for I := 0 to FConnections.Count - 1 do
    begin
      Conn := TZSSEConnection(FConnections[I]);
      if not Conn.Connected then
      begin
        SetLength(Dead, DeadCount + 1);
        Dead[DeadCount] := Conn;
        Inc(DeadCount);
        Continue;
      end;

      if ABroadcastAll or Conn.HasTopic(ATopic) then
      begin
        Conn.AcquireDispatch;
        Targets[TargetCount] := Conn;
        Inc(TargetCount);
      end;
    end;

    // Remove connections already marked as closed
    for I := 0 to DeadCount - 1 do
      FConnections.Remove(Dead[I]);
  finally
    FLock.Leave;
  end;

  DeadCount := 0;
  SetLength(Dead, 0);

  // 2. Lock-free dispatch (no global lock held during network I/O)
  for I := 0 to TargetCount - 1 do
  begin
    Conn := Targets[I];
    try
      if Conn.SendRaw(ARaw) then
      begin
        Inc(Result);
        InterLockedIncrement64(FTotalDelivered);
      end
      else
      begin
        InterLockedIncrement64(FTotalDropped);
        SetLength(Dead, DeadCount + 1);
        Dead[DeadCount] := Conn;
        Inc(DeadCount);
      end;
    finally
      Conn.ReleaseDispatch;
    end;
  end;

  // 3. Immediate cleanup of broken connections discovered during dispatch
  if DeadCount > 0 then
  begin
    FLock.Enter;
    try
      for I := 0 to DeadCount - 1 do
        FConnections.Remove(Dead[I]);
    finally
      FLock.Leave;
    end;

    for I := 0 to DeadCount - 1 do
      Dead[I].Close;
  end;
end;

function TZSSEBroker.Publish(const ATopic, AData: string; const AEvent: string;
  const AId: string; ARetryMs: Integer): Integer;
var
  Ev: TZSSEEvent;
  Raw: RawByteString;
begin
  Ev.Id := TZSSEFormatter.SanitizeSingleLine(AId);
  Ev.EventType := TZSSEFormatter.SanitizeSingleLine(AEvent);
  Ev.Data := AData;
  Ev.RetryMs := ARetryMs;
  Ev.Topic := Trim(ATopic);
  Ev.Timestamp := Now;

  Raw := TZSSEFormatter.FormatEvent(Ev);
  InterLockedIncrement64(FTotalPublished);

  if (FReplayBufferSize > 0) and (Ev.Id <> '') then
  begin
    FLock.Enter;
    try
      RecordEventLocked(Ev);
    finally
      FLock.Leave;
    end;
  end;

  Result := DispatchRaw(Ev.Topic, Raw, False);
end;

function TZSSEBroker.Broadcast(const AData: string; const AEvent: string;
  const AId: string; ARetryMs: Integer): Integer;
var
  Ev: TZSSEEvent;
  Raw: RawByteString;
begin
  Ev.Id := TZSSEFormatter.SanitizeSingleLine(AId);
  Ev.EventType := TZSSEFormatter.SanitizeSingleLine(AEvent);
  Ev.Data := AData;
  Ev.RetryMs := ARetryMs;
  Ev.Topic := '*';
  Ev.Timestamp := Now;

  Raw := TZSSEFormatter.FormatEvent(Ev);
  InterLockedIncrement64(FTotalPublished);

  if (FReplayBufferSize > 0) and (Ev.Id <> '') then
  begin
    FLock.Enter;
    try
      RecordEventLocked(Ev);
    finally
      FLock.Leave;
    end;
  end;

  Result := DispatchRaw('*', Raw, True);
end;

function TZSSEBroker.BroadcastComment(const AText: string): Integer;
var
  Raw: RawByteString;
begin
  Raw := TZSSEFormatter.FormatComment(AText);
  Result := DispatchRaw('*', Raw, True);
end;

function TZSSEBroker.ReplaySince(AConn: TZSSEConnection; const ATopic: string;
  const ALastEventID: string): Integer;
var
  TargetId, FilterTopic: string;
  Snapshot: array of TZSSEEvent;
  SnapCount, I, Idx, FoundPos: Integer;
  Ev: TZSSEEvent;
begin
  Result := 0;
  if not Assigned(AConn) then
    Exit;

  TargetId := Trim(ALastEventID);
  if TargetId = '' then
    TargetId := AConn.LastEventID;
  if TargetId = '' then
    Exit(0);

  FilterTopic := Trim(ATopic);
  SnapCount := 0;
  FoundPos := -1;

  FLock.Enter;
  try
    if FHistoryCount = 0 then
      Exit(0);

    // Locate the latest occurrence of TargetId in the ring buffer
    for I := 0 to FHistoryCount - 1 do
    begin
      Idx := (FHistoryHead + I) mod FReplayBufferSize;
      if FHistory[Idx].Id = TargetId then
        FoundPos := I;
    end;

    if (FoundPos < 0) or (FoundPos >= FHistoryCount - 1) then
      Exit(0);

    SetLength(Snapshot, FHistoryCount - FoundPos - 1);
    for I := FoundPos + 1 to FHistoryCount - 1 do
    begin
      Idx := (FHistoryHead + I) mod FReplayBufferSize;
      Ev := FHistory[Idx];
      if (FilterTopic <> '') and (FilterTopic <> '*') then
      begin
        if (Ev.Topic = '*') or SameText(Ev.Topic, FilterTopic) then
        begin
          Snapshot[SnapCount] := Ev;
          Inc(SnapCount);
        end;
      end
      else
      begin
        if (Ev.Topic = '*') or (FilterTopic = '*') or AConn.HasTopic(Ev.Topic) then
        begin
          Snapshot[SnapCount] := Ev;
          Inc(SnapCount);
        end;
      end;
    end;
  finally
    FLock.Leave;
  end;

  for I := 0 to SnapCount - 1 do
  begin
    if not AConn.SendEvent(Snapshot[I]) then
      Break;
    Inc(Result);
  end;
end;

function TZSSEBroker.PruneDisconnected: Integer;
var
  I: Integer;
  Conn: TZSSEConnection;
begin
  Result := 0;
  FLock.Enter;
  try
    for I := FConnections.Count - 1 downto 0 do
    begin
      Conn := TZSSEConnection(FConnections[I]);
      if (not Conn.Connected) or Conn.CheckDisconnected then
      begin
        FConnections.Delete(I);
        Conn.Close;
        Inc(Result);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TZSSEBroker.Shutdown;
var
  I: Integer;
  Snapshot: array of TZSSEConnection;
begin
  FLock.Enter;
  try
    FShuttingDown := True;
    SetLength(Snapshot, FConnections.Count);
    for I := 0 to FConnections.Count - 1 do
      Snapshot[I] := TZSSEConnection(FConnections[I]);
    FConnections.Clear;
  finally
    FLock.Leave;
  end;

  // Signal all connections to exit WaitLoop immediately
  for I := 0 to High(Snapshot) do
    Snapshot[I].Close;
end;

procedure TZSSEBroker.ServeConnection(ARequest: TRequest; AResponse: TResponse;
  const ATopic: string; AHeartbeatIntervalMs: Integer; AReplayMissed: Boolean;
  APollIntervalMs: Integer);
begin
  ServeConnection(ARequest, AResponse, [ATopic], AHeartbeatIntervalMs, AReplayMissed, APollIntervalMs);
end;

procedure TZSSEBroker.ServeConnection(ARequest: TRequest; AResponse: TResponse;
  const ATopics: array of string; AHeartbeatIntervalMs: Integer; AReplayMissed: Boolean;
  APollIntervalMs: Integer);
var
  Conn: TZSSEConnection;
  AtCapacity: Boolean;
begin
  PruneDisconnected;

  FLock.Enter;
  try
    AtCapacity := FShuttingDown or
      ((FMaxConnections > 0) and (FConnections.Count >= FMaxConnections));
  finally
    FLock.Leave;
  end;

  if AtCapacity then
  begin
    if Assigned(AResponse) then
    begin
      AResponse.Code := 503;
      AResponse.CodeText := 'Service Unavailable';
      AResponse.ContentType := 'application/problem+json; charset=utf-8';
      AResponse.SetCustomHeader('Retry-After', '5');
      AResponse.Content :=
        '{"type":"https://tools.ietf.org/html/rfc9457",' +
        '"title":"Service Unavailable",' +
        '"status":503,' +
        '"detail":"Maximum concurrent SSE connections reached. Please retry after 5 seconds."}';
      if not AResponse.HeadersSent then
        AResponse.SendContent;
    end;
    Exit;
  end;

  Conn := TZSSEConnection.Create(ARequest, AResponse);
  try
    if not TrySubscribe(Conn, ATopics) then
    begin
      Conn.Close;
      Exit;
    end;
    try
      if AReplayMissed and (Conn.LastEventID <> '') then
      begin
        if Length(ATopics) = 1 then
          ReplaySince(Conn, ATopics[0], Conn.LastEventID)
        else
          ReplaySince(Conn, '', Conn.LastEventID);
      end;
      Conn.WaitLoop(AHeartbeatIntervalMs, APollIntervalMs);
    finally
      Unsubscribe(Conn);
    end;
  finally
    Conn.Free;
  end;
end;

function TZSSEBroker.ConnectionCount: Integer;
begin
  FLock.Enter;
  try
    Result := FConnections.Count;
  finally
    FLock.Leave;
  end;
end;

function TZSSEBroker.TopicSubscriberCount(const ATopic: string): Integer;
var
  I: Integer;
  Conn: TZSSEConnection;
begin
  Result := 0;
  FLock.Enter;
  try
    for I := 0 to FConnections.Count - 1 do
    begin
      Conn := TZSSEConnection(FConnections[I]);
      if Conn.Connected and Conn.HasTopic(ATopic) then
        Inc(Result);
    end;
  finally
    FLock.Leave;
  end;
end;

{$IFNDEF CPU64}
initialization
  GSSEAtomicLock := TCriticalSection.Create;

finalization
  GSSEAtomicLock.Free;
{$ENDIF}

end.
