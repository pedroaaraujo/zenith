unit Zenith.Crud;

{$IFDEF FPC}
  {$mode Delphi}{$H+}
{$ENDIF}

interface

uses
  Classes, SysUtils, HTTPDefs, TypInfo,
  swagger4laz,
  Zenith.App, Zenith.Consts, Zenith.Exceptions, Zenith.Messages,
  Zenith.Security, Zenith.Crud.Interceptor,
  DeltaModel, DeltaModel.Metadata, DeltaModel.ORM.Pool, DeltaModel.ORM.DML, DeltaModel.Generics;

type
  { Modern Fluent REST CRUD Controller and Auto-Router for Zenith }
  TZenithCrud<T: TDeltaModel> = class
  private
    class var FInstance: TZenithCrud<T>;
  private
    FPool: TDeltaConnectionPool;
    FBasePath: string;
    FTag: string;
    FModelName: string;
    FInterceptor: IZenithCrudInterceptor<T>;
    FSecurityResolver: IZenithSecurityResolver;
    FRBACPolicy: TZRBACPolicy<T>;
    FIsRBACPolicyOnly: Boolean;

    function ResolveSecurity(ARequest: TRequest): TZSecurityContext;
    function ParseId(ARequest: TRequest): Int64;
    procedure CheckAuthorization(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest);

    procedure ExecuteBeforeQuery(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; AQuery: TDeltaQuery<T>);
    procedure ExecuteBeforeInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T);
    procedure ExecuteAfterInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse);
    procedure ExecuteBeforeUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AExistingModel, AInputModel: T);
    procedure ExecuteAfterUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse);
    procedure ExecuteBeforeDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64);
    procedure ExecuteAfterDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64; AResponse: TResponse);

    class procedure HandleGetAll(ARequest: TRequest; AResponse: TResponse); static;
    class procedure HandleGetById(ARequest: TRequest; AResponse: TResponse); static;
    class procedure HandleCreateItem(ARequest: TRequest; AResponse: TResponse); static;
    class procedure HandleUpdateItem(ARequest: TRequest; AResponse: TResponse); static;
    class procedure HandleDeleteItem(ARequest: TRequest; AResponse: TResponse); static;

    procedure DoGetAll(ARequest: TRequest; AResponse: TResponse);
    procedure DoGetById(ARequest: TRequest; AResponse: TResponse);
    procedure DoCreateItem(ARequest: TRequest; AResponse: TResponse);
    procedure DoUpdateItem(ARequest: TRequest; AResponse: TResponse);
    procedure DoDeleteItem(ARequest: TRequest; AResponse: TResponse);
  public
    constructor Create(const ABasePath: string; APool: TDeltaConnectionPool);
    destructor Destroy; override;

    function WithTag(const ATag: string): TZenithCrud<T>;
    function WithInterceptor(AInterceptor: IZenithCrudInterceptor<T>): TZenithCrud<T>;
    function WithSecurityResolver(AResolver: IZenithSecurityResolver): TZenithCrud<T>;
    function WithRBAC(APolicy: TZRBACPolicy<T>): TZenithCrud<T>;
    procedure Register;
  end;

implementation

uses
  DeltaSerialization;

{ TZenithCrud<T> }

constructor TZenithCrud<T>.Create(const ABasePath: string; APool: TDeltaConnectionPool);
begin
  inherited Create;
  FPool := APool;
  FBasePath := ABasePath;
  FTag := '';
  FModelName := '';
  FInterceptor := nil;
  FSecurityResolver := nil;
  FRBACPolicy := nil;
  FIsRBACPolicyOnly := False;
  FInstance := Self;
end;

destructor TZenithCrud<T>.Destroy;
begin
  FRBACPolicy := nil;
  FInterceptor := nil;
  FSecurityResolver := nil;
  if FInstance = Self then
    FInstance := nil;
  inherited Destroy;
end;

function TZenithCrud<T>.WithTag(const ATag: string): TZenithCrud<T>;
begin
  FTag := ATag;
  Result := Self;
end;

function TZenithCrud<T>.WithInterceptor(AInterceptor: IZenithCrudInterceptor<T>): TZenithCrud<T>;
begin
  FInterceptor := AInterceptor;
  FIsRBACPolicyOnly := False;
  Result := Self;
