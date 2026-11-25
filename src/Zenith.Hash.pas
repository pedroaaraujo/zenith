unit Zenith.Hash;

{$mode ObjFPC}{$H+}

interface

function SHA256Hash(x: string): string;
function SHA256Hex(const AData: RawByteString): string;
function HMACSHA256(const AKey, AData: string): string;

implementation

uses
  fpsha256;

function SHA256Hash(x: string): string;
var
  Ctx: TSHA256;
begin
  Ctx.Init;
  if Length(x) > 0 then
    Ctx.Update(@x[1], Length(x));
  Ctx.Final;
  SetLength(Result, SizeOf(TSHA256Digest));
  Move(Ctx.Digest[0], Result[1], SizeOf(TSHA256Digest));
end;

function SHA256Hex(const AData: RawByteString): string;
const
  HEX_LOWER: array[0..15] of Char = '0123456789abcdef';
var
  Raw: string;
  I: Integer;
  B: Byte;
begin
  Raw := SHA256Hash(string(AData));
  SetLength(Result, Length(Raw) * 2);
  for I := 1 to Length(Raw) do
  begin
    B := Ord(Raw[I]);
    Result[(I - 1) * 2 + 1] := HEX_LOWER[B shr 4];
    Result[(I - 1) * 2 + 2] := HEX_LOWER[B and $0F];
  end;
end;

function HMACSHA256(const AKey, AData: string): string;
var
  Digest: TSHA256Digest;
  DataPtr: PByte;
  Dummy: Byte;
begin
  Result := '';
  if AKey = '' then
    Exit;

  Dummy := 0;
  if Length(AData) > 0 then
    DataPtr := @AData[1]
  else
    DataPtr := @Dummy;

  Digest := Default(TSHA256Digest);
  if TSHA256.HMAC(@AKey[1], Length(AKey), DataPtr, Length(AData), Digest) then
  begin
    SetLength(Result, SizeOf(TSHA256Digest));
    Move(Digest[0], Result[1], SizeOf(TSHA256Digest));
  end;
end;

end.
