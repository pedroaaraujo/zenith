unit Zenith.Env;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

{ Ordem de resolução: SetEnvVariable (processo atual) > variável de ambiente
  do sistema > arquivo .env ao lado do executável > DefaultValue.
  O .env é lido uma única vez (na inicialização da unit); use ReloadEnvFile
  para recarregá-lo. }
function GetEnvVariable(const VarName: string; const DefaultValue: string = ''): string;
{ Interpreta Y/YES/S/SIM/TRUE/ON/1 como verdadeiro e N/NO/NAO/NÃO/FALSE/OFF/0 como falso. }
function GetEnvBool(const VarName: string; const DefaultValue: Boolean = False): Boolean;
procedure SetEnvVariable(const VarName, Value: string);
procedure ReloadEnvFile(const AFileName: string = '');
function GetEnvGeneration: UInt64;

implementation

uses
  SyncObjs;

{$IFDEF UNIX}
function c_setenv(name: PChar; value: PChar; overwrite: Integer): Integer; cdecl; external 'c' name 'setenv';
{$ENDIF}
{$IFDEF WINDOWS}
function SetEnvironmentVariableA(lpName, lpValue: PChar): LongBool; stdcall; external 'kernel32' name 'SetEnvironmentVariableA';
{$ENDIF}

var
  GLock: TCriticalSection = nil;
  GLocalEnv: TStringList = nil;
  GFileEnv: TStringList = nil;
  GEnvGeneration: UInt64 = 1;

function GetEnvGeneration: UInt64;
begin
  GLock.Acquire;
  try
    Result := GEnvGeneration;
  finally
    GLock.Release;
  end;
end;

function ParseEnvLine(const ALine: string; out AName, AValue: string): Boolean;
var
  Line: string;
  P: SizeInt;
  Q: Char;
begin
  Result := False;
  Line := Trim(ALine);
  if (Line = '') or (Line[1] = '#') then
    Exit;
  if SameText(Copy(Line, 1, 7), 'export ') then
    Line := Trim(Copy(Line, 8, MaxInt));
  P := Pos('=', Line);
  if P <= 1 then
    Exit;
  AName := Trim(Copy(Line, 1, P - 1));
  AValue := Trim(Copy(Line, P + 1, MaxInt));
  if (Length(AValue) >= 2) and (AValue[1] in ['"', '''']) then
  begin
    Q := AValue[1];
    P := LastDelimiter(Q, AValue);
    if P > 1 then
      AValue := Copy(AValue, 2, P - 2);
  end
  else
  begin
    { Comentário inline só para valores sem aspas: VAR=valor # comentário }
    P := Pos(' #', AValue);
    if P > 0 then
      AValue := TrimRight(Copy(AValue, 1, P - 1));
  end;
  Result := AName <> '';
end;

procedure ReloadEnvFile(const AFileName: string);
var
  SL, Parsed: TStringList;
  Arquivo, N, V: string;
  I: Integer;
begin
  Arquivo := AFileName;
  if Arquivo = '' then
    Arquivo := ExtractFilePath(ParamStr(0)) + '.env';

  Parsed := TStringList.Create;
  if FileExists(Arquivo) then
  begin
    SL := TStringList.Create;
    try
      try
        SL.LoadFromFile(Arquivo);
        for I := 0 to SL.Count - 1 do
          if ParseEnvLine(SL[I], N, V) then
            Parsed.Values[N] := V;
      except
        { .env ilegível: segue apenas com o ambiente do processo. }
      end;
    finally
      SL.Free;
    end;
  end;

  GLock.Acquire;
  try
    GFileEnv.Free;
    GFileEnv := Parsed;
    Inc(GEnvGeneration);
  finally
    GLock.Release;
  end;
end;

function GetEnvVariable(const VarName: string; const DefaultValue: string
  ): string;
begin
  Result := '';
  GLock.Acquire;
  try
    if Assigned(GLocalEnv) and (GLocalEnv.IndexOfName(VarName) >= 0) then
      Result := GLocalEnv.Values[VarName];
  finally
    GLock.Release;
  end;
  if Result <> '' then
    Exit;

  { Process environment variables are the deployment-level override. }
  Result := GetEnvironmentVariable(VarName);
  if Result <> '' then
    Exit;

  GLock.Acquire;
  try
    if Assigned(GFileEnv) then
      Result := GFileEnv.Values[VarName];
  finally
    GLock.Release;
  end;

  if Result = '' then
    Result := DefaultValue;
end;

function GetEnvBool(const VarName: string; const DefaultValue: Boolean): Boolean;
var
  V: string;
begin
  V := UpperCase(Trim(GetEnvVariable(VarName, '')));
  if (V = 'Y') or (V = 'YES') or (V = 'S') or (V = 'SIM') or (V = 'TRUE') or
     (V = 'ON') or (V = '1') then
    Exit(True);
  if (V = 'N') or (V = 'NO') or (V = 'NAO') or (V = 'NÃO') or (V = 'FALSE') or
     (V = 'OFF') or (V = '0') then
    Exit(False);
  Result := DefaultValue;
end;

procedure SetEnvVariable(const VarName, Value: string);
begin
  GLock.Acquire;
  try
    if not Assigned(GLocalEnv) then
      GLocalEnv := TStringList.Create;
    GLocalEnv.Values[VarName] := Value;
    Inc(GEnvGeneration);
  finally
    GLock.Release;
  end;

  {$IFDEF WINDOWS}
  SetEnvironmentVariableA(PChar(VarName), PChar(Value));
  {$ENDIF}
  {$IFDEF UNIX}
  c_setenv(PChar(VarName), PChar(Value), 1);
  {$ENDIF}
end;

initialization
  GLock := TCriticalSection.Create;
  ReloadEnvFile('');

finalization
  FreeAndNil(GLocalEnv);
  FreeAndNil(GFileEnv);
  FreeAndNil(GLock);

end.
