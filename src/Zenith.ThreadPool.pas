unit Zenith.ThreadPool;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs;

type
  TZenithThreadPool = class;
  TZenithWorkerThread = class;

  { TZenithConnectionQueue: High-performance thread-safe FIFO queue backed by a circular ring buffer }
  TZenithConnectionQueue = class
  private
    FItems: array of TObject;
    FHead: Integer;
    FTail: Integer;
    FCount: Integer;
    FCapacity: Integer;
    FMaxCapacity: Integer;
    FLock: TCriticalSection;
    function GetCount: Integer;
    procedure ExpandCapacity;
  public
    constructor Create(AInitialCapacity: Integer = 1024; AMaxCapacity: Integer = 65536);
    destructor Destroy; override;
    function Enqueue(AItem: TObject): Boolean;
    function Dequeue(out AItem: TObject): Boolean;
    procedure Clear;
    property Count: Integer read GetCount;
    property Capacity: Integer read FCapacity;
    property MaxCapacity: Integer read FMaxCapacity write FMaxCapacity;
  end;

  { TZenithWorkerThread: Pre-allocated worker thread waiting on TEvent (0% idle CPU) }
  TZenithWorkerThread = class(TThread)
  private
    FPool: TZenithThreadPool;
    FEvent: TEvent;
    FIsBusy: Boolean;
    FProcessedRequests: Int64;
    FWorkerId: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TZenithThreadPool; AWorkerId: Integer);
    destructor Destroy; override;
    procedure Signal;
    property IsBusy: Boolean read FIsBusy;
    property ProcessedRequests: Int64 read FProcessedRequests;
    property WorkerId: Integer read FWorkerId;
  end;

  TZenithWorkHandler = procedure(AItem: TObject) of object;
  TZenithWorkerErrorHandler = procedure(AWorker: TZenithWorkerThread; AItem: TObject; E: Exception) of object;

  { TZenithThreadPool: High-performance pre-allocated worker pool manager }
  TZenithThreadPool = class
  private
    FQueue: TZenithConnectionQueue;
    FWorkers: array of TZenithWorkerThread;
    FIdleWorkers: array of TZenithWorkerThread;
    FIdleCount: Integer;
    FWorkerCount: Integer;
    FActive: Boolean;
    FLock: TCriticalSection;
    FTotalQueued: Int64;
    FTotalProcessed: Int64;
    FTotalRejected: Int64;
    FOnExecuteWork: TZenithWorkHandler;
    FOnError: TZenithWorkerErrorHandler;
    function GetActiveWorkers: Integer;
    function GetIdleWorkers: Integer;
    function GetQueueCount: Integer;
    function GetQueueCapacity: Integer;
    function GetMaxQueueCapacity: Integer;
    procedure SetMaxQueueCapacity(AValue: Integer);
  protected
    function PopItem(AWorker: TZenithWorkerThread; out AItem: TObject): Boolean;
    procedure RegisterWorkerIdle(AWorker: TZenithWorkerThread);
    procedure DoExecuteItem(AItem: TObject); virtual;
    procedure DoHandleWorkerError(AWorker: TZenithWorkerThread; AItem: TObject; E: Exception); virtual;
  public
    constructor Create(AWorkerCount: Integer = 0; AMaxQueueCapacity: Integer = 65536);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    function QueueWork(AItem: TObject): Boolean;
    function QueueConnection(AItem: TObject): Boolean; inline;

    property Active: Boolean read FActive;
    property WorkerCount: Integer read FWorkerCount;
    property ActiveWorkers: Integer read GetActiveWorkers;
    property IdleWorkers: Integer read GetIdleWorkers;
    property Queue: TZenithConnectionQueue read FQueue;
    property QueueCount: Integer read GetQueueCount;
    property QueueCapacity: Integer read GetQueueCapacity;
    property MaxQueueCapacity: Integer read GetMaxQueueCapacity write SetMaxQueueCapacity;
    property TotalQueued: Int64 read FTotalQueued;
    property TotalProcessed: Int64 read FTotalProcessed;
    property TotalRejected: Int64 read FTotalRejected;
    property OnExecuteWork: TZenithWorkHandler read FOnExecuteWork write FOnExecuteWork;
    property OnError: TZenithWorkerErrorHandler read FOnError write FOnError;
  end;

