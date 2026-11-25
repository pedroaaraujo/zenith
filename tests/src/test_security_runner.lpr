program test_security_runner;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, consoletestrunner,
  test_zenith_security;

type
  TSecurityTestRunner = class(TTestRunner)
  protected
    procedure AppendLongOpts; override;
  end;

procedure TSecurityTestRunner.AppendLongOpts;
begin
  inherited AppendLongOpts;
end;

var
  Application: TSecurityTestRunner;

begin
  DefaultRunAllTests := True;
  DefaultFormat := fPlain;
  Application := TSecurityTestRunner.Create(nil);
  try
    Application.Initialize;
    Application.Title := 'Zenith Security Test Suite';
    Application.Run;
  finally
    Application.Free;
  end;
end.
