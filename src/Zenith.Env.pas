unit Zenith.Env;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

function GetEnvVariable(const VarName: string; const DefaultValue: string = ''): string;
procedure SetEnvVariable(const VarName, Value: string);

implementation

{$IFDEF UNIX}
function c_setenv(name: PChar; value: PChar; overwrite: Integer): Integer; cdecl; external 'c' name 'setenv';
{$ENDIF}
{$IFDEF WINDOWS}
function SetEnvironmentVariableA(lpName, lpValue: PChar): LongBool; stdcall; external 'kernel32' name 'SetEnvironmentVariableA';
{$ENDIF}

var
  GLocalEnv: TStringList = nil;

function GetEnvVariable(const VarName: string; const DefaultValue: string
  ): string;
var
  SL: TStringList;
  Arquivo: string;
begin
  if Assigned(GLocalEnv) and (GLocalEnv.IndexOfName(VarName) >= 0) then
  begin
    Result := GLocalEnv.Values[VarName];
    if not Result.IsEmpty then Exit;
  end;

  { Process environment variables are the deployment-level override. }
  Result := GetEnvironmentVariable(VarName);
  if not Result.IsEmpty then
    Exit;

  Arquivo := ExtractFilePath(ParamStr(0)) + '.env';
  if FileExists(Arquivo) then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile(Arquivo);
      Result := SL.Values[VarName];
    finally
      SL.Free;
    end;
  end;

  if Result.IsEmpty then
  begin
    Result := DefaultValue;
  end;
end;

procedure SetEnvVariable(const VarName, Value: string);
begin
  if not Assigned(GLocalEnv) then
    GLocalEnv := TStringList.Create;
  GLocalEnv.Values[VarName] := Value;

  {$IFDEF WINDOWS}
  SetEnvironmentVariableA(PChar(VarName), PChar(Value));
  {$ENDIF}
  {$IFDEF UNIX}
  c_setenv(PChar(VarName), PChar(Value), 1);
  {$ENDIF}
end;

initialization

finalization
  if Assigned(GLocalEnv) then
    FreeAndNil(GLocalEnv);

end.
