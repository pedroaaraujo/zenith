{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2011- by the Free Pascal development team
    
    Zenith High-Performance ThreadPool Edition (Zero Thread-Per-Request)
    TASK #1257
}
unit fphttpserver;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, sockets, sslbase, sslsockets, ssockets, resolve, httpdefs,
  Zenith.ThreadPool;

const
  ReadBufLen = 4096;
  { Limites padrão de leitura (sobrescrevíveis por propriedade ou variável de ambiente) }
  ZENITH_DEFAULT_MAX_BODY_SIZE = 10 * 1024 * 1024;   // ZENITH_MAX_BODY_SIZE (bytes)
  ZENITH_DEFAULT_MAX_HEADER_SIZE = 64 * 1024;        // ZENITH_MAX_HEADER_SIZE (bytes)
  ZENITH_DEFAULT_READ_TIMEOUT_MS = 30000;            // ZENITH_READ_TIMEOUT_MS

type
  TFPHTTPConnection = class;
  TFPHTTPConnectionThread = class;
  TFPCustomHttpServer = class;
  TRequestErrorHandler = procedure(Sender: TObject; E: Exception) of object;
  TGetSocketHandlerEvent = procedure(Sender: TObject; const UseSSL: Boolean; out AHandler: TSocketHandler) of object;
  TSocketHandlerCreatedEvent = procedure(Sender: TObject; AHandler: TSocketHandler) of object;

  { TFPHTTPConnectionRequest }

  TFPHTTPConnectionRequest = class(TRequest)
  private
    FConnection: TFPHTTPConnection;
  protected
    procedure InitRequestVars; override;
  published
    property Connection: TFPHTTPConnection read FConnection;
  end;

  { TFPHTTPConnectionResponse }

  TFPHTTPConnectionResponse = class(TResponse)
  private
    FConnection: TFPHTTPConnection;
  protected
    procedure DoSendHeaders(Headers: TStrings); override;
    procedure DoSendContent; override;
    property Connection: TFPHTTPConnection read FConnection;
  end;

  { TFPHTTPConnection }

  TFPHTTPConnection = class(TObject)
  private
    FOnError: TRequestErrorHandler;
    FServer: TFPCustomHTTPServer;
    FSocket: TSocketStream;
    FBuffer: Ansistring;
    FHeaderBytes: Int64;
    FHeaderDeadline: QWord;
    procedure CheckHeaderLimits;
    procedure SendRawError(ACode: Integer; const AReason: string);
    procedure InterPretHeader(ARequest: TFPHTTPConnectionRequest; const AHeader: String);
    function ReadString: String;
    function GetLookupHostNames: Boolean;
  protected
    procedure ReadRequestContent(ARequest: TFPHTTPConnectionRequest); virtual;
    procedure UnknownHeader(ARequest: TFPHTTPConnectionRequest; const AHeader: String); virtual;
    procedure HandleRequestError(E: Exception); virtual;
    procedure SetupSocket; virtual;
    function ReadRequestHeaders: TFPHTTPConnectionRequest;
  public
    constructor Create(AServer: TFPCustomHTTPServer; ASocket: TSocketStream);
    destructor Destroy; override;
    procedure HandleRequest; virtual;
    function TakeBuffer: Ansistring;
    property Buffer: Ansistring read FBuffer;
    property Socket: TSocketStream read FSocket;
    property Server: TFPCustomHTTPServer read FServer;
    property OnRequestError: TRequestErrorHandler read FOnError write FOnError;
    property LookupHostNames: Boolean read GetLookupHostNames;
  end;

  { TFPHTTPConnectionThread }

  TFPHTTPConnectionThread = class(TThread)
  private
    FConnection: TFPHTTPConnection;
    FThreadList: TThreadList;
  public
    constructor CreateConnection(AConnection: TFPHTTPConnection); virtual;
    constructor CreateConnection(AConnection: TFPHTTPConnection; AThreadList: TThreadList);
    procedure Execute; override;
    property Connection: TFPHTTPConnection read FConnection;
  end;

  { TFPHttpServer }
  THTTPServerRequestHandler = procedure(Sender: TObject;
    var ARequest: TFPHTTPConnectionRequest;
    var AResponse: TFPHTTPConnectionResponse) of object;

  { TFPCustomHttpServer }

  TFPCustomHttpServer = class(TComponent)
  private
    FAcceptIdleTimeout: Cardinal;
    FAdminMail: string;
    FAdminName: string;
    FAfterSocketHandlerCreated: TSocketHandlerCreatedEvent;
    FCertificateData: TCertificateData;
    FOnAcceptIdle: TNotifyEvent;
    FOnAllowConnect: TConnectQuery;
    FOnGetSocketHandler: TGetSocketHandlerEvent;
    FOnRequest: THTTPServerRequestHandler;
    FOnRequestError: TRequestErrorHandler;
    FAddress: string;
    FPort: Word;
    FQueueSize: Word;
    FServer: TInetServer;
    FLoadActivate: Boolean;
    FServerBanner: string;
    FLookupHostNames: Boolean;
    FThreaded: Boolean;
    FConnectionThreadList: TThreadList;
    FConnectionCount: Integer;
    FUseSSL: Boolean;

    // Zenith ThreadPool extensions
    FThreadPool: TZenithThreadPool;
    FUseThreadPool: Boolean;
    FThreadPoolSize: Integer;
    FThreadPoolQueueLimit: Integer;
    FMaxRequestBodySize: Int64;
    FMaxHeaderSize: Int64;
    FReadTimeout: Integer;

    procedure DoCreateClientHandler(Sender: TObject; out AHandler: TSocketHandler);
    function GetActive: Boolean;
    function GetHostName: string;
    procedure SetAcceptIdleTimeout(AValue: Cardinal);
    procedure SetActive(const AValue: Boolean);
    procedure SetCertificateData(AValue: TCertificateData);
    procedure SetHostName(AValue: string);
    procedure SetIdle(AValue: TNotifyEvent);
    procedure SetOnAllowConnect(const AValue: TConnectQuery);
    procedure SetAddress(const AValue: string);
    procedure SetPort(const AValue: Word);
    procedure SetQueueSize(const AValue: Word);
    procedure SetThreaded(const AValue: Boolean);
    procedure SetUseThreadPool(const AValue: Boolean);
    procedure SetThreadPoolSize(const AValue: Integer);
    procedure SetThreadPoolQueueLimit(const AValue: Integer);
    procedure SetupSocket;
    procedure WaitForRequests(MaxAttempts: Integer = 10);
    procedure DoProcessConnection(AItem: TObject);
    procedure EnsureThreadPool;
    procedure DestroyThreadPool;
  protected
    // Override this to create descendent
    function CreateSSLSocketHandler: TSocketHandler;
    // Override this to create descendent
    function CreateCertificateData: TCertificateData; virtual;
    // Override this to create descendent
    function GetSocketHandler(const UseSSL: Boolean): TSocketHandler; virtual;
    // Override these to create descendents of the request/response instead.
    function CreateRequest: TFPHTTPConnectionRequest; virtual;
    function CreateResponse(ARequest: TFPHTTPConnectionRequest): TFPHTTPConnectionResponse; virtual;
    procedure InitRequest(ARequest: TFPHTTPConnectionRequest); virtual;
    procedure InitResponse(AResponse: TFPHTTPConnectionResponse); virtual;
    // Called on accept errors
    procedure DoAcceptError(Sender: TObject; ASocket: Longint; E: Exception; var ErrorAction: TAcceptErrorAction);
    // Create a connection handling object.
    function CreateConnection(Data: TSocketStream): TFPHTTPConnection; virtual;
    // Create a connection handling thread (legacy thread-per-request fallback).
    function CreateConnectionThread(Conn: TFPHTTPConnection): TFPHTTPConnectionThread; virtual;
    // Check if server is inactive
    procedure CheckInactive;
    // Called by TInetServer when a new connection is accepted.
    procedure DoConnect(Sender: TObject; Data: TSocketStream); virtual;
    // Create and configure TInetServer
    procedure CreateServerSocket; virtual;
    // Start server socket
    procedure StartServerSocket; virtual;
    // Stop server socket
    procedure StopServerSocket; virtual;
    // Free server socket instance
    procedure FreeServerSocket; virtual;
    // Handle request. This calls OnRequest. It can be overridden by descendants to provide standard handling.
    procedure HandleRequest(var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse); virtual;
    // Called when a connection encounters an unexpected error. Will call OnRequestError when set.
    procedure HandleRequestError(Sender: TObject; E: Exception); virtual;
    // Connection count
    property ConnectionCount: Integer read FConnectionCount;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    property ThreadPool: TZenithThreadPool read FThreadPool;
    property UseThreadPool: Boolean read FUseThreadPool write SetUseThreadPool default True;
    property ThreadPoolSize: Integer read FThreadPoolSize write SetThreadPoolSize;
    property ThreadPoolQueueLimit: Integer read FThreadPoolQueueLimit write SetThreadPoolQueueLimit;
    // Tamanho máximo do corpo aceito (Content-Length). Acima disso responde 413.
    property MaxRequestBodySize: Int64 read FMaxRequestBodySize write FMaxRequestBodySize;
    // Tamanho máximo somado da linha inicial e dos headers. Acima disso responde 431.
    property MaxHeaderSize: Int64 read FMaxHeaderSize write FMaxHeaderSize;
    // Timeout (ms) de cada leitura e prazo total para receber os headers. 0 desativa.
    property ReadTimeout: Integer read FReadTimeout write FReadTimeout;
  protected
    // Set to true to start listening.
    property Active: Boolean read GetActive write SetActive default False;
    // Address to listen on.
    property Address: string read FAddress write SetAddress;
    // Port to listen on.
    property Port: Word read FPort write SetPort default 80;
    // Max connections on queue (for Listen call)
    property QueueSize: Word read FQueueSize write SetQueueSize default 5;
    // Called when deciding whether to accept a connection.
    property OnAllowConnect: TConnectQuery read FOnAllowConnect write SetOnAllowConnect;
    // Use a thread to handle a connection ?
    property Threaded: Boolean read FThreaded write SetThreaded;
    // Called to handle the request. If Threaded=True, it is called in a worker thread.
    property OnRequest: THTTPServerRequestHandler read FOnRequest write FOnRequest;
    // Called when an unexpected error occurs during handling of the request.
    property OnRequestError: TRequestErrorHandler read FOnRequestError write FOnRequestError;
    // Called when there are no connections waiting.
    property OnAcceptIdle: TNotifyEvent read FOnAcceptIdle write SetIdle;
    // If >0, when no new connection appeared after timeout, OnAcceptIdle is called.
    property AcceptIdleTimeout: Cardinal read FAcceptIdleTimeout write SetAcceptIdleTimeout;
  published
    // Additional server information
    property AdminMail: string read FAdminMail write FAdminMail;
    property AdminName: string read FAdminName write FAdminName;
    property ServerBanner: string read FServerBanner write FServerBanner;
    property LookupHostNames: Boolean read FLookupHostNames write FLookupHostNames;
    property HostName: string read GetHostName write SetHostName; deprecated 'Use CertificateData instead';
    property CertificateData: TCertificateData read FCertificateData write SetCertificateData;
    property UseSSL: Boolean read FUseSSL write FUseSSL;
    property OnGetSocketHandler: TGetSocketHandlerEvent read FOnGetSocketHandler write FOnGetSocketHandler;
    property AfterSocketHandlerCreate: TSocketHandlerCreatedEvent read FAfterSocketHandlerCreated write FAfterSocketHandlerCreated;
  end;

  TFPHttpServer = class(TFPCustomHttpServer)
  published
    property Active;
    property Port;
    property QueueSize;
    property OnAllowConnect;
    property Threaded;
    property OnRequest;
    property OnRequestError;
    property OnAcceptIdle;
    property AcceptIdleTimeout;
    property UseThreadPool;
    property ThreadPoolSize;
    property ThreadPoolQueueLimit;
  end;

  EHTTPServer = class(EHTTP);