end;

function TZenithCrud<T>.WithSecurityResolver(AResolver: IZenithSecurityResolver): TZenithCrud<T>;
begin
  FSecurityResolver := AResolver;
  Result := Self;
end;

function TZenithCrud<T>.WithRBAC(APolicy: TZRBACPolicy<T>): TZenithCrud<T>;
begin
  FRBACPolicy := APolicy;
  if FInterceptor = nil then
  begin
    FInterceptor := APolicy;
    FIsRBACPolicyOnly := True;
  end;
  Result := Self;
end;

function TZenithCrud<T>.ResolveSecurity(ARequest: TRequest): TZSecurityContext;
var
  Resolver: IZenithSecurityResolver;
begin
  Resolver := FSecurityResolver;
  if Resolver = nil then
    Resolver := GetZenithSecurityResolver;

  if Resolver <> nil then
    Result := Resolver.Resolve(ARequest)
  else
    Result := TZSecurityContext.CreateAnonymous;
end;

function TZenithCrud<T>.ParseId(ARequest: TRequest): Int64;
var
  Val: Int64;
begin
  if not TryStrToInt64(ARequest.RouteParams['id'], Val) or (Val < 1) then
    raise EBadRequest.Create(MsgCrudInvalidId);
  Result := Val;
end;

procedure TZenithCrud<T>.CheckAuthorization(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest);
var
  Reason: string;
begin
  Reason := '';

  if Assigned(FRBACPolicy) and not FRBACPolicy.Authorize(AAction, ASecurity, ARequest, Reason) then
  begin
    if not ASecurity.IsAuthenticated then
      raise EUnauthorized.Create(MsgCrudResponseUnauthorized)
    else
      raise EForbidden.Create(MsgCrudResponseForbidden);
  end;

  if Assigned(FInterceptor) and not FIsRBACPolicyOnly and
     not FInterceptor.Authorize(AAction, ASecurity, ARequest, Reason) then
  begin
    if not ASecurity.IsAuthenticated then
    begin
      if Reason.IsEmpty then Reason := MsgCrudResponseUnauthorized;
      raise EUnauthorized.Create(Reason);
    end
    else
    begin
      if Reason.IsEmpty then Reason := MsgCrudResponseForbidden;
      raise EForbidden.Create(Reason);
    end;
  end;
end;

procedure TZenithCrud<T>.ExecuteBeforeQuery(AAction: TZCrudAction; const ASecurity: TZSecurityContext; ARequest: TRequest; AQuery: TDeltaQuery<T>);
begin
  if Assigned(FRBACPolicy) then
    FRBACPolicy.BeforeQuery(AAction, ASecurity, ARequest, AQuery);
  if Assigned(FInterceptor) and not FIsRBACPolicyOnly then
    FInterceptor.BeforeQuery(AAction, ASecurity, ARequest, AQuery);
end;

procedure TZenithCrud<T>.ExecuteBeforeInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T);
begin
  if Assigned(FRBACPolicy) then
    FRBACPolicy.BeforeInsert(ASecurity, ARequest, AModel);
  if Assigned(FInterceptor) and not FIsRBACPolicyOnly then
    FInterceptor.BeforeInsert(ASecurity, ARequest, AModel);
end;

procedure TZenithCrud<T>.ExecuteAfterInsert(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse);
begin
  if Assigned(FRBACPolicy) then
    FRBACPolicy.AfterInsert(ASecurity, ARequest, AModel, AResponse);
  if Assigned(FInterceptor) and not FIsRBACPolicyOnly then
    FInterceptor.AfterInsert(ASecurity, ARequest, AModel, AResponse);
end;

procedure TZenithCrud<T>.ExecuteBeforeUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AExistingModel, AInputModel: T);
begin
  if Assigned(FRBACPolicy) then
    FRBACPolicy.BeforeUpdate(ASecurity, ARequest, AExistingModel, AInputModel);
  if Assigned(FInterceptor) and not FIsRBACPolicyOnly then
    FInterceptor.BeforeUpdate(ASecurity, ARequest, AExistingModel, AInputModel);
end;

