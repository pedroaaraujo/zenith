{
    Zenith Framework - Native Idempotency Middleware & LRU Store Engine
    Implements IETF Draft "The Idempotency-Key HTTP Header Field"
    (draft-ietf-httpapi-idempotency-key-header) with RFC 9457 Problem Details.

    Features:
    - O(1) Thread-Safe in-memory LRU store (TZenithMemoryIdempotencyStore)
      backed by a native chained hash table + doubly-linked LRU ring-list
    - Monotonic TTL expiration (GetTickCount64, default: 86,400s / 24h)
    - Strict key format and length validation (default max: 128 chars, HTTP 400)
    - Anti-replay and concurrency lock: HTTP 409 Conflict for in-flight requests
    - Strict payload fingerprint: SHA-256 over method, target and body;
      HTTP 422 Unprocessable Entity (RFC 9457) on payload/target mismatch
    - Full response replay: cached status code, headers, content-type and body
      with 'Idempotent-Replayed: true' header
    - Automatic key release on HTTP 5xx responses or unhandled exceptions
    - 100% domain-agnostic open-source implementation
}

{$mode objfpc}{$H+}

unit Zenith.Idempotency;

interface

uses
  Classes, SysUtils, SyncObjs, httpdefs, fpsha256;

const
  ZENITH_IDEMPOTENCY_DEFAULT_CAPACITY = 10000;
  ZENITH_IDEMPOTENCY_DEFAULT_TTL_SEC  = 86400;
  ZENITH_IDEMPOTENCY_MAX_KEY_LENGTH   = 128;

