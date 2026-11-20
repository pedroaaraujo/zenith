unit Zenith.Crud;

{$IFDEF FPC}
  {$mode Delphi}{$H+}
{$ENDIF}

interface

uses
  Classes, SysUtils, HTTPDefs, TypInfo,
  Zenith.App, Zenith.Consts, Zenith.Exceptions, Zenith.Messages,
  DeltaModel, DeltaModel.Metadata, DeltaModel.ORM.Pool, DeltaModel.ORM.DML, DeltaModel.Generics;

type
  { Generic REST CRUD Controller and Auto-Router for Zenith }
  TZenithCrud<T: TDeltaModel> = class
  private
    class var FPool: TDeltaConnectionPool;
    class var FBasePath: string;
    class var FTag: string;
    class var FModelName: string;
    class function ParseId(ARequest: TRequest): Int64; static;
    class procedure GetAll(ARequest: TRequest; AResponse: TResponse); static;
    class procedure GetById(ARequest: TRequest; AResponse: TResponse); static;
    class procedure CreateItem(ARequest: TRequest; AResponse: TResponse); static;
    class procedure UpdateItem(ARequest: TRequest; AResponse: TResponse); static;
    class procedure DeleteItem(ARequest: TRequest; AResponse: TResponse); static;
  public
    class procedure Register(const ABasePath: string; const ATag: string; APool: TDeltaConnectionPool);
  end;

implementation

uses
  DeltaSerialization;

class function TZenithCrud<T>.ParseId(ARequest: TRequest): Int64;
var
  Val: Int64;
begin
  if not TryStrToInt64(ARequest.RouteParams['id'], Val) or (Val < 1) then
    raise EBadRequest.Create(MsgCrudInvalidId);
  Result := Val;
end;

