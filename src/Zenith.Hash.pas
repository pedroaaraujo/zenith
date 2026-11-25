unit Zenith.Hash;

{$mode ObjFPC}{$H+}

interface

function SHA256Hash(x: string): string;
function SHA256Hex(const AData: RawByteString): string;
function HMACSHA256(const AKey, AData: string): string;

implementation

{$IF (FPC_FULLVERSION >= 30203) AND NOT DEFINED(ZENITH_PURE_SHA256)}
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
{$ELSE}
{ Fallback puro em Pascal para FPC < 3.2.3 (ex.: FPC 3.2.2 do Ubuntu/Debian,
  onde a unit fpsha256 do fcl-hash ainda não existe). }
function SwapEndian32(Value: Cardinal): Cardinal; inline;
begin
  Result := ((Value and $000000FF) shl 24) or
            ((Value and $0000FF00) shl 8) or
            ((Value and $00FF0000) shr 8) or
            ((Value and $FF000000) shr 24);
end;

function SHA256Hash(x: string): string;
const
  K: array[0..63] of Cardinal = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5,
    $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3,
    $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc,
    $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7,
    $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13,
    $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3,
    $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5,
    $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208,
    $90befffa, $a4506ceb, $bef9a3f7, $c67178f2
  );
var
  A, B: Cardinal;
  BitLen: QWord;
  OrigLen, PaddedBytes, WordCount, I, J: SizeInt;
  Buf: RawByteString;
  D: array of Cardinal;
  W: array[0..63] of Cardinal;
  G, H: array[0..7] of Cardinal;
begin
  {$PUSH}
  {$R-}{$Q-}
  OrigLen := Length(x);
  PaddedBytes := OrigLen + 9;
  if (PaddedBytes mod 64) <> 0 then
    PaddedBytes := ((PaddedBytes div 64) + 1) * 64;
  WordCount := PaddedBytes div 4;
  D := nil;
  SetLength(D, WordCount);
  Buf := '';
  SetLength(Buf, PaddedBytes);
  FillChar(Buf[1], PaddedBytes, 0);
  if OrigLen > 0 then
    Move(x[1], Buf[1], OrigLen);
  Buf[OrigLen + 1] := #$80;
  Move(Buf[1], D[0], PaddedBytes);

  BitLen := QWord(OrigLen) * 8;
  D[WordCount - 2] := SwapEndian32(Cardinal(BitLen shr 32));
  D[WordCount - 1] := SwapEndian32(Cardinal(BitLen and $FFFFFFFF));

  H[0] := $6a09e667;
  H[1] := $bb67ae85;
  H[2] := $3c6ef372;
  H[3] := $a54ff53a;
  H[4] := $510e527f;
  H[5] := $9b05688c;
  H[6] := $1f83d9ab;
  H[7] := $5be0cd19;

  I := 0;
  while I < WordCount do
  begin
    for J := 0 to 15 do
    begin
      W[J] := SwapEndian32(D[I]);
      Inc(I);
    end;
    for J := 16 to 63 do
    begin
      A := W[J - 15];
      B := W[J - 2];
      W[J] := W[J - 16] +
              (((A shr 7) or (A shl 25)) xor ((A shr 18) or (A shl 14)) xor (A shr 3)) +
              W[J - 7] +
              (((B shr 17) or (B shl 15)) xor ((B shr 19) or (B shl 13)) xor (B shr 10));
    end;

    G := H;
    for J := 0 to 63 do
    begin
      A := G[4];
      B := G[0];
      A := G[7] +
           (((A shr 6) or (A shl 26)) xor ((A shr 11) or (A shl 21)) xor ((A shr 25) or (A shl 7))) +
           ((G[4] and G[5]) or ((not G[4]) and G[6])) +
           K[J] + W[J];
      Inc(G[3], A);
      A := A +
           (((B shr 2) or (B shl 30)) xor ((B shr 13) or (B shl 19)) xor ((B shr 22) or (B shl 10))) +
           ((G[0] and G[1]) or (G[1] and G[2]) or (G[2] and G[0]));
      G[7] := G[6];
      G[6] := G[5];
      G[5] := G[4];
      G[4] := G[3];
      G[3] := G[2];
      G[2] := G[1];
      G[1] := G[0];
      G[0] := A;
    end;

    for J := 0 to 7 do
      Inc(H[J], G[J]);
  end;

  SetLength(Result, 32);
  for J := 0 to 31 do
    Result[J + 1] := AnsiChar((H[J shr 2] shr ((3 - (J and 3)) * 8)) and $FF);
  {$POP}
end;

function HMACSHA256(const AKey, AData: string): string;
const
  BLOCK_SIZE = 64;
var
  KeyBlock, IPad, OPad: string;
  I: Integer;
begin
  Result := '';
  if AKey = '' then
    Exit;

  if Length(AKey) > BLOCK_SIZE then
    KeyBlock := SHA256Hash(AKey)
  else
    KeyBlock := AKey;

  if Length(KeyBlock) < BLOCK_SIZE then
  begin
    I := Length(KeyBlock);
    SetLength(KeyBlock, BLOCK_SIZE);
    FillChar(KeyBlock[I + 1], BLOCK_SIZE - I, 0);
  end;

  SetLength(IPad, BLOCK_SIZE);
  SetLength(OPad, BLOCK_SIZE);
  for I := 1 to BLOCK_SIZE do
  begin
    Byte(IPad[I]) := Byte(KeyBlock[I]) xor $36;
    Byte(OPad[I]) := Byte(KeyBlock[I]) xor $5C;
  end;

  Result := SHA256Hash(OPad + SHA256Hash(IPad + AData));
end;
{$ENDIF}

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

end.
