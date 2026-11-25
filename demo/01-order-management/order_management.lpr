program order_management;

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
  Order.Model,
  Order.Route;

var
  LPort: Integer;
begin
  LPort := StrToIntDef(GetEnvironmentVariable('PORT'), StrToIntDef(GetEnvironmentVariable('ZENITH_PORT'), 8080));

  WriteLn('================================================================================');
  WriteLn('       ZENITH FRAMEWORK - ORDER MANAGEMENT / RMS STARTER REST API               ');
  WriteLn('================================================================================');
  WriteLn('[Init] Inicializando banco de dados SQLite e catálogo de demonstração...');
  InitializeOrderStore;
  { As rotas CRUD capturam o pool: registrar somente após criá-lo. }
  RegisterOrderDemoRoutes;

  WriteLn('[Init] Swagger UI disponível em: http://localhost:' + IntToStr(LPort) + '/docs');
  WriteLn('[Init] OpenAPI spec em: http://localhost:' + IntToStr(LPort) + '/openapi.json');
  WriteLn('[Init] Inicializando servidor HTTP Zenith na porta ' + IntToStr(LPort) + '...');

  ZenithApp
    .SetTitle('Zenith RMS - Order Management Starter API')
    .SetPort(LPort)
    .Run;
end.
