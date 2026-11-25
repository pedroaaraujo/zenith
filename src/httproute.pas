{
    Zenith High-Performance HTTP Request Router (Radix Tree / Segment Trie)
    Drop-in replacement for FCL-Web httproute.pp with O(K) segment resolution,
    deterministic priority (Static > Param > Wildcard), registration-order independence,
    and native support for rmPatch and rmConnect.
}

{$mode objfpc}{$H+}

unit httproute;

interface

uses
  Classes, SysUtils, httpdefs;

type
  EHTTPRoute = class(EHTTP);

  // Forward definitions
  THTTPRouter = class;
  THTTPRouterClass = class of THTTPRouter;

  // HTTP methods supported by the router (expanded with rmPatch and rmConnect)
  TRouteMethod = (rmUnknown, rmAll, rmGet, rmPost, rmPut, rmDelete, rmOptions, rmHead, rmTrace, rmPatch, rmConnect);
  TRouteMethods = set of TRouteMethod;
  TRouteOption = (roCaseSensitive, roEmptyMatchesAll);
  TRouteOptions = set of TRouteOption;
  TArrayOfString = array of string;

  { THTTPRoute }

  THTTPRoute = class(TCollectionItem)
  private
    FDefault: Boolean;
    FMethod: TRouteMethod;
    FURLPattern: String;
    FPatternSegments: TArrayOfString;
    procedure SetURLPattern(AValue: String);
  protected
    procedure DoHandleRequest(ARequest: TRequest; AResponse: TResponse); virtual;
  public
    destructor Destroy; override;
    procedure HandleRequest(ARequest: TRequest; AResponse: TResponse);
    procedure ExtractParams(const ASegs: TArrayOfString; AParams: TStrings);
    function Matches(const APattern: String; AMethod: TRouteMethod; Options: TRouteOptions): Boolean;
    function MatchPattern(const Path: String; L: TStrings; Options: TRouteOptions): Boolean;
    function MatchMethod(const AMethod: TRouteMethod): Boolean;
    property PatternSegments: TArrayOfString read FPatternSegments;
  published
    property Default: Boolean read FDefault write FDefault;
    property URLPattern: String read FURLPattern write SetURLPattern;
    property Method: TRouteMethod read FMethod write FMethod;
  end;
  THTTPRouteClass = class of THTTPRoute;

  { THTTPRouteList }

  THTTPRouteList = class(TCollection)
  private
    function GetR(AIndex: Integer): THTTPRoute;
    procedure SetR(AIndex: Integer; AValue: THTTPRoute);
  public
    property Routes[AIndex: Integer]: THTTPRoute read GetR write SetR; default;
  end;

  TRouteCallBack = procedure(ARequest: TRequest; AResponse: TResponse);

  { THTTPRouteCallback }

  THTTPRouteCallback = class(THTTPRoute)
  private
    FCallBack: TRouteCallBack;
  protected
    procedure DoHandleRequest(ARequest: TRequest; AResponse: TResponse); override;
  public
    property CallBack: TRouteCallBack read FCallBack write FCallBack;
  end;

  TRouteCallBackEx = procedure(AData: Pointer; ARequest: TRequest; AResponse: TResponse);

  { THTTPRouteCallbackEx }

  THTTPRouteCallbackEx = class(THTTPRoute)
  private
    FCallBack: TRouteCallBackEx;
    FData: Pointer;
  protected
    procedure DoHandleRequest(ARequest: TRequest; AResponse: TResponse); override;
  public
    property CallBack: TRouteCallBackEx read FCallBack write FCallBack;
    property Data: Pointer read FData write FData;
  end;

  TRouteEvent = procedure(ARequest: TRequest; AResponse: TResponse) of object;

  { THTTPRouteEvent }

  THTTPRouteEvent = class(THTTPRoute)
  private
    FEvent: TRouteEvent;
  protected
    procedure DoHandleRequest(ARequest: TRequest; AResponse: TResponse); override;
  public
    property Event: TRouteEvent read FEvent write FEvent;
  end;

{$INTERFACES CORBA}
  IRouteInterface = interface ['{10115353-10BA-4B00-FDA5-80B69AC4CAD0}']
    procedure HandleRequest(ARequest: TRequest; AResponse: TResponse);
  end;

  { THTTPRouteInterface }

  THTTPRouteInterface = class(THTTPRoute)
  private
    FIntf: IRouteInterface;
  protected
    procedure DoHandleRequest(ARequest: TRequest; AResponse: TResponse); override;
  public
    property Intf: IRouteInterface read FIntf write FIntf;
  end;

  TRouteObject = class(TObject, IRouteInterface)
  public
    constructor Create; virtual;
    procedure HandleRequest(ARequest: TRequest; AResponse: TResponse); virtual; abstract;
  end;
  TRouteObjectClass = class of TRouteObject;

  { THTTPRouteObject }

  THTTPRouteObject = class(THTTPRoute)
  private
    FClass: TRouteObjectClass;
  protected
    procedure DoHandleRequest(ARequest: TRequest; AResponse: TResponse); override;
  public
    property ObjectClass: TRouteObjectClass read FClass write FClass;
  end;

  THTTPRouteRequestEvent = procedure(Sender: TObject; ARequest: TRequest; AResponse: TResponse) of object;

  { THTTPRouter }

  THTTPRouter = class(TComponent)
  private
    FAfterRequest: THTTPRouteRequestEvent;
    FBeforeRequest: THTTPRouteRequestEvent;
    FRouteOptions: TRouteOptions;
    FRoutes: THTTPRouteList;
    FRootNode: TObject; // Internal root TRadixNode instance
    FDefaultRoutes: array[TRouteMethod] of THTTPRoute;
    function GetR(AIndex: Integer): THTTPRoute;
    class procedure DoneService;
    class var
      FService: THTTPRouter;
      FServiceClass: THTTPRouterClass;
    function GetRouteCount: Integer;
    procedure InsertRouteToTree(ARoute: THTTPRoute);
  protected
    function CreateHTTPRoute(AClass: THTTPRouteClass; const APattern: String; AMethod: TRouteMethod; IsDefault: Boolean): THTTPRoute; virtual;
    function CreateRouteList: THTTPRouteList; virtual;
    procedure CheckDuplicate(APattern: String; AMethod: TRouteMethod; isDefault: Boolean);
    procedure DoRouteRequest(ARequest: TRequest; AResponse: TResponse); virtual;
    function GetRequestPath(ARequest: TRequest): String; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RebuildRadixTree;
    procedure DeleteRoute(AIndex: Integer);
    procedure DeleteRouteByID(AID: Integer);
    procedure DeleteRoute(ARoute: THTTPRoute);
    class function SanitizeRoute(const Path: String): String;
    class function Service: THTTPRouter;
    class function ServiceClass: THTTPRouterClass;
    class procedure SetServiceClass(AClass: THTTPRouterClass);
    class function StringToRouteMethod(const S: String): TRouteMethod;
    function RegisterRoute(const APattern: String; AEvent: TRouteEvent; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; AMethod: TRouteMethod; AEvent: TRouteEvent; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; const AIntf: IRouteInterface; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; AMethod: TRouteMethod; const AIntf: IRouteInterface; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; const AObjectClass: TRouteObjectClass; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; AMethod: TRouteMethod; const AObjectClass: TRouteObjectClass; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; AData: Pointer; ACallBack: TRouteCallBackEx; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; AData: Pointer; AMethod: TRouteMethod; ACallBack: TRouteCallBackEx; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; ACallBack: TRouteCallBack; IsDefault: Boolean = False): THTTPRoute; overload;
    function RegisterRoute(const APattern: String; AMethod: TRouteMethod; ACallBack: TRouteCallBack; IsDefault: Boolean = False): THTTPRoute; overload;
    function FindHTTPRoute(const Path: String; AMethod: TRouteMethod; Params: TStrings; out MethodMismatch: Boolean): THTTPRoute;
    function GetHTTPRoute(const Path: String; AMethod: TRouteMethod; Params: TStrings): THTTPRoute;
    procedure RouteRequest(ARequest: TRequest; AResponse: TResponse);
    property Routes[AIndex: Integer]: THTTPRoute read GetR; default;
    property RouteCount: Integer read GetRouteCount;
    property BeforeRequest: THTTPRouteRequestEvent read FBeforeRequest write FBeforeRequest;
    property AfterRequest: THTTPRouteRequestEvent read FAfterRequest write FAfterRequest;
    property RouteOptions: TRouteOptions read FRouteOptions write FRouteOptions;
  end;

