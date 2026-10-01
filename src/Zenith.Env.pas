unit Zenith.Env;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

function GetEnvVariable(const VarName: string; const DefaultValue: string = ''): string;

implementation

function GetEnvVariable(const VarName: string; const DefaultValue: string
  ): string;
var
  SL: TStringList;
  Arquivo: string;
begin
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

end.
