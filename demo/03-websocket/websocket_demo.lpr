program websocket_demo;

{
  Zenith Native WebSocket Server Demo (RFC 6455 + RFC 7692 + CBOR/BSON + CWT)
}

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  Classes, SysUtils, fphttpapp,
  Zenith.App,
  Zenith.Security.CWT,
  WebSocket.Route;

begin
  Randomize;
  if TCWT.GetSecret = '' then
    TCWT.SetSecret('zenith-demo-cwt-secret-change-in-production');

  RegisterWebSocketRoutes;

  ZenithApp
    .SetTitle('Zenith WebSocket Realtime Demo')
    .SetThreaded(True)
    .SetPort(8088)
    .Run;
end.