function GetStatusCode(ACode: Integer): String;

implementation

resourcestring
  SErrSocketActive = 'Operation not allowed while server is active';
  SErrReadingSocket = 'Error reading data from the socket';
  SErrMissingProtocol = 'Missing HTTP protocol version in request';

function GetStatusCode(ACode: Integer): String;
begin
  case ACode of
    100: Result := 'Continue';
    101: Result := 'Switching Protocols';
    200: Result := 'OK';
    201: Result := 'Created';
    202: Result := 'Accepted';
    203: Result := 'Non-Authoritative Information';
    204: Result := 'No Content';
    205: Result := 'Reset Content';
    206: Result := 'Partial Content';
    300: Result := 'Multiple Choices';
    301: Result := 'Moved Permanently';
    302: Result := 'Found';
    303: Result := 'See Other';
    304: Result := 'Not Modified';
    305: Result := 'Use Proxy';
    307: Result := 'Temporary Redirect';
    400: Result := 'Bad Request';
    401: Result := 'Unauthorized';
    402: Result := 'Payment Required';
    403: Result := 'Forbidden';
    404: Result := 'Not Found';
    405: Result := 'Method Not Allowed';
    406: Result := 'Not Acceptable';
    407: Result := 'Proxy Authentication Required';
    408: Result := 'Request Time-out';
    409: Result := 'Conflict';
    410: Result := 'Gone';
    411: Result := 'Length Required';
    412: Result := 'Precondition Failed';
    413: Result := 'Request Entity Too Large';
    414: Result := 'Request-URI Too Large';
    415: Result := 'Unsupported Media Type';
    416: Result := 'Requested range not satisfiable';
    417: Result := 'Expectation Failed';
    418: Result := 'I''m a teapot';
    421: Result := 'Misdirected Request';
    422: Result := 'Unprocessable Entity';
    423: Result := 'Locked';
    424: Result := 'Failed Dependency';
    425: Result := 'Too Early';
    426: Result := 'Upgrade Required';
    428: Result := 'Precondition Required';
    429: Result := 'Too Many Requests';
    431: Result := 'Request Header Fields Too Large';
    451: Result := 'Unavailable For Legal Reasons';

    500: Result := 'Internal Server Error';
    501: Result := 'Not Implemented';
    502: Result := 'Bad Gateway';
    503: Result := 'Service Unavailable';
    504: Result := 'Gateway Time-out';
    505: Result := 'HTTP Version not supported';
  else
    Result := 'Unknown status';
  end;