function RouteMethodToString(R: TRouteMethod): String;
function HTTPRouter: THTTPRouter;
function SplitPathSegments(const APath: string): TArrayOfString;

const
  RouteMethodNames: array[TRouteMethod] of String = (
    '', '', 'GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'HEAD', 'TRACE', 'PATCH', 'CONNECT'
  );

implementation

uses strutils, typinfo, Zenith.Gzip, Zenith.Idempotency;

resourcestring
  EDuplicateRoute = 'Duplicate route pattern: %s and method: %s';
  EDuplicateDefaultRoute = 'Duplicate default route registered with pattern: %s and method: %s';

type
  TSegmentKind = (skStatic, skParam, skWildcard);

  { TRadixNode }

  TRadixNode = class
  private
    FSegment: string;          // Segment literal or param/wildcard variable name
    FKind: TSegmentKind;       // skStatic, skParam, skWildcard
    FStaticChildren: array of TRadixNode;
    FStaticCount: Integer;
    FParamChild: TRadixNode;    // Prioridade 2 (:param)
    FWildcardChild: TRadixNode; // Prioridade 3 (*wildcard)
    FRoutes: array[TRouteMethod] of THTTPRoute;
    FParamNames: array[TRouteMethod] of string; // Nome de parametro especifico por metodo
    FHasRoutes: Boolean;
    procedure EnsureStaticCapacity;
  public
    constructor Create(const ASegment: string; AKind: TSegmentKind);
    destructor Destroy; override;

    function FindStaticChild(const ASeg: string; ACaseSensitive: Boolean): TRadixNode;
    function GetOrCreateStaticChild(const ASeg: string; ACaseSensitive: Boolean): TRadixNode;
    function GetOrCreateParamChild(const AParamName: string): TRadixNode;
    function GetOrCreateWildcardChild(const AWildcardName: string): TRadixNode;

    procedure SetParamName(AMethod: TRouteMethod; const AParamName: string);
    function GetParamName(AMethod: TRouteMethod): string;

    procedure SetRoute(AMethod: TRouteMethod; ARoute: THTTPRoute);
    function FindRouteForMethod(AMethod: TRouteMethod; out AMethodMismatch: Boolean): THTTPRoute;

    property Segment: string read FSegment;
    property Kind: TSegmentKind read FKind;
    property HasRoutes: Boolean read FHasRoutes;
    property ParamChild: TRadixNode read FParamChild;
    property WildcardChild: TRadixNode read FWildcardChild;
  end;

{ TRadixNode Implementation }

constructor TRadixNode.Create(const ASegment: string; AKind: TSegmentKind);
var
  M: TRouteMethod;
begin
  inherited Create;
  FSegment := ASegment;
  FKind := AKind;
  FStaticCount := 0;
  SetLength(FStaticChildren, 0);
  FParamChild := nil;
  FWildcardChild := nil;
  FHasRoutes := False;
  for M := Low(TRouteMethod) to High(TRouteMethod) do
  begin
    FRoutes[M] := nil;
    FParamNames[M] := '';
  end;
  if AKind in [skParam, skWildcard] then
    FParamNames[rmAll] := ASegment;
end;

destructor TRadixNode.Destroy;
var
  I: Integer;
begin
  for I := 0 to FStaticCount - 1 do
    FreeAndNil(FStaticChildren[I]);
  SetLength(FStaticChildren, 0);
  FreeAndNil(FParamChild);
  FreeAndNil(FWildcardChild);
  inherited Destroy;
end;

procedure TRadixNode.EnsureStaticCapacity;
begin
  if FStaticCount >= Length(FStaticChildren) then
  begin
    if Length(FStaticChildren) = 0 then
      SetLength(FStaticChildren, 4)
    else
      SetLength(FStaticChildren, Length(FStaticChildren) * 2);
  end;
end;

function TRadixNode.FindStaticChild(const ASeg: string; ACaseSensitive: Boolean): TRadixNode;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FStaticCount - 1 do
  begin
    if ACaseSensitive then
    begin
      if FStaticChildren[I].FSegment = ASeg then
        Exit(FStaticChildren[I]);
    end
    else
    begin
      if SameText(FStaticChildren[I].FSegment, ASeg) then
        Exit(FStaticChildren[I]);
    end;
  end;
