unit Zenith.WebSocket.Deflate;

{
  Zenith High-Performance WebSocket Suite
  RFC 7692: Compression Extensions for WebSocket (permessage-deflate)
  Zero external dependencies (uses native FPC zstream / paszlib).
}

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, zstream, zbase, zdeflate, zinflate;

const
  WS_DEFLATE_DEFAULT_MAX_OUTPUT = 16 * 1024 * 1024; // 16 MB anti-zip-bomb limit

type
  EZWebSocketDeflateError = class(Exception);
  EZWebSocketDeflateLimitExceeded = class(EZWebSocketDeflateError);

  { TZWebSocketDeflateConfig }
  TZWebSocketDeflateConfig = record
    Enabled: Boolean;
    ClientNoContextTakeover: Boolean;
    ServerNoContextTakeover: Boolean;
    ClientMaxWindowBits: Byte;
    ServerMaxWindowBits: Byte;
    CompressionLevel: TCompressionLevel;
    MaxDecompressedSize: Int64;
    class function Default: TZWebSocketDeflateConfig; static;
  end;

  { TZWebSocketDeflate }
  TZWebSocketDeflate = class
  private
    class function LevelToZLib(ALevel: TCompressionLevel): Integer; static;
  public
    class function IsPermessageDeflateRequested(const AExtensionsHeader: string): Boolean; static;
    class function Negotiate(const AClientHeader: string; out AResponseHeader: string): TZWebSocketDeflateConfig; static;
    class function BuildResponseExtensionHeader(const AClientHeader: string): string; static;

    { RFC 7692 Section 7.2.1: Raw DEFLATE with Z_SYNC_FLUSH and trailing 00 00 FF FF stripped }
    class function Compress(const AData: RawByteString; ALevel: TCompressionLevel = clDefault): RawByteString; overload; static;
    class function Compress(const ABytes: TBytes; ALevel: TCompressionLevel = clDefault): TBytes; overload; static;

    { RFC 7692 Section 7.2.2: Append 00 00 FF FF and raw INFLATE with anti-OOM output guard }
    class function Decompress(const AData: RawByteString; AMaxOutputSize: Int64 = WS_DEFLATE_DEFAULT_MAX_OUTPUT): RawByteString; overload; static;
    class function Decompress(const ABytes: TBytes; AMaxOutputSize: Int64 = WS_DEFLATE_DEFAULT_MAX_OUTPUT): TBytes; overload; static;
  end;

implementation

{ TZWebSocketDeflateConfig }

class function TZWebSocketDeflateConfig.Default: TZWebSocketDeflateConfig;
begin
  Result.Enabled := False;
  Result.ClientNoContextTakeover := True;
  Result.ServerNoContextTakeover := True;
  Result.ClientMaxWindowBits := 15;
  Result.ServerMaxWindowBits := 15;
  Result.CompressionLevel := clDefault;
  Result.MaxDecompressedSize := WS_DEFLATE_DEFAULT_MAX_OUTPUT;
end;

{ TZWebSocketDeflate }

class function TZWebSocketDeflate.LevelToZLib(ALevel: TCompressionLevel): Integer;
begin
  case ALevel of
    clNone:    Result := Z_NO_COMPRESSION;
    clFastest: Result := Z_BEST_SPEED;
    clMax:     Result := Z_BEST_COMPRESSION;
  else
    Result := Z_DEFAULT_COMPRESSION;
  end;
end;

class function TZWebSocketDeflate.IsPermessageDeflateRequested(const AExtensionsHeader: string): Boolean;
begin
  Result := Pos('permessage-deflate', LowerCase(Trim(AExtensionsHeader))) > 0;
end;

class function TZWebSocketDeflate.Negotiate(const AClientHeader: string; out AResponseHeader: string): TZWebSocketDeflateConfig;
begin
  Result := TZWebSocketDeflateConfig.Default;
  AResponseHeader := '';

  if not IsPermessageDeflateRequested(AClientHeader) then
    Exit;

  Result.Enabled := True;
  Result.ClientNoContextTakeover := True;
  Result.ServerNoContextTakeover := True;
  AResponseHeader := 'permessage-deflate; client_no_context_takeover; server_no_context_takeover';
end;

class function TZWebSocketDeflate.BuildResponseExtensionHeader(const AClientHeader: string): string;
begin
  Negotiate(AClientHeader, Result);
end;

class function TZWebSocketDeflate.Compress(const AData: RawByteString; ALevel: TCompressionLevel): RawByteString;
var
  Z: z_stream;
  Err: Integer;
  OutBuf: array[0..16383] of Byte;
  OutStream: TMemoryStream;
  Have, Len: SizeInt;
  P: PByte;
