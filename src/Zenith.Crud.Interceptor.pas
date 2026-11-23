unit Zenith.Crud.Interceptor;

{$IFDEF FPC}
  {$mode Delphi}{$H+}
{$ENDIF}

interface

uses
  Classes, SysUtils, HTTPDefs, TypInfo,
  Zenith.Security, Zenith.Messages,
  DeltaModel, DeltaModel.Generics;

type
  { CRUD Action types }
  TZCrudAction = (caList, caGet, caCreate, caUpdate, caDelete);

  { CRUD Interceptor Contract }
  IZenithCrudInterceptor<T: TDeltaModel> = interface
    ['{8E1A334B-529A-481C-9E4B-8EFA622E64A1}']
    function Authorize(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; out AReason: string): Boolean;
    procedure BeforeQuery(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; AQuery: TDeltaQuery<T>);
    procedure BeforeInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T);
    procedure AfterInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse);
    procedure BeforeUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AExistingModel, AInputModel: T);
    procedure AfterUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse);
    procedure BeforeDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64);
    procedure AfterDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64; AResponse: TResponse);
  end;

  { Base Default Interceptor (No-Op) }
  TZCrudInterceptor<T: TDeltaModel> = class(TInterfacedObject, IZenithCrudInterceptor<T>)
  public
    function Authorize(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; out AReason: string): Boolean; virtual;
    procedure BeforeQuery(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; AQuery: TDeltaQuery<T>); virtual;
    procedure BeforeInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T); virtual;
    procedure AfterInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse); virtual;
    procedure BeforeUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AExistingModel, AInputModel: T); virtual;
    procedure AfterUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse); virtual;
    procedure BeforeDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64); virtual;
    procedure AfterDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64; AResponse: TResponse); virtual;
  end;

  { Scope Mapping Record }
  TZScopeRule = record
    ModelField: string;
    ContextAttribute: string;
  end;

  { Declarative Fluent RBAC & Multi-Tenant Scoping Policy }
  TZRBACPolicy<T: TDeltaModel> = class(TZCrudInterceptor<T>)
  private
    FRequireAuth: Boolean;
    FAllowedRoles: array[TZCrudAction] of TStringList;
    FPermissionPrefix: string;
    FScopes: array of TZScopeRule;
  public
    constructor Create;
    destructor Destroy; override;

    function RequireAuth(AValue: Boolean = True): TZRBACPolicy<T>;
    function AllowRoles(AAction: TZCrudAction; const ARoles: array of string): TZRBACPolicy<T>;
    function AllowAllRoles(const ARoles: array of string): TZRBACPolicy<T>;
    function WithPermissionPrefix(const APrefix: string): TZRBACPolicy<T>;
    function WithScope(const AModelField, AContextAttribute: string): TZRBACPolicy<T>;

    function IsAuthRequired: Boolean;

    function Authorize(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; out AReason: string): Boolean; override;
    procedure BeforeQuery(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; AQuery: TDeltaQuery<T>); override;
    procedure BeforeInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T); override;
    procedure BeforeUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AExistingModel, AInputModel: T); override;
  end;

implementation

uses
  DeltaModel.Fields;

{ TZCrudInterceptor<T> }

function TZCrudInterceptor<T>.Authorize(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; out AReason: string): Boolean;
begin
  AReason := '';
  Result := True;
end;

procedure TZCrudInterceptor<T>.BeforeQuery(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; AQuery: TDeltaQuery<T>);
begin
  // No-op
end;

procedure TZCrudInterceptor<T>.BeforeInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T);
begin
  // No-op
end;

procedure TZCrudInterceptor<T>.AfterInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse);
begin
  // No-op
end;

procedure TZCrudInterceptor<T>.BeforeUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AExistingModel, AInputModel: T);
begin
  // No-op
end;

procedure TZCrudInterceptor<T>.AfterUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse);
begin
  // No-op
end;

procedure TZCrudInterceptor<T>.BeforeDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64);
begin
  // No-op
end;

procedure TZCrudInterceptor<T>.AfterDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64; AResponse: TResponse);
begin
  // No-op
end;

{ TZRBACPolicy<T> }

constructor TZRBACPolicy<T>.Create;
var
  Act: TZCrudAction;
begin
  inherited Create;
  FRequireAuth := False;
  FPermissionPrefix := '';
  SetLength(FScopes, 0);
  for Act := Low(TZCrudAction) to High(TZCrudAction) do
  begin
    FAllowedRoles[Act] := TStringList.Create;
    FAllowedRoles[Act].CaseSensitive := False;
  end;
end;

destructor TZRBACPolicy<T>.Destroy;
var
  Act: TZCrudAction;
begin
  for Act := Low(TZCrudAction) to High(TZCrudAction) do
    FAllowedRoles[Act].Free;
  inherited Destroy;
end;

function TZRBACPolicy<T>.RequireAuth(AValue: Boolean): TZRBACPolicy<T>;
begin
  FRequireAuth := AValue;
  Result := Self;
end;

function TZRBACPolicy<T>.AllowRoles(AAction: TZCrudAction; const ARoles: array of string): TZRBACPolicy<T>;
var
  R: string;
begin
  FRequireAuth := True;
  for R in ARoles do
    FAllowedRoles[AAction].Add(Trim(R));
  Result := Self;
end;

function TZRBACPolicy<T>.AllowAllRoles(const ARoles: array of string): TZRBACPolicy<T>;
var
  Act: TZCrudAction;
begin
  for Act := Low(TZCrudAction) to High(TZCrudAction) do
    AllowRoles(Act, ARoles);
  Result := Self;
end;

