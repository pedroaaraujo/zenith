program test_zenith_runner;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, consoletestrunner,
  test_zenith_unit,
  test_zenith_e2e;

type
  TZenithTestRunner = class(TTestRunner)
  protected
    procedure AppendLongOpts; override;
  end;

procedure TZenithTestRunner.AppendLongOpts;
begin
  inherited AppendLongOpts;
end;

var
  Application: TZenithTestRunner;

begin
  DefaultRunAllTests := True;
  DefaultFormat := fPlain;
  Application := TZenithTestRunner.Create(nil);
  try
    Application.Initialize;
    Application.Title := 'Zenith Unit & E2E Test Suite';
    Application.Run;
  finally
    Application.Free;
  end;
end.