begin
  Result := '';
  if Length(AData) = 0 then
    Exit;

  FillChar(Z, SizeOf(Z), 0);
  // -MAX_WBITS (-15) produces raw RFC 1951 DEFLATE stream without zlib header/checksum
  Err := deflateInit2(Z, LevelToZLib(ALevel), Z_DEFLATED, -MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY);
  if Err <> Z_OK then
    raise EZWebSocketDeflateError.CreateFmt('deflateInit2 failed with code %d', [Err]);

  OutStream := TMemoryStream.Create;
  try
    try
      Z.next_in := PByte(@AData[1]);
      Z.avail_in := Length(AData);

      repeat
        Z.next_out := @OutBuf[0];
        Z.avail_out := SizeOf(OutBuf);
        Err := deflate(Z, Z_SYNC_FLUSH);
        if (Err <> Z_OK) and (Err <> Z_STREAM_END) and (Err <> Z_BUF_ERROR) then
          raise EZWebSocketDeflateError.CreateFmt('deflate(Z_SYNC_FLUSH) failed with code %d', [Err]);

        Have := SizeOf(OutBuf) - Z.avail_out;
        if Have > 0 then
          OutStream.WriteBuffer(OutBuf[0], Have);
      until (Z.avail_in = 0) and (Z.avail_out > 0);
    finally
      deflateEnd(Z);
    end;

    Len := OutStream.Size;
    // RFC 7692 Section 7.2.1: Remove trailing 0x00 0x00 0xFF 0xFF
    if Len >= 4 then
    begin
      P := PByte(OutStream.Memory);
      if (P[Len - 4] = $00) and (P[Len - 3] = $00) and
         (P[Len - 2] = $FF) and (P[Len - 1] = $FF) then
        Dec(Len, 4);
    end;

    SetLength(Result, Len);
    if Len > 0 then
      Move(OutStream.Memory^, Result[1], Len);
  finally
    OutStream.Free;
  end;
end;

class function TZWebSocketDeflate.Compress(const ABytes: TBytes; ALevel: TCompressionLevel): TBytes;
var
  Raw, CompRaw: RawByteString;
begin
  if Length(ABytes) = 0 then
    Exit(nil);

  SetLength(Raw, Length(ABytes));
  Move(ABytes[0], Raw[1], Length(ABytes));

  CompRaw := Compress(Raw, ALevel);
  SetLength(Result, Length(CompRaw));
  if Length(CompRaw) > 0 then
    Move(CompRaw[1], Result[0], Length(CompRaw));
end;

class function TZWebSocketDeflate.Decompress(const AData: RawByteString; AMaxOutputSize: Int64): RawByteString;
var
  Z: z_stream;
  Err: Integer;
  InBuf: RawByteString;
  OutBuf: array[0..16383] of Byte;
  OutStream: TMemoryStream;
  Have: SizeInt;
  TotalOut: Int64;
begin
  Result := '';
  if Length(AData) = 0 then
    Exit;

  // RFC 7692 Section 7.2.2: Append 0x00 0x00 0xFF 0xFF trailer before raw INFLATE
  SetLength(InBuf, Length(AData) + 4);
  Move(AData[1], InBuf[1], Length(AData));
  InBuf[Length(AData) + 1] := AnsiChar($00);
  InBuf[Length(AData) + 2] := AnsiChar($00);
  InBuf[Length(AData) + 3] := AnsiChar($FF);
  InBuf[Length(AData) + 4] := AnsiChar($FF);

  FillChar(Z, SizeOf(Z), 0);
  // -MAX_WBITS (-15) decodes raw RFC 1951 DEFLATE stream
  Err := inflateInit2(Z, -MAX_WBITS);
  if Err <> Z_OK then
    raise EZWebSocketDeflateError.CreateFmt('inflateInit2 failed with code %d', [Err]);

  OutStream := TMemoryStream.Create;
  try
    try
      Z.next_in := PByte(@InBuf[1]);
      Z.avail_in := Length(InBuf);
      TotalOut := 0;

      repeat
        Z.next_out := @OutBuf[0];
        Z.avail_out := SizeOf(OutBuf);
        Err := inflate(Z, Z_SYNC_FLUSH);
        if (Err <> Z_OK) and (Err <> Z_STREAM_END) and (Err <> Z_BUF_ERROR) then
          raise EZWebSocketDeflateError.CreateFmt('Failed to decompress WebSocket message (RFC 7692): inflate error %d', [Err]);

        Have := SizeOf(OutBuf) - Z.avail_out;
        if Have > 0 then
        begin
          Inc(TotalOut, Have);
          if (AMaxOutputSize > 0) and (TotalOut > AMaxOutputSize) then
            raise EZWebSocketDeflateLimitExceeded.CreateFmt(
              'Decompressed WebSocket message exceeds maximum limit (%d bytes)', [AMaxOutputSize]
            );
          OutStream.WriteBuffer(OutBuf[0], Have);
        end;

        if Err = Z_STREAM_END then
          Break;
      until (Z.avail_in = 0) and (Z.avail_out > 0);
    finally
      inflateEnd(Z);
    end;

    SetLength(Result, OutStream.Size);
    if OutStream.Size > 0 then
      Move(OutStream.Memory^, Result[1], OutStream.Size);
  finally
    OutStream.Free;
  end;
end;

class function TZWebSocketDeflate.Decompress(const ABytes: TBytes; AMaxOutputSize: Int64): TBytes;
var
  Raw, DecompRaw: RawByteString;
begin
  if Length(ABytes) = 0 then
    Exit(nil);

  SetLength(Raw, Length(ABytes));
  Move(ABytes[0], Raw[1], Length(ABytes));

  DecompRaw := Decompress(Raw, AMaxOutputSize);
  SetLength(Result, Length(DecompRaw));
  if Length(DecompRaw) > 0 then
    Move(DecompRaw[1], Result[0], Length(DecompRaw));
end;

end.
