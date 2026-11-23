{
    Zenith Framework - GZIP Compression and Decompression Engine (RFC 1952)
    100% Native Free Pascal paszlib implementation via zstream (TCompressionStream / TDecompressionStream).
    Zero external C library bindings. Sub-millisecond performance.
}

{$mode objfpc}{$H+}

unit Zenith.Gzip;

interface

uses
  Classes, SysUtils, zstream;

{ Compresses binary data or UTF-8 string into GZIP format (RFC 1952) }
function GZipCompress(const AData: RawByteString; ALevel: TCompressionLevel = clDefault): RawByteString;

{ Decompresses GZIP payload (RFC 1952) validating header and CRC32 integrity }
function GZipDecompress(const ACompressed: RawByteString): RawByteString;

{ Utilities for stream compression and decompression }
procedure GZipCompressStream(AInput, AOutput: TStream; ALevel: TCompressionLevel = clDefault);
procedure GZipDecompressStream(AInput, AOutput: TStream);

implementation

var
  CRC32Table: array[0..255] of LongWord;
  CRC32TableInit: Boolean = False;

procedure InitCRC32Table;
var
  I, J: Integer;
  C: LongWord;
begin
  if CRC32TableInit then
    Exit;
  for I := 0 to 255 do
  begin
    C := LongWord(I);
    for J := 0 to 7 do
    begin
      if (C and 1) <> 0 then
        C := $EDB88320 xor (C shr 1)
      else
        C := C shr 1;
    end;
    CRC32Table[I] := C;
  end;
  CRC32TableInit := True;
end;

function UpdateCRC32(ACRC: LongWord; const ABuffer; ACount: Integer): LongWord;
var
  P: PByte;
  I: Integer;
begin
  Result := ACRC;
  P := @ABuffer;
  for I := 0 to ACount - 1 do
  begin
    Result := CRC32Table[(Result xor P^) and $FF] xor (Result shr 8);
    Inc(P);
  end;
end;

procedure GZipCompressStream(AInput, AOutput: TStream; ALevel: TCompressionLevel = clDefault);
const
  GZipHeader: array[0..9] of Byte = ($1F, $8B, $08, $00, $00, $00, $00, $00, $00, $FF);
var
  ZipStream: TCompressionStream;
  Buffer: array[0..8191] of Byte;
  BytesRead: Integer;
  CRC, TotalSize: LongWord;
  Trailer: array[0..1] of LongWord;
begin
  if (AInput = nil) or (AOutput = nil) then Exit;
  InitCRC32Table;

  AOutput.WriteBuffer(GZipHeader, SizeOf(GZipHeader));

  CRC := $FFFFFFFF;
  TotalSize := 0;

  ZipStream := TCompressionStream.Create(ALevel, AOutput, True);
  try
    repeat
      BytesRead := AInput.Read(Buffer, SizeOf(Buffer));
      if BytesRead > 0 then
      begin
        CRC := UpdateCRC32(CRC, Buffer, BytesRead);
        Inc(TotalSize, LongWord(BytesRead));
        ZipStream.WriteBuffer(Buffer, BytesRead);
      end;
    until BytesRead = 0;
  finally
    ZipStream.Free;
  end;

  Trailer[0] := NtoLE(CRC xor $FFFFFFFF);
  Trailer[1] := NtoLE(TotalSize);
  AOutput.WriteBuffer(Trailer, SizeOf(Trailer));
end;

procedure GZipDecompressStream(AInput, AOutput: TStream);
const
  FHCRC    = $02;
  FEXTRA   = $04;
  FNAME    = $08;
  FCOMMENT = $10;
var
  Header: array[0..9] of Byte;
  Flags, B: Byte;
  ExtraLen: Word;
  PayloadLen: Int64;
  PayloadStream: TMemoryStream;
  UnzipStream: TDecompressionStream;
  Buffer: array[0..8191] of Byte;
  BytesRead: Integer;
  CRC, ExpectedCRC, TotalSize, ExpectedSize: LongWord;
  Trailer: array[0..1] of LongWord;
