{
    Zenith Framework - W3C Server-Sent Events (SSE) Test Suite & Benchmark
    FPCUnit tests covering:
    - HTML Living Standard Section 9.2 wire formatting (single/multi-line, UTF-8/emojis, id, event, retry, comments)
    - Canonical HTTP headers (Content-Type, Cache-Control, Connection, X-Accel-Buffering)
    - Last-Event-ID extraction and ring-buffer replay on reconnect
    - TZSSEBroker multi-topic concurrent pub/sub
    - Real TCP/HTTP server with TZenithThreadPool: heartbeat, abrupt disconnect, zero thread-leak
    - Throughput benchmark (events/sec & deliveries/sec)
}

{$mode objfpc}{$H+}

unit test_zenith_sse;

interface

uses
  Classes, SysUtils, SyncObjs, fpcunit, testregistry,
  httpdefs, fphttpserver, ssockets, sockets,
  Zenith.SSE, Zenith.ThreadPool;

type
  { TTestZenithSSE }
  TTestZenithSSE = class(TTestCase)
  published
    procedure TestFormatSingleLineEvent;
    procedure TestFormatMultiLineDataLF_CRLF_CR;
    procedure TestFormatEmptyDataEvent;
    procedure TestFormatUTF8AndEmojis;
    procedure TestFormatFullFieldsAndSanitization;
    procedure TestFormatCommentsAndRetry;
    procedure TestApplyCanonicalHeaders;
    procedure TestExtractLastEventID;
    procedure TestStreamWriteAndClose;
    procedure TestBrokerTopicRoutingAndWildcard;
    procedure TestBrokerMultiTopicSubscriptionAndScopedDelivery;
    procedure TestBrokerReplaySinceLastEventID;
    procedure TestBrokerConcurrentMultiSubscriber;
    procedure TestLiveServerHeadersEventsHeartbeatAndResume;
    procedure TestLiveServerAbruptDisconnectZeroThreadLeak;
    procedure TestBrokerMaxConnectionsLimitReturns503;
    procedure TestBenchmarkEventsPerSecond;
  end;

implementation

const
  TEST_SSE_PORT_BASE = 18940;

type
  { Mock TRequest to test Last-Event-ID extraction without a socket }
  TMockSSERequest = class(TRequest)
  public
    constructor Create; override;
  end;

  { Mock TResponse to validate canonical W3C headers }
  TMockSSEResponse = class(TResponse)
  protected
    procedure DoSendHeaders(Headers: TStrings); override;
    procedure DoSendContent; override;
  public
    SentHeaders: TStringList;
    constructor Create(ARequest: TRequest); reintroduce;
    destructor Destroy; override;
  end;

  { TStream that intentionally fails after N bytes to simulate a broken pipe }
  TFailingStream = class(TMemoryStream)
  private
    FFailAfterBytes: Int64;
    FWrittenTotal: Int64;
  public
    constructor Create(AFailAfterBytes: Int64);
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

  { Publisher thread for concurrent TZSSEBroker stress testing }
  TPublisherThread = class(TThread)
  private
    FBroker: TZSSEBroker;
    FTopic: string;
    FCount: Integer;
    FWorkerId: Integer;
    FDeliveredSum: Int64;
  protected
    procedure Execute; override;
  public
    constructor Create(ABroker: TZSSEBroker; const ATopic: string;
      ACount, AWorkerId: Integer);
    property DeliveredSum: Int64 read FDeliveredSum;
  end;

  { Real background HTTP server for live SSE integration tests }
  TSSEServerThread = class(TThread)
  private
    FServer: TFPHttpServer;
    FBroker: TZSSEBroker;
    FPort: Word;
    FHeartbeatMs: Integer;
    FPollMs: Integer;
    FReadyEvent: TEvent;
    FStartError: string;
    procedure HandleRequest(Sender: TObject;
      var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Word; ABroker: TZSSEBroker;
      AHeartbeatMs: Integer = 150; APollMs: Integer = 30;
      AThreadPoolSize: Integer = 4);
    destructor Destroy; override;
    function WaitReady(ATimeoutMs: Cardinal = 3000): Boolean;
    procedure StopServer;
    property Server: TFPHttpServer read FServer;
    property StartError: string read FStartError;
  end;

{ TMockSSERequest }

constructor TMockSSERequest.Create;
begin
  inherited Create;
end;

{ TMockSSEResponse }

constructor TMockSSEResponse.Create(ARequest: TRequest);
begin
  inherited Create(ARequest);
  SentHeaders := TStringList.Create;
end;

destructor TMockSSEResponse.Destroy;
begin
  FreeAndNil(SentHeaders);
  inherited Destroy;
end;

