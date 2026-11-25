unit Zenith.Log;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, Zenith.Env;

type
  TLogLevel = (llDebug, llInfo, llWarning, llError, llCritical);
  TLogLevelSet = set of TLogLevel;
  TLogFormat = (lfText, lfJson);

  { TZenithLogWriterThread }
  TZenithLogWriterThread = class(TThread)
  private
    FLogFilePath: string;
    FQueueLock: TCriticalSection;
    FQueueEvent: TEvent;
    FFlushedEvent: TEvent;
    FQueue: TStringList;
    FWriting: Boolean;
    procedure DrainBatch(ABatch: TStringList; var AStream: TFileStream);
  protected
    procedure Execute; override;
  public
    constructor Create(const ALogFilePath: string);
    destructor Destroy; override;
    procedure Enqueue(const ALine: string);
    procedure Flush(ATimeoutMs: Cardinal = 5000);
  end;

  { TZenithLogger }
  TZenithLogger = class
  private
    FLogFilePath: string;
    FLogLevels: set of TLogLevel;
    FLogFormat: TLogFormat;
    FIncludeTimestamp: Boolean;
    FLock: TCriticalSection;
    FWriter: TZenithLogWriterThread;
    function LogLevelToString(ALevel: TLogLevel): string;
    function GetTimestamp: string;
    function FormatLogLine(ALevel: TLogLevel; const AMessage: RawByteString): string;
  public
    constructor Create(const ALogFilePath: string = ''; AIncludeTimestamp: Boolean = True);
    destructor Destroy; override;
    procedure SetLogLevels(ALevels: TLogLevelSet);
    procedure SetLogFormat(AFormat: TLogFormat);
    procedure Flush;
    procedure Log(ALevel: TLogLevel; const AMessage: RawByteString);
    procedure Debug(const AMessage: RawByteString);
    procedure Info(const AMessage: RawByteString);
    procedure Warning(const AMessage: RawByteString);
    procedure Error(const AMessage: RawByteString);
    procedure Critical(const AMessage: RawByteString);
  end;

  var
    ZenithLogger: TZenithLogger;

implementation

function EscapeJsonString(const S: RawByteString): string;
const
  HexChars: array[0..15] of Char = '0123456789abcdef';
var
  I: SizeInt;
  B: Byte;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create(Length(S) + 16);
  try
    for I := 1 to Length(S) do
    begin
      B := Byte(S[I]);
      case B of
        Ord('"'): SB.Append('\"');
        Ord('\'): SB.Append('\\');
        8:  SB.Append('\b');
        9:  SB.Append('\t');
        10: SB.Append('\n');
        12: SB.Append('\f');
        13: SB.Append('\r');
      else
        if B < 32 then
          SB.Append('\u00').Append(HexChars[B shr 4]).Append(HexChars[B and $0F])
        else
          SB.Append(AnsiChar(B));
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TZenithLogWriterThread }