procedure TZenithCrud<T>.ExecuteAfterUpdate(const ASecurity: TZSecurityContext; ARequest: TRequest; AModel: T; AResponse: TResponse);
begin
  if Assigned(FRBACPolicy) then
    FRBACPolicy.AfterUpdate(ASecurity, ARequest, AModel, AResponse);
  if Assigned(FInterceptor) and not FIsRBACPolicyOnly then
    FInterceptor.AfterUpdate(ASecurity, ARequest, AModel, AResponse);
end;

procedure TZenithCrud<T>.ExecuteBeforeDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64);
begin
  if Assigned(FRBACPolicy) then
    FRBACPolicy.BeforeDelete(ASecurity, ARequest, AId);
  if Assigned(FInterceptor) and not FIsRBACPolicyOnly then
    FInterceptor.BeforeDelete(ASecurity, ARequest, AId);
end;

procedure TZenithCrud<T>.ExecuteAfterDelete(const ASecurity: TZSecurityContext; ARequest: TRequest; AId: Int64; AResponse: TResponse);
begin
  if Assigned(FRBACPolicy) then
    FRBACPolicy.AfterDelete(ASecurity, ARequest, AId, AResponse);
  if Assigned(FInterceptor) and not FIsRBACPolicyOnly then
    FInterceptor.AfterDelete(ASecurity, ARequest, AId, AResponse);
end;

class procedure TZenithCrud<T>.HandleGetAll(ARequest: TRequest; AResponse: TResponse);
begin
  if FInstance = nil then
    raise EServerError.Create('TZenithCrud instance not initialized');
  FInstance.DoGetAll(ARequest, AResponse);
end;

class procedure TZenithCrud<T>.HandleGetById(ARequest: TRequest; AResponse: TResponse);
begin
  if FInstance = nil then
    raise EServerError.Create('TZenithCrud instance not initialized');
  FInstance.DoGetById(ARequest, AResponse);
end;

class procedure TZenithCrud<T>.HandleCreateItem(ARequest: TRequest; AResponse: TResponse);
begin
  if FInstance = nil then
    raise EServerError.Create('TZenithCrud instance not initialized');
  FInstance.DoCreateItem(ARequest, AResponse);
end;

class procedure TZenithCrud<T>.HandleUpdateItem(ARequest: TRequest; AResponse: TResponse);
begin
  if FInstance = nil then
    raise EServerError.Create('TZenithCrud instance not initialized');
  FInstance.DoUpdateItem(ARequest, AResponse);
end;

class procedure TZenithCrud<T>.HandleDeleteItem(ARequest: TRequest; AResponse: TResponse);
begin
  if FInstance = nil then
    raise EServerError.Create('TZenithCrud instance not initialized');
  FInstance.DoDeleteItem(ARequest, AResponse);
end;

procedure TZenithCrud<T>.DoGetAll(ARequest: TRequest; AResponse: TResponse);
var
  SecCtx: TZSecurityContext;
  Lease: IDeltaPooledEngine;
  Query: TDeltaQuery<T>;
  List: TGDeltaModelList<T>;
  PageNum, PageSz: Integer;
  OrderByClause: string;
  MemStream: TMemoryStream;
begin
  SecCtx := ResolveSecurity(ARequest);
  try
    CheckAuthorization(caList, SecCtx, ARequest);

    Lease := FPool.Acquire;
    Query := TDeltaQuery<T>.Create(Lease);
    try
      ExecuteBeforeQuery(caList, SecCtx, ARequest, Query);

      PageNum := StrToIntDef(ARequest.QueryFields.Values['page'], 0);
      PageSz := StrToIntDef(ARequest.QueryFields.Values['page_size'], 0);
      if PageSz = 0 then
        PageSz := StrToIntDef(ARequest.QueryFields.Values['limit'], 0);

      OrderByClause := ARequest.QueryFields.Values['sort'];
      if OrderByClause.IsEmpty then
        OrderByClause := ARequest.QueryFields.Values['order_by'];

      if not OrderByClause.IsEmpty then
        Query.OrderBy(OrderByClause);

      if SameText(ARequest.QueryFields.Values['stream'], 'true') then
      begin
        MemStream := TMemoryStream.Create;
        Query.StreamJsonTo(MemStream, 500);
        MemStream.Position := 0;
        AResponse.Code := StatusOK;
        AResponse.ContentType := 'application/json; charset=utf-8';
        AResponse.ContentStream := MemStream;
        AResponse.FreeContentStream := True;
        AResponse.SendContent;
        Exit;
      end;

      if (PageNum > 0) and (PageSz > 0) then
        Query.Page(PageNum, PageSz)
      else if PageSz > 0 then
        Query.Limit(PageSz);

      List := Query.All;
      try
        AResponse.Code := StatusOK;
        AResponse.ContentType := 'application/json; charset=utf-8';
        AResponse.Content := List.ToJson;
      finally
        List.Free;
      end;
    finally
      Query.Free;
    end;
  finally
    SecCtx.FreeInternalObjects;
  end;