end;

function GetHostNameByAddress(const AnAddress: String): String;
var
  Resolver: THostResolver;
begin
  Result := '';
  if AnAddress = '' then exit;
  Resolver := THostResolver.Create(nil);
  try
    if Resolver.AddressLookup(AnAddress) then
      Result := Resolver.ResolvedName;
  finally
    FreeAndNil(Resolver);
  end;
end;

procedure TFPHTTPConnectionRequest.InitRequestVars;
var
  P: Integer;
  S: String;
begin
  S := URL;
  P := Pos('?', S);
  if (P <> 0) then
    SetHTTPVariable(hvQuery, Copy(S, P + 1, Length(S) - P));
  if Assigned(FConnection) and FConnection.LookupHostNames then
    SetHTTPVariable(hvRemoteHost, GetHostNameByAddress(RemoteAddress));
  inherited InitRequestVars;
end;

function SocketAddrToString(ASocketAddr: TSockAddr): String;
begin
  if ASocketAddr.sa_family = AF_INET then
    Result := NetAddrToStr(ASocketAddr.sin_addr)
  else
    Result := '';
end;

procedure TFPHTTPConnectionResponse.DoSendHeaders(Headers: TStrings);
var
  S: String;
  I: Integer;
begin
  S := Format('HTTP/1.1 %3d %s'#13#10, [Code, GetStatusCode(Code)]);
  for I := 0 to Headers.Count - 1 do
    S := S + Headers[I] + #13#10;
  // Final empty line after headers
  Connection.Socket.WriteBuffer(S[1], Length(S));
end;

procedure TFPHTTPConnectionResponse.DoSendContent;
begin
  if Assigned(ContentStream) then
    Connection.Socket.CopyFrom(ContentStream, 0)
  else
    Contents.SaveToStream(Connection.Socket);
end;

{ TFPHTTPConnection }

function TFPHTTPConnection.ReadString: String;
  procedure FillBuffer;
  var
    R: Integer;
  begin
    SetLength(FBuffer, ReadBufLen);
    R := FSocket.Read(FBuffer[1], ReadBufLen);
    if R < 0 then
      raise EHTTPServer.Create(SErrReadingSocket);
    if (R < ReadBufLen) then
      SetLength(FBuffer, R);
  end;

var
  CheckLF, Done: Boolean;
  P, L: Integer;
begin
  Result := '';
  Done := False;
  CheckLF := False;
  repeat
    if Length(FBuffer) = 0 then
      FillBuffer;
    CheckHeaderLimits;
    if Length(FBuffer) = 0 then
      Done := True
    else if CheckLF then
    begin
      if (FBuffer[1] <> #10) then
        Result := Result + #13
      else
      begin
        Delete(FBuffer, 1, 1);
        Done := True;
      end;
      CheckLF := False;
    end;
    if not Done then
    begin
      P := Pos(#13#10, FBuffer);
      if P = 0 then
      begin
        L := Length(FBuffer);
        CheckLF := FBuffer[L] = #13;
        if CheckLF then
          Result := Result + Copy(FBuffer, 1, L - 1)
        else
          Result := Result + FBuffer;
        Inc(FHeaderBytes, L);
        FBuffer := '';
      end
      else
      begin
        Result := Result + Copy(FBuffer, 1, P - 1);
        Delete(FBuffer, 1, P + 1);
        Inc(FHeaderBytes, P + 1);
        Done := True;
      end;
    end;
  until Done;
end;

procedure TFPHTTPConnection.CheckHeaderLimits;
begin
  if (FServer = nil) then
    Exit;
  if (FServer.MaxHeaderSize > 0) and (FHeaderBytes > FServer.MaxHeaderSize) then
    raise EHTTPServer.CreateHelp('Request header fields too large', 431);
  if (FHeaderDeadline > 0) and (GetTickCount64 > FHeaderDeadline) then
    raise EHTTPServer.CreateHelp('Request header timeout', 408);
end;

procedure TFPHTTPConnection.SendRawError(ACode: Integer; const AReason: string);
var
  S: AnsiString;
begin
  if FSocket = nil then
    Exit;
  S := 'HTTP/1.1 ' + IntToStr(ACode) + ' ' + AReason + #13#10 +
       'Content-Length: 0'#13#10 +
       'Connection: close'#13#10#13#10;
  try
    FSocket.WriteBuffer(S[1], Length(S));
  except
    { O cliente pode ter fechado a conexão; nada a fazer. }
  end;
end;

procedure TFPHTTPConnection.UnknownHeader(ARequest: TFPHTTPConnectionRequest; const AHeader: String);
begin
  // No-op
end;

procedure TFPHTTPConnection.HandleRequestError(E: Exception);
begin
  if Assigned(FOnError) then
    try
      FOnError(Self, E);
    except
    end;
end;

procedure TFPHTTPConnection.SetupSocket;
begin
{$if defined(FreeBSD) or defined(Linux)}
  FSocket.ReadFlags := MSG_NOSIGNAL;
  FSocket.WriteFlags := MSG_NOSIGNAL;
{$endif}
end;

procedure TFPHTTPConnection.InterPretHeader(ARequest: TFPHTTPConnectionRequest; const AHeader: String);
var
  P: Integer;
  N, V: String;
begin
  V := AHeader;
  P := Pos(':', V);
  if (P = 0) then
  begin
    UnknownHeader(ARequest, AHeader);
    Exit;
  end;
  N := Copy(V, 1, P - 1);
  Delete(V, 1, P);
  V := Trim(V);
  ARequest.SetFieldByName(N, V);
end;

procedure ParseStartLine(Request: TFPHTTPConnectionRequest; AStartLine: String);
  function GetNextWord(var S: String): string;
  var
    P: Integer;
  begin
    P := Pos(' ', S);
    if (P = 0) then
      P := Length(S) + 1;
    Result := Copy(S, 1, P - 1);
    Delete(S, 1, P);
  end;

var
  S: String;
  I: Integer;
begin
  if AStartLine = '' then
    Exit;
  Request.Method := GetNextWord(AStartLine);
  Request.URL := GetNextWord(AStartLine);
  S := Request.URL;
  I := Pos('?', S);
  if (I > 0) then
    S := Copy(S, 1, I - 1);
  if (Length(S) > 1) and (S[1] <> '/') then
    S := '/' + S
  else if S = '/' then
    S := '';
  Request.PathInfo := S;
  S := GetNextWord(AStartLine);
  if (S <> '') and (Pos('HTTP/', S) <> 1) then
    raise EHTTPServer.CreateHelp(SErrMissingProtocol, 400);
  Delete(S, 1, 5);
  Request.ProtocolVersion := Trim(S);
end;

procedure TFPHTTPConnection.ReadRequestContent(ARequest: TFPHTTPConnectionRequest);
var
  P, L, R: Integer;
  S: String;
begin
  S := '';
  L := ARequest.ContentLength;
  if (L < 0) then
    raise EHTTPServer.CreateHelp('Invalid Content-Length', 400);
  if Assigned(FServer) and (FServer.MaxRequestBodySize > 0) and
     (Int64(L) > FServer.MaxRequestBodySize) then
    raise EHTTPServer.CreateHelp('Payload too large', 413);
  if (L > 0) then
  begin
    SetLength(S, L);
    P := Length(FBuffer);
    { Bytes já lidos além do corpo (cliente enviou mais que o Content-Length)
      não podem ser copiados para S: limitar a cópia evita escrita fora do buffer. }
    if P > L then
      P := L;
    if (P > 0) then
    begin
      Move(FBuffer[1], S[1], P);
      Delete(FBuffer, 1, P);
      L := L - P;
    end;
    P := P + 1;
    R := 1;
    while (L <> 0) and (R > 0) do
    begin
      R := FSocket.Read(S[P], L);
      if R < 0 then
        raise EHTTPServer.Create(SErrReadingSocket);
      if (R > 0) then
      begin
        P := P + R;
        L := L - R;
      end;
    end;
  end;
  ARequest.InitContent(S);
end;

function TFPHTTPConnection.ReadRequestHeaders: TFPHTTPConnectionRequest;
var
  StartLine, S: String;
begin
  Result := Server.CreateRequest;
  try
    Server.InitRequest(Result);
    Result.FConnection := Self;
    FHeaderBytes := 0;
    if Server.ReadTimeout > 0 then
      FHeaderDeadline := GetTickCount64 + QWord(Server.ReadTimeout)
    else
      FHeaderDeadline := 0;
    StartLine := ReadString;
    ParseStartLine(Result, StartLine);
    repeat
      S := ReadString;
      if (S <> '') then
        InterPretHeader(Result, S);
    until (S = '');
    Result.RemoteAddress := SocketAddrToString(FSocket.RemoteAddress);
    Result.ServerPort := FServer.Port;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

constructor TFPHTTPConnection.Create(AServer: TFPCustomHttpServer; ASocket: TSocketStream);
begin
  FSocket := ASocket;
  FServer := AServer;
  if Assigned(FServer) then
    InterLockedIncrement(FServer.FConnectionCount);
end;

destructor TFPHTTPConnection.Destroy;
begin
  if Assigned(FServer) then
    InterLockedDecrement(FServer.FConnectionCount);
  FreeAndNil(FSocket);
  inherited Destroy;
end;

function TFPHTTPConnection.TakeBuffer: Ansistring;
begin
  Result := FBuffer;
  FBuffer := '';
end;

function TFPHTTPConnection.GetLookupHostNames: Boolean;
begin
  if Assigned(FServer) then
    Result := FServer.LookupHostNames
  else
    Result := False;
end;

procedure TFPHTTPConnection.HandleRequest;
var
  Req: TFPHTTPConnectionRequest;
  Resp: TFPHTTPConnectionResponse;
begin
  try
    SetupSocket;
    if Assigned(FServer) and (FServer.ReadTimeout > 0) then
      FSocket.IOTimeout := FServer.ReadTimeout;
    Req := ReadRequestHeaders;
    try
      Req.ServerPort := Server.Port;
      if Req.ContentLength <> 0 then
        ReadRequestContent(Req);
      FHeaderDeadline := 0;
      { Handlers (SSE/WebSocket) podem manter o socket aberto por tempo
        indeterminado: o timeout vale apenas para a leitura da requisição. }
      if FSocket.IOTimeout <> 0 then
        FSocket.IOTimeout := 0;
      Req.InitRequestVars;
      Resp := Server.CreateResponse(Req);
      try
        Server.InitResponse(Resp);
        Resp.FConnection := Self;
        if Server.Active then
          Server.HandleRequest(Req, Resp);
        if Assigned(Resp) and (not Resp.ContentSent) then
          Resp.SendContent;
      finally
        FreeAndNil(Resp);
      end;
    finally
      FreeAndNil(Req);
    end;
  except
    on E: Exception do
    begin
      if (E is EHTTPServer) and (E.HelpContext >= 400) and (E.HelpContext <= 599) then
        SendRawError(E.HelpContext, E.Message);
      HandleRequestError(E);
    end;
  end;
end;

{ TFPHTTPConnectionThread (Legacy thread-per-request fallback) }

constructor TFPHTTPConnectionThread.CreateConnection(AConnection: TFPHTTPConnection);
begin
  FConnection := AConnection;
  FreeOnTerminate := True;
  inherited Create(False);
end;

constructor TFPHTTPConnectionThread.CreateConnection(AConnection: TFPHTTPConnection; AThreadList: TThreadList);
begin
  FThreadList := AThreadList;
  if Assigned(FThreadList) then
    FThreadList.Add(Self);
  CreateConnection(AConnection);
end;

procedure TFPHTTPConnectionThread.Execute;
begin
  try
    try
      FConnection.HandleRequest;
    finally
      FreeAndNil(FConnection);
      if Assigned(FThreadList) then
        FThreadList.Remove(Self);
    end;
  except
  end;
end;

{ TFPCustomHttpServer }

procedure TFPCustomHttpServer.HandleRequestError(Sender: TObject; E: Exception);
begin
  if Assigned(FOnRequestError) then
    try
      FOnRequestError(Sender, E);
    except
    end;
end;

procedure TFPCustomHttpServer.DoAcceptError(Sender: TObject; ASocket: Longint;
  E: Exception; var ErrorAction: TAcceptErrorAction);
begin
  if not Active then
    ErrorAction := AEAStop
  else
    ErrorAction := AEARaise;
end;

function TFPCustomHttpServer.GetActive: Boolean;
begin
  if (csDesigning in ComponentState) then
    Result := FLoadActivate
  else
    Result := Assigned(FServer);
end;

procedure TFPCustomHttpServer.DoCreateClientHandler(Sender: TObject; out AHandler: TSocketHandler);
begin
  AHandler := GetSocketHandler(UseSSL);
end;

function TFPCustomHttpServer.GetHostName: string;
begin
  Result := FCertificateData.HostName;
end;

procedure TFPCustomHttpServer.SetAcceptIdleTimeout(AValue: Cardinal);
begin
  if FAcceptIdleTimeout = AValue then Exit;
  FAcceptIdleTimeout := AValue;
  if Assigned(FServer) then
    FServer.AcceptIdleTimeOut := AValue;
end;

procedure TFPCustomHttpServer.StopServerSocket;
begin
  if Assigned(FServer) then
    FServer.StopAccepting(False);
end;

procedure TFPCustomHttpServer.EnsureThreadPool;
begin
  if not Assigned(FThreadPool) then
  begin
    FThreadPool := TZenithThreadPool.Create(FThreadPoolSize, FThreadPoolQueueLimit);
    FThreadPool.OnExecuteWork := @DoProcessConnection;
  end;
  if not FThreadPool.Active then
    FThreadPool.Start;
end;

procedure TFPCustomHttpServer.DestroyThreadPool;
begin
  if Assigned(FThreadPool) then
  begin
    FThreadPool.Stop;
    FreeAndNil(FThreadPool);
  end;
end;

procedure TFPCustomHttpServer.DoProcessConnection(AItem: TObject);
var
  Con: TFPHTTPConnection;
begin
  Con := TFPHTTPConnection(AItem);
  try
    Con.HandleRequest;
  finally
    FreeAndNil(Con);
  end;
end;

procedure TFPCustomHttpServer.SetActive(const AValue: Boolean);
begin
  if AValue = GetActive then Exit;
  FLoadActivate := AValue;
  if not (csDesigning in ComponentState) then
  begin
    if AValue then
    begin
      if Threaded and FUseThreadPool then
        EnsureThreadPool;
      CreateServerSocket;
      SetupSocket;
      StartServerSocket;
      FreeServerSocket;
    end
    else
    begin
      StopServerSocket;
      if Assigned(FThreadPool) then
        FThreadPool.Stop;
    end;
  end;
end;

procedure TFPCustomHttpServer.SetCertificateData(AValue: TCertificateData);
begin
  if FCertificateData = AValue then Exit;
  FCertificateData := AValue;
end;

procedure TFPCustomHttpServer.SetHostName(AValue: string);
begin
  FCertificateData.HostName := AValue;
end;

procedure TFPCustomHttpServer.SetIdle(AValue: TNotifyEvent);
begin
  FOnAcceptIdle := AValue;
  if Assigned(FServer) then
    FServer.OnIdle := AValue;
end;

procedure TFPCustomHttpServer.SetOnAllowConnect(const AValue: TConnectQuery);
begin
  if FOnAllowConnect = AValue then Exit;
  CheckInactive;
  FOnAllowConnect := AValue;
end;

procedure TFPCustomHttpServer.SetAddress(const AValue: string);
begin
  if FAddress = AValue then Exit;
  CheckInactive;
  FAddress := AValue;
end;

procedure TFPCustomHttpServer.SetPort(const AValue: Word);
begin
  if FPort = AValue then Exit;
  CheckInactive;
  FPort := AValue;
end;

procedure TFPCustomHttpServer.SetQueueSize(const AValue: Word);
begin
  if FQueueSize = AValue then Exit;
  CheckInactive;
  FQueueSize := AValue;
end;

procedure TFPCustomHttpServer.SetThreaded(const AValue: Boolean);
begin
  if FThreaded = AValue then Exit;
  CheckInactive;
  FThreaded := AValue;
  if FThreaded and not FUseThreadPool and not Assigned(FConnectionThreadList) then
    FConnectionThreadList := TThreadList.Create;
end;

procedure TFPCustomHttpServer.SetUseThreadPool(const AValue: Boolean);
begin
  if FUseThreadPool = AValue then Exit;
  CheckInactive;
  FUseThreadPool := AValue;
end;

procedure TFPCustomHttpServer.SetThreadPoolSize(const AValue: Integer);
begin
  if FThreadPoolSize = AValue then Exit;
  CheckInactive;
  FThreadPoolSize := AValue;
end;

procedure TFPCustomHttpServer.SetThreadPoolQueueLimit(const AValue: Integer);
begin
  if FThreadPoolQueueLimit = AValue then Exit;
  FThreadPoolQueueLimit := AValue;
  if Assigned(FThreadPool) then
    FThreadPool.MaxQueueCapacity := AValue;
end;

function TFPCustomHttpServer.CreateRequest: TFPHTTPConnectionRequest;
begin
  Result := TFPHTTPConnectionRequest.Create;
end;

function TFPCustomHttpServer.CreateResponse(ARequest: TFPHTTPConnectionRequest): TFPHTTPConnectionResponse;
begin
  Result := TFPHTTPConnectionResponse.Create(ARequest);
end;

procedure TFPCustomHttpServer.InitRequest(ARequest: TFPHTTPConnectionRequest);
begin
end;

procedure TFPCustomHttpServer.InitResponse(AResponse: TFPHTTPConnectionResponse);
begin
end;

function TFPCustomHttpServer.CreateConnection(Data: TSocketStream): TFPHTTPConnection;
begin
  Result := TFPHTTPConnection.Create(Self, Data);
end;

function TFPCustomHttpServer.CreateConnectionThread(Conn: TFPHTTPConnection): TFPHTTPConnectionThread;
begin
  if not Assigned(FConnectionThreadList) then
    FConnectionThreadList := TThreadList.Create;
  Result := TFPHTTPConnectionThread.CreateConnection(Conn, FConnectionThreadList);
end;

procedure TFPCustomHttpServer.CheckInactive;
begin
  if GetActive then
    raise EHTTPServer.Create(SErrSocketActive);
end;

procedure TFPCustomHttpServer.DoConnect(Sender: TObject; Data: TSocketStream);
var
  Con: TFPHTTPConnection;
begin
  Con := CreateConnection(Data);
  try
    Con.FServer := Self;
    Con.OnRequestError := @HandleRequestError;
    if Threaded then
    begin
      if FUseThreadPool then
      begin
        EnsureThreadPool;
        if not FThreadPool.QueueWork(Con) then
        begin
          // Queue full: reject safely and close connection
          HandleRequestError(Self, EHTTPServer.Create('Server busy: ThreadPool queue full'));
          Con.Free;
        end;
        // If enqueued successfully, the worker thread takes ownership of Con and frees it
      end
      else
        CreateConnectionThread(Con); // Fallback modo thread-per-request
    end
    else
      Con.HandleRequest;
  finally
    if not Threaded then
      Con.Free;
  end;
end;

procedure TFPCustomHttpServer.SetupSocket;
begin
  FServer.QueueSize := Self.QueueSize;
  FServer.ReuseAddress := True;
end;

procedure TFPCustomHttpServer.CreateServerSocket;
begin
  if FAddress = '' then
    FServer := TInetServer.Create(FPort)
  else
    FServer := TInetServer.Create(FAddress, FPort);
  FServer.OnCreateClientSocketHandler := @DoCreateClientHandler;
  FServer.MaxConnections := -1;
  FServer.OnConnectQuery := OnAllowConnect;
  FServer.OnConnect := @DoConnect;
  FServer.OnAcceptError := @DoAcceptError;
  FServer.OnIdle := OnAcceptIdle;
  FServer.AcceptIdleTimeOut := AcceptIdleTimeout;
end;

procedure TFPCustomHttpServer.StartServerSocket;
begin
  FServer.Bind;
  FServer.Listen;
  FServer.StartAccepting;
end;

procedure TFPCustomHttpServer.FreeServerSocket;
begin
  FreeAndNil(FServer);
end;

procedure TFPCustomHttpServer.HandleRequest(var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
begin
  if Assigned(FOnRequest) then
    FOnRequest(Self, ARequest, AResponse);
end;

constructor TFPCustomHttpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPort := 80;
  FQueueSize := 128; // High listen backlog for high concurrency
  FServerBanner := 'Zenith';
  FCertificateData := CreateCertificateData;
  FUseThreadPool := True;
  FThreadPoolSize := 0; // Auto-detect baseado em cores CPU
  FThreadPoolQueueLimit := 65536;
  FThreadPool := nil;
  FMaxRequestBodySize := StrToInt64Def(GetEnvironmentVariable('ZENITH_MAX_BODY_SIZE'), ZENITH_DEFAULT_MAX_BODY_SIZE);
  FMaxHeaderSize := StrToInt64Def(GetEnvironmentVariable('ZENITH_MAX_HEADER_SIZE'), ZENITH_DEFAULT_MAX_HEADER_SIZE);
  FReadTimeout := StrToIntDef(GetEnvironmentVariable('ZENITH_READ_TIMEOUT_MS'), ZENITH_DEFAULT_READ_TIMEOUT_MS);
end;

procedure TFPCustomHttpServer.WaitForRequests(MaxAttempts: Integer);
var
  FLastCount, ACount: Integer;
begin
  ACount := 0;
  FLastCount := FConnectionCount;
  while (FConnectionCount > 0) and (ACount < MaxAttempts) do
  begin
    Sleep(50);
    if (FConnectionCount = FLastCount) then
      Inc(ACount)
    else
    begin
      FLastCount := FConnectionCount;
      ACount := 0;
    end;
  end;
end;

function TFPCustomHttpServer.CreateCertificateData: TCertificateData;
begin
  Result := TCertificateData.Create;
end;

function TFPCustomHttpServer.CreateSSLSocketHandler: TSocketHandler;
var
  S: TSSLSocketHandler;
  CK: TCertAndKey;
begin
  S := TSSLSocketHandler.GetDefaultHandler;
  try
    if CertificateData.NeedCertificateData then
    begin
      S.CertGenerator.HostName := CertificateData.Hostname;
      CK := S.CertGenerator.CreateCertificateAndKey;
      CertificateData.Certificate.Value := CK.Certificate;
      CertificateData.PrivateKey.Value := CK.PrivateKey;
    end;
    S.CertificateData := Self.CertificateData;
    Result := S;
  except
    S.Free;
    raise;
  end;
end;

function TFPCustomHttpServer.GetSocketHandler(const UseSSL: Boolean): TSocketHandler;
begin
  Result := nil;
  if Assigned(FOnGetSocketHandler) then
    FOnGetSocketHandler(Self, UseSSL, Result);
  if (Result = nil) then
    if UseSSL then
      Result := CreateSSLSocketHandler
    else
      Result := TSocketHandler.Create;
  if Assigned(FAfterSocketHandlerCreated) then
    FAfterSocketHandlerCreated(Self, Result);
end;

destructor TFPCustomHttpServer.Destroy;
var
  ThreadList: TList;
  I: Integer;
begin
  Active := False;
  if Threaded and (FConnectionCount > 0) then
  begin
    WaitForRequests;
    if Assigned(FConnectionThreadList) then
    begin
      ThreadList := FConnectionThreadList.LockList;
      try
        for I := ThreadList.Count - 1 downto 0 do
          CloseSocket(TFPHTTPConnectionThread(ThreadList[I]).Connection.Socket.Handle);
      finally
        FConnectionThreadList.UnlockList;
      end;
      WaitForRequests(High(Integer));
    end;
  end;
  DestroyThreadPool;
  FreeAndNil(FConnectionThreadList);
  FreeAndNil(FCertificateData);
  inherited Destroy;
end;

end.
