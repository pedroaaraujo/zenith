unit Zenith.App;

{$mode ObjFPC}{$H+}

interface

uses
  {$ifdef FCGI}
    fpfcgi,
  {$else}
    fphttpapp,
  {$endif}
  Classes, SysUtils, httproute, HTTPDefs,

  swagger4laz,
  Zenith.Core,
  Zenith.Log,
  Zenith.Env,
  Zenith.Security,
  Zenith.Exceptions;

type

  { TZenithApp }

  TZenithApp = class
  public
    function SetThreaded(const Value: Boolean): TZenithApp;
    function SetUseThreadPool(const Value: Boolean): TZenithApp;
    function SetThreadPoolSize(const ASize: Integer): TZenithApp;
    function SetThreadPoolQueueLimit(const ALimit: Integer): TZenithApp;
    function SetTitle(const ATitle: string): TZenithApp;
    function SetDescription(const ADescription: string): TZenithApp;
    function SetVersion(const AVersion: string): TZenithApp;
    function SetDocRoute(const ARoute: string): TZenithApp;
    function SetPort(const APort: Integer): TZenithApp;
    function SetQueueSize(const ASize: Word): TZenithApp;
    function SetSecurityResolver(AResolver: IZenithSecurityResolver): TZenithApp;
    procedure Run;
    procedure AfterConstruction; override;
  end;

var
  Router: TSwaggerRouter;
  ZenithApp: TZenithApp;

implementation

uses
  DeltaModel;

type
  { Aplica CORS por requisição, encadeado ao BeforeRequest já registrado
    (Swagger4Laz). Com lista de origens, devolve apenas a origem recebida
    quando ela é permitida, conforme a especificação Fetch. }
  TZenithCorsHook = class
  private
    FPrevious: THTTPRouteRequestEvent;
    FOrigins: TStringList;
    FAllowAny: Boolean;
    FAllowCredentials: Boolean;
  public
    constructor Create(const AOrigins: string; AAllowCredentials: Boolean);
    destructor Destroy; override;
    function IsAllowed(const AOrigin: string): Boolean;
    procedure BeforeRequest(Sender: TObject; ARequest: TRequest; AResponse: TResponse);
  end;

var
  GCorsHook: TZenithCorsHook = nil;

constructor TZenithCorsHook.Create(const AOrigins: string; AAllowCredentials: Boolean);
var
  Item: string;
begin
  inherited Create;
  FOrigins := TStringList.Create;
  FOrigins.CaseSensitive := False;
  for Item in AOrigins.Split([',']) do
    if Trim(Item) <> '' then
      FOrigins.Add(Trim(Item).TrimRight(['/']));
  FAllowAny := FOrigins.IndexOf('*') >= 0;
  { "*" não pode ser combinado com credenciais (Fetch/CORS). }
  FAllowCredentials := AAllowCredentials and not FAllowAny;
end;

destructor TZenithCorsHook.Destroy;
begin
  FOrigins.Free;
  inherited Destroy;
end;

function TZenithCorsHook.IsAllowed(const AOrigin: string): Boolean;
begin
  Result := (AOrigin <> '') and (FOrigins.IndexOf(AOrigin) >= 0);
end;

procedure TZenithCorsHook.BeforeRequest(Sender: TObject; ARequest: TRequest; AResponse: TResponse);
var
  Origin: string;
begin
  if Assigned(FPrevious) then
    FPrevious(Sender, ARequest, AResponse);

  Origin := Trim(ARequest.GetCustomHeader('Origin'));
  if FAllowAny then
    AResponse.SetCustomHeader('Access-Control-Allow-Origin', '*')
  else
  begin
    AResponse.SetCustomHeader('Vary', 'Origin');
    if not IsAllowed(Origin) then
      Exit;
    AResponse.SetCustomHeader('Access-Control-Allow-Origin', Origin);
    if FAllowCredentials then
      AResponse.SetCustomHeader('Access-Control-Allow-Credentials', 'true');
  end;
  AResponse.SetCustomHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS, PUT, PATCH, DELETE');
  AResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, If-Match, If-None-Match, If-Modified-Since, If-Unmodified-Since, Idempotency-Key, Last-Event-ID');
  AResponse.SetCustomHeader('Access-Control-Expose-Headers', 'ETag, Idempotent-Replayed, Accept-Patch, Retry-After, Content-Encoding');
  AResponse.SetCustomHeader('Access-Control-Max-Age', '600');