end;

function TRadixNode.GetOrCreateStaticChild(const ASeg: string; ACaseSensitive: Boolean): TRadixNode;
begin
  Result := FindStaticChild(ASeg, ACaseSensitive);
  if Result = nil then
  begin
    EnsureStaticCapacity;
    Result := TRadixNode.Create(ASeg, skStatic);
    FStaticChildren[FStaticCount] := Result;
    Inc(FStaticCount);
  end;
end;

function TRadixNode.GetOrCreateParamChild(const AParamName: string): TRadixNode;
begin
  if FParamChild = nil then
    FParamChild := TRadixNode.Create(AParamName, skParam);
  Result := FParamChild;
end;

function TRadixNode.GetOrCreateWildcardChild(const AWildcardName: string): TRadixNode;
begin
  if FWildcardChild = nil then
    FWildcardChild := TRadixNode.Create(AWildcardName, skWildcard);
  Result := FWildcardChild;
end;

procedure TRadixNode.SetParamName(AMethod: TRouteMethod; const AParamName: string);
var
  M: TRouteMethod;
begin
  if AParamName = '' then Exit;
  if AMethod = rmAll then
  begin
    for M := Low(TRouteMethod) to High(TRouteMethod) do
      if FParamNames[M] = '' then
        FParamNames[M] := AParamName;
    FParamNames[rmAll] := AParamName;
  end
  else
    FParamNames[AMethod] := AParamName;
end;

function TRadixNode.GetParamName(AMethod: TRouteMethod): string;
begin
  Result := '';
  if (AMethod in [Low(TRouteMethod)..High(TRouteMethod)]) and (FParamNames[AMethod] <> '') then
    Result := FParamNames[AMethod]
  else if FParamNames[rmAll] <> '' then
    Result := FParamNames[rmAll]
  else
    Result := FSegment;
end;

procedure TRadixNode.SetRoute(AMethod: TRouteMethod; ARoute: THTTPRoute);
begin
  FRoutes[AMethod] := ARoute;
  FHasRoutes := True;
end;

function TRadixNode.FindRouteForMethod(AMethod: TRouteMethod; out AMethodMismatch: Boolean): THTTPRoute;
var
  M: TRouteMethod;
  AnyRoute: Boolean;
begin
  Result := nil;
  AMethodMismatch := False;
  if not FHasRoutes then Exit;

  // 1. Direct method match
  if FRoutes[AMethod] <> nil then
  begin
    Result := FRoutes[AMethod];
    Exit;
  end;

  // 2. Fallback to rmAll wildcard method
  if FRoutes[rmAll] <> nil then
  begin
    Result := FRoutes[rmAll];
    Exit;
  end;

  // 3. Check if any route is registered for another method on this node
  AnyRoute := False;
  for M := Low(TRouteMethod) to High(TRouteMethod) do
  begin
    if FRoutes[M] <> nil then
    begin
      AnyRoute := True;
      Break;
    end;
  end;

  if AnyRoute then
    AMethodMismatch := True;
end;

{ Helper Functions }

function SplitPathSegments(const APath: string): TArrayOfString;
var
  Len, I, SegStart: Integer;
  Seg: string;
  Count: Integer;
begin
  Result := nil;
  SetLength(Result, 8);
  Count := 0;
  Len := Length(APath);
  I := 1;
  while (I <= Len) and (APath[I] <> '?') do
  begin
    while (I <= Len) and (APath[I] = '/') do
      Inc(I);
    if (I > Len) or (APath[I] = '?') then
      Break;
    SegStart := I;
    while (I <= Len) and (APath[I] <> '/') and (APath[I] <> '?') do
      Inc(I);
    Seg := Copy(APath, SegStart, I - SegStart);
    if Seg <> '' then
    begin
      if Count >= Length(Result) then
        SetLength(Result, Length(Result) * 2);
      Result[Count] := Seg;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function MatchRadix(ANode: TRadixNode; const ASegs: TArrayOfString; ASegIdx, ASegTotal: Integer;
  AMethod: TRouteMethod; AParams: TStrings; AOptions: TRouteOptions;
  var AMethodMismatch: Boolean): THTTPRoute;
var
  StaticNode: TRadixNode;
  ParamStartCount: Integer;
  RestPath: string;
  I: Integer;
  SubMismatch: Boolean;
begin
  Result := nil;
  if ANode = nil then Exit;

  // 1. Base case: Reached the end of the requested URL segments
  if ASegIdx >= ASegTotal then
  begin
    if ANode.HasRoutes then
    begin
      SubMismatch := False;
      Result := ANode.FindRouteForMethod(AMethod, SubMismatch);
      if SubMismatch then
        AMethodMismatch := True;
      if Result <> nil then
        Exit;
    end;

    // If no direct route matched on this node, check if a wildcard child can consume empty remainder:
    if (ANode.WildcardChild <> nil) and ANode.WildcardChild.HasRoutes then
    begin
      SubMismatch := False;
      Result := ANode.WildcardChild.FindRouteForMethod(AMethod, SubMismatch);
      if SubMismatch then
        AMethodMismatch := True;
      if Result <> nil then
      begin
        if AParams <> nil then
          AParams.Values[ANode.WildcardChild.GetParamName(AMethod)] := '';
        Exit;
      end;
    end;

    Exit;
  end;

  // 2. Still have segments to process (ASegIdx < ASegTotal)

  // PRIORITY 1 (HIGHEST): Static Literal Node
  StaticNode := ANode.FindStaticChild(ASegs[ASegIdx], roCaseSensitive in AOptions);
  if StaticNode <> nil then
  begin
    SubMismatch := False;
    Result := MatchRadix(StaticNode, ASegs, ASegIdx + 1, ASegTotal, AMethod, AParams, AOptions, SubMismatch);
    if SubMismatch then
      AMethodMismatch := True;
    if Result <> nil then
      Exit;
  end;

  // PRIORITY 2: Parametric Node (:param)
  if ANode.ParamChild <> nil then
  begin
    ParamStartCount := 0;
    if AParams <> nil then
    begin
      ParamStartCount := AParams.Count;
      AParams.Values[ANode.ParamChild.GetParamName(AMethod)] := ASegs[ASegIdx];
    end;

    SubMismatch := False;
    Result := MatchRadix(ANode.ParamChild, ASegs, ASegIdx + 1, ASegTotal, AMethod, AParams, AOptions, SubMismatch);
    if SubMismatch then
      AMethodMismatch := True;
    if Result <> nil then
      Exit;

    // If a deeper branch failed, revert added parameters for backtracking
    if AParams <> nil then
    begin
      while AParams.Count > ParamStartCount do
        AParams.Delete(AParams.Count - 1);
    end;
  end;

  // PRIORITY 3 (LOWEST): Wildcard Node (*wildcard)
  if (ANode.WildcardChild <> nil) and ANode.WildcardChild.HasRoutes then
  begin
    SubMismatch := False;
    Result := ANode.WildcardChild.FindRouteForMethod(AMethod, SubMismatch);
    if SubMismatch then
      AMethodMismatch := True;
    if Result <> nil then
    begin
      if AParams <> nil then
      begin
        RestPath := '';
        for I := ASegIdx to ASegTotal - 1 do
        begin
          if I > ASegIdx then
            RestPath := RestPath + '/' + ASegs[I]
          else
            RestPath := ASegs[I];
        end;
        AParams.Values[ANode.WildcardChild.GetParamName(AMethod)] := RestPath;
      end;
      Exit;
    end;
  end;