class procedure TZenithCrud<T>.GetAll(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
  Query: TDeltaQuery<T>;
  List: TGDeltaModelList<T>;
  PageNum, PageSz: Integer;
  OrderByClause: string;
  MemStream: TMemoryStream;
begin
  Lease := FPool.Acquire;
  Query := TDeltaQuery<T>.Create(Lease);
  try
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
end;

class procedure TZenithCrud<T>.GetById(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
  Query: TDeltaQuery<T>;
  Item: T;
  IdVal: Int64;
begin
  IdVal := ParseId(ARequest);
  Lease := FPool.Acquire;
  Query := TDeltaQuery<T>.Create(Lease);
  try
    Item := Query.FindById(IdVal);
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
end;

class procedure TZenithCrud<T>.CreateItem(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
  Item: T;
  Query: TDeltaQuery<T>;
begin
  Item := T.Create;
  try
    try
      Item.FromJson(ARequest.Content);
    except
      on E: Exception do
        raise EBadRequest.Create(MsgCrudInvalidJson + E.Message);
    end;

    Item.Validate;

    Lease := FPool.Acquire;
    Query := TDeltaQuery<T>.Create(Lease);
    try
      if not Query.Insert(Item) then
        raise EServerError.Create(MsgCrudCouldNotInsert);
      AResponse.Code := StatusCreated;
      AResponse.ContentType := 'application/json; charset=utf-8';
      AResponse.Content := Item.ToJson;
    finally
      Query.Free;
    end;
  finally
    Item.Free;
  end;
end;

class procedure TZenithCrud<T>.UpdateItem(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
  ExistingItem, InputItem: T;
  Query: TDeltaQuery<T>;
  IdVal: Int64;
  Meta: TModelMetadata;
begin
  IdVal := ParseId(ARequest);
  Lease := FPool.Acquire;
  Query := TDeltaQuery<T>.Create(Lease);
  try
    ExistingItem := Query.FindById(IdVal);
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

        InputItem.Validate;

        CopyObject(InputItem, ExistingItem);
        Meta := TRTTICache.GetModelMetadata(T);
        if not Meta.PKPropName.IsEmpty then
          SetOrdProp(ExistingItem, Meta.PKPropName, IdVal);

        if not Query.Update(ExistingItem) then
          raise EServerError.Create(MsgCrudCouldNotUpdate);

        AResponse.Code := StatusOK;
        AResponse.ContentType := 'application/json; charset=utf-8';
        AResponse.Content := ExistingItem.ToJson;
      finally
        InputItem.Free;
      end;
    finally
      ExistingItem.Free;
    end;
  finally
    Query.Free;
  end;
end;

class procedure TZenithCrud<T>.DeleteItem(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
  IdVal: Int64;
begin
  IdVal := ParseId(ARequest);
  Lease := FPool.Acquire;
  if not Lease.DeleteById(T, IdVal) then
    raise EResourceNotFound.Create(TitleNotFound);
  AResponse.Code := StatusNoContent;
end;

class procedure TZenithCrud<T>.Register(const ABasePath: string; const ATag: string; APool: TDeltaConnectionPool);
var
  CleanPath, ModelName: string;
  SampleInstance: T;
  SchemaJson: string;
begin
  FPool := APool;
  CleanPath := ABasePath.Trim;
  if not CleanPath.StartsWith('/') then
    CleanPath := '/' + CleanPath;
  if (Length(CleanPath) > 1) and CleanPath.EndsWith('/') then
    CleanPath := Copy(CleanPath, 1, Length(CleanPath) - 1);
  FBasePath := CleanPath;
  FTag := ATag;

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

  // 1. GET /base
  Router
    .Get(CleanPath, GetAll)
    .AddTag(ATag)
    .SetSummary(MsgCrudSummaryList(ATag))
    .AddQueryParam('page', False, 'integer', '1', MsgCrudParamPage)
    .AddQueryParam('page_size', False, 'integer', '50', MsgCrudParamPageSize)
    .AddQueryParam('sort', False, 'string', '', MsgCrudParamSort)
    .AddResponseRefArray(StatusOK, ModelName, MsgCrudResponseListOK)
    .AddResponse(StatusBadRequest, MsgCrudResponseBadRequest);

  // 2. GET /base/:id
  Router
    .Get(CleanPath + '/:id', GetById)
    .AddTag(ATag)
    .SetSummary(MsgCrudSummaryGetById(ATag))
    .AddPathParam('id', True, 'integer', '1', MsgCrudParamId)
    .AddResponseRef(StatusOK, ModelName, MsgCrudResponseGetOK)
    .AddResponse(StatusNotFound, TitleNotFound);

  // 3. POST /base
  Router
    .Post(CleanPath, CreateItem)
    .AddTag(ATag)
    .SetSummary(MsgCrudSummaryCreate(ATag))
    .SetBodyContentRef(ModelName, True, 'application/json', MsgCrudPayload)
    .AddResponseRef(StatusCreated, ModelName, MsgCrudResponseCreated)
    .AddResponse(StatusBadRequest, MsgCrudResponseInvalidPayload)
    .AddResponse(StatusUnprocessableEntity, MsgCrudResponseValidation);

  // 4. PUT /base/:id
  Router
    .Put(CleanPath + '/:id', UpdateItem)
    .AddTag(ATag)
    .SetSummary(MsgCrudSummaryUpdate(ATag))
    .AddPathParam('id', True, 'integer', '1', MsgCrudParamId)
    .SetBodyContentRef(ModelName, True, 'application/json', MsgCrudPayload)
    .AddResponseRef(StatusOK, ModelName, MsgCrudResponseUpdated)
    .AddResponse(StatusBadRequest, MsgCrudResponseInvalidPayload)
    .AddResponse(StatusNotFound, TitleNotFound)
    .AddResponse(StatusUnprocessableEntity, MsgCrudResponseValidation);

  // 5. DELETE /base/:id
  Router
    .Delete(CleanPath + '/:id', DeleteItem)
    .AddTag(ATag)
    .SetSummary(MsgCrudSummaryDelete(ATag))
    .AddPathParam('id', True, 'integer', '1', MsgCrudParamId)
    .AddResponse(StatusNoContent, MsgCrudResponseDeleted)
    .AddResponse(StatusNotFound, TitleNotFound);
end;

end.