end;

function CorsEnabled: Boolean;
begin
  { CORS é opt-in: sem ZENITH_ALLOW_CORS=Y nenhum header CORS é emitido. }
  Result := GetEnvBool('ZENITH_ALLOW_CORS', False);
end;

{ TZenithApp }

procedure ZenithRegisterModelProc(const AName, ASchemaJson: string);
begin
  if Assigned(Router) then
    Router.EnsureModel(AName, ASchemaJson)
  else if Assigned(SwaggerRouter) then
    SwaggerRouter.EnsureModel(AName, ASchemaJson);
end;

procedure AllowCors(ARequest: TRequest; AResponse: TResponse);
begin
  AResponse.Code := 204;
  AResponse.SendHeaders;
end;

procedure NotFound(ARequest: TRequest; AResponse: TResponse);
begin
  if ARequest.Method.Equals('OPTIONS') and CorsEnabled then
  begin
    AllowCors(ARequest, AResponse);
    Exit;
  end;

  raise ENotFound.Create('not found');
end;

procedure TZenithApp.AfterConstruction;
begin
  inherited AfterConstruction;
  Application.Port := StrToIntDef(GetEnvVariable('ZENITH_PORT'), 8080);
  ZenithLogger := TZenithLogger.Create(GetEnvVariable('ZENITH_LOGFILE'));
  ConfigureApplication(Application);
  SetDocRoute('/docs');

  if CorsEnabled then
  begin
    GCorsHook := TZenithCorsHook.Create(
      GetEnvVariable('ZENITH_CORS_ORIGIN', ''),
      GetEnvBool('ZENITH_CORS_ALLOW_CREDENTIALS', False));
    GCorsHook.FPrevious := HTTPRouter.BeforeRequest;
    HTTPRouter.BeforeRequest := @GCorsHook.BeforeRequest;
  end;

  HTTPRouter.RegisterRoute(
    '/not-found',
    httproute.rmAll,
    @NotFound,
    True
  );
end;

function TZenithApp.SetThreaded(const Value: Boolean): TZenithApp;
begin
  Application.Threaded := Value;
  Result := Self;
end;

function TZenithApp.SetUseThreadPool(const Value: Boolean): TZenithApp;
begin
  Application.UseThreadPool := Value;
  Result := Self;
end;

function TZenithApp.SetThreadPoolSize(const ASize: Integer): TZenithApp;
begin
  Application.ThreadPoolSize := ASize;
  Result := Self;
end;

function TZenithApp.SetThreadPoolQueueLimit(const ALimit: Integer): TZenithApp;
begin
  Application.ThreadPoolQueueLimit := ALimit;
  Result := Self;
end;

function TZenithApp.SetTitle(const ATitle: string): TZenithApp;
begin
  Application.Title := ATitle;
  Router.SetTitle(ATitle);
  Result := Self;
end;

function TZenithApp.SetDescription(const ADescription: string): TZenithApp;
begin
  Router.SetDescription(ADescription);
  Result := Self;
end;

function TZenithApp.SetVersion(const AVersion: string): TZenithApp;
begin
  Router.SetVersion(AVersion);
  Result := Self;
end;

function TZenithApp.SetDocRoute(const ARoute: string): TZenithApp;
begin
  Router.SetDocRoute(ARoute);
  Result := Self;
end;

function TZenithApp.SetPort(const APort: Integer): TZenithApp;
begin
  Application.Port := APort;
  Result := Self;
end;

function TZenithApp.SetQueueSize(const ASize: Word): TZenithApp;
begin
  Application.QueueSize := ASize;
  Result := Self;
end;

function TZenithApp.SetSecurityResolver(AResolver: IZenithSecurityResolver): TZenithApp;
begin
  SetZenithSecurityResolver(AResolver);
  Result := Self;
end;

procedure TZenithApp.Run;
begin
  Application.Initialize;
  ZenithLogger.Info('Application running on port ' + Application.Port.ToString);
  Application.Run;
end;

initialization
  Router := SwaggerRouter;
  ZenithApp := TZenithApp.Create;
  SetDeltaModelRegisterSchemaProc(@ZenithRegisterModelProc);

finalization
  SetDeltaModelRegisterSchemaProc(nil);
  ZenithApp.Free;
  FreeAndNil(GCorsHook);

end.
