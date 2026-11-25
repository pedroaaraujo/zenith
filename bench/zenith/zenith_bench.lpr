{
  Benchmark: Zenith (roteador radix, thread pool, DeltaModel streamer).
  Rotas equivalentes às de bench/fpweb/fpweb_bench.lpr.
}
program zenith_bench;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, cwstring,
  {$ENDIF}
  Classes, SysUtils, httpdefs, fphttpapp,
  Zenith.App, Bench.Model;

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
  M: TBenchMessage;
begin
  M := TBenchMessage.Create;
  try
    M.message.Value := 'Hello, World!';
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := M.ToJson;
  finally
    M.Free;
  end;
end;

procedure Items(ARequest: TRequest; AResponse: TResponse);
var
  L: TBenchItemList;
  It: TBenchItem;
  I: Integer;
begin
  L := TBenchItemList.Create;
  try
    for I := 1 to ITEM_COUNT do
    begin
      It := TBenchItem.Create;
      It.id.Value := I;
      It.name.Value := 'Item ' + IntToStr(I);
      It.price.Value := I * 1.5;
      It.active.Value := Odd(I);
      L.Add(It);
    end;
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := L.ToJson;
  finally
    L.Free;
  end;
end;

procedure Echo(ARequest: TRequest; AResponse: TResponse);
var
  It: TBenchItem;
begin
  It := TBenchItem.Create;
  try
    It.FromJson(ARequest.Content);
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := It.ToJson;
  finally
    It.Free;
  end;
end;

begin
  Router.Get('/plaintext', @Plaintext);
  Router.Get('/json', @JsonHello);
  Router.Get('/items', @Items);
  Router.Post('/echo', @Echo);
  ZenithApp
    .SetPort(StrToIntDef(GetEnvironmentVariable('BENCH_PORT'), 9002))
    .SetThreaded(True)
    .Run;
end.
