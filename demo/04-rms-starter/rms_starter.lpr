{
    Zenith Framework - RMS Starter Demo Application
    Complete REST API starter for Products, Customers, Sales, and W3C SSE Events.
}

program rms_starter;

{$mode Delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  Classes,
  SysUtils,
  SQLite3Conn,
  fphttpapp,
  Zenith.App,
  Rms.Model,
  Rms.Route;

var
  LPort: Integer;
  LWorkers: Integer;
begin
  Randomize;
  LPort := StrToIntDef(GetEnvironmentVariable('PORT'),
    StrToIntDef(GetEnvironmentVariable('ZENITH_PORT'), 8080));
  LWorkers := StrToIntDef(GetEnvironmentVariable('ZENITH_THREADPOOL_WORKERS'), 16);

  WriteLn('================================================================================');
  WriteLn('           ZENITH FRAMEWORK - RMS STARTER REST API & REAL-TIME SSE              ');
  WriteLn('================================================================================');
  WriteLn('[Init] Initializing SQLite database and seeding sample RMS catalog...');
  InitializeRmsStore;
  RegisterRmsStarterRoutes;

  WriteLn('[Init] Swagger UI:    http://127.0.0.1:' + IntToStr(LPort) + '/docs');
  WriteLn('[Init] OpenAPI 3.1:   http://127.0.0.1:' + IntToStr(LPort) + '/docs/openapi.json');
  WriteLn('[Init] Health check:  http://127.0.0.1:' + IntToStr(LPort) + '/api/v1/health');
  WriteLn('[Init] SSE stream:    http://127.0.0.1:' + IntToStr(LPort) + '/api/v1/events/sales');
  WriteLn('[Init] Starting Zenith HTTP server on port ' + IntToStr(LPort) +
    ' (ThreadPool workers: ' + IntToStr(LWorkers) + ')...');

  ZenithApp
    .SetTitle('Zenith RMS Starter API')
    .SetDescription('Complete REST API starter with Products, Customers, Sales, OpenAPI 3.1, and W3C SSE.')
    .SetVersion('1.0.0')
    .SetDocRoute('/docs')
    .SetThreaded(True)
    .SetUseThreadPool(True)
    .SetThreadPoolSize(LWorkers)
    .SetPort(LPort)
    .Run;
end.