end;

function RouteMethodToString(R: TRouteMethod): String;
begin
  if R = rmUnknown then
    Result := ''
  else if R = rmAll then
    Result := '*'
  else
    Result := RouteMethodNames[R];
end;

function HTTPRouter: THTTPRouter;
begin
  Result := THTTPRouter.Service;
end;

{ THTTPRouteCallback }

procedure THTTPRouteCallback.DoHandleRequest(ARequest: TRequest; AResponse: TResponse);
begin
  if Assigned(FCallBack) then
    FCallBack(ARequest, AResponse);
end;

{ THTTPRouteCallbackEx }

procedure THTTPRouteCallbackEx.DoHandleRequest(ARequest: TRequest; AResponse: TResponse);
begin
  if Assigned(FCallBack) then
    FCallBack(FData, ARequest, AResponse);
end;

{ THTTPRouteEvent }

procedure THTTPRouteEvent.DoHandleRequest(ARequest: TRequest; AResponse: TResponse);
begin
  if Assigned(FEvent) then
    FEvent(ARequest, AResponse);
end;

{ THTTPRouteInterface }

procedure THTTPRouteInterface.DoHandleRequest(ARequest: TRequest; AResponse: TResponse);
begin
  if Assigned(FIntf) then
    FIntf.HandleRequest(ARequest, AResponse);
end;

{ TRouteObject }

constructor TRouteObject.Create;
begin
  // Allow descendants to override
end;

{ THTTPRouteObject }

procedure THTTPRouteObject.DoHandleRequest(ARequest: TRequest; AResponse: TResponse);
var
  O: TRouteObject;
begin
  if Assigned(ObjectClass) then
  begin
    O := ObjectClass.Create;
    try
      O.HandleRequest(ARequest, AResponse);
    finally
      O.Free;
    end;
  end;
end;

{ THTTPRouteList }

function THTTPRouteList.GetR(AIndex: Integer): THTTPRoute;
begin
  Result := Items[AIndex] as THTTPRoute;
end;

procedure THTTPRouteList.SetR(AIndex: Integer; AValue: THTTPRoute);
begin
  Items[AIndex] := AValue;
end;

{ THTTPRoute }

procedure THTTPRoute.SetURLPattern(AValue: String);
var
  V: String;
begin
  V := IncludeHTTPPathDelimiter(AValue);
  if (V <> '') and (V <> '/') and (V[1] = '/') then
    Delete(V, 1, 1);
  if FURLPattern = V then Exit;
  FURLPattern := V;
  FPatternSegments := SplitPathSegments(FURLPattern);
  if (Collection <> nil) and (Collection.Owner is THTTPRouter) then
    THTTPRouter(Collection.Owner).RebuildRadixTree;
end;

destructor THTTPRoute.Destroy;
begin
  SetLength(FPatternSegments, 0);
  inherited Destroy;
end;

procedure THTTPRoute.ExtractParams(const ASegs: TArrayOfString; AParams: TStrings);
var
  I, J: Integer;
  Seg, ParamName, RestPath: string;
begin
  if AParams = nil then Exit;
  for I := 0 to High(FPatternSegments) do
  begin
    Seg := FPatternSegments[I];
    if (Length(Seg) > 0) and (Seg[1] = ':') then
    begin
      ParamName := Copy(Seg, 2, MaxInt);
      if I <= High(ASegs) then
        AParams.Values[ParamName] := ASegs[I]
      else
        AParams.Values[ParamName] := '';
    end
    else if (Length(Seg) > 0) and (Seg[1] = '*') then
    begin
      ParamName := Copy(Seg, 2, MaxInt);
      RestPath := '';
      for J := I to High(ASegs) do
      begin
        if J > I then
          RestPath := RestPath + '/' + ASegs[J]
        else
          RestPath := ASegs[J];
      end;
      AParams.Values[ParamName] := RestPath;
      Break;
    end;
  end;
end;

procedure THTTPRoute.DoHandleRequest(ARequest: TRequest; AResponse: TResponse);
begin
  // Virtual base: implemented in subclasses
end;

procedure THTTPRoute.HandleRequest(ARequest: TRequest; AResponse: TResponse);
begin
  DoHandleRequest(ARequest, AResponse);
end;

function THTTPRoute.Matches(const APattern: String; AMethod: TRouteMethod; Options: TRouteOptions): Boolean;
begin
  Result := ((Method = rmAll) or (AMethod = Method));
  if Result then
    Result := SameText(URLPattern, APattern) or ((URLPattern = '') and (roEmptyMatchesAll in Options));
end;

function THTTPRoute.MatchMethod(const AMethod: TRouteMethod): Boolean;
begin
  Result := (Method = rmAll) or (Method = AMethod);
end;