end;

procedure TZenithCrud<T>.DoGetById(ARequest: TRequest; AResponse: TResponse);
var
  SecCtx: TZSecurityContext;
  Lease: IDeltaPooledEngine;
  Query: TDeltaQuery<T>;
  Item: T;
  IdVal: Int64;
  Meta: TModelMetadata;
  PKName: string;
begin
  IdVal := ParseId(ARequest);
  SecCtx := ResolveSecurity(ARequest);
  try
    CheckAuthorization(caGet, SecCtx, ARequest);

    Lease := FPool.Acquire;
    Query := TDeltaQuery<T>.Create(Lease);
    try
      ExecuteBeforeQuery(caGet, SecCtx, ARequest, Query);

      Meta := TRTTICache.GetModelMetadata(T);
      PKName := Meta.PKFieldName;
      if PKName.IsEmpty then
        PKName := 'id';

      Query.AndWhere(PKName, IdVal);
      Item := Query.First;
      try
        if Item = nil then
          raise EResourceNotFound.Create(TitleNotFound);
        AResponse.Code := StatusOK;
        AResponse.ContentType := 'application/json; charset=utf-8';
        AResponse.Content := Item.ToJson;
      finally
        Item.Free;
      end;
    finally
      Query.Free;
    end;
  finally
    SecCtx.FreeInternalObjects;
  end;
end;

procedure TZenithCrud<T>.DoCreateItem(ARequest: TRequest; AResponse: TResponse);
var
  SecCtx: TZSecurityContext;
  Lease: IDeltaPooledEngine;
  Item: T;
  Query: TDeltaQuery<T>;
begin
  SecCtx := ResolveSecurity(ARequest);
  try
    CheckAuthorization(caCreate, SecCtx, ARequest);

    Item := T.Create;
    try
      try
        Item.FromJson(ARequest.Content);
      except
        on E: Exception do
          raise EBadRequest.Create(MsgCrudInvalidJson + E.Message);
      end;

      ExecuteBeforeInsert(SecCtx, ARequest, Item);

      Item.Validate;

      Lease := FPool.Acquire;
      Query := TDeltaQuery<T>.Create(Lease);
      try
        if not Query.Insert(Item) then
          raise EServerError.Create(MsgCrudCouldNotInsert);
        AResponse.Code := StatusCreated;
        AResponse.ContentType := 'application/json; charset=utf-8';
        AResponse.Content := Item.ToJson;

        ExecuteAfterInsert(SecCtx, ARequest, Item, AResponse);
      finally
        Query.Free;
      end;
    finally
      Item.Free;
    end;
  finally
    SecCtx.FreeInternalObjects;
  end;
end;

procedure TZenithCrud<T>.DoUpdateItem(ARequest: TRequest; AResponse: TResponse);
var
  SecCtx: TZSecurityContext;
  Lease: IDeltaPooledEngine;
  ExistingItem, InputItem: T;
  Query: TDeltaQuery<T>;
  IdVal: Int64;
  Meta: TModelMetadata;
  PKName: string;