type
  { Idempotency key lifecycle state per IETF Draft }
  TIdempotencyStatus = (
    isPending,    { Operation currently in-flight }
    isCompleted   { Operation completed with cached response }
  );

  { HTTP response header name/value pair stored for replay }
  TIdempotencyHeader = record
    Name: string;
    Value: string;
  end;
  TIdempotencyHeaderArray = array of TIdempotencyHeader;

  { Cached idempotency entry }
  TIdempotencyRecord = record
    Key: string;
    RequestHash: string;
    Status: TIdempotencyStatus;
    CreatedAt: TDateTime;
    LastAccessedAt: TDateTime;
    ResponseCode: Integer;
    ResponseContentType: string;
    ResponseBody: RawByteString;
    ResponseHeaders: TIdempotencyHeaderArray;
  end;
  PIdempotencyRecord = ^TIdempotencyRecord;

  { Operational store telemetry counters }
  TIdempotencyStoreStats = record
    ActiveCount: Integer;
    Capacity: Integer;
    TTLSeconds: Integer;
    Hits: Int64;
    Misses: Int64;
    Conflicts: Int64;
    PayloadMismatches: Int64;
    Evictions: Int64;
    Expirations: Int64;
  end;

  { Storage contract for idempotency backends }
  IZenithIdempotencyStore = interface
    ['{A6B9C184-7F89-4D2A-9289-EC8E0A9D8210}']
    function TryAcquire(const AKey, ARequestHash: string;
      out AExisting: TIdempotencyRecord;
      out AIsConflict: Boolean;
      out AIsPayloadMismatch: Boolean): Boolean;
    procedure Complete(const AKey: string; ACode: Integer;
      const AContentType: string; const ABody: RawByteString); overload;
    procedure Complete(const AKey: string; ACode: Integer;
      const AContentType: string; const ABody: RawByteString;
      const AHeaders: TIdempotencyHeaderArray); overload;
    procedure Release(const AKey: string);
    function Get(const AKey: string; out ARecord: TIdempotencyRecord): Boolean;
    function PurgeExpired: Integer;
    procedure Clear;
    function Count: Integer;
    function GetStats: TIdempotencyStoreStats;
    function GetCapacity: Integer;
    procedure SetCapacity(AValue: Integer);
    function GetTTLSeconds: Integer;
    procedure SetTTLSeconds(AValue: Integer);
    property Capacity: Integer read GetCapacity write SetCapacity;
    property TTLSeconds: Integer read GetTTLSeconds write SetTTLSeconds;
  end;

  { Internal doubly-linked LRU node with O(1) hash bucket chaining }
  TIdempotencyNode = class
  public
    Data: TIdempotencyRecord;
    KeyHash: Cardinal;
    CreatedTick: QWord;
    Prev: TIdempotencyNode;
    Next: TIdempotencyNode;
    BucketNext: TIdempotencyNode;
    constructor Create(const AKey, ARequestHash: string; AKeyHash: Cardinal;
      AStatus: TIdempotencyStatus; ANowTick: QWord; ANowTime: TDateTime);
  end;

  { High-performance thread-safe O(1) in-memory LRU + TTL store }
  TZenithMemoryIdempotencyStore = class(TInterfacedObject, IZenithIdempotencyStore)
  private
    FLock: TCriticalSection;
    FBuckets: array of TIdempotencyNode;
    FMask: Cardinal;
    FCount: Integer;
    FHead: TIdempotencyNode; { Most recently used node (MRU) }
    FTail: TIdempotencyNode; { Least recently used node (LRU) }
    FCapacity: Integer;
    FTTLSeconds: Integer;
    FHits: Int64;
    FMisses: Int64;
    FConflicts: Int64;
    FPayloadMismatches: Int64;
    FEvictions: Int64;
    FExpirations: Int64;

    class function HashKey(const AKey: string): Cardinal; static; inline;
    class function NextPow2(AValue: Integer): Integer; static;
    procedure InitBuckets(ABucketCount: Integer);
    procedure Rehash(ANewBucketCount: Integer);
    function FindNode(const AKey: string; AKeyHash: Cardinal): TIdempotencyNode; inline;
    procedure InsertIntoBucket(ANode: TIdempotencyNode); inline;
    procedure RemoveFromBucket(ANode: TIdempotencyNode); inline;
    function IsExpired(ANode: TIdempotencyNode; ANowTick: QWord): Boolean; inline;
    procedure AttachHead(ANode: TIdempotencyNode); inline;
    procedure DetachNode(ANode: TIdempotencyNode); inline;
    procedure MoveToHead(ANode: TIdempotencyNode); inline;
    procedure RemoveAndFreeNode(ANode: TIdempotencyNode); inline;
    procedure EvictTail;
    function PurgeExpiredInternal(ANowTick: QWord): Integer;

    function GetCapacity: Integer;
    procedure SetCapacity(AValue: Integer);
    function GetTTLSeconds: Integer;
    procedure SetTTLSeconds(AValue: Integer);
  public
    constructor Create(ACapacity: Integer = ZENITH_IDEMPOTENCY_DEFAULT_CAPACITY;
      ATTLSeconds: Integer = ZENITH_IDEMPOTENCY_DEFAULT_TTL_SEC);
    destructor Destroy; override;

    function TryAcquire(const AKey, ARequestHash: string;
      out AExisting: TIdempotencyRecord;
      out AIsConflict: Boolean;
      out AIsPayloadMismatch: Boolean): Boolean;
    procedure Complete(const AKey: string; ACode: Integer;
      const AContentType: string; const ABody: RawByteString); overload;
    procedure Complete(const AKey: string; ACode: Integer;
      const AContentType: string; const ABody: RawByteString;
      const AHeaders: TIdempotencyHeaderArray); overload;
    procedure Release(const AKey: string);
    function Get(const AKey: string; out ARecord: TIdempotencyRecord): Boolean;
    function PurgeExpired: Integer;
    procedure Clear;
    function Count: Integer;
    function GetStats: TIdempotencyStoreStats;

    property Capacity: Integer read GetCapacity write SetCapacity;
    property TTLSeconds: Integer read GetTTLSeconds write SetTTLSeconds;
  end;

  { HTTP idempotency middleware controller }
  TZenithIdempotency = class
  private
    class var FDefaultStore: IZenithIdempotencyStore;
    class var FStoreLock: TCriticalSection;
    class var FEnabled: Boolean;
    class var FMaxKeyLength: Integer;
    class function GetDefaultStore: IZenithIdempotencyStore; static;
    class procedure SetDefaultStore(const AValue: IZenithIdempotencyStore); static;
    class function EscapeJsonString(const AStr: string): string; static;
    class function BuildProblemJson(AStatus: Integer; const ATitle, ADetail, AInstance: string): string; static;
    class function ExtractResponseHeaders(AResponse: TResponse): TIdempotencyHeaderArray; static;
    class procedure ApplyResponseHeaders(AResponse: TResponse; const AHeaders: TIdempotencyHeaderArray); static;
    class function IsReplayableHeader(const AHeaderName: string): Boolean; static;
  public
    class constructor CreateClass;
    class destructor DestroyClass;

    class function HasIdempotencyHeader(ARequest: TRequest; out ARawKey: string): Boolean;
    class function GetIdempotencyKey(ARequest: TRequest): string;
    class function ValidateAndNormalizeKey(const ARawKey: string;
      out ANormalizedKey, AErrorDetail: string): Boolean;

    class function ExtractRequestScope(ARequest: TRequest; const AScope: string = ''): string;
    class function BuildScopedStoreKey(const ANormalizedKey, AScopeContext: string): string;

    class function ComputeRequestHash(ARequest: TRequest): string; overload;
    class function ComputeRequestHash(ARequest: TRequest; const AScope: string): string; overload;
    class function ComputeRequestHash(const AMethod, APath: string;
      const AContent: RawByteString; const AScope: string = ''): string; overload;

    class function ProcessBefore(ARequest: TRequest; AResponse: TResponse;
      AStore: IZenithIdempotencyStore = nil): Boolean; overload;
    class function ProcessBefore(ARequest: TRequest; AResponse: TResponse;
      const AScope: string; AStore: IZenithIdempotencyStore = nil): Boolean; overload;
    class procedure ProcessAfter(ARequest: TRequest; AResponse: TResponse;
      AStore: IZenithIdempotencyStore = nil); overload;
    class procedure ProcessAfter(ARequest: TRequest; AResponse: TResponse;
      const AScope: string; AStore: IZenithIdempotencyStore = nil); overload;
    class procedure ReleaseOnError(ARequest: TRequest;
      AStore: IZenithIdempotencyStore = nil); overload;
    class procedure ReleaseOnError(ARequest: TRequest;
      const AScope: string; AStore: IZenithIdempotencyStore = nil); overload;

    class property DefaultStore: IZenithIdempotencyStore read GetDefaultStore write SetDefaultStore;
    class property Enabled: Boolean read FEnabled write FEnabled;
    class property MaxKeyLength: Integer read FMaxKeyLength write FMaxKeyLength;
  end;

{ Utility function returning lowercase hexadecimal SHA-256 digest }
function ZenithSHA256(const AData: RawByteString): string;

implementation

function ZenithSHA256(const AData: RawByteString): string;
var
  Bytes: TBytes;
  HexOut: AnsiString;
begin
  if Length(AData) = 0 then
    SetLength(Bytes, 0)
  else
  begin
    SetLength(Bytes, Length(AData));
    Move(AData[1], Bytes[0], Length(AData));
  end;
  TSHA256.DigestHexa(Bytes, HexOut);
  Result := LowerCase(string(HexOut));
