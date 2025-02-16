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
  Arquivo := ExtractFilePath(ParamStr(0)) + '.env';
  if not FileExists(Arquivo) then
  begin
    Result := GetEnvironmentVariable(VarName);
  end
  else
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
