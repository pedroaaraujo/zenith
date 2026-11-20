{
    Zenith Framework - GZIP Compression and Decompression Engine (RFC 1952)
    100% Native Free Pascal paszlib implementation via zstream (TGZipCompressionStream / TGZipDecompressionStream).
    Zero external C library bindings. Sub-millisecond performance.
}

{$mode objfpc}{$H+}

unit Zenith.Gzip;

interface

uses
  Classes, SysUtils, zstream;

{ Compacta dados binários ou string UTF-8 no formato GZIP (RFC 1952) }
function GZipCompress(const AData: RawByteString; ALevel: TCompressionLevel = clDefault): RawByteString;

{ Descompacta payload GZIP (RFC 1952) validando cabeçalho e integridade CRC32 }
function GZipDecompress(const ACompressed: RawByteString): RawByteString;

{ Utilitários para compactação e descompactação de streams }
procedure GZipCompressStream(AInput, AOutput: TStream; ALevel: TCompressionLevel = clDefault);
procedure GZipDecompressStream(AInput, AOutput: TStream);

implementation

procedure GZipCompressStream(AInput, AOutput: TStream; ALevel: TCompressionLevel = clDefault);
var
  ZipStream: TGZipCompressionStream;
  Buffer: array[0..8191] of Byte;
  BytesRead: Integer;
begin
  if (AInput = nil) or (AOutput = nil) then Exit;
  ZipStream := TGZipCompressionStream.Create(ALevel, AOutput);
  try
    repeat
      BytesRead := AInput.Read(Buffer, SizeOf(Buffer));
      if BytesRead > 0 then
        ZipStream.WriteBuffer(Buffer, BytesRead);
    until BytesRead = 0;
  finally
    // A destruição de TGZipCompressionStream escreve o rodapé RFC 1952 com CRC32 e tamanho
    ZipStream.Free;
  end;
end;

procedure GZipDecompressStream(AInput, AOutput: TStream);
var
  UnzipStream: TGZipDecompressionStream;
  Buffer: array[0..8191] of Byte;
  BytesRead: Integer;
begin
  if (AInput = nil) or (AOutput = nil) then Exit;
  UnzipStream := TGZipDecompressionStream.Create(AInput);
  try
    repeat
      BytesRead := UnzipStream.Read(Buffer, SizeOf(Buffer));
      if BytesRead > 0 then
        AOutput.WriteBuffer(Buffer, BytesRead);
    until BytesRead = 0;
  finally
    UnzipStream.Free;
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