constructor TZenithLogWriterThread.Create(const ALogFilePath: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLogFilePath := ALogFilePath;
  FQueueLock := TCriticalSection.Create;
  FQueueEvent := TEvent.Create(nil, False, False, '');
  FFlushedEvent := TEvent.Create(nil, True, True, '');
  FQueue := TStringList.Create;
  FWriting := False;
  Start;
end;

destructor TZenithLogWriterThread.Destroy;
begin
  Terminate;
  FQueueEvent.SetEvent;
  WaitFor;
  FreeAndNil(FQueue);
  FreeAndNil(FFlushedEvent);
  FreeAndNil(FQueueEvent);
  FreeAndNil(FQueueLock);
  inherited Destroy;
end;

procedure TZenithLogWriterThread.Enqueue(const ALine: string);
begin
  FQueueLock.Acquire;
  try
    FQueue.Add(ALine);
    FFlushedEvent.ResetEvent;
  finally
    FQueueLock.Release;
  end;
  FQueueEvent.SetEvent;
end;

procedure TZenithLogWriterThread.Flush(ATimeoutMs: Cardinal);
begin
  FQueueEvent.SetEvent;
  FFlushedEvent.WaitFor(ATimeoutMs);
end;

procedure TZenithLogWriterThread.DrainBatch(ABatch: TStringList; var AStream: TFileStream);
var
  I: Integer;
  Chunk: RawByteString;
  Dir: string;
begin
  if ABatch.Count = 0 then
    Exit;

  try
    if AStream = nil then
    begin
      Dir := ExtractFileDir(FLogFilePath);
      if (Dir <> '') and not DirectoryExists(Dir) then
        ForceDirectories(Dir);
      if FileExists(FLogFilePath) then
      begin
        AStream := TFileStream.Create(FLogFilePath, fmOpenReadWrite or fmShareDenyWrite);
        AStream.Seek(0, soEnd);
      end
      else
        AStream := TFileStream.Create(FLogFilePath, fmCreate or fmShareDenyWrite);
    end;

    Chunk := '';
    for I := 0 to ABatch.Count - 1 do
      Chunk := Chunk + RawByteString(ABatch[I]) + RawByteString(LineEnding);

    if Length(Chunk) > 0 then
      AStream.WriteBuffer(Chunk[1], Length(Chunk));
  except
    FreeAndNil(AStream);
  end;
  ABatch.Clear;
end;

procedure TZenithLogWriterThread.Execute;
var
  Batch, SwapTmp: TStringList;
  Stream: TFileStream;
begin
  Stream := nil;
  Batch := TStringList.Create;
  try
    while True do
    begin
      FQueueLock.Acquire;
      try
        if FQueue.Count > 0 then
        begin
          SwapTmp := Batch;
          Batch := FQueue;
          FQueue := SwapTmp;
          FWriting := True;
        end
        else
        begin
          FWriting := False;
          FFlushedEvent.SetEvent;
        end;
      finally
        FQueueLock.Release;
      end;

      if Batch.Count > 0 then
        DrainBatch(Batch, Stream)
      else if Terminated then
        Break
      else
        FQueueEvent.WaitFor(250);
    end;
  finally
    Batch.Free;
    FreeAndNil(Stream);
  end;
end;

{ TZenithLogger }

constructor TZenithLogger.Create(const ALogFilePath: string; AIncludeTimestamp: Boolean);
begin
  FLogFilePath := ALogFilePath;
  FIncludeTimestamp := AIncludeTimestamp;
  FLock := TCriticalSection.Create;
  // Níveis padrão: Debug só quando ZENITH_LOG_DEBUG=Y
  FLogLevels := [llInfo, llWarning, llError, llCritical];
  if GetEnvBool('ZENITH_LOG_DEBUG', False) then
    Include(FLogLevels, llDebug);

  if SameText(Trim(GetEnvVariable('ZENITH_LOG_FORMAT', 'text')), 'json') then
    FLogFormat := lfJson
  else
    FLogFormat := lfText;

  if FLogFilePath <> '' then
    FWriter := TZenithLogWriterThread.Create(FLogFilePath)
  else
    FWriter := nil;
end;

destructor TZenithLogger.Destroy;
begin
  FreeAndNil(FWriter);
  FLock.Free;
  inherited Destroy;
end;

procedure TZenithLogger.SetLogLevels(ALevels: TLogLevelSet);
begin
  FLock.Acquire;
  try
    FLogLevels := ALevels;
  finally
    FLock.Release;
  end;
end;

procedure TZenithLogger.SetLogFormat(AFormat: TLogFormat);
begin
  FLock.Acquire;
  try
    FLogFormat := AFormat;
  finally
    FLock.Release;
  end;
end;

procedure TZenithLogger.Flush;
begin
  if FWriter <> nil then
    FWriter.Flush;
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

function TZenithLogger.FormatLogLine(ALevel: TLogLevel; const AMessage: RawByteString): string;
var
  LevelStr, Ts: string;
begin
  LevelStr := LogLevelToString(ALevel);
  if FLogFormat = lfJson then
  begin
    if FIncludeTimestamp then
    begin
      Ts := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now);
      Result := '{"timestamp":"' + Ts + '","level":"' + LevelStr +
        '","message":"' + EscapeJsonString(AMessage) + '"}';
    end
    else
      Result := '{"level":"' + LevelStr + '","message":"' + EscapeJsonString(AMessage) + '"}';
  end
  else
  begin
    if FIncludeTimestamp then
      Result := '[' + GetTimestamp + '] [' + LevelStr + '] ' + string(AMessage)
    else
      Result := '[' + LevelStr + '] ' + string(AMessage);
  end;
end;

procedure TZenithLogger.Log(ALevel: TLogLevel; const AMessage: RawByteString);
var
  LogLine: string;
begin
  { Filtra o nível e formata fora do lock: só a escrita/enfileiramento é serializada. }
  if not (ALevel in FLogLevels) then
    Exit;

  LogLine := FormatLogLine(ALevel, AMessage);

  FLock.Acquire;
  try
    {$IFDEF WINDOWS}
    Writeln(Utf8ToAnsi(LogLine));
    {$ELSE}
    Writeln(LogLine);
    {$ENDIF}
  finally
    FLock.Release;
  end;

  if FWriter <> nil then
    FWriter.Enqueue(LogLine);
end;

procedure TZenithLogger.Debug(const AMessage: RawByteString);
begin
  Log(llDebug, AMessage);
end;

procedure TZenithLogger.Info(const AMessage: RawByteString);
begin
  Log(llInfo, AMessage);
end;

procedure TZenithLogger.Warning(const AMessage: RawByteString);
begin
  Log(llWarning, AMessage);
end;

procedure TZenithLogger.Error(const AMessage: RawByteString);
begin
  Log(llError, AMessage);
end;

procedure TZenithLogger.Critical(const AMessage: RawByteString);
begin
  Log(llCritical, AMessage);
end;

finalization
  if ZenithLogger <> nil then
    ZenithLogger.Free;

end.