procedure TMockSSEResponse.DoSendHeaders(Headers: TStrings);
begin
  SentHeaders.Assign(Headers);
end;

procedure TMockSSEResponse.DoSendContent;
begin
  // No-op
end;

{ TFailingStream }

constructor TFailingStream.Create(AFailAfterBytes: Int64);
begin
  inherited Create;
  FFailAfterBytes := AFailAfterBytes;
  FWrittenTotal := 0;
end;

function TFailingStream.Write(const Buffer; Count: Longint): Longint;
begin
  if FWrittenTotal >= FFailAfterBytes then
    raise EWriteError.Create('Simulated EPIPE broken pipe');
  Result := inherited Write(Buffer, Count);
  Inc(FWrittenTotal, Result);
end;

{ TPublisherThread }

constructor TPublisherThread.Create(ABroker: TZSSEBroker; const ATopic: string;
  ACount, AWorkerId: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FBroker := ABroker;
  FTopic := ATopic;
  FCount := ACount;
  FWorkerId := AWorkerId;
  FDeliveredSum := 0;
end;

procedure TPublisherThread.Execute;
var
  I: Integer;
begin
  for I := 1 to FCount do
    Inc(FDeliveredSum, FBroker.Publish(
      FTopic,
      Format('{"worker":%d,"seq":%d}', [FWorkerId, I]),
      'TMetric',
      Format('%d-%d', [FWorkerId, I])
    ));
end;

{ TSSEServerThread }

constructor TSSEServerThread.Create(APort: Word; ABroker: TZSSEBroker;
  AHeartbeatMs: Integer; APollMs: Integer; AThreadPoolSize: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPort := APort;
  FBroker := ABroker;
  FHeartbeatMs := AHeartbeatMs;
  FPollMs := APollMs;
  FReadyEvent := TEvent.Create(nil, True, False, '');
  FStartError := '';

  FServer := TFPHttpServer.Create(nil);
  FServer.Port := FPort;
  FServer.Threaded := True;
  FServer.UseThreadPool := True;
  FServer.ThreadPoolSize := AThreadPoolSize;
  FServer.AcceptIdleTimeout := 50;
  FServer.OnRequest := @HandleRequest;
end;

destructor TSSEServerThread.Destroy;
begin
  StopServer;
  FreeAndNil(FServer);
  FreeAndNil(FReadyEvent);
  inherited Destroy;
end;

procedure TSSEServerThread.HandleRequest(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  Topic: string;
begin
  if Pos('/events/metrics', ARequest.PathInfo) = 1 then
    Topic := 'metrics'
  else if Pos('/events/notifications', ARequest.PathInfo) = 1 then
    Topic := 'notifications'
  else
    Topic := '*';

  FBroker.ServeConnection(ARequest, AResponse, Topic, FHeartbeatMs, True, FPollMs);
end;

procedure TSSEServerThread.Execute;
begin
  try
    FReadyEvent.SetEvent;
    FServer.Active := True;
  except
    on E: Exception do
    begin
      FStartError := E.Message;
      FReadyEvent.SetEvent;
    end;
  end;
end;

function TSSEServerThread.WaitReady(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FReadyEvent.WaitFor(ATimeoutMs) = wrSignaled;
  Sleep(80); // Wait for bind/listen to complete
end;

procedure TSSEServerThread.StopServer;
begin
  if Assigned(FBroker) then
    FBroker.Shutdown;
  if Assigned(FServer) and FServer.Active then
    FServer.Active := False;
end;

{ Helper to read partial response data from a TInetSocket with timeout }
function ReadAvailableFromSocket(ASock: TInetSocket; ATimeoutMs: Integer;
  const AStopSubstring: string = ''): RawByteString;
var
  Buf: array[0..4095] of Byte;
  N: LongInt;
  StartTick: QWord;
begin
  Result := '';
  ASock.IOTimeout := 100;
  StartTick := GetTickCount64;
  while (GetTickCount64 - StartTick) < QWord(ATimeoutMs) do
  begin
    try
      N := ASock.Read(Buf[0], SizeOf(Buf));
      if N > 0 then
      begin
        SetLength(Result, Length(Result) + N);
        Move(Buf[0], Result[Length(Result) - N + 1], N);
        if (AStopSubstring <> '') and (Pos(AStopSubstring, Result) > 0) then
          Exit;
      end
      else if N = 0 then
        Exit
      else
        Sleep(10);
    except
      Sleep(10);
    end;
  end;
end;

function StreamToRaw(AStream: TMemoryStream): RawByteString;
begin
  SetLength(Result, AStream.Size);
  if AStream.Size > 0 then
    Move(AStream.Memory^, Result[1], AStream.Size);
end;

{ TTestZenithSSE }

procedure TTestZenithSSE.TestFormatSingleLineEvent;
var
  OutRaw: RawByteString;
begin
  OutRaw := TZSSEFormatter.FormatEvent('{"percent":42}');
  AssertEquals('Single-line event must follow W3C format',
    'data: {"percent":42}'#10#10, string(OutRaw));
end;

procedure TTestZenithSSE.TestFormatMultiLineDataLF_CRLF_CR;
var
  OutLF, OutCRLF, OutCR: RawByteString;
begin
  // LF
  OutLF := TZSSEFormatter.FormatEvent('line1'#10'line2'#10'line3');
  AssertEquals('LF multi-line data',
    'data: line1'#10'data: line2'#10'data: line3'#10#10, string(OutLF));

  // CRLF
  OutCRLF := TZSSEFormatter.FormatEvent('alpha'#13#10'beta'#13#10'gamma');
  AssertEquals('CRLF multi-line data',
    'data: alpha'#10'data: beta'#10'data: gamma'#10#10, string(OutCRLF));

  // CR with blank middle line
  OutCR := TZSSEFormatter.FormatEvent('row1'#13#13'row3');
  AssertEquals('CR with blank middle line',
    'data: row1'#10'data: '#10'data: row3'#10#10, string(OutCR));
end;

procedure TTestZenithSSE.TestFormatEmptyDataEvent;
var
  OutRaw: RawByteString;
begin
  OutRaw := TZSSEFormatter.FormatEvent('', 'TProgress', 'prog-0');
  AssertEquals('Empty data still emits data field to trigger dispatch',
    'id: prog-0'#10'event: TProgress'#10'data: '#10#10, string(OutRaw));
end;

procedure TTestZenithSSE.TestFormatUTF8AndEmojis;
var
  Payload: string;
  OutRaw: RawByteString;
begin
  Payload := 'Notificação concluída 🚀🔥✅ — Métrica: 99,8% (日本語)';
  OutRaw := TZSSEFormatter.FormatEvent(Payload, 'TNotification', 'notif-utf8-1');
  AssertEquals('UTF-8 and multi-byte emojis must be preserved losslessly',
    'id: notif-utf8-1'#10'event: TNotification'#10'data: ' + Payload + #10#10,
    string(OutRaw));
end;

procedure TTestZenithSSE.TestFormatFullFieldsAndSanitization;
var
  OutRaw: RawByteString;
begin
  // CR, LF, and NUL in id and event must be stripped to prevent SSE field injection
  OutRaw := TZSSEFormatter.FormatEvent(
    '{"cpu":18.5}',
    'TMetric'#13#10'injected',
    'evt'#10'100'#0'x',
    3000
  );
  AssertEquals('Sanitized full W3C event',
    'id: evt100x'#10'event: TMetricinjected'#10'retry: 3000'#10'data: {"cpu":18.5}'#10#10,
    string(OutRaw));
end;

procedure TTestZenithSSE.TestFormatCommentsAndRetry;
begin
  AssertEquals('Heartbeat comment', ': ping'#10#10,
    string(TZSSEFormatter.FormatComment('ping')));
  AssertEquals('Empty comment', ':'#10#10,
    string(TZSSEFormatter.FormatComment('')));
  AssertEquals('Multi-line comment', ': lineA'#10': lineB'#10#10,
    string(TZSSEFormatter.FormatComment('lineA'#13#10'lineB')));
  AssertEquals('Retry directive', 'retry: 5000'#10#10,
    string(TZSSEFormatter.FormatRetry(5000)));
end;

procedure TTestZenithSSE.TestApplyCanonicalHeaders;
var
  Req: TMockSSERequest;
  Resp: TMockSSEResponse;
  HeadersText: string;
begin
  Req := TMockSSERequest.Create;
  Resp := TMockSSEResponse.Create(Req);
  try
    TZSSEStream.ApplyHeaders(Resp);
    Resp.SendHeaders;
    HeadersText := Resp.SentHeaders.Text;

    AssertEquals('HTTP status 200', 200, Resp.Code);
    AssertEquals('Content-Type canonical', SSE_CONTENT_TYPE, Resp.ContentType);
    AssertEquals('Cache-Control canonical', SSE_CACHE_CONTROL, Resp.CacheControl);
    AssertTrue('Must include Content-Type header',
      Pos('Content-Type: text/event-stream; charset=utf-8', HeadersText) > 0);
    AssertTrue('Must include Cache-Control header',
      Pos('Cache-Control: no-cache, no-transform', HeadersText) > 0);
    AssertTrue('Must include Connection: keep-alive header',
      Pos('Connection: keep-alive', HeadersText) > 0);
    AssertTrue('Must include X-Accel-Buffering: no header',
      Pos('X-Accel-Buffering: no', HeadersText) > 0);
  finally
    Resp.Free;
    Req.Free;
  end;
end;

procedure TTestZenithSSE.TestExtractLastEventID;
var
  Req: TMockSSERequest;
begin
  // 1. Standard Last-Event-ID header
  Req := TMockSSERequest.Create;
  try
    Req.SetCustomHeader('Last-Event-ID', 'evt-42');
    AssertEquals('Standard Last-Event-ID header', 'evt-42',
      TZSSEFormatter.ExtractLastEventID(Req));
  finally
    Req.Free;
  end;

  // 2. Lowercase last-event-id header
  Req := TMockSSERequest.Create;
  try
    Req.CustomHeaders.Values['last-event-id'] := 'evt-99';
    AssertEquals('Case-insensitive last-event-id header', 'evt-99',
      TZSSEFormatter.ExtractLastEventID(Req));
  finally
    Req.Free;
  end;

  // 3. Query string fallback lastEventId
  Req := TMockSSERequest.Create;
  try
    Req.QueryFields.Values['lastEventId'] := 'evt-77';
    AssertEquals('Query param fallback lastEventId', 'evt-77',
      TZSSEFormatter.ExtractLastEventID(Req));
  finally
    Req.Free;
  end;
end;

procedure TTestZenithSSE.TestStreamWriteAndClose;
var
  FailMem: TFailingStream;
  Sse: TZSSEStream;
begin
  FailMem := TFailingStream.Create(10); // Fails after the first write
  Sse := TZSSEStream.Create(FailMem, False);
  try
    AssertTrue('First write succeeds', Sse.SendEvent('hello-world', 'TNotification', '1'));
    AssertTrue('Still connected after first write', Sse.Connected);
    AssertEquals('EventsSent = 1', 1, Sse.EventsSent);
    AssertTrue('BytesSent > 0', Sse.BytesSent > 0);

    // Second write triggers simulated EPIPE -> must return False and mark Connected=False without raising
    AssertFalse('Second write fails cleanly on broken pipe',
      Sse.SendEvent('second-event', 'TNotification', '2'));
    AssertFalse('Marked disconnected immediately', Sse.Connected);
    AssertFalse('Subsequent comment returns False', Sse.SendComment('ping'));
  finally
    Sse.Free;
    FailMem.Free;
  end;
end;

procedure TTestZenithSSE.TestBrokerTopicRoutingAndWildcard;
var
  Broker: TZSSEBroker;
  S1, S2, S3: TMemoryStream;
  C1, C2, C3: TZSSEConnection;
  Delivered: Integer;
begin
  Broker := TZSSEBroker.Create(32);
  S1 := TMemoryStream.Create;
  S2 := TMemoryStream.Create;
  S3 := TMemoryStream.Create;
  C1 := TZSSEConnection.CreateFromStream(S1, '', 'cli-notif');
  C2 := TZSSEConnection.CreateFromStream(S2, '', 'cli-metric');
  C3 := TZSSEConnection.CreateFromStream(S3, '', 'cli-all');
  try
    Broker.Subscribe(C1, 'notifications');
    Broker.Subscribe(C2, 'metrics');
    Broker.Subscribe(C3, '*');

    AssertEquals('3 active connections', 3, Broker.ConnectionCount);
    AssertEquals('2 subscribers on notifications (specific + wildcard)',
      2, Broker.TopicSubscriberCount('notifications'));

    Delivered := Broker.Publish('notifications', '{"msg":"done"}', 'TNotification', 'n-1');
    AssertEquals('Delivered to C1 and C3', 2, Delivered);
    AssertTrue('C1 got notification', Pos('n-1', string(StreamToRaw(S1))) > 0);
    AssertEquals('C2 did NOT get notification', 0, S2.Size);
    AssertTrue('C3 wildcard got notification', Pos('n-1', string(StreamToRaw(S3))) > 0);

    Delivered := Broker.BroadcastComment('ping');
    AssertEquals('Heartbeat comment reached all 3', 3, Delivered);
    AssertTrue('C2 got heartbeat comment', Pos(': ping'#10#10, string(StreamToRaw(S2))) > 0);

    Broker.Unsubscribe(C1);
    Broker.Unsubscribe(C2);
    Broker.Unsubscribe(C3);
    AssertEquals('0 connections after unsubscribe', 0, Broker.ConnectionCount);
  finally
    C1.Free;
    C2.Free;
    C3.Free;
    S1.Free;
    S2.Free;
    S3.Free;
    Broker.Free;
  end;
end;

procedure TTestZenithSSE.TestBrokerMultiTopicSubscriptionAndScopedDelivery;
var
  Broker: TZSSEBroker;
  SUser1, SUser2: TMemoryStream;
  CUser1, CUser2: TZSSEConnection;
  Delivered: Integer;
begin
  Broker := TZSSEBroker.Create(32);
  SUser1 := TMemoryStream.Create;
  SUser2 := TMemoryStream.Create;
  // User 1 in Org 9, User 2 in Org 9
  CUser1 := TZSSEConnection.CreateFromStream(SUser1, '', 'cli-user1');
  CUser2 := TZSSEConnection.CreateFromStream(SUser2, '', 'cli-user2');
  try
    Broker.Subscribe(CUser1, ['user:9:101', 'org:9']);
    Broker.Subscribe(CUser2, ['user:9:102', 'org:9']);

    AssertEquals('2 active connections', 2, Broker.ConnectionCount);
    AssertTrue('User 1 has user topic', CUser1.HasTopic('user:9:101'));
    AssertTrue('User 1 has org topic', CUser1.HasTopic('org:9'));
    AssertFalse('User 1 does not have user 2 topic', CUser1.HasTopic('user:9:102'));

    // 1. Publish to User 1 only
    Delivered := Broker.Publish('user:9:101', '{"msg":"para usuario 101"}', 'notificacao.criada', '1');
    AssertEquals('Delivered to 1 user', 1, Delivered);
    AssertTrue('User 1 received data', SUser1.Size > 0);
    AssertEquals('User 2 received nothing', 0, SUser2.Size);

    // 2. Publish to Org 9 (both User 1 and User 2)
    SUser1.Size := 0;
    SUser2.Size := 0;
    Delivered := Broker.Publish('org:9', '{"msg":"alerta global org 9"}', 'notificacao.alerta', '2');
    AssertEquals('Delivered to both org subscribers', 2, Delivered);
    AssertTrue('User 1 received org broadcast', SUser1.Size > 0);
    AssertTrue('User 2 received org broadcast', SUser2.Size > 0);
  finally
    Broker.Unsubscribe(CUser1);
    Broker.Unsubscribe(CUser2);
    CUser1.Free;
    CUser2.Free;
    SUser1.Free;
    SUser2.Free;
    Broker.Free;
  end;
end;

procedure TTestZenithSSE.TestBrokerReplaySinceLastEventID;
var
  Broker: TZSSEBroker;
  S: TMemoryStream;
  Conn: TZSSEConnection;
  Replayed: Integer;
  Raw: string;
begin
  Broker := TZSSEBroker.Create(16);
  S := TMemoryStream.Create;
  try
    Broker.Publish('progress', '{"step":1}', 'TProgress', 'p-1');
    Broker.Publish('progress', '{"step":2}', 'TProgress', 'p-2');
    Broker.Publish('metrics', '{"cpu":50}', 'TMetric', 'm-1');
    Broker.Publish('progress', '{"step":3}', 'TProgress', 'p-3');
    Broker.Publish('progress', '{"step":4}', 'TProgress', 'p-4');

    // Client reconnects with Last-Event-ID = p-2 on topic progress
    Conn := TZSSEConnection.CreateFromStream(S, 'p-2', 'cli-resume');
    try
      Replayed := Broker.ReplaySince(Conn, 'progress');
      AssertEquals('Must replay exactly 2 missed progress events (p-3, p-4)', 2, Replayed);
      Raw := string(StreamToRaw(S));
      AssertTrue('Contains p-3', Pos('id: p-3', Raw) > 0);
      AssertTrue('Contains p-4', Pos('id: p-4', Raw) > 0);
      AssertEquals('Does not replay p-2 itself', 0, Pos('id: p-2', Raw));
      AssertEquals('Does not replay unrelated metrics topic', 0, Pos('id: m-1', Raw));
    finally
      Conn.Free;
    end;
  finally
    S.Free;
    Broker.Free;
  end;
end;

procedure TTestZenithSSE.TestBrokerConcurrentMultiSubscriber;
const
  SUB_COUNT = 12;
  PUB_THREADS = 4;
  EVENTS_PER_PUB = 200;
var
  Broker: TZSSEBroker;
  Streams: array[0..SUB_COUNT - 1] of TMemoryStream;
  Conns: array[0..SUB_COUNT - 1] of TZSSEConnection;
  Pubs: array[0..PUB_THREADS - 1] of TPublisherThread;
  I: Integer;
  TotalExpected: Int64;
begin
  Broker := TZSSEBroker.Create(64);
  try
    for I := 0 to SUB_COUNT - 1 do
    begin
      Streams[I] := TMemoryStream.Create;
      Conns[I] := TZSSEConnection.CreateFromStream(Streams[I], '', Format('sub-%d', [I]));
      Broker.Subscribe(Conns[I], 'metrics');
    end;

    for I := 0 to PUB_THREADS - 1 do
    begin
      Pubs[I] := TPublisherThread.Create(Broker, 'metrics', EVENTS_PER_PUB, I + 1);
      Pubs[I].Start;
    end;

    for I := 0 to PUB_THREADS - 1 do
    begin
      Pubs[I].WaitFor;
      Pubs[I].Free;
    end;

    TotalExpected := Int64(PUB_THREADS) * EVENTS_PER_PUB * SUB_COUNT;
    AssertEquals('All published events accounted for',
      Int64(PUB_THREADS) * EVENTS_PER_PUB, Broker.TotalPublished);
    AssertEquals('All deliveries across concurrent subscribers succeeded',
      TotalExpected, Broker.TotalDelivered);
    AssertEquals('Zero dropped events', 0, Broker.TotalDropped);

    for I := 0 to SUB_COUNT - 1 do
    begin
      AssertTrue('Subscriber stream received non-empty data', Streams[I].Size > 0);
      Broker.Unsubscribe(Conns[I]);
      Conns[I].Free;
      Streams[I].Free;
    end;
  finally
    Broker.Free;
  end;
end;

procedure TTestZenithSSE.TestLiveServerHeadersEventsHeartbeatAndResume;
var
  Broker: TZSSEBroker;
  Srv: TSSEServerThread;
  Sock, Sock2: TInetSocket;
  ReqStr, Resp1, Resp2: RawByteString;
  Port: Word;
begin
  Port := TEST_SSE_PORT_BASE;
  Broker := TZSSEBroker.Create(32);
  Srv := TSSEServerThread.Create(Port, Broker, 120, 25, 4);
  try
    Srv.Start;
    AssertTrue('Server thread became ready', Srv.WaitReady(3000));
    AssertEquals('No server startup error', '', Srv.StartError);

    // 1. Initial SSE connection to /events/metrics
    Sock := TInetSocket.Create('127.0.0.1', Port, 2000);
    try
      ReqStr :=
        'GET /events/metrics HTTP/1.1'#13#10 +
        'Host: 127.0.0.1'#13#10 +
        'Accept: text/event-stream'#13#10#13#10;
      Sock.WriteBuffer(ReqStr[1], Length(ReqStr));

      // Wait for connection registration in the broker
      Sleep(100);
      AssertEquals('Broker must have 1 active SSE connection', 1, Broker.ConnectionCount);

      // Publish 2 events and wait for 1 automatic heartbeat (120ms)
      Broker.Publish('metrics', '{"rps":12500}', 'TMetric', 'm-101');
      Broker.Publish('metrics', 'lineA'#10'lineB', 'TMetric', 'm-102');
      Resp1 := ReadAvailableFromSocket(Sock, 600, ': ping');

      AssertTrue('Live HTTP 200 OK', Pos('HTTP/1.1 200 OK', string(Resp1)) > 0);
      AssertTrue('Live Content-Type', Pos('Content-Type: text/event-stream; charset=utf-8', string(Resp1)) > 0);
      AssertTrue('Live Cache-Control', Pos('Cache-Control: no-cache, no-transform', string(Resp1)) > 0);
      AssertTrue('Live Connection: keep-alive', Pos('Connection: keep-alive', string(Resp1)) > 0);
      AssertTrue('Live X-Accel-Buffering: no', Pos('X-Accel-Buffering: no', string(Resp1)) > 0);
      AssertTrue('Live event m-101 received', Pos('id: m-101'#10'event: TMetric'#10'data: {"rps":12500}'#10#10, string(Resp1)) > 0);
      AssertTrue('Live multi-line event m-102 received', Pos('data: lineA'#10'data: lineB'#10#10, string(Resp1)) > 0);
      AssertTrue('Automatic heartbeat (: ping) received', Pos(': ping'#10#10, string(Resp1)) > 0);
    finally
      Sock.Free; // Disconnect client 1
    end;

    // Publish m-103 while client is disconnected
    Broker.Publish('metrics', '{"rps":15000}', 'TMetric', 'm-103');

    // 2. Client reconnects sending Last-Event-ID: m-101 -> must replay m-102 and m-103
    Sock2 := TInetSocket.Create('127.0.0.1', Port, 2000);
    try
      ReqStr :=
        'GET /events/metrics HTTP/1.1'#13#10 +
        'Host: 127.0.0.1'#13#10 +
        'Accept: text/event-stream'#13#10 +
        'Last-Event-ID: m-101'#13#10#13#10;
      Sock2.WriteBuffer(ReqStr[1], Length(ReqStr));

      Resp2 := ReadAvailableFromSocket(Sock2, 500, 'm-103');
      AssertTrue('Replayed m-102', Pos('id: m-102', string(Resp2)) > 0);
      AssertTrue('Replayed m-103', Pos('id: m-103', string(Resp2)) > 0);
      AssertEquals('Must NOT replay m-101', 0, Pos('id: m-101', string(Resp2)));
    finally
      Sock2.Free;
    end;

    Srv.StopServer;
    Srv.WaitFor;
  finally
    Srv.Free;
    Broker.Free;
  end;
end;

procedure TTestZenithSSE.TestLiveServerAbruptDisconnectZeroThreadLeak;
const
  POOL_SIZE = 4;
  CLIENT_COUNT = 8; // 2 waves exceeding POOL_SIZE to prove zero-leak worker recycling
var
  Broker: TZSSEBroker;
  Srv: TSSEServerThread;
  Socks: array[0..3] of TInetSocket;
  Wave, I, WaitStep: Integer;
  ReqStr: RawByteString;
  Port: Word;
begin
  Port := TEST_SSE_PORT_BASE + 1;
  Broker := TZSSEBroker.Create(16);
  Srv := TSSEServerThread.Create(Port, Broker, 5000, 25, POOL_SIZE);
  try
    Srv.Start;
    AssertTrue('Server ready', Srv.WaitReady(3000));
    AssertEquals('No server error', '', Srv.StartError);

    ReqStr :=
      'GET /events/notifications HTTP/1.1'#13#10 +
      'Host: 127.0.0.1'#13#10 +
      'Accept: text/event-stream'#13#10#13#10;

    // 2 waves of 4 clients each (8 total connections on a 4-worker pool)
    for Wave := 1 to 2 do
    begin
      for I := 0 to 3 do
      begin
        Socks[I] := TInetSocket.Create('127.0.0.1', Port, 2000);
        Socks[I].WriteBuffer(ReqStr[1], Length(ReqStr));
      end;

      // Wait for all 4 clients to register
      for WaitStep := 1 to 40 do
      begin
        if Broker.ConnectionCount = 4 then
          Break;
        Sleep(20);
      end;
      AssertEquals(Format('Wave %d: 4 active connections', [Wave]), 4, Broker.ConnectionCount);

      // Abruptly close all 4 sockets without draining
      for I := 0 to 3 do
        FreeAndNil(Socks[I]);

      // Wait for immediate disconnect detection (25ms poll) and full ThreadPool worker recycling
      for WaitStep := 1 to 60 do
      begin
        if (Broker.ConnectionCount = 0) and
           Assigned(Srv.Server.ThreadPool) and
           (Srv.Server.ThreadPool.ActiveWorkers = 0) then
          Break;
        Sleep(25);
      end;

      AssertEquals(Format('Wave %d: Broker cleaned all disconnected clients', [Wave]),
        0, Broker.ConnectionCount);
      AssertNotNull('ThreadPool must be initialized', Srv.Server.ThreadPool);
      AssertEquals(Format('Wave %d: Zero active workers leaked', [Wave]),
        0, Srv.Server.ThreadPool.ActiveWorkers);
      AssertEquals(Format('Wave %d: All workers idle and recycled', [Wave]),
        POOL_SIZE, Srv.Server.ThreadPool.IdleWorkers);
    end;

    AssertTrue('ThreadPool processed all 8 SSE connections cleanly',
      Srv.Server.ThreadPool.TotalProcessed >= CLIENT_COUNT);

    Srv.StopServer;
    Srv.WaitFor;
  finally
    Srv.Free;
    Broker.Free;
  end;
end;

procedure TTestZenithSSE.TestBrokerMaxConnectionsLimitReturns503;
var
  Broker: TZSSEBroker;
  Srv: TSSEServerThread;
  Sock1, Sock2, Sock3: TInetSocket;
  ReqStr, Resp3: RawByteString;
  Port: Word;
  WaitStep: Integer;
begin
  Port := TEST_SSE_PORT_BASE + 2;
  Broker := TZSSEBroker.Create(16, 2); // MaxConnections = 2
  Srv := TSSEServerThread.Create(Port, Broker, 5000, 25, 4);
  try
    AssertEquals('Initial MaxConnections', 2, Broker.MaxConnections);
    Srv.Start;
    AssertTrue('Server ready', Srv.WaitReady(3000));
    AssertEquals('No server error', '', Srv.StartError);

    ReqStr :=
      'GET /events/metrics HTTP/1.1'#13#10 +
      'Host: 127.0.0.1'#13#10 +
      'Accept: text/event-stream'#13#10#13#10;

    Sock1 := TInetSocket.Create('127.0.0.1', Port, 2000);
    Sock2 := TInetSocket.Create('127.0.0.1', Port, 2000);
    try
      Sock1.WriteBuffer(ReqStr[1], Length(ReqStr));
      Sock2.WriteBuffer(ReqStr[1], Length(ReqStr));

      for WaitStep := 1 to 40 do
      begin
        if Broker.ConnectionCount = 2 then
          Break;
        Sleep(20);
      end;
      AssertEquals('2 active connections at capacity', 2, Broker.ConnectionCount);

      // 3rd connection exceeds MaxConnections -> must receive immediate HTTP 503 + Retry-After: 5
      Sock3 := TInetSocket.Create('127.0.0.1', Port, 2000);
      try
        Sock3.WriteBuffer(ReqStr[1], Length(ReqStr));
        Resp3 := ReadAvailableFromSocket(Sock3, 500, 'Retry-After');
        AssertTrue('Must return HTTP 503 Service Unavailable',
          Pos('503 Service Unavailable', string(Resp3)) > 0);
        AssertTrue('Must include Retry-After: 5 header',
          Pos('Retry-After: 5', string(Resp3)) > 0);
        AssertTrue('Must return application/problem+json RFC 9457 body',
          Pos('application/problem+json', string(Resp3)) > 0);
        AssertEquals('Active connection count remains 2', 2, Broker.ConnectionCount);
      finally
        Sock3.Free;
      end;
    finally
      Sock2.Free;
      Sock1.Free;
    end;

    Srv.StopServer;
    Srv.WaitFor;
  finally
    Srv.Free;
    Broker.Free;
  end;
end;

procedure TTestZenithSSE.TestBenchmarkEventsPerSecond;
const
  BENCH_SUBSCRIBERS = 10;
  BENCH_EVENTS = 20000;
var
  Broker: TZSSEBroker;
  Streams: array[0..BENCH_SUBSCRIBERS - 1] of TMemoryStream;
  Conns: array[0..BENCH_SUBSCRIBERS - 1] of TZSSEConnection;
  I: Integer;
  T0, T1, ElapsedMs: QWord;
  EventsPerSec, DeliveriesPerSec: Double;
  HeapBefore, HeapAfter: TFPCHeapStatus;
begin
  HeapBefore := GetFPCHeapStatus;
  Broker := TZSSEBroker.Create(64);
  try
    for I := 0 to BENCH_SUBSCRIBERS - 1 do
    begin
      Streams[I] := TMemoryStream.Create;
      Streams[I].SetSize(2 * 1024 * 1024); // Pre-allocate 2MB to measure pure broker/formatter throughput
      Streams[I].Position := 0;
      Conns[I] := TZSSEConnection.CreateFromStream(Streams[I], '', Format('bench-%d', [I]));
      Broker.Subscribe(Conns[I], 'metrics');
    end;

    T0 := GetTickCount64;
    for I := 1 to BENCH_EVENTS do
      Broker.Publish('metrics', '{"cpu":41.2,"mem":62.8,"ok":true}', 'TMetric', IntToStr(I));
    T1 := GetTickCount64;

    ElapsedMs := T1 - T0;
    if ElapsedMs = 0 then
      ElapsedMs := 1;

    EventsPerSec := (BENCH_EVENTS * 1000.0) / ElapsedMs;
    DeliveriesPerSec := (Broker.TotalDelivered * 1000.0) / ElapsedMs;

    AssertEquals('All benchmark deliveries completed',
      Int64(BENCH_EVENTS) * BENCH_SUBSCRIBERS, Broker.TotalDelivered);
    AssertTrue('Throughput must exceed 5,000 events/sec', EventsPerSec > 5000.0);

    for I := 0 to BENCH_SUBSCRIBERS - 1 do
    begin
      Broker.Unsubscribe(Conns[I]);
      Conns[I].Free;
      Streams[I].Free;
    end;
  finally
    Broker.Free;
  end;

  HeapAfter := GetFPCHeapStatus;

  WriteLn(Format(
    '[BENCHMARK W3C SSE] Events=%d | Subscribers=%d | Deliveries=%d | Elapsed=%dms | %.0f events/s | %.0f deliveries/s | HeapDelta=%d bytes',
    [BENCH_EVENTS, BENCH_SUBSCRIBERS, Int64(BENCH_EVENTS) * BENCH_SUBSCRIBERS,
     ElapsedMs, EventsPerSec, DeliveriesPerSec,
     Int64(HeapAfter.CurrHeapUsed) - Int64(HeapBefore.CurrHeapUsed)]
  ));
end;

initialization
  RegisterTest(TTestZenithSSE);

end.