function GetZenithOptimalWorkerCount: Integer;

implementation

function GetZenithOptimalWorkerCount: Integer;
var
  EnvVal: string;
  Parsed: Integer;
  CPUs: Integer;
begin
  EnvVal := GetEnvironmentVariable('ZENITH_THREADPOOL_WORKERS');
  if EnvVal = '' then
    EnvVal := GetEnvironmentVariable('ZENITH_WORKERS');
  if EnvVal <> '' then
  begin
    Parsed := StrToIntDef(EnvVal, 0);
    if Parsed > 0 then
      Exit(Parsed);
  end;

  CPUs := GetCPUCount;
  if CPUs < 1 then CPUs := 1;
  // For I/O-bound HTTP servers: 4 workers per core, floor of 16 and cap of 128
  Result := CPUs * 4;
  if Result < 16 then Result := 16;
  if Result > 128 then Result := 128;
end;

{ TZenithConnectionQueue }

constructor TZenithConnectionQueue.Create(AInitialCapacity: Integer; AMaxCapacity: Integer);
begin
  inherited Create;
  if AInitialCapacity < 16 then
    AInitialCapacity := 16;
  if AMaxCapacity < AInitialCapacity then
    AMaxCapacity := AInitialCapacity;

  FCapacity := AInitialCapacity;
  FMaxCapacity := AMaxCapacity;
  SetLength(FItems, FCapacity);
  FHead := 0;
  FTail := 0;
  FCount := 0;
  FLock := TCriticalSection.Create;
end;

destructor TZenithConnectionQueue.Destroy;
begin
  Clear;
  FreeAndNil(FLock);
  SetLength(FItems, 0);
  inherited Destroy;
end;

procedure TZenithConnectionQueue.ExpandCapacity;
var
  NewCap: Integer;
  NewItems: array of TObject;
  I: Integer;
begin
  NewCap := FCapacity * 2;
  if NewCap > FMaxCapacity then
    NewCap := FMaxCapacity;

  if NewCap <= FCapacity then
    Exit;

  SetLength(NewItems, NewCap);
  for I := 0 to FCount - 1 do
    NewItems[I] := FItems[(FHead + I) mod FCapacity];

  FItems := NewItems;
  FHead := 0;
  FTail := FCount;
  FCapacity := NewCap;
end;

function TZenithConnectionQueue.Enqueue(AItem: TObject): Boolean;
begin
  Result := False;
  if not Assigned(AItem) then
    Exit;

  FLock.Enter;
  try
    if FCount >= FMaxCapacity then
      Exit(False);

    if FCount = FCapacity then
    begin
      ExpandCapacity;
      if FCount = FCapacity then
        Exit(False);
    end;

    FItems[FTail] := AItem;
    FTail := (FTail + 1) mod FCapacity;
    Inc(FCount);
    Result := True;
  finally
    FLock.Leave;
  end;
end;

function TZenithConnectionQueue.Dequeue(out AItem: TObject): Boolean;
begin
  Result := False;
  AItem := nil;

  FLock.Enter;
  try
    if FCount = 0 then
      Exit(False);

    AItem := FItems[FHead];
    FItems[FHead] := nil;
    FHead := (FHead + 1) mod FCapacity;
    Dec(FCount);
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TZenithConnectionQueue.Clear;
var
  Item: TObject;
begin
  FLock.Enter;
  try
    while FCount > 0 do
    begin
      Item := FItems[FHead];
      FItems[FHead] := nil;
      FHead := (FHead + 1) mod FCapacity;
      Dec(FCount);
      if Assigned(Item) then
      begin
        try
          Item.Free;
        except
          // Prevent destructor exceptions from corrupting queue cleanup
        end;
      end;
    end;
    FHead := 0;
    FTail := 0;
    FCount := 0;
  finally
    FLock.Leave;
  end;
end;

function TZenithConnectionQueue.GetCount: Integer;
begin
  FLock.Enter;
  try
    Result := FCount;
  finally
    FLock.Leave;
  end;
end;

{ TZenithWorkerThread }