begin
  if (AInput = nil) or (AOutput = nil) then Exit;
  InitCRC32Table;

  if (AInput.Size - AInput.Position) < 18 then
    raise EStreamError.Create('Invalid GZIP stream: truncated payload');

  AInput.ReadBuffer(Header, SizeOf(Header));
  if (Header[0] <> $1F) or (Header[1] <> $8B) or (Header[2] <> $08) then
    raise EStreamError.Create('Invalid GZIP header');

  Flags := Header[3];

  if (Flags and FEXTRA) <> 0 then
  begin
    AInput.ReadBuffer(ExtraLen, SizeOf(ExtraLen));
    ExtraLen := LEtoN(ExtraLen);
    AInput.Seek(ExtraLen, soCurrent);
  end;

  if (Flags and FNAME) <> 0 then
  begin
    repeat
      AInput.ReadBuffer(B, 1);
    until B = 0;
  end;

  if (Flags and FCOMMENT) <> 0 then
  begin
    repeat
      AInput.ReadBuffer(B, 1);
    until B = 0;
  end;

  if (Flags and FHCRC) <> 0 then
    AInput.Seek(2, soCurrent);

  PayloadLen := (AInput.Size - AInput.Position) - SizeOf(Trailer);
  if PayloadLen < 0 then
    raise EStreamError.Create('Invalid GZIP stream: missing trailer');

  PayloadStream := TMemoryStream.Create;
  try
    if PayloadLen > 0 then
      PayloadStream.CopyFrom(AInput, PayloadLen);
    PayloadStream.Position := 0;

    AInput.ReadBuffer(Trailer, SizeOf(Trailer));
    ExpectedCRC := LEtoN(Trailer[0]);
    ExpectedSize := LEtoN(Trailer[1]);

    CRC := $FFFFFFFF;
    TotalSize := 0;

    UnzipStream := TDecompressionStream.Create(PayloadStream, True);
    try
      repeat
        BytesRead := UnzipStream.Read(Buffer, SizeOf(Buffer));
        if BytesRead > 0 then
        begin
          CRC := UpdateCRC32(CRC, Buffer, BytesRead);
          Inc(TotalSize, LongWord(BytesRead));
          AOutput.WriteBuffer(Buffer, BytesRead);
        end;
      until BytesRead = 0;
    finally
      UnzipStream.Free;
    end;

    if (CRC xor $FFFFFFFF) <> ExpectedCRC then
      raise EStreamError.Create('Invalid GZIP stream: CRC32 mismatch');
    if TotalSize <> ExpectedSize then
      raise EStreamError.Create('Invalid GZIP stream: size mismatch');
  finally
    PayloadStream.Free;
  end;
end;

function GZipCompress(const AData: RawByteString; ALevel: TCompressionLevel = clDefault): RawByteString;
var
  InStream, OutStream: TMemoryStream;
begin
  if Length(AData) = 0 then
    Exit('');

  InStream := TMemoryStream.Create;
  OutStream := TMemoryStream.Create;
  try
    InStream.WriteBuffer(AData[1], Length(AData));
    InStream.Position := 0;
    GZipCompressStream(InStream, OutStream, ALevel);
    SetLength(Result, OutStream.Size);
    if OutStream.Size > 0 then
    begin
      OutStream.Position := 0;
      OutStream.ReadBuffer(Result[1], OutStream.Size);
    end;
  finally
    InStream.Free;
    OutStream.Free;
  end;
end;

function GZipDecompress(const ACompressed: RawByteString): RawByteString;
var
  InStream, OutStream: TMemoryStream;
begin
  if Length(ACompressed) = 0 then
    Exit('');

  InStream := TMemoryStream.Create;
  OutStream := TMemoryStream.Create;
  try
    InStream.WriteBuffer(ACompressed[1], Length(ACompressed));
    InStream.Position := 0;
    GZipDecompressStream(InStream, OutStream);
    SetLength(Result, OutStream.Size);
    if OutStream.Size > 0 then
    begin
      OutStream.Position := 0;
      OutStream.ReadBuffer(Result[1], OutStream.Size);
    end;
  finally
    InStream.Free;
    OutStream.Free;
  end;
end;

end.