begin
  IdVal := ParseId(ARequest);
  SecCtx := ResolveSecurity(ARequest);
  try
    CheckAuthorization(caUpdate, SecCtx, ARequest);

    Lease := FPool.Acquire;
    Query := TDeltaQuery<T>.Create(Lease);
    try
      ExecuteBeforeQuery(caUpdate, SecCtx, ARequest, Query);

      Meta := TRTTICache.GetModelMetadata(T);
      PKName := Meta.PKFieldName;
      if PKName.IsEmpty then
        PKName := 'id';

      Query.AndWhere(PKName, IdVal);
      ExistingItem := Query.First;
      if ExistingItem = nil then
        raise EResourceNotFound.Create(TitleNotFound);
      try
        InputItem := T.Create;
        try
          try
            InputItem.FromJson(ARequest.Content);
          except
            on E: Exception do
              raise EBadRequest.Create(MsgCrudInvalidJson + E.Message);
          end;

          ExecuteBeforeUpdate(SecCtx, ARequest, ExistingItem, InputItem);

          InputItem.Validate;

          CopyObject(InputItem, ExistingItem);
          if not Meta.PKPropName.IsEmpty then
            SetOrdProp(ExistingItem, Meta.PKPropName, IdVal);

          if not Query.Update(ExistingItem) then
            raise EServerError.Create(MsgCrudCouldNotUpdate);

          AResponse.Code := StatusOK;
          AResponse.ContentType := 'application/json; charset=utf-8';
          AResponse.Content := ExistingItem.ToJson;

          ExecuteAfterUpdate(SecCtx, ARequest, ExistingItem, AResponse);
        finally
          InputItem.Free;
        end;
      finally
        ExistingItem.Free;
      end;
    finally
      Query.Free;
    end;
  finally
    SecCtx.FreeInternalObjects;
  end;
end;

procedure TZenithCrud<T>.DoDeleteItem(ARequest: TRequest; AResponse: TResponse);
var
  SecCtx: TZSecurityContext;
  Lease: IDeltaPooledEngine;
  Query: TDeltaQuery<T>;
  ExistingItem: T;
  IdVal: Int64;
  Meta: TModelMetadata;
  PKName: string;
begin
  IdVal := ParseId(ARequest);
  SecCtx := ResolveSecurity(ARequest);
  try
    CheckAuthorization(caDelete, SecCtx, ARequest);

    ExecuteBeforeDelete(SecCtx, ARequest, IdVal);

    Lease := FPool.Acquire;
    Query := TDeltaQuery<T>.Create(Lease);
    try
      ExecuteBeforeQuery(caDelete, SecCtx, ARequest, Query);

      Meta := TRTTICache.GetModelMetadata(T);
      PKName := Meta.PKFieldName;
      if PKName.IsEmpty then
        PKName := 'id';

      Query.AndWhere(PKName, IdVal);
      ExistingItem := Query.First;
      if ExistingItem = nil then
        raise EResourceNotFound.Create(TitleNotFound);
      try
        if not Lease.DeleteById(T, IdVal) then
          raise EResourceNotFound.Create(TitleNotFound);

        AResponse.Code := StatusNoContent;

        ExecuteAfterDelete(SecCtx, ARequest, IdVal, AResponse);
      finally
        ExistingItem.Free;
      end;
    finally
      Query.Free;
    end;
  finally
    SecCtx.FreeInternalObjects;
  end;
end;

procedure TZenithCrud<T>.Register;
var
  CleanPath, ModelName: string;
  SampleInstance: T;
  SchemaJson: string;
  RouteList, RouteGet, RoutePost, RoutePut, RouteDel: THTTPDocRoute;
  IsAuthEnabled: Boolean;