end;

{ TIdempotencyNode }

constructor TIdempotencyNode.Create(const AKey, ARequestHash: string;
  AKeyHash: Cardinal; AStatus: TIdempotencyStatus; ANowTick: QWord;
  ANowTime: TDateTime);
begin
  inherited Create;
  Data.Key := AKey;
  Data.RequestHash := ARequestHash;
  Data.Status := AStatus;
  Data.CreatedAt := ANowTime;
  Data.LastAccessedAt := ANowTime;
  Data.ResponseCode := 0;
  Data.ResponseContentType := '';
  Data.ResponseBody := '';
  SetLength(Data.ResponseHeaders, 0);
  KeyHash := AKeyHash;
  CreatedTick := ANowTick;
  Prev := nil;
  Next := nil;
  BucketNext := nil;
end;

{ TZenithMemoryIdempotencyStore }

class function TZenithMemoryIdempotencyStore.HashKey(const AKey: string): Cardinal;
var
  I: Integer;
begin
  { FNV-1a 32-bit hash }
  Result := 2166136261;
  for I := 1 to Length(AKey) do
  begin
    Result := Result xor Ord(AKey[I]);
    Result := Cardinal(QWord(Result) * 16777619);
  end;
end;

class function TZenithMemoryIdempotencyStore.NextPow2(AValue: Integer): Integer;
begin
  Result := 64;
  while (Result < AValue) and (Result < 1048576) do
    Result := Result shl 1;
end;

procedure TZenithMemoryIdempotencyStore.InitBuckets(ABucketCount: Integer);
var
  Pow2: Integer;
begin
  Pow2 := NextPow2(ABucketCount);
  SetLength(FBuckets, Pow2);
  FillChar(FBuckets[0], Pow2 * SizeOf(TIdempotencyNode), 0);
  FMask := Cardinal(Pow2 - 1);
end;

procedure TZenithMemoryIdempotencyStore.Rehash(ANewBucketCount: Integer);
var
  Curr: TIdempotencyNode;
begin
  InitBuckets(ANewBucketCount);
  Curr := FHead;
  while Curr <> nil do
  begin
    Curr.BucketNext := nil;
    InsertIntoBucket(Curr);
    Curr := Curr.Next;
  end;
end;

function TZenithMemoryIdempotencyStore.FindNode(const AKey: string;
  AKeyHash: Cardinal): TIdempotencyNode;
var
  Curr: TIdempotencyNode;
begin
  Curr := FBuckets[AKeyHash and FMask];
  while Curr <> nil do
  begin
    if (Curr.KeyHash = AKeyHash) and (Curr.Data.Key = AKey) then
    begin
      Result := Curr;
      Exit;
    end;
    Curr := Curr.BucketNext;
  end;
  Result := nil;
end;

procedure TZenithMemoryIdempotencyStore.InsertIntoBucket(ANode: TIdempotencyNode);
var
  BucketIdx: Cardinal;
begin
  BucketIdx := ANode.KeyHash and FMask;
  ANode.BucketNext := FBuckets[BucketIdx];
  FBuckets[BucketIdx] := ANode;
end;

procedure TZenithMemoryIdempotencyStore.RemoveFromBucket(ANode: TIdempotencyNode);
var
  BucketIdx: Cardinal;
  Curr, PrevNode: TIdempotencyNode;
begin
  BucketIdx := ANode.KeyHash and FMask;
  Curr := FBuckets[BucketIdx];
  PrevNode := nil;
  while Curr <> nil do
  begin
    if Curr = ANode then
    begin
      if PrevNode = nil then
        FBuckets[BucketIdx] := Curr.BucketNext
      else
        PrevNode.BucketNext := Curr.BucketNext;
      ANode.BucketNext := nil;
      Exit;
    end;
    PrevNode := Curr;
    Curr := Curr.BucketNext;
  end;
end;

function TZenithMemoryIdempotencyStore.IsExpired(ANode: TIdempotencyNode;
  ANowTick: QWord): Boolean;
begin
  Result := (ANowTick - ANode.CreatedTick) >= (QWord(FTTLSeconds) * 1000);
end;

constructor TZenithMemoryIdempotencyStore.Create(ACapacity: Integer;
  ATTLSeconds: Integer);
var
  InitialBuckets: Integer;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FHead := nil;
  FTail := nil;
  FCount := 0;
  FHits := 0;
  FMisses := 0;
  FConflicts := 0;
  FPayloadMismatches := 0;
  FEvictions := 0;
  FExpirations := 0;

  if ACapacity < 1 then
    FCapacity := ZENITH_IDEMPOTENCY_DEFAULT_CAPACITY
  else
    FCapacity := ACapacity;

  if ATTLSeconds < 1 then
    FTTLSeconds := ZENITH_IDEMPOTENCY_DEFAULT_TTL_SEC
  else
    FTTLSeconds := ATTLSeconds;

  InitialBuckets := FCapacity;
  if InitialBuckets > 65536 then
    InitialBuckets := 65536;
  InitBuckets(InitialBuckets);
end;

destructor TZenithMemoryIdempotencyStore.Destroy;
begin
  Clear;
  SetLength(FBuckets, 0);
  FLock.Free;
  inherited Destroy;
end;

function TZenithMemoryIdempotencyStore.GetCapacity: Integer;
begin
  FLock.Enter;
  try
    Result := FCapacity;
  finally
    FLock.Leave;
  end;
end;

procedure TZenithMemoryIdempotencyStore.SetCapacity(AValue: Integer);
begin
  FLock.Enter;
  try
    if AValue < 1 then
      FCapacity := 1
    else
      FCapacity := AValue;
    while FCount > FCapacity do
      EvictTail;
  finally
    FLock.Leave;
  end;
end;

function TZenithMemoryIdempotencyStore.GetTTLSeconds: Integer;
begin
  FLock.Enter;
  try
    Result := FTTLSeconds;
  finally
    FLock.Leave;
  end;
end;

procedure TZenithMemoryIdempotencyStore.SetTTLSeconds(AValue: Integer);
begin
  FLock.Enter;
  try
    if AValue < 1 then
      FTTLSeconds := 1
    else
      FTTLSeconds := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TZenithMemoryIdempotencyStore.AttachHead(ANode: TIdempotencyNode);
begin
  ANode.Next := FHead;
  ANode.Prev := nil;
  if FHead <> nil then
    FHead.Prev := ANode;
  FHead := ANode;
  if FTail = nil then
    FTail := ANode;
end;

procedure TZenithMemoryIdempotencyStore.DetachNode(ANode: TIdempotencyNode);
begin
  if ANode.Prev <> nil then
    ANode.Prev.Next := ANode.Next
  else
    FHead := ANode.Next;

  if ANode.Next <> nil then
    ANode.Next.Prev := ANode.Prev
  else
    FTail := ANode.Prev;

  ANode.Prev := nil;
  ANode.Next := nil;
end;

procedure TZenithMemoryIdempotencyStore.MoveToHead(ANode: TIdempotencyNode);
begin
  if ANode = FHead then Exit;
  DetachNode(ANode);
  AttachHead(ANode);
end;

procedure TZenithMemoryIdempotencyStore.RemoveAndFreeNode(ANode: TIdempotencyNode);
begin
  DetachNode(ANode);
  RemoveFromBucket(ANode);
  Dec(FCount);
  ANode.Free;
end;

procedure TZenithMemoryIdempotencyStore.EvictTail;
var
  OldTail: TIdempotencyNode;
begin
  if FTail = nil then Exit;
  OldTail := FTail;
  RemoveAndFreeNode(OldTail);
  Inc(FEvictions);
end;

function TZenithMemoryIdempotencyStore.PurgeExpiredInternal(ANowTick: QWord): Integer;
var
  Curr, ToDelete: TIdempotencyNode;
begin
  Result := 0;
  Curr := FTail;
  while Curr <> nil do
  begin
    if IsExpired(Curr, ANowTick) then
    begin
      ToDelete := Curr;
      Curr := Curr.Prev;
      RemoveAndFreeNode(ToDelete);
      Inc(FExpirations);
      Inc(Result);
    end
    else
      Curr := Curr.Prev;
  end;
end;

function TZenithMemoryIdempotencyStore.PurgeExpired: Integer;
begin
  FLock.Enter;
  try
    Result := PurgeExpiredInternal(GetTickCount64);
  finally
    FLock.Leave;
  end;
end;

function TZenithMemoryIdempotencyStore.TryAcquire(const AKey, ARequestHash: string;
  out AExisting: TIdempotencyRecord;
  out AIsConflict: Boolean;
  out AIsPayloadMismatch: Boolean): Boolean;
var
  Node: TIdempotencyNode;
  KeyHash: Cardinal;
  NowTick: QWord;
  NowTime: TDateTime;
begin
  AIsConflict := False;
  AIsPayloadMismatch := False;
  AExisting := Default(TIdempotencyRecord);
  KeyHash := HashKey(AKey);

  FLock.Enter;
  try
    NowTick := GetTickCount64;
    NowTime := Now;

    Node := FindNode(AKey, KeyHash);
    if Node <> nil then
    begin
      if IsExpired(Node, NowTick) then
      begin
        RemoveAndFreeNode(Node);
        Inc(FExpirations);
        Node := nil;
      end
      else
      begin
        Node.Data.LastAccessedAt := NowTime;
        MoveToHead(Node);
        AExisting := Node.Data;

        { 1. Concurrent in-flight request -> HTTP 409 Conflict }
        if Node.Data.Status = isPending then
        begin
          AIsConflict := True;
          Inc(FConflicts);
          Result := False;
          Exit;
        end;

        { 2. Same key reused with different payload/target -> HTTP 422 }
        if Node.Data.RequestHash <> ARequestHash then
        begin
          AIsPayloadMismatch := True;
          Inc(FPayloadMismatches);
          Result := False;
          Exit;
        end;

        { 3. Identical replay of completed response }
        Inc(FHits);
        Result := False;
        Exit;
      end;
    end;

    { Missing or expired key: purge expired tail entries in amortized O(1) and enforce LRU }
    while (FTail <> nil) and IsExpired(FTail, NowTick) do
    begin
      RemoveAndFreeNode(FTail);
      Inc(FExpirations);
    end;

    while FCount >= FCapacity do
      EvictTail;

    if (FCount >= Length(FBuckets) * 2) and (Length(FBuckets) < 1048576) then
      Rehash(Length(FBuckets) * 2);

    Node := TIdempotencyNode.Create(AKey, ARequestHash, KeyHash, isPending, NowTick, NowTime);
    AttachHead(Node);
    InsertIntoBucket(Node);
    Inc(FCount);
    Inc(FMisses);

    AExisting := Node.Data;
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TZenithMemoryIdempotencyStore.Complete(const AKey: string; ACode: Integer;
  const AContentType: string; const ABody: RawByteString);
var
  EmptyHeaders: TIdempotencyHeaderArray;