function THTTPRoute.MatchPattern(const Path: String; L: TStrings; Options: TRouteOptions): Boolean;

  function StartsWith(C: Char; S: String): Boolean;
  begin
    Result := (Length(S) > 0) and (S[1] = C);
  end;

  function EndsWith(C: Char; S: String): Boolean;
  var
    Len: Integer;
  begin
    Len := Length(S);
    Result := (Len > 0) and (S[Len] = C);
  end;

  function SameString(A, B: String): Boolean;
  begin
    if roCaseSensitive in Options then
      Result := (A = B)
    else
      Result := SameText(A, B);
  end;

  procedure ExtractNextPathLevel(var ALeft: string; var ALvl: string; var ARight: string; const ADelim: Char = '/');
  var
    P: Integer;
  begin
    if (ALvl <> ADelim) then
    begin
      ALeft := ALeft + ALvl;
      if StartsWith(ADelim, ARight) then
      begin
        ALeft := ALeft + ADelim;
        Delete(ARight, 1, 1);
      end;
    end;
    P := Pos(ADelim, ARight);
    if P = 0 then
      P := Length(ARight) + 1;
    ALvl := Copy(ARight, 1, P - 1);
    ARight := Copy(ARight, P, MaxInt);
  end;

  procedure ExtractPrevPathLevel(var ALeft: string; var ALvl: string; var ARight: string; const ADelim: Char = '/');
  var
    P, Len: Integer;
  begin
    if (ALvl <> ADelim) then
    begin
      ARight := ALvl + ARight;
      Len := Length(ALeft);
      if EndsWith(ADelim, ALeft) then
      begin
        ARight := ADelim + ARight;
        Delete(ALeft, Len, 1);
      end;
    end;
    P := RPos(ADelim, ALeft);
    ALvl := Copy(ALeft, P + 1, MaxInt);
    ALeft := Copy(ALeft, 1, P);
  end;

var
  APathInfo: String;
  APattern: String;
  VLeftPat, VRightPat, VLeftVal, VRightVal, VVal, VPat, VName: string;

begin
  Result := False;
  if (URLPattern = '') then
    Exit(roEmptyMatchesAll in Options);
  APathInfo := Path;
  APattern := URLPattern;
  Delete(APattern, Pos('?', APattern), MaxInt);
  Delete(APathInfo, Pos('?', APathInfo), MaxInt);
  if StartsWith('/', APattern) then
    Delete(APattern, 1, 1);
  if StartsWith('/', APathInfo) then
    Delete(APathInfo, 1, 1);
  VLeftPat := '';
  VLeftVal := '';
  VPat := '/';
  VVal := '/';
  VRightPat := APattern;
  VRightVal := APathInfo;
  repeat
    ExtractNextPathLevel(VLeftPat, VPat, VRightPat);
    ExtractNextPathLevel(VLeftVal, VVal, VRightVal);
    if StartsWith(':', VPat) then
    begin
      if L <> nil then
        L.Values[Copy(VPat, 2, MaxInt)] := VVal;
    end
    else if StartsWith('*', VPat) then
    begin
      VName := Copy(VPat, 2, MaxInt);
      VLeftPat := VRightPat;
      VLeftVal := VVal + VRightVal;
      VPat := '/';
      VVal := '/';
      VRightPat := '';
      VRightVal := '';
      if EndsWith('/', VLeftPat) and not EndsWith('/', VLeftVal) then
        Delete(VLeftPat, Length(VLeftPat), 1);
      repeat
        ExtractPrevPathLevel(VLeftPat, VPat, VRightPat);
        ExtractPrevPathLevel(VLeftVal, VVal, VRightVal);
        if StartsWith(':', VPat) then
        begin
          if L <> nil then
            L.Values[Copy(VPat, 2, MaxInt)] := VVal;
        end
        else
        begin
          if not ((VPat = '') and (VLeftPat = '')) and not SameString(VPat, VVal) then
            Exit;
        end;
        if (VLeftPat = '') or (VLeftVal = '') then
        begin
          if VLeftPat = '' then
          begin
            if (VName <> '') and (L <> nil) then
              L.Values[VName] := VLeftVal + VVal;
            Result := True;
          end;
          Exit;
        end;
      until False;
    end
    else
    begin
      if not SameString(VPat, VVal) then
        Exit;
    end;

    if (VRightPat = '') or (VRightVal = '') then
    begin
      if (VRightPat = '') and (VRightVal = '') then
        Result := True
      else if (VRightPat = '/') then
        Result := True;
      Exit;
    end;
  until False;
end;

{ THTTPRouter }

constructor THTTPRouter.Create(AOwner: TComponent);
var
  M: TRouteMethod;
begin
  inherited Create(AOwner);
  FRootNode := TRadixNode.Create('', skStatic);
  for M := Low(TRouteMethod) to High(TRouteMethod) do
    FDefaultRoutes[M] := nil;
  FRoutes := CreateRouteList;
end;

destructor THTTPRouter.Destroy;
begin
  FreeAndNil(FRoutes);
  FreeAndNil(FRootNode);
  inherited Destroy;
end;

function THTTPRouter.GetR(AIndex: Integer): THTTPRoute;
begin
  Result := FRoutes[AIndex];
end;

function THTTPRouter.GetRouteCount: Integer;
begin
  Result := FRoutes.Count;
end;

function THTTPRouter.CreateRouteList: THTTPRouteList;
begin
  Result := THTTPRouteList.Create(THTTPRoute);
end;

procedure THTTPRouter.InsertRouteToTree(ARoute: THTTPRoute);
var
  Segs: TArrayOfString;
  CurrNode: TRadixNode;
  I: Integer;
  Seg, ParamName: string;
begin
  if ARoute = nil then Exit;
  if ARoute.Default then
  begin
    FDefaultRoutes[ARoute.Method] := ARoute;
    if ARoute.Method = rmAll then
      FDefaultRoutes[rmAll] := ARoute;
    Exit;
  end;

  if Length(ARoute.PatternSegments) > 0 then
    Segs := ARoute.PatternSegments
  else
    Segs := SplitPathSegments(ARoute.URLPattern);
  CurrNode := TRadixNode(FRootNode);

  for I := 0 to High(Segs) do
  begin
    Seg := Segs[I];
    if (Length(Seg) > 0) and (Seg[1] = '*') then
    begin
      ParamName := Copy(Seg, 2, MaxInt);
      CurrNode := CurrNode.GetOrCreateWildcardChild(ParamName);
      CurrNode.SetParamName(ARoute.Method, ParamName);
      Break; // Wildcard is always terminal
    end
    else if (Length(Seg) > 0) and (Seg[1] = ':') then
    begin
      ParamName := Copy(Seg, 2, MaxInt);
      CurrNode := CurrNode.GetOrCreateParamChild(ParamName);
      CurrNode.SetParamName(ARoute.Method, ParamName);
    end
    else
    begin
      CurrNode := CurrNode.GetOrCreateStaticChild(Seg, roCaseSensitive in FRouteOptions);
    end;
  end;

  CurrNode.SetRoute(ARoute.Method, ARoute);
end;

procedure THTTPRouter.RebuildRadixTree;
var
  I: Integer;
  M: TRouteMethod;
begin
  FreeAndNil(FRootNode);
  FRootNode := TRadixNode.Create('', skStatic);
  for M := Low(TRouteMethod) to High(TRouteMethod) do
    FDefaultRoutes[M] := nil;

  if FRoutes <> nil then
  begin
    for I := 0 to FRoutes.Count - 1 do
      InsertRouteToTree(FRoutes[I]);
  end;
end;

procedure THTTPRouter.DeleteRoute(AIndex: Integer);
begin
  FRoutes.Delete(AIndex);
  RebuildRadixTree;
end;

procedure THTTPRouter.DeleteRouteByID(AID: Integer);
var
  Item: TCollectionItem;
begin
  Item := FRoutes.FindItemID(AID);
  if Item <> nil then
  begin
    Item.Free;
    RebuildRadixTree;
  end;
end;

procedure THTTPRouter.DeleteRoute(ARoute: THTTPRoute);
begin
  ARoute.Free;
  RebuildRadixTree;
end;

procedure THTTPRouter.CheckDuplicate(APattern: String; AMethod: TRouteMethod; isDefault: Boolean);
var
  I, DI: Integer;
  R: THTTPRoute;
begin
  DI := -1;
  for I := 0 to FRoutes.Count - 1 do
  begin
    R := FRoutes[I];
    if R.Default then
      DI := I;
    if R.Matches(APattern, AMethod, FRouteOptions) then
      raise EHTTPRoute.CreateFmt(EDuplicateRoute, [APattern, RouteMethodToString(AMethod)]);
  end;
  if isDefault and (DI <> -1) then
    raise EHTTPRoute.CreateFmt(EDuplicateDefaultRoute, [APattern, RouteMethodToString(AMethod)]);
end;

function THTTPRouter.CreateHTTPRoute(AClass: THTTPRouteClass; const APattern: String;
  AMethod: TRouteMethod; IsDefault: Boolean): THTTPRoute;
begin
  CheckDuplicate(APattern, AMethod, IsDefault);
  Result := AClass.Create(FRoutes);
  with Result do
  begin
    URLPattern := APattern;
    Default := IsDefault;
    Method := AMethod;
  end;
  InsertRouteToTree(Result);
end;

class function THTTPRouter.SanitizeRoute(const Path: String): String;
var
  APathInfo: String;
begin
  APathInfo := Path;
  Delete(APathInfo, Pos('?', APathInfo), MaxInt);
  Result := IncludeHTTPPathDelimiter(APathInfo);
end;

class function THTTPRouter.Service: THTTPRouter;
begin
  if FService = nil then
    FService := ServiceClass.Create(nil);
  Result := FService;
end;

class function THTTPRouter.ServiceClass: THTTPRouterClass;
begin
  if FServiceClass = nil then
    FServiceClass := THTTPRouter;
  Result := FServiceClass;
end;

class procedure THTTPRouter.SetServiceClass(AClass: THTTPRouterClass);
begin
  if Assigned(FService) then
    FreeAndNil(FService);
  FServiceClass := AClass;
end;

class procedure THTTPRouter.DoneService;
begin
  FreeAndNil(FService);
end;

class function THTTPRouter.StringToRouteMethod(const S: String): TRouteMethod;
var
  MN: String;
begin
  Result := High(TRouteMethod);
  MN := UpperCase(S);
  while (Result > Low(TRouteMethod)) and (RouteMethodNames[Result] <> MN) do
    Result := Pred(Result);
  if Result = rmAll then
    Result := rmUnknown;
end;

function THTTPRouter.RegisterRoute(const APattern: String; AData: Pointer;
  ACallBack: TRouteCallBackEx; IsDefault: Boolean): THTTPRoute;
begin
  Result := RegisterRoute(APattern, AData, rmAll, ACallBack, IsDefault);
end;

function THTTPRouter.RegisterRoute(const APattern: String; AData: Pointer;
  AMethod: TRouteMethod; ACallBack: TRouteCallBackEx; IsDefault: Boolean): THTTPRoute;
begin
  Result := CreateHTTPRoute(THTTPRouteCallbackEx, APattern, AMethod, IsDefault);
  THTTPRouteCallbackEx(Result).CallBack := ACallBack;
  THTTPRouteCallbackEx(Result).Data := AData;
end;

function THTTPRouter.RegisterRoute(const APattern: String; ACallBack: TRouteCallBack;
  IsDefault: Boolean): THTTPRoute;
begin
  Result := RegisterRoute(APattern, rmAll, ACallBack, IsDefault);
end;

function THTTPRouter.RegisterRoute(const APattern: String; AMethod: TRouteMethod;
  ACallBack: TRouteCallBack; IsDefault: Boolean): THTTPRoute;
begin
  Result := CreateHTTPRoute(THTTPRouteCallback, APattern, AMethod, IsDefault);
  THTTPRouteCallback(Result).CallBack := ACallBack;
end;

function THTTPRouter.RegisterRoute(const APattern: String; AEvent: TRouteEvent;
  IsDefault: Boolean): THTTPRoute;
begin
  Result := RegisterRoute(APattern, rmAll, AEvent, IsDefault);
end;

function THTTPRouter.RegisterRoute(const APattern: String; AMethod: TRouteMethod;
  AEvent: TRouteEvent; IsDefault: Boolean): THTTPRoute;
begin
  Result := CreateHTTPRoute(THTTPRouteEvent, APattern, AMethod, IsDefault);
  THTTPRouteEvent(Result).Event := AEvent;
end;

function THTTPRouter.RegisterRoute(const APattern: String; const AIntf: IRouteInterface;
  IsDefault: Boolean): THTTPRoute;
begin
  Result := RegisterRoute(APattern, rmAll, AIntf, IsDefault);
end;

function THTTPRouter.RegisterRoute(const APattern: String; AMethod: TRouteMethod;
  const AIntf: IRouteInterface; IsDefault: Boolean): THTTPRoute;
begin
  Result := CreateHTTPRoute(THTTPRouteInterface, APattern, AMethod, IsDefault);
  THTTPRouteInterface(Result).Intf := AIntf;
end;

function THTTPRouter.RegisterRoute(const APattern: String; const AObjectClass: TRouteObjectClass;
  IsDefault: Boolean): THTTPRoute;
begin
  Result := RegisterRoute(APattern, rmAll, AObjectClass, IsDefault);
end;

function THTTPRouter.RegisterRoute(const APattern: String; AMethod: TRouteMethod;
  const AObjectClass: TRouteObjectClass; IsDefault: Boolean): THTTPRoute;
begin
  Result := CreateHTTPRoute(THTTPRouteObject, APattern, AMethod, IsDefault);
  THTTPRouteObject(Result).ObjectClass := AObjectClass;
end;

function THTTPRouter.FindHTTPRoute(const Path: String; AMethod: TRouteMethod; Params: TStrings;
  out MethodMismatch: Boolean): THTTPRoute;
var
  APathInfo: String;
  Segs: TArrayOfString;
  SegCount: Integer;
begin
  APathInfo := SanitizeRoute(Path);
  MethodMismatch := False;
  Result := nil;

  Segs := SplitPathSegments(APathInfo);
  SegCount := Length(Segs);

  // O(K) Radix Tree resolution
  Result := MatchRadix(TRadixNode(FRootNode), Segs, 0, SegCount, AMethod, Params, FRouteOptions, MethodMismatch);

  // If not found, search Default routes
  if Result = nil then
  begin
    if (AMethod in [Low(TRouteMethod)..High(TRouteMethod)]) and (FDefaultRoutes[AMethod] <> nil) then
      Result := FDefaultRoutes[AMethod]
    else if FDefaultRoutes[rmAll] <> nil then
      Result := FDefaultRoutes[rmAll];
  end;

  if Result <> nil then
  begin
    if Params <> nil then
    begin
      Params.Clear;
      Result.ExtractParams(Segs, Params);
    end;
  end
  else if Params <> nil then
    Params.Clear;
end;

function THTTPRouter.GetHTTPRoute(const Path: String; AMethod: TRouteMethod; Params: TStrings): THTTPRoute;
const
  Status: array[Boolean] of Integer = (404, 405);
  StatusText: array[Boolean] of String = ('Not found', 'Method not allowed');
var
  MethodMismatch: Boolean;
  E: EHTTPRoute;
begin
  Result := FindHTTPRoute(Path, AMethod, Params, MethodMismatch);
  if not Assigned(Result) then
  begin
    E := EHTTPRoute.Create(StatusText[MethodMismatch]);
    E.StatusText := StatusText[MethodMismatch];
    E.StatusCode := Status[MethodMismatch];
    raise E;
  end;
end;

function THTTPRouter.GetRequestPath(ARequest: TRequest): String;
begin
  Result := SanitizeRoute(ARequest.PathInfo);
end;

procedure THTTPRouter.DoRouteRequest(ARequest: TRequest; AResponse: TResponse);
var
  APath: String;
  AMethod: TRouteMethod;
  R: THTTPRoute;
  L: TStrings;
  I: Integer;
  N, V: string;
begin
  APath := GetRequestPath(ARequest);
  AMethod := StringToRouteMethod(ARequest.Method);
  L := TStringList.Create;
  try
    R := GetHTTPRoute(APath, AMethod, L);
    for I := 0 to L.Count - 1 do
    begin
      L.GetNameValue(I, N, V);
      if (N <> '') then
        ARequest.RouteParams[N] := V;
    end;
    R.HandleRequest(ARequest, AResponse);
  finally
    L.Free;
  end;
end;

procedure ClearCustomHeaderCaseInsensitive(AHeaders: TStrings; const AName: string);
var
  Idx, SepPos: Integer;
  Line, N, V: string;
begin
  if (not Assigned(AHeaders)) or (AHeaders.Count = 0) then
    Exit;
  for Idx := AHeaders.Count - 1 downto 0 do
  begin
    Line := Trim(AHeaders[Idx]);
    AHeaders.GetNameValue(Idx, N, V);
    if SameText(Trim(N), AName) then
    begin
      AHeaders.Delete(Idx);
      Continue;
    end;
    SepPos := Pos(':', Line);
    if SepPos = 0 then
      SepPos := Pos('=', Line);
    if SepPos > 0 then
    begin
      N := Trim(Copy(Line, 1, SepPos - 1));
      if SameText(N, AName) then
        AHeaders.Delete(Idx);
    end;
  end;
end;

procedure THTTPRouter.RouteRequest(ARequest: TRequest; AResponse: TResponse);
var
  AMethod: TRouteMethod;
  CT, CTBase: string;
  P: Integer;
  CE, AE: string;
  Compressed, RawContent: RawByteString;
  CompStream: TMemoryStream;
  StreamLen: Int64;