constructor TZenithWorkerThread.Create(APool: TZenithThreadPool; AWorkerId: Integer);
begin
  FPool := APool;
  FWorkerId := AWorkerId;
  FIsBusy := False;
  FProcessedRequests := 0;
  // ManualReset = True, InitialState = False
  FEvent := TEvent.Create(nil, True, False, '');
  FreeOnTerminate := False;
  inherited Create(False); // Start immediately
end;

destructor TZenithWorkerThread.Destroy;
begin
  FreeAndNil(FEvent);
  inherited Destroy;
end;

procedure TZenithWorkerThread.Signal;
begin
  if Assigned(FEvent) then
    FEvent.SetEvent;
end;

procedure TZenithWorkerThread.Execute;
var
  Item: TObject;
begin
  while not Terminated do
  begin
    // Try to pop an item from the queue or register as idle
    if FPool.PopItem(Self, Item) then
    begin
      FIsBusy := True;
      try
        try
          FPool.DoExecuteItem(Item);
        except
          on E: Exception do
            FPool.DoHandleWorkerError(Self, Item, E);
        end;
      finally
        FIsBusy := False;
        Inc(FProcessedRequests);
        {$IFDEF CPU64}
        InterlockedIncrement64(FPool.FTotalProcessed);
        {$ELSE}
        FPool.FLock.Acquire;
        try
          Inc(FPool.FTotalProcessed);
        finally
          FPool.FLock.Release;
        end;
        {$ENDIF}
      end;
      // If more connections are queued, process the next one immediately without waiting
      Continue;
    end;

    if Terminated then
      Break;

    // Queue was empty; thread registered itself as idle in PopItem.
    // Wait on TEvent (0% idle CPU in kernel).
    // When new work arrives via Signal or the pool stops, the event is signaled.
    FEvent.WaitFor(INFINITE);
  end;
end;

{ TZenithThreadPool }

constructor TZenithThreadPool.Create(AWorkerCount: Integer; AMaxQueueCapacity: Integer);
begin
  inherited Create;
  if AWorkerCount <= 0 then
    AWorkerCount := GetZenithOptimalWorkerCount;

  FWorkerCount := AWorkerCount;
  if AMaxQueueCapacity < 1024 then
    AMaxQueueCapacity := 65536;

  FQueue := TZenithConnectionQueue.Create(1024, AMaxQueueCapacity);
  FLock := TCriticalSection.Create;
  FActive := False;
  FTotalQueued := 0;
  FTotalProcessed := 0;
  FTotalRejected := 0;
  FIdleCount := 0;
  SetLength(FWorkers, 0);
  SetLength(FIdleWorkers, 0);
end;

destructor TZenithThreadPool.Destroy;
begin
  Stop;
  FreeAndNil(FQueue);
  FreeAndNil(FLock);
  inherited Destroy;
end;

procedure TZenithThreadPool.Start;
var
  I: Integer;
begin
  if FActive then
    Exit;

  FLock.Enter;
  try
    FActive := True;
    SetLength(FWorkers, FWorkerCount);
    SetLength(FIdleWorkers, FWorkerCount);
    FIdleCount := 0;

    for I := 0 to FWorkerCount - 1 do
      FWorkers[I] := TZenithWorkerThread.Create(Self, I);
  finally
    FLock.Leave;
  end;
end;

procedure TZenithThreadPool.Stop;
var
  I: Integer;
  OldWorkers: array of TZenithWorkerThread;
  OldCount: Integer;
begin
  if not FActive then
    Exit;

  FLock.Enter;
  try
    FActive := False;
    OldCount := FWorkerCount;
    SetLength(OldWorkers, OldCount);
    for I := 0 to OldCount - 1 do
      OldWorkers[I] := FWorkers[I];

    // Signal termination and wake all workers
    for I := 0 to OldCount - 1 do
    begin
      if Assigned(OldWorkers[I]) then
      begin
        OldWorkers[I].Terminate;
        OldWorkers[I].Signal;
      end;
    end;
  finally
    FLock.Leave;
  end;

  // Wait for each thread to finish outside the lock
  for I := 0 to OldCount - 1 do
  begin
    if Assigned(OldWorkers[I]) then
    begin
      OldWorkers[I].WaitFor;
      FreeAndNil(OldWorkers[I]);
    end;
  end;

  FLock.Enter;
  try
    FIdleCount := 0;
    SetLength(FIdleWorkers, 0);
    SetLength(FWorkers, 0);
    FWorkerCount := 0;
    if Assigned(FQueue) then
      FQueue.Clear;
  finally
    FLock.Leave;
  end;
