unit Zenith.Env;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

function GetEnvVariable(VarName: string): string;  

implementation

function GetEnvVariable(VarName: string): string;
var
  SL: TStringList;
  Arquivo: string;
begin
  Arquivo := ExtractFilePath(ParamStr(0)) + '.env';
  if not FileExists(Arquivo) then
  begin
    Exit(GetEnvironmentVariable(VarName));
  end;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(Arquivo);
    Result := SL.Values[VarName];
  finally
    SL.Free;
  end;
end;

end.