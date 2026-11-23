program test_sse_runner;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, consoletestrunner,
  test_zenith_sse;

type
  TSSETestRunner = class(TTestRunner)
  protected
    procedure AppendLongOpts; override;
  end;

procedure TSSETestRunner.AppendLongOpts;
begin
  inherited AppendLongOpts;
end;

var
  Application: TSSETestRunner;

begin
  DefaultRunAllTests := True;
  DefaultFormat := fPlain;
  Application := TSSETestRunner.Create(nil);
  try
    Application.Initialize;
    Application.Title := 'Zenith W3C SSE Test Suite';
    Application.Run;
  finally
    Application.Free;
  end;
end.