begin
  CleanPath := FBasePath.Trim;
  if not CleanPath.StartsWith('/') then
    CleanPath := '/' + CleanPath;
  if (Length(CleanPath) > 1) and CleanPath.EndsWith('/') then
    CleanPath := Copy(CleanPath, 1, Length(CleanPath) - 1);
  FBasePath := CleanPath;

  if FTag.IsEmpty then
    FTag := T.ClassName;

  SampleInstance := T.Create;
  try
    ModelName := SampleInstance.ClassName;
    if ModelName.StartsWith('T') then
      ModelName := Copy(ModelName, 2, Length(ModelName) - 1);
    FModelName := ModelName;
    SchemaJson := SampleInstance.SwaggerSchemaObject();
    Router.EnsureModel(ModelName, SchemaJson);
  finally
    SampleInstance.Free;
  end;

  IsAuthEnabled := (FSecurityResolver <> nil) or
                   ((FRBACPolicy <> nil) and FRBACPolicy.IsAuthRequired) or
                   (FInterceptor <> nil);

  // 1. GET /base
  RouteList := Router
    .Get(CleanPath, HandleGetAll)
    .AddTag(FTag)
    .SetSummary(MsgCrudSummaryList(FTag))
    .AddQueryParam('page', False, 'integer', '1', MsgCrudParamPage)
    .AddQueryParam('page_size', False, 'integer', '50', MsgCrudParamPageSize)
    .AddQueryParam('sort', False, 'string', '', MsgCrudParamSort)
    .AddResponseRefArray(StatusOK, ModelName, MsgCrudResponseListOK)
    .AddResponse(StatusBadRequest, MsgCrudResponseBadRequest);

  // 2. GET /base/:id
  RouteGet := Router
    .Get(CleanPath + '/:id', HandleGetById)
    .AddTag(FTag)
    .SetSummary(MsgCrudSummaryGetById(FTag))
    .AddPathParam('id', True, 'integer', '1', MsgCrudParamId)
    .AddResponseRef(StatusOK, ModelName, MsgCrudResponseGetOK)
    .AddResponse(StatusNotFound, TitleNotFound);

  // 3. POST /base
  RoutePost := Router
    .Post(CleanPath, HandleCreateItem)
    .AddTag(FTag)
    .SetSummary(MsgCrudSummaryCreate(FTag))
    .SetBodyContentRef(ModelName, True, 'application/json', MsgCrudPayload)
    .AddResponseRef(StatusCreated, ModelName, MsgCrudResponseCreated)
    .AddResponse(StatusBadRequest, MsgCrudResponseInvalidPayload)
    .AddResponse(StatusUnprocessableEntity, MsgCrudResponseValidation);

  // 4. PUT /base/:id
  RoutePut := Router
    .Put(CleanPath + '/:id', HandleUpdateItem)
    .AddTag(FTag)
    .SetSummary(MsgCrudSummaryUpdate(FTag))
    .AddPathParam('id', True, 'integer', '1', MsgCrudParamId)
    .SetBodyContentRef(ModelName, True, 'application/json', MsgCrudPayload)
    .AddResponseRef(StatusOK, ModelName, MsgCrudResponseUpdated)
    .AddResponse(StatusBadRequest, MsgCrudResponseInvalidPayload)
    .AddResponse(StatusNotFound, TitleNotFound)
    .AddResponse(StatusUnprocessableEntity, MsgCrudResponseValidation);

  // 5. DELETE /base/:id
  RouteDel := Router
    .Delete(CleanPath + '/:id', HandleDeleteItem)
    .AddTag(FTag)
    .SetSummary(MsgCrudSummaryDelete(FTag))
    .AddPathParam('id', True, 'integer', '1', MsgCrudParamId)
    .AddResponse(StatusNoContent, MsgCrudResponseDeleted)
    .AddResponse(StatusNotFound, TitleNotFound);

  if IsAuthEnabled then
  begin
    RouteList.SetSecurityBearer
      .AddResponse(StatusUnauthorized, MsgCrudResponseUnauthorized)
      .AddResponse(StatusForbidden, MsgCrudResponseForbidden);

    RouteGet.SetSecurityBearer
      .AddResponse(StatusUnauthorized, MsgCrudResponseUnauthorized)
      .AddResponse(StatusForbidden, MsgCrudResponseForbidden);

    RoutePost.SetSecurityBearer
      .AddResponse(StatusUnauthorized, MsgCrudResponseUnauthorized)
      .AddResponse(StatusForbidden, MsgCrudResponseForbidden);

    RoutePut.SetSecurityBearer
      .AddResponse(StatusUnauthorized, MsgCrudResponseUnauthorized)
      .AddResponse(StatusForbidden, MsgCrudResponseForbidden);

    RouteDel.SetSecurityBearer
      .AddResponse(StatusUnauthorized, MsgCrudResponseUnauthorized)
      .AddResponse(StatusForbidden, MsgCrudResponseForbidden);
  end;
end;

end.