function TZRBACPolicy<T>.WithPermissionPrefix(const APrefix: string): TZRBACPolicy<T>;
begin
  FRequireAuth := True;
  FPermissionPrefix := UpperCase(Trim(APrefix));
  Result := Self;
end;

function TZRBACPolicy<T>.WithScope(const AModelField, AContextAttribute: string): TZRBACPolicy<T>;
var
  Len: Integer;
begin
  Len := Length(FScopes);
  SetLength(FScopes, Len + 1);
  FScopes[Len].ModelField := Trim(AModelField);
  FScopes[Len].ContextAttribute := Trim(AContextAttribute);
  Result := Self;
end;

function TZRBACPolicy<T>.IsAuthRequired: Boolean;
begin
  Result := FRequireAuth;
end;

function TZRBACPolicy<T>.Authorize(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; out AReason: string): Boolean;
var
  I: Integer;
  HasRoleMatch: Boolean;
  RequiredPerm: string;
begin
  AReason := '';

  if FRequireAuth and not ASecurity.IsAuthenticated then
  begin
    AReason := MsgCrudResponseUnauthorized;
    Exit(False);
  end;

  // Check roles if configured for this action
  if FAllowedRoles[AAction].Count > 0 then
  begin
    HasRoleMatch := False;
    for I := 0 to FAllowedRoles[AAction].Count - 1 do
    begin
      if ASecurity.HasRole(FAllowedRoles[AAction][I]) then
      begin
        HasRoleMatch := True;
        Break;
      end;
    end;
    if not HasRoleMatch then
    begin
      AReason := MsgCrudResponseForbidden;
      Exit(False);
    end;
  end;

  // Check permissions generated from prefix
  if not FPermissionPrefix.IsEmpty then
  begin
    case AAction of
      caList, caGet: RequiredPerm := FPermissionPrefix + '_READ';
      caCreate:      RequiredPerm := FPermissionPrefix + '_CREATE';
      caUpdate:      RequiredPerm := FPermissionPrefix + '_UPDATE';
      caDelete:      RequiredPerm := FPermissionPrefix + '_DELETE';
    end;

    if not (ASecurity.HasPermission(RequiredPerm) or
            ASecurity.HasPermission(FPermissionPrefix + '_ALL') or
            ASecurity.HasPermission('*')) then
    begin
      AReason := MsgCrudResponseForbidden;
      Exit(False);
    end;
  end;

  Result := True;
end;

procedure TZRBACPolicy<T>.BeforeQuery(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; AQuery: TDeltaQuery<T>);
var
  I: Integer;
  AttrVal: string;
  IntVal: Int64;
begin
  for I := 0 to High(FScopes) do
  begin
    AttrVal := ASecurity.GetAttribute(FScopes[I].ContextAttribute, '');
    if not AttrVal.IsEmpty then
    begin
      if TryStrToInt64(AttrVal, IntVal) then
        AQuery.AndWhere(FScopes[I].ModelField, IntVal)
      else
        AQuery.AndWhere(FScopes[I].ModelField, AttrVal);
    end;
  end;
end;

procedure TZRBACPolicy<T>.BeforeInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T);
var
  I: Integer;
  PropInfo: PPropInfo;
  AttrVal: string;
  IntVal: Int64;
  FieldObj: TObject;
begin
  for I := 0 to High(FScopes) do
  begin
    PropInfo := GetPropInfo(AModel.ClassInfo, FScopes[I].ModelField);
    if PropInfo <> nil then
    begin
      AttrVal := ASecurity.GetAttribute(FScopes[I].ContextAttribute, '');
      if not AttrVal.IsEmpty then
      begin
        if PropInfo^.PropType^.Kind in [tkInteger, tkInt64] then
        begin
          if TryStrToInt64(AttrVal, IntVal) then
            SetOrdProp(AModel, PropInfo, IntVal);
        end
        else if PropInfo^.PropType^.Kind in [tkSString, tkLString, tkAString, tkUString] then
          SetStrProp(AModel, PropInfo, AttrVal)
        else if PropInfo^.PropType^.Kind = tkClass then
        begin
          FieldObj := GetObjectProp(AModel, PropInfo);
          if (FieldObj <> nil) and (FieldObj is TDeltaField) then
          begin
            if TryStrToInt64(AttrVal, IntVal) then
              TDeltaField(FieldObj).Value := IntVal
            else
              TDeltaField(FieldObj).Value := AttrVal;
          end;
        end;
      end;
    end;
  end;
end;

procedure TZRBACPolicy<T>.BeforeUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AExistingModel, AInputModel: T);
var
  I: Integer;
  PropInfo: PPropInfo;
  FieldObjExisting, FieldObjInput: TObject;
begin
  for I := 0 to High(FScopes) do
  begin
    PropInfo := GetPropInfo(AExistingModel.ClassInfo, FScopes[I].ModelField);
    if PropInfo <> nil then
    begin
      if PropInfo^.PropType^.Kind in [tkInteger, tkInt64] then
        SetOrdProp(AInputModel, PropInfo, GetOrdProp(AExistingModel, PropInfo))
      else if PropInfo^.PropType^.Kind in [tkSString, tkLString, tkAString, tkUString] then
        SetStrProp(AInputModel, PropInfo, GetStrProp(AExistingModel, PropInfo))
      else if PropInfo^.PropType^.Kind = tkClass then
      begin
        FieldObjExisting := GetObjectProp(AExistingModel, PropInfo);
        FieldObjInput := GetObjectProp(AInputModel, PropInfo);
        if (FieldObjExisting is TDeltaField) and (FieldObjInput is TDeltaField) then
          TDeltaField(FieldObjInput).Value := TDeltaField(FieldObjExisting).Value;
      end;
    end;
  end;
end;

end.