begin
  SetLength(EmptyHeaders, 0);
  Complete(AKey, ACode, AContentType, ABody, EmptyHeaders);
end;

procedure TZenithMemoryIdempotencyStore.Complete(const AKey: string; ACode: Integer;
  const AContentType: string; const ABody: RawByteString;
  const AHeaders: TIdempotencyHeaderArray);
var
  Node: TIdempotencyNode;
  KeyHash: Cardinal;
begin
  KeyHash := HashKey(AKey);
  FLock.Enter;
  try
    Node := FindNode(AKey, KeyHash);
    if Node <> nil then
    begin
      Node.Data.Status := isCompleted;
      Node.Data.ResponseCode := ACode;
      Node.Data.ResponseContentType := AContentType;
      Node.Data.ResponseBody := ABody;
      Node.Data.ResponseHeaders := Copy(AHeaders);
      Node.Data.LastAccessedAt := Now;
      MoveToHead(Node);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TZenithMemoryIdempotencyStore.Release(const AKey: string);
var
  Node: TIdempotencyNode;
  KeyHash: Cardinal;
begin
  KeyHash := HashKey(AKey);
  FLock.Enter;
  try
    Node := FindNode(AKey, KeyHash);
    if Node <> nil then
      RemoveAndFreeNode(Node);
  finally
    FLock.Leave;
  end;
end;

function TZenithMemoryIdempotencyStore.Get(const AKey: string;
  out ARecord: TIdempotencyRecord): Boolean;
var
  Node: TIdempotencyNode;
  KeyHash: Cardinal;
  NowTick: QWord;
begin
  ARecord := Default(TIdempotencyRecord);
  KeyHash := HashKey(AKey);
  FLock.Enter;
  try
    Node := FindNode(AKey, KeyHash);
    if Node <> nil then
    begin
      NowTick := GetTickCount64;
      if IsExpired(Node, NowTick) then
      begin
        RemoveAndFreeNode(Node);
        Inc(FExpirations);
        Result := False;
      end
      else
      begin
        Node.Data.LastAccessedAt := Now;
        MoveToHead(Node);
        ARecord := Node.Data;
        Result := True;
      end;
    end
    else
      Result := False;
  finally
    FLock.Leave;
  end;
end;

procedure TZenithMemoryIdempotencyStore.Clear;
var
  Curr, NextNode: TIdempotencyNode;
begin
  FLock.Enter;
  try
    Curr := FHead;
    while Curr <> nil do
    begin
      NextNode := Curr.Next;
      Curr.Free;
      Curr := NextNode;
    end;
    FHead := nil;
    FTail := nil;
    FCount := 0;
    if Length(FBuckets) > 0 then
      FillChar(FBuckets[0], Length(FBuckets) * SizeOf(TIdempotencyNode), 0);
  finally
    FLock.Leave;
  end;
end;

function TZenithMemoryIdempotencyStore.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FCount;
  finally
    FLock.Leave;
  end;
end;

function TZenithMemoryIdempotencyStore.GetStats: TIdempotencyStoreStats;
begin
  FLock.Enter;
  try
    Result.ActiveCount := FCount;
    Result.Capacity := FCapacity;
    Result.TTLSeconds := FTTLSeconds;
    Result.Hits := FHits;
    Result.Misses := FMisses;
    Result.Conflicts := FConflicts;
    Result.PayloadMismatches := FPayloadMismatches;
    Result.Evictions := FEvictions;
    Result.Expirations := FExpirations;
  finally
    FLock.Leave;
  end;
end;

{ TZenithIdempotency }

class constructor TZenithIdempotency.CreateClass;
begin
  FEnabled := True;
  FMaxKeyLength := ZENITH_IDEMPOTENCY_MAX_KEY_LENGTH;
  FDefaultStore := nil;
  FStoreLock := TCriticalSection.Create;
end;

class destructor TZenithIdempotency.DestroyClass;
begin
  FDefaultStore := nil;
  FreeAndNil(FStoreLock);
end;

class function TZenithIdempotency.GetDefaultStore: IZenithIdempotencyStore;
begin
  FStoreLock.Enter;
  try
    if FDefaultStore = nil then
      FDefaultStore := TZenithMemoryIdempotencyStore.Create(
        ZENITH_IDEMPOTENCY_DEFAULT_CAPACITY,
        ZENITH_IDEMPOTENCY_DEFAULT_TTL_SEC
      );
    Result := FDefaultStore;
  finally
    FStoreLock.Leave;
  end;
end;

class procedure TZenithIdempotency.SetDefaultStore(const AValue: IZenithIdempotencyStore);
begin
  FStoreLock.Enter;
  try
    FDefaultStore := AValue;
  finally
    FStoreLock.Leave;
  end;
end;

