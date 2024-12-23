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
  Zenith.Exceptions;

type

  { TZenithApp }

  TZenithApp = class
  public
    function SetThreaded(const Value: Boolean): TZenithApp;
    function SetTitle(const ATitle: string): TZenithApp;
    function SetDescription(const ADescription: string): TZenithApp;
    function SetVersion(const AVersion: string): TZenithApp;
    function SetDocRoute(const ARoute: string): TZenithApp;
    procedure Run;
    procedure AfterConstruction; override;
  end;

var
  Router: TSwaggerRouter;
  ZenithApp: TZenithApp;

implementation

{ TZenithApp }

procedure NotFound(ARequest: TRequest; AResponse: TResponse);
begin
  raise ENotFound.Create('not found');
end;

procedure TZenithApp.AfterConstruction;
begin
  inherited AfterConstruction;
  Application.Port := StrToIntDef(GetEnvVariable('ZENITH_PORT'), 8080);
  ZenithLogger := TZenithLogger.Create(GetEnvVariable('ZENITH_LOGFILE'));
  ConfigureApplication(Application);
  SetDocRoute('/docs');

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

procedure TZenithApp.Run;
begin
  Application.Initialize;
  ZenithLogger.Info('Application running on port ' + Application.Port.ToString);
  Application.Run;
end;

initialization
  Router := SwaggerRouter;
  ZenithApp := TZenithApp.Create;

finalization
  ZenithApp.Free;

end.