begin
  // 1. Inbound GZIP Decompression (Content-Encoding: gzip)
  CE := ARequest.ContentEncoding;
  if (CE = '') and (ARequest.CustomHeaders.Count > 0) then
    CE := ARequest.GetCustomHeader('Content-Encoding');

  if (CE <> '') and (Pos('gzip', LowerCase(Trim(CE))) > 0) and (Length(ARequest.Content) > 0) then
  begin
    try
      ARequest.Content := GZipDecompress(ARequest.Content);
      ARequest.ContentEncoding := '';
      ClearCustomHeaderCaseInsensitive(ARequest.CustomHeaders, 'Content-Encoding');
    except
      on E: Exception do
      begin
        AResponse.Code := 400;
        AResponse.ContentType := 'application/problem+json; charset=utf-8';
        AResponse.Content := '{"type":"urn:zenith:problem:invalid-gzip","title":"Bad Request","status":400,"detail":"Falha ao descompactar payload GZIP: ' + E.Message + '"}';
        AResponse.SendContent;
        Exit;
      end;
    end;
  end;

  // 2. Strict Content-Type Validation on Write Methods (POST, PUT, PATCH)
  AMethod := StringToRouteMethod(ARequest.Method);
  if AMethod in [rmPost, rmPut, rmPatch] then
  begin
    CT := Trim(ARequest.ContentType);
    if (CT = '') and (ARequest.CustomHeaders.Count > 0) then
      CT := Trim(ARequest.GetCustomHeader('Content-Type'));

    P := Pos(';', CT);
    if P > 0 then
      CTBase := LowerCase(Trim(Copy(CT, 1, P - 1)))
    else
      CTBase := LowerCase(CT);

    if CTBase = '' then
    begin
      // Mandatory default fallback: assume application/json
      ARequest.ContentType := 'application/json';
    end
    else
    begin
      // List of accepted canonical media types
      if not (
         (CTBase = 'application/json') or
         (CTBase = 'application/cbor') or
         (CTBase = 'application/bson') or
         (CTBase = 'application/x-bson') or
         (CTBase = 'application/xml') or
         (CTBase = 'text/xml') or
         (CTBase = 'text/csv') or
         (CTBase = 'application/csv') or
         (CTBase = 'application/x-www-form-urlencoded') or
         (CTBase = 'multipart/form-data') or
         (CTBase = 'application/problem+json') or
         (CTBase = 'application/octet-stream')
      ) then
      begin
        AResponse.Code := 400;
        AResponse.ContentType := 'application/problem+json; charset=utf-8';
        AResponse.Content := '{"type":"urn:zenith:problem:unsupported-media-type","title":"Bad Request","status":400,"detail":"Content-Type não suportado. Formatos aceitos: application/json, application/cbor, application/bson, application/xml, text/csv, application/x-www-form-urlencoded, multipart/form-data."}';
        AResponse.SendContent;
        Exit;
      end;
    end;
  end;

  // 3. Idempotency middleware validation (IETF Draft Idempotency-Key)
  if not TZenithIdempotency.ProcessBefore(ARequest, AResponse) then
  begin
    // Response short-circuited by middleware (400/409/422 RFC 9457 or cached replay)
    AE := ARequest.AcceptEncoding;
    if (AE = '') and (ARequest.CustomHeaders.Count > 0) then
      AE := ARequest.GetCustomHeader('Accept-Encoding');
    if (AE <> '') and (Pos('gzip', LowerCase(Trim(AE))) > 0) and (not AResponse.ContentSent) and
       ShouldGzipCompress(AResponse.ContentType, Length(AResponse.Content)) and
       ((AResponse.ContentEncoding = '') or (Pos('gzip', LowerCase(Trim(AResponse.ContentEncoding))) = 0)) then
    begin
      try
        Compressed := GZipCompress(AResponse.Content);
        CompStream := TMemoryStream.Create;
        if Length(Compressed) > 0 then
        begin
          CompStream.WriteBuffer(Compressed[1], Length(Compressed));
          CompStream.Position := 0;
        end;
        AResponse.Contents.Clear;
        AResponse.FreeContentStream := True;
        AResponse.ContentStream := CompStream;
        AResponse.ContentLength := CompStream.Size;
        ClearCustomHeaderCaseInsensitive(AResponse.CustomHeaders, 'Content-Encoding');
        AResponse.ContentEncoding := 'gzip';
      except
      end;
    end;
    AResponse.SendContent;
    Exit;
  end;

  if Assigned(FBeforeRequest) then
    FBeforeRequest(Self, ARequest, AResponse);

  try
    DoRouteRequest(ARequest, AResponse);
  except
    on E: Exception do
    begin
      TZenithIdempotency.ReleaseOnError(ARequest);
      raise;
    end;
  end;

  if Assigned(FAfterRequest) then
    FAfterRequest(Self, ARequest, AResponse);

  TZenithIdempotency.ProcessAfter(ARequest, AResponse);

  // 3. Outbound GZIP Compression (Accept-Encoding: gzip)
  AE := ARequest.AcceptEncoding;
  if (AE = '') and (ARequest.CustomHeaders.Count > 0) then
    AE := ARequest.GetCustomHeader('Accept-Encoding');

  if (AE <> '') and (Pos('gzip', LowerCase(Trim(AE))) > 0) and (not AResponse.ContentSent) and
     ((AResponse.ContentEncoding = '') or (Pos('gzip', LowerCase(Trim(AResponse.ContentEncoding))) = 0)) then
  begin
    RawContent := '';
    if Assigned(AResponse.ContentStream) then
    begin
      AResponse.ContentStream.Position := 0;
      StreamLen := AResponse.ContentStream.Size;
      if StreamLen > 0 then
      begin
        SetLength(RawContent, StreamLen);
        AResponse.ContentStream.ReadBuffer(RawContent[1], StreamLen);
      end;
    end
    else
      RawContent := AResponse.Content;

    if ShouldGzipCompress(AResponse.ContentType, Length(RawContent)) then
    begin
      try
        Compressed := GZipCompress(RawContent);
        CompStream := TMemoryStream.Create;
        if Length(Compressed) > 0 then
        begin
          CompStream.WriteBuffer(Compressed[1], Length(Compressed));
          CompStream.Position := 0;
        end;
        AResponse.Contents.Clear;
        AResponse.FreeContentStream := True;
        AResponse.ContentStream := CompStream;
        AResponse.ContentLength := CompStream.Size;
        ClearCustomHeaderCaseInsensitive(AResponse.CustomHeaders, 'Content-Encoding');
        AResponse.ContentEncoding := 'gzip';
      except
        // If compression fails, keep original payload
      end;
    end;
  end;

  // Final safeguard: ensure Content-Encoding is never present in CustomHeaders when native ContentEncoding is set,
  // or migrate Content-Encoding from CustomHeaders to native ContentEncoding to prevent duplicate HTTP headers.
  if AResponse.ContentEncoding <> '' then
    ClearCustomHeaderCaseInsensitive(AResponse.CustomHeaders, 'Content-Encoding')
  else if (AResponse.CustomHeaders.Count > 0) and (AResponse.GetCustomHeader('Content-Encoding') <> '') then
  begin
    AResponse.ContentEncoding := AResponse.GetCustomHeader('Content-Encoding');
    ClearCustomHeaderCaseInsensitive(AResponse.CustomHeaders, 'Content-Encoding');
  end;
end;

finalization
  THTTPRouter.DoneService;
end.
