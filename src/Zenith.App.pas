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
  if ARequest.Method.Equals('OPTIONS') and
     GetEnvVariable('ZENITH_ALLOW_CORS', 'Y').Equals('Y') then
  begin
    AllowCors(ARequest, AResponse);
    Exit;
  end;

  raise ENotFound.Create('not found');
end;

procedure TZenithApp.AfterConstruction;
var
  CorsOrigin: string;
begin
  inherited AfterConstruction;
  Application.Port := StrToIntDef(GetEnvVariable('ZENITH_PORT'), 8080);
  ZenithLogger := TZenithLogger.Create(GetEnvVariable('ZENITH_LOGFILE'));
  ConfigureApplication(Application);
  SetDocRoute('/docs');

  if GetEnvVariable('ZENITH_ALLOW_CORS', 'Y').Equals('Y') then
  begin
    CorsOrigin := GetEnvVariable('ZENITH_CORS_ORIGIN', '*').Trim;
    Router.AddCustomHeader('Access-Control-Allow-Origin', CorsOrigin);
    Router.AddCustomHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS, PUT, DELETE');
    Router.AddCustomHeader('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
    Router.AddCustomHeader('Vary', 'Origin');
    if not CorsOrigin.Equals('*') and
       GetEnvVariable('ZENITH_CORS_ALLOW_CREDENTIALS', 'N').Equals('Y') then
      Router.AddCustomHeader('Access-Control-Allow-Credentials', 'true');
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

end.
