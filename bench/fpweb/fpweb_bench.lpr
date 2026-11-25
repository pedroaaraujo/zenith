{
  Benchmark de referência: fpWeb puro (FPC fcl-web), sem units do Zenith.
  Compile SEM -Fu../../src para usar fphttpapp/httproute originais do FPC.
  Rotas equivalentes às de bench/zenith/zenith_bench.lpr.
}
program fpweb_bench;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, cwstring,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, httpdefs, httproute, fphttpapp;

const
  ITEM_COUNT = 50;

procedure Plaintext(ARequest: TRequest; AResponse: TResponse);
begin
  AResponse.Code := 200;
  AResponse.ContentType := 'text/plain; charset=utf-8';
  AResponse.Content := 'Hello, World!';
end;

procedure JsonHello(ARequest: TRequest; AResponse: TResponse);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create(['message', 'Hello, World!']);
  try
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := O.AsJSON;
  finally
    O.Free;
  end;
end;

procedure Items(ARequest: TRequest; AResponse: TResponse);
var
  A: TJSONArray;
  I: Integer;
begin
  A := TJSONArray.Create;
  try
    for I := 1 to ITEM_COUNT do
      A.Add(TJSONObject.Create(['id', I, 'name', 'Item ' + IntToStr(I),
        'price', I * 1.5, 'active', Odd(I)]));
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := A.AsJSON;
  finally
    A.Free;
  end;
end;

procedure Echo(ARequest: TRequest; AResponse: TResponse);
var
  D: TJSONData;
begin
  D := GetJSON(ARequest.Content);
  try
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := D.AsJSON;
  finally
    D.Free;
  end;
end;

begin
  HTTPRouter.RegisterRoute('/plaintext', rmGet, @Plaintext);
  HTTPRouter.RegisterRoute('/json', rmGet, @JsonHello);
  HTTPRouter.RegisterRoute('/items', rmGet, @Items);
  HTTPRouter.RegisterRoute('/echo', rmPost, @Echo);
  Application.Port := StrToIntDef(GetEnvironmentVariable('BENCH_PORT'), 9001);
  Application.Threaded := True;
  Application.Initialize;
  Application.Run;
end.