end;

function TZenithThreadPool.PopItem(AWorker: TZenithWorkerThread; out AItem: TObject): Boolean;
begin
  Result := False;
  AItem := nil;

  if not FActive or AWorker.Terminated then
    Exit;

  FLock.Enter;
  try
    if FQueue.Dequeue(AItem) then
    begin
      Result := True;
      Exit;
    end;

    // Empty queue: register worker as idle and reset its wait event
    RegisterWorkerIdle(AWorker);
    AWorker.FEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TZenithThreadPool.RegisterWorkerIdle(AWorker: TZenithWorkerThread);
var
  I: Integer;
begin
  for I := 0 to FIdleCount - 1 do
    if FIdleWorkers[I] = AWorker then
      Exit;

  if FIdleCount >= Length(FIdleWorkers) then
    SetLength(FIdleWorkers, FIdleCount + 16);

  FIdleWorkers[FIdleCount] := AWorker;
  Inc(FIdleCount);
end;

function TZenithThreadPool.QueueWork(AItem: TObject): Boolean;
var
  WorkerToSignal: TZenithWorkerThread;
begin
  Result := False;
  WorkerToSignal := nil;

  if not FActive then
    Exit;

  FLock.Enter;
  try
    if not FQueue.Enqueue(AItem) then
    begin
      Inc(FTotalRejected);
      Exit(False);
    end;

    Inc(FTotalQueued);
    Result := True;

    // If an idle worker is waiting, pick it to wake up
    if FIdleCount > 0 then
    begin
      Dec(FIdleCount);
      WorkerToSignal := FIdleWorkers[FIdleCount];
      FIdleWorkers[FIdleCount] := nil;
    end;
  finally
    FLock.Leave;
  end;

  // Signal outside the lock to avoid mutex contention when waking the worker
  if Assigned(WorkerToSignal) then
    WorkerToSignal.Signal;
end;

function TZenithThreadPool.QueueConnection(AItem: TObject): Boolean;
begin
  Result := QueueWork(AItem);
end;

procedure TZenithThreadPool.DoExecuteItem(AItem: TObject);
begin
  if Assigned(FOnExecuteWork) then
    FOnExecuteWork(AItem)
  else if Assigned(AItem) then
    AItem.Free;
end;

procedure TZenithThreadPool.DoHandleWorkerError(AWorker: TZenithWorkerThread; AItem: TObject; E: Exception);
begin
  if Assigned(FOnError) then
  begin
    try
      FOnError(AWorker, AItem, E);
    except
    end;
  end;
end;

function TZenithThreadPool.GetActiveWorkers: Integer;
begin
  FLock.Enter;
  try
    Result := FWorkerCount - FIdleCount;
    if Result < 0 then Result := 0;
  finally
    FLock.Leave;
  end;
end;

function TZenithThreadPool.GetIdleWorkers: Integer;
begin
  FLock.Enter;
  try
    Result := FIdleCount;
  finally
    FLock.Leave;
  end;
end;

function TZenithThreadPool.GetQueueCount: Integer;
begin
  if Assigned(FQueue) then
    Result := FQueue.Count
  else
    Result := 0;
end;

function TZenithThreadPool.GetQueueCapacity: Integer;
begin
  if Assigned(FQueue) then
    Result := FQueue.Capacity
  else
    Result := 0;
end;

function TZenithThreadPool.GetMaxQueueCapacity: Integer;
begin
  if Assigned(FQueue) then
    Result := FQueue.MaxCapacity
  else
    Result := 0;
end;

procedure TZenithThreadPool.SetMaxQueueCapacity(AValue: Integer);
begin
  if Assigned(FQueue) then
    FQueue.MaxCapacity := AValue;
end;

end.
