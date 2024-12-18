unit Zenith.Log;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  TLogLevel = (llDebug, llInfo, llWarning, llError, llCritical);
  TLogLevelSet = set of TLogLevel;

  { TZenithLogger }
  TZenithLogger = class
  private
    FLogFilePath: string;
    FLogLevels: set of TLogLevel;
    FIncludeTimestamp: Boolean;
    function LogLevelToString(ALevel: TLogLevel): string;
    function GetTimestamp: string;
  public
    constructor Create(const ALogFilePath: string = ''; AIncludeTimestamp: Boolean = True);
    procedure SetLogLevels(ALevels: TLogLevelSet);
    procedure Log(ALevel: TLogLevel; const AMessage: string);
    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warning(const AMessage: string);
    procedure Error(const AMessage: string);
    procedure Critical(const AMessage: string);
  end;

  var
    ZenithLogger: TZenithLogger;

implementation

{ TZenithLogger }

constructor TZenithLogger.Create(const ALogFilePath: string; AIncludeTimestamp: Boolean);
begin
  FLogFilePath := ALogFilePath;
  FIncludeTimestamp := AIncludeTimestamp;
  // Default log levels
  FLogLevels := [llDebug, llInfo, llWarning, llError, llCritical];
end;

procedure TZenithLogger.SetLogLevels(ALevels: TLogLevelSet);
begin
  FLogLevels := ALevels;
end;

function TZenithLogger.LogLevelToString(ALevel: TLogLevel): string;
begin
  case ALevel of
    llDebug:    Result := 'DEBUG';
    llInfo:     Result := 'INFO';
    llWarning:  Result := 'WARNING';
    llError:    Result := 'ERROR';
    llCritical: Result := 'CRITICAL';
  else
    Result := 'UNKNOWN';
  end;
end;

function TZenithLogger.GetTimestamp: string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now);
end;

procedure TZenithLogger.Log(ALevel: TLogLevel; const AMessage: string);
var
  LogLine: string;
  LogFile: TextFile;
begin
  if not (ALevel in FLogLevels) then
    Exit;

  if FIncludeTimestamp then
    LogLine := Format('[%s] [%s] %s', [GetTimestamp, LogLevelToString(ALevel), AMessage])
  else
    LogLine := Format('[%s] %s', [LogLevelToString(ALevel), AMessage]);

  if FLogFilePath.Trim.IsEmpty then
  begin
    Writeln(LogLine);
    Exit;
  end;

  if not FileExists(FLogFilePath) then
    AssignFile(LogFile, FLogFilePath)
  else
    Append(LogFile);
  Rewrite(LogFile);
  Writeln(LogFile, LogLine);
  CloseFile(LogFile);
end;

procedure TZenithLogger.Debug(const AMessage: string);
begin
  Log(llDebug, AMessage);
end;

procedure TZenithLogger.Info(const AMessage: string);
begin
  Log(llInfo, AMessage);
end;

procedure TZenithLogger.Warning(const AMessage: string);
begin
  Log(llWarning, AMessage);
end;

procedure TZenithLogger.Error(const AMessage: string);
begin
  Log(llError, AMessage);
end;

procedure TZenithLogger.Critical(const AMessage: string);
begin
  Log(llCritical, AMessage);
end;


finalization
  if ZenithLogger <> nil then
    ZenithLogger.Free;

end.
