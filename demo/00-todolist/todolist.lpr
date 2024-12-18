program todolist;

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  Classes,
  Sysutils,
  fphttpapp,
  Zenith.Core,
  Zenith.Env,
  swagger4laz;

begin
  Application.Title := 'TodoList';
  Application.Port := StrToIntDef(GetEnvVariable('ZENITH_PORT'), 8080);
  Application.Threaded := False;

  Application.Initialize;

  ConfigureApplication(Application);
  SwaggerRouter
    .SetTitle(Application.Title)
    .SetDescription('API reference')
    .SetVersion('1.0.0.0')
    .SetDocRoute('/docs');

  Application.Run;
end.