class function TZenithIdempotency.EscapeJsonString(const AStr: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(AStr) do
  begin
    C := AStr[I];
    case C of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #12:  Result := Result + '\f';
      #13:  Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
end;

class function TZenithIdempotency.BuildProblemJson(AStatus: Integer;
  const ATitle, ADetail, AInstance: string): string;
begin
  if AInstance <> '' then
    Result := Format(
      '{"type":"https://tools.ietf.org/html/rfc9457",' +
      '"title":"%s",' +
      '"status":%d,' +
      '"detail":"%s",' +
      '"instance":"%s"}',
      [EscapeJsonString(ATitle), AStatus, EscapeJsonString(ADetail), EscapeJsonString(AInstance)]
    )
  else
    Result := Format(
      '{"type":"https://tools.ietf.org/html/rfc9457",' +
      '"title":"%s",' +
      '"status":%d,' +
      '"detail":"%s"}',
      [EscapeJsonString(ATitle), AStatus, EscapeJsonString(ADetail)]
    );
end;

class function TZenithIdempotency.IsReplayableHeader(const AHeaderName: string): Boolean;
var
  LowerName: string;
begin
  LowerName := LowerCase(Trim(AHeaderName));
  Result :=
    (LowerName <> '') and
    (LowerName <> 'content-type') and
    (LowerName <> 'content-length') and
    (LowerName <> 'content-encoding') and
    (LowerName <> 'transfer-encoding') and
    (LowerName <> 'connection') and
    (LowerName <> 'keep-alive') and
    (LowerName <> 'date') and
    (LowerName <> 'idempotent-replayed');
end;

class function TZenithIdempotency.ExtractResponseHeaders(AResponse: TResponse): TIdempotencyHeaderArray;
var
  I, SepPos, Count: Integer;
  Line, HName, HVal: string;
  HasLocation, HasETag, HasCacheControl: Boolean;

  procedure AppendHeader(const AName, AValue: string);
  begin
    SetLength(Result, Count + 1);
    Result[Count].Name := AName;
    Result[Count].Value := AValue;
    Inc(Count);
  end;

begin
  SetLength(Result, 0);
  Count := 0;
  HasLocation := False;
  HasETag := False;
  HasCacheControl := False;

  for I := 0 to AResponse.CustomHeaders.Count - 1 do
  begin
    Line := AResponse.CustomHeaders[I];
    SepPos := Pos('=', Line);
    if SepPos = 0 then
      SepPos := Pos(':', Line);
    if SepPos > 1 then
    begin
      HName := Trim(Copy(Line, 1, SepPos - 1));
      HVal := Trim(Copy(Line, SepPos + 1, MaxInt));
      if IsReplayableHeader(HName) then
      begin
        AppendHeader(HName, HVal);
        if SameText(HName, 'Location') then HasLocation := True
        else if SameText(HName, 'ETag') then HasETag := True
        else if SameText(HName, 'Cache-Control') then HasCacheControl := True;
      end;
    end;
  end;

  if (not HasLocation) and (AResponse.Location <> '') then
    AppendHeader('Location', AResponse.Location);
  if (not HasETag) and (AResponse.ETag <> '') then
    AppendHeader('ETag', AResponse.ETag);
  if (not HasCacheControl) and (AResponse.CacheControl <> '') then
    AppendHeader('Cache-Control', AResponse.CacheControl);
end;

class procedure TZenithIdempotency.ApplyResponseHeaders(AResponse: TResponse;
  const AHeaders: TIdempotencyHeaderArray);
var
  I: Integer;
begin
  for I := 0 to High(AHeaders) do
  begin
    if SameText(AHeaders[I].Name, 'Location') then
      AResponse.Location := AHeaders[I].Value
    else if SameText(AHeaders[I].Name, 'ETag') then
      AResponse.ETag := AHeaders[I].Value
    else if SameText(AHeaders[I].Name, 'Cache-Control') then
      AResponse.CacheControl := AHeaders[I].Value
    else if SameText(AHeaders[I].Name, 'Content-Encoding') then
      AResponse.ContentEncoding := AHeaders[I].Value
    else
      AResponse.SetCustomHeader(AHeaders[I].Name, AHeaders[I].Value);
  end;
end;

class function TZenithIdempotency.HasIdempotencyHeader(ARequest: TRequest;
  out ARawKey: string): Boolean;
var
  I, SepPos: Integer;
  Line, HName: string;
begin
  ARawKey := '';
  Result := False;

  { 1. Inspect CustomHeaders directly to distinguish absent vs present-but-empty header }
  for I := 0 to ARequest.CustomHeaders.Count - 1 do
  begin
    Line := ARequest.CustomHeaders[I];
    SepPos := Pos('=', Line);
    if SepPos = 0 then
      SepPos := Pos(':', Line);
    if SepPos > 1 then
      HName := Trim(Copy(Line, 1, SepPos - 1))
    else
      HName := Trim(Line);

    if SameText(HName, 'Idempotency-Key') or SameText(HName, 'X-Idempotency-Key') then
    begin
      if SepPos > 0 then
        ARawKey := Copy(Line, SepPos + 1, MaxInt)
      else
        ARawKey := '';
      Result := True;
      Exit;
    end;
  end;

  { 2. Fallback to GetCustomHeader for request adapters with alternate header storage }
  ARawKey := ARequest.GetCustomHeader('Idempotency-Key');
  if ARawKey <> '' then
  begin
    Result := True;
    Exit;
  end;

  ARawKey := ARequest.GetCustomHeader('X-Idempotency-Key');
  if ARawKey <> '' then
    Result := True;
end;

class function TZenithIdempotency.GetIdempotencyKey(ARequest: TRequest): string;
var
  RawKey, Normalized, ErrDetail: string;
begin
  Result := '';
  if not HasIdempotencyHeader(ARequest, RawKey) then Exit;
  if ValidateAndNormalizeKey(RawKey, Normalized, ErrDetail) then
    Result := Normalized;
end;

class function TZenithIdempotency.ValidateAndNormalizeKey(const ARawKey: string;
  out ANormalizedKey, AErrorDetail: string): Boolean;
var
  S: string;
  I: Integer;
  C: Char;
begin
  ANormalizedKey := '';
  AErrorDetail := '';
  Result := False;

  S := Trim(ARawKey);
  if S = '' then
  begin
    AErrorDetail := 'Idempotency-Key header must not be empty.';
    Exit;
  end;

  { Support RFC 8941 Structured Field String ("...") }
  if (S[1] = '"') or (S[Length(S)] = '"') then
  begin
    if (Length(S) < 3) or (S[1] <> '"') or (S[Length(S)] <> '"') then
    begin
      AErrorDetail := 'Idempotency-Key header has malformed quotes.';
      Exit;
    end;
    S := Copy(S, 2, Length(S) - 2);
    if Trim(S) = '' then
    begin
      AErrorDetail := 'Idempotency-Key header must not be empty.';
      Exit;
    end;
  end;

  if Length(S) > FMaxKeyLength then
  begin
    AErrorDetail := Format('Idempotency-Key exceeds maximum allowed length of %d characters.', [FMaxKeyLength]);
    Exit;
  end;

  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (Ord(C) < $21) or (Ord(C) > $7E) or (C = '"') or (C = '\') then
    begin
      AErrorDetail := 'Idempotency-Key contains invalid, whitespace, or control characters.';
      Exit;
    end;
  end;

  ANormalizedKey := S;
  Result := True;
end;

class function TZenithIdempotency.ExtractRequestScope(ARequest: TRequest;
  const AScope: string): string;
var
  I, SepPos: Integer;
  Line, HName, HVal: string;
  AuthVal, TenantVal, ApiKeyVal: string;
begin
  Result := Trim(AScope);
  if Result <> '' then
    Exit;

  if not Assigned(ARequest) then
    Exit('');

  AuthVal := Trim(ARequest.Authorization);
  TenantVal := '';
  ApiKeyVal := '';

  if Assigned(ARequest.CustomHeaders) then
  begin
    for I := 0 to ARequest.CustomHeaders.Count - 1 do
    begin
      Line := ARequest.CustomHeaders[I];
      SepPos := Pos('=', Line);
      if SepPos = 0 then
        SepPos := Pos(':', Line);
      if SepPos > 1 then
      begin
        HName := Trim(Copy(Line, 1, SepPos - 1));
        HVal := Trim(Copy(Line, SepPos + 1, MaxInt));
        if (AuthVal = '') and SameText(HName, 'Authorization') then
          AuthVal := HVal
        else if (TenantVal = '') and (SameText(HName, 'X-Tenant-Id') or SameText(HName, 'X-Tenant-ID')) then
          TenantVal := HVal
        else if (ApiKeyVal = '') and (SameText(HName, 'X-API-Key') or SameText(HName, 'X-Api-Key')) then
          ApiKeyVal := HVal;
      end;
    end;
  end;

  if AuthVal = '' then
    AuthVal := Trim(ARequest.GetCustomHeader('Authorization'));
  if TenantVal = '' then
    TenantVal := Trim(ARequest.GetCustomHeader('X-Tenant-Id'));
  if ApiKeyVal = '' then
    ApiKeyVal := Trim(ARequest.GetCustomHeader('X-API-Key'));

  if (AuthVal <> '') and (TenantVal <> '') then
    Result := AuthVal + '|tenant:' + TenantVal
  else if AuthVal <> '' then
    Result := AuthVal
  else if TenantVal <> '' then
    Result := 'tenant:' + TenantVal
  else if ApiKeyVal <> '' then
    Result := 'apikey:' + ApiKeyVal
  else
    Result := '';
end;

class function TZenithIdempotency.BuildScopedStoreKey(const ANormalizedKey,
  AScopeContext: string): string;
var
  ScopeDigest: string;
begin
  if AScopeContext = '' then
    Result := ANormalizedKey
  else
  begin
    ScopeDigest := Copy(ZenithSHA256(RawByteString(AScopeContext)), 1, 16);
    Result := ScopeDigest + ':' + ANormalizedKey;
  end;
end;

class function TZenithIdempotency.ComputeRequestHash(const AMethod, APath: string;
  const AContent: RawByteString; const AScope: string): string;
var
  Fingerprint: RawByteString;
  ScopeHash: string;
begin
  if AScope <> '' then
  begin
    ScopeHash := Copy(ZenithSHA256(RawByteString(AScope)), 1, 16);
    Fingerprint := RawByteString(ScopeHash) + ':' +
      RawByteString(UpperCase(AMethod)) + ':' + RawByteString(APath) + ':' + AContent;
  end
  else
    Fingerprint := RawByteString(UpperCase(AMethod)) + ':' + RawByteString(APath) + ':' + AContent;
  Result := ZenithSHA256(Fingerprint);
end;

class function TZenithIdempotency.ComputeRequestHash(ARequest: TRequest;
  const AScope: string): string;
var
  Target, EffectiveScope: string;
begin
  Target := ARequest.PathInfo;
  if ARequest.QueryString <> '' then
    Target := Target + '?' + ARequest.QueryString;
  EffectiveScope := ExtractRequestScope(ARequest, AScope);
  Result := ComputeRequestHash(ARequest.Method, Target, ARequest.Content, EffectiveScope);
end;

class function TZenithIdempotency.ComputeRequestHash(ARequest: TRequest): string;
begin
  Result := ComputeRequestHash(ARequest, '');
end;

class function TZenithIdempotency.ProcessBefore(ARequest: TRequest; AResponse: TResponse;
  AStore: IZenithIdempotencyStore): Boolean;
begin
  Result := ProcessBefore(ARequest, AResponse, '', AStore);
end;

class function TZenithIdempotency.ProcessBefore(ARequest: TRequest; AResponse: TResponse;
  const AScope: string; AStore: IZenithIdempotencyStore): Boolean;
var
  RawKey, Key, ScopedKey, ScopeCtx, ErrDetail, HashStr: string;
  Existing: TIdempotencyRecord;
  IsConflict, IsMismatch: Boolean;
  Store: IZenithIdempotencyStore;
begin
  Result := True;
  if not FEnabled then Exit;

  if not HasIdempotencyHeader(ARequest, RawKey) then Exit;

  { 0. Key format and length validation -> HTTP 400 Bad Request (RFC 9457) }
  if not ValidateAndNormalizeKey(RawKey, Key, ErrDetail) then
  begin
    AResponse.Code := 400;
    AResponse.ContentType := 'application/problem+json; charset=utf-8';
    AResponse.Content := BuildProblemJson(400, 'Bad Request', ErrDetail, ARequest.PathInfo);
    Result := False;
    Exit;
  end;

  Store := AStore;
  if Store = nil then
    Store := DefaultStore;

  ScopeCtx := ExtractRequestScope(ARequest, AScope);
  ScopedKey := BuildScopedStoreKey(Key, ScopeCtx);
  HashStr := ComputeRequestHash(ARequest, ScopeCtx);

  if not Store.TryAcquire(ScopedKey, HashStr, Existing, IsConflict, IsMismatch) then
  begin
    { 1. Active in-flight concurrency: HTTP 409 Conflict (RFC 9457) }
    if IsConflict then
    begin
      AResponse.Code := 409;
      AResponse.ContentType := 'application/problem+json; charset=utf-8';
      AResponse.Content := BuildProblemJson(
        409,
        'Conflict',
        Format('A request with the Idempotency-Key ''%s'' is currently in progress.', [Key]),
        ARequest.PathInfo
      );
      Result := False;
      Exit;
    end;

    { 2. Payload or target mismatch: HTTP 422 Unprocessable Entity (RFC 9457) }
    if IsMismatch then
    begin
      AResponse.Code := 422;
      AResponse.ContentType := 'application/problem+json; charset=utf-8';
      AResponse.Content := BuildProblemJson(
        422,
        'Unprocessable Entity',
        Format('Idempotency-Key ''%s'' payload or target mismatch with original request.', [Key]),
        ARequest.PathInfo
      );
      Result := False;
      Exit;
    end;

    { 3. Successful replay: restore cached status, headers, content-type and body }
    AResponse.Code := Existing.ResponseCode;
    if Existing.ResponseContentType <> '' then
      AResponse.ContentType := Existing.ResponseContentType
    else
      AResponse.ContentType := 'application/json; charset=utf-8';

    ApplyResponseHeaders(AResponse, Existing.ResponseHeaders);
    if AResponse.Contents is TStringList then
      TStringList(AResponse.Contents).SkipLastLineBreak := True;
    AResponse.Content := Existing.ResponseBody;
    AResponse.SetCustomHeader('Idempotent-Replayed', 'true');
    Result := False;
    Exit;
  end;

  { Key acquired successfully in isPending state }
  Result := True;
end;

class procedure TZenithIdempotency.ProcessAfter(ARequest: TRequest; AResponse: TResponse;
  AStore: IZenithIdempotencyStore);
begin
  ProcessAfter(ARequest, AResponse, '', AStore);
end;

class procedure TZenithIdempotency.ProcessAfter(ARequest: TRequest; AResponse: TResponse;
  const AScope: string; AStore: IZenithIdempotencyStore);
var
  Key, ScopedKey, ScopeCtx: string;
  Store: IZenithIdempotencyStore;
  Body: RawByteString;
  Headers: TIdempotencyHeaderArray;
  StreamLen: Int64;
begin
  if not FEnabled then Exit;

  Key := GetIdempotencyKey(ARequest);
  if Key = '' then Exit;

  ScopeCtx := ExtractRequestScope(ARequest, AScope);
  ScopedKey := BuildScopedStoreKey(Key, ScopeCtx);

  Store := AStore;
  if Store = nil then
    Store := DefaultStore;

  { Transient server errors (HTTP 5xx or unset code): release key to allow client retry }
  if (AResponse.Code >= 500) or (AResponse.Code <= 0) then
  begin
    Store.Release(ScopedKey);
    Exit;
  end;

  { Extract response body }
  Body := '';
  if Assigned(AResponse.ContentStream) then
  begin
    AResponse.ContentStream.Position := 0;
    StreamLen := AResponse.ContentStream.Size;
    if StreamLen > 0 then
    begin
      SetLength(Body, StreamLen);
      AResponse.ContentStream.ReadBuffer(Body[1], StreamLen);
      AResponse.ContentStream.Position := 0;
    end;
  end
  else
    Body := AResponse.Content;

  Headers := ExtractResponseHeaders(AResponse);

  { Mark operation as completed with cached headers and body }
  Store.Complete(ScopedKey, AResponse.Code, AResponse.ContentType, Body, Headers);
end;

class procedure TZenithIdempotency.ReleaseOnError(ARequest: TRequest;
  AStore: IZenithIdempotencyStore);
begin
  ReleaseOnError(ARequest, '', AStore);
end;

class procedure TZenithIdempotency.ReleaseOnError(ARequest: TRequest;
  const AScope: string; AStore: IZenithIdempotencyStore);
var
  Key, ScopedKey, ScopeCtx: string;
  Store: IZenithIdempotencyStore;
begin
  if not FEnabled then Exit;

  Key := GetIdempotencyKey(ARequest);
  if Key = '' then Exit;

  ScopeCtx := ExtractRequestScope(ARequest, AScope);
  ScopedKey := BuildScopedStoreKey(Key, ScopeCtx);

  Store := AStore;
  if Store = nil then
    Store := DefaultStore;

  Store.Release(ScopedKey);
end;

end.
