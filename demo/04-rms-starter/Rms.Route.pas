{
    Zenith Framework - RMS Starter Demo (Fluent Routes, OpenAPI 3.1 & SSE)
    Demonstrates:
    - TZenithCrud<T> for Products & Customers
    - Type-safe TDeltaQuery<T> filters (Q.M.<field>.Eq/Lt) and zero-alloc reusable cursors
    - Atomic transactional Sales creation & cancellation with inventory management
    - Real-time W3C Server-Sent Events (Zenith.SSE) for live sales notifications
    - RFC 9457 Problem Details error handling
}

unit Rms.Route;

{$mode Delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  HTTPDefs,
  fpjson,
  jsonparser,
  fgl,
  Zenith.App,
  Zenith.Constants,
  Zenith.Exceptions,
  Zenith.Crud,
  Zenith.SSE,
  Swagger4Laz,
  DeltaModel,
  DeltaModel.Fields,
  DeltaModel.Generics,
  DeltaModel.ORM.Interfaces,
  DeltaModel.ORM.Pool,
  DeltaModel.JsonStreamer,
  Rms.Model;

const
  { API route paths }
  PATH_HEALTH         = '/api/v1/health';
  PATH_PRODUCTS       = '/api/v1/products';
  PATH_LOW_STOCK      = '/api/v1/products/low-stock';
  PATH_CUSTOMERS      = '/api/v1/customers';
  PATH_SALES          = '/api/v1/sales';
  PATH_EVENTS_SALES   = '/api/v1/events/sales';
  PATH_SUB_ROOT       = '';
  PATH_SUB_BY_ID      = '/:id';
  PATH_SUB_CANCEL     = '/:id/cancel';

  { Route & query parameter names }
  PARAM_ID            = 'id';
  PARAM_PAGE          = 'page';
  PARAM_PAGE_SIZE     = 'page_size';
  PARAM_STATUS        = 'status';
  PARAM_THRESHOLD     = 'threshold';

  { Pagination defaults }
  DEFAULT_PAGE        = 1;
  DEFAULT_PAGE_SIZE   = 10;
  MAX_PAGE_SIZE       = 100;
  DEFAULT_LOW_STOCK   = 10.0;

  { OpenAPI tags }
  TAG_SYSTEM          = 'System';
  TAG_PRODUCTS        = 'Products';
  TAG_CUSTOMERS       = 'Customers';
  TAG_SALES           = 'Sales';
  TAG_EVENTS          = 'Real-Time Events (SSE)';

procedure RegisterRmsStarterRoutes;

implementation

{ Helper: loads child TSaleItem records into TSale.items using type-safe TDeltaQuery }
procedure LoadSaleItems(const ALease: IDeltaORMEngine; ASale: TSale);
var
  QItems: TDeltaQuery<TSaleItem>;
  ItemList: TGDeltaModelList<TSaleItem>;
  I: Integer;
begin
  if (ASale = nil) or (ASale.items.Count > 0) then
    Exit;
  QItems := TDeltaQuery<TSaleItem>.Create(ALease);
  try
    ItemList := QItems
      .Where(QItems.M.sale_id.Eq(ASale.id.AsInt64))
      .OrderBy(QItems.M.id, odAsc)
      .All;
    try
      for I := 0 to ItemList.Count - 1 do
        ASale.items.Add(ItemList[I]);
      ItemList.Records.FreeObjects := False;
      ItemList.Records.Clear;
    finally
      ItemList.Free;
    end;
  finally
    QItems.Free;
  end;
end;

{ GET /api/v1/health - Service health and entity counts }
procedure HandleHealth(AReq: TRequest; AResp: TResponse);
var
  Lease: IDeltaORMEngine;
  QProd: TDeltaQuery<TProduct>;
  QCust: TDeltaQuery<TCustomer>;
  QSale: TDeltaQuery<TSale>;
  Payload: TJSONObject;
begin
  Lease := RmsPool.Acquire;
  QProd := TDeltaQuery<TProduct>.Create(Lease);
  QCust := TDeltaQuery<TCustomer>.Create(Lease);
  QSale := TDeltaQuery<TSale>.Create(Lease);
  Payload := TJSONObject.Create;
  try
    Payload.Add('status', 'ok');
    Payload.Add('service', 'zenith-rms-starter');
    Payload.Add('products_count', QProd.Count);
    Payload.Add('customers_count', QCust.Count);
    Payload.Add('sales_count', QSale.Count);
    if Assigned(RmsEventBroker) then
      Payload.Add('sse_subscribers', RmsEventBroker.ConnectionCount)
    else
      Payload.Add('sse_subscribers', 0);

    AResp.Code := HTTP_STATUS_OK;
    AResp.ContentType := MIME_APPLICATION_JSON;
    AResp.Content := Payload.AsJSON;
  finally
    Payload.Free;
    QSale.Free;
    QCust.Free;
    QProd.Free;
  end;
end;

{ GET /api/v1/products/low-stock - Type-safe filter + zero-alloc reusable cursor }
procedure HandleLowStockProducts(AReq: TRequest; AResp: TResponse);
var
  Threshold: Double;
  Lease: IDeltaORMEngine;
  Q: TDeltaQuery<TProduct>;
  Prod: TProduct;
  RespObj: TJSONObject;
  ItemsArr: TJSONArray;
begin
  Threshold := StrToFloatDef(Trim(AReq.QueryFields.Values[PARAM_THRESHOLD]), DEFAULT_LOW_STOCK);
  if Threshold < 0 then
    Threshold := DEFAULT_LOW_STOCK;

  Lease := RmsPool.Acquire;
  Q := TDeltaQuery<TProduct>.Create(Lease);
  RespObj := TJSONObject.Create;
  try
    // Type-safe predicate and ordering via DeltaModel flyweight schema
    Q.Where(Q.M.stock_qty.Lt(Threshold))
     .OrderBy(Q.M.stock_qty, odAsc);

    ItemsArr := TJSONArray.Create;
    RespObj.Add('threshold', Threshold);
    RespObj.Add('data', ItemsArr);

    // Reusable cursor loop (zero per-row object allocation)
    for Prod in Q.Cursor do
      ItemsArr.Add(GetJSON(TDeltaFastJsonStreamer.ModelToJson(Prod)));

    RespObj.Add('count', ItemsArr.Count);

    AResp.Code := HTTP_STATUS_OK;
    AResp.ContentType := MIME_APPLICATION_JSON;
    AResp.Content := RespObj.AsJSON;
  finally
    RespObj.Free;
    Q.Free;
  end;
end;

{ GET /api/v1/sales - Paginated list using type-safe filters and reusable cursor }
procedure HandleListSales(AReq: TRequest; AResp: TResponse);
var
  Page, PageSize, TotalPages: Integer;
  TotalRecords: Int64;
  StatusFilter: string;
  Lease: IDeltaORMEngine;
  Q: TDeltaQuery<TSale>;
  SaleRec: TSale;
  RespObj: TJSONObject;
  DataArr: TJSONArray;
begin
  Page := StrToIntDef(AReq.QueryFields.Values[PARAM_PAGE], DEFAULT_PAGE);
  if Page < 1 then Page := DEFAULT_PAGE;
  PageSize := StrToIntDef(AReq.QueryFields.Values[PARAM_PAGE_SIZE], DEFAULT_PAGE_SIZE);
  if PageSize < 1 then PageSize := DEFAULT_PAGE_SIZE;
  if PageSize > MAX_PAGE_SIZE then PageSize := MAX_PAGE_SIZE;

  StatusFilter := UpperCase(Trim(AReq.QueryFields.Values[PARAM_STATUS]));

  Lease := RmsPool.Acquire;
  Q := TDeltaQuery<TSale>.Create(Lease);
  RespObj := TJSONObject.Create;
  try
    if StatusFilter <> '' then
      Q.Where(Q.M.status.Eq(StatusFilter));

    TotalRecords := Q.Count;
    TotalPages := (TotalRecords + PageSize - 1) div PageSize;
    if TotalPages < 1 then TotalPages := 1;

    Q.OrderBy(Q.M.id, odDesc)
     .Page(Page, PageSize);

    RespObj.Add('page', Page);
    RespObj.Add('page_size', PageSize);
    RespObj.Add('total_records', TotalRecords);
    RespObj.Add('total_pages', TotalPages);

    DataArr := TJSONArray.Create;
    RespObj.Add('data', DataArr);

    // Reusable cursor iteration avoids allocating a full list of models in memory
    for SaleRec in Q.Cursor do
      DataArr.Add(GetJSON(TDeltaFastJsonStreamer.ModelToJson(SaleRec)));

    AResp.Code := HTTP_STATUS_OK;
    AResp.ContentType := MIME_APPLICATION_JSON;
    AResp.Content := RespObj.AsJSON;
  finally
    RespObj.Free;
    Q.Free;
  end;
end;

{ GET /api/v1/sales/:id - Fetch single sale with eager-loaded items }
procedure HandleGetSaleById(AReq: TRequest; AResp: TResponse);
var
  SaleId: Int64;
  Lease: IDeltaORMEngine;
  Q: TDeltaQuery<TSale>;
  Sale: TSale;
begin
  SaleId := StrToInt64Def(AReq.RouteParams[PARAM_ID], 0);
  if SaleId <= 0 then
    raise EBadRequest.Create('Invalid sale identifier.');

  Lease := RmsPool.Acquire;
  Q := TDeltaQuery<TSale>.Create(Lease);
  try
    Sale := Q.Include('items').FindById(SaleId);
    if Sale = nil then
      raise ENotFound.CreateFmt('Sale #%d not found.', [SaleId]);
    try
      LoadSaleItems(Lease, Sale);
      AResp.Code := HTTP_STATUS_OK;
      AResp.ContentType := MIME_APPLICATION_JSON;
      AResp.Content := TDeltaFastJsonStreamer.ModelToJson(Sale);
    finally
      Sale.Free;
    end;
  finally
    Q.Free;
  end;
end;

{ POST /api/v1/sales - Create sale atomically with stock & credit validation + SSE broadcast }
procedure HandleCreateSale(AReq: TRequest; AResp: TResponse);
var
  JsonDoc: TJSONData;
  BodyObj, ItemObj: TJSONObject;
  ItemsArr: TJSONArray;
  CustomerId, ProductId, CreatedSaleId: Int64;
  Qty, UnitPrice, LineTotal, TotalAmount, StockAvail: Double;
  ProdName: string;
  Lease: IDeltaORMEngine;
  QCust: TDeltaQuery<TCustomer>;
  QProd: TDeltaQuery<TProduct>;
  QSale: TDeltaQuery<TSale>;
  QItem: TDeltaQuery<TSaleItem>;
  Cust: TCustomer;
  Prod: TProduct;
  Sale: TSale;
  SaleItem: TSaleItem;
  ItemsToInsert: TFPGObjectList<TSaleItem>;
  ProductsToUpdate: TFPGObjectList<TProduct>;
  JsonBytes: RawByteString;
  I: Integer;
begin
  if Trim(AReq.Content) = '' then
    raise EBadRequest.Create('Request body cannot be empty.');

  try
    JsonDoc := GetJSON(AReq.Content);
  except
    on E: Exception do
      raise EBadRequest.CreateFmt('Malformed JSON payload: %s', [E.Message]);
  end;

  if not (JsonDoc is TJSONObject) then
  begin
    JsonDoc.Free;
    raise EBadRequest.Create('Root JSON payload must be an object.');
  end;

  BodyObj := TJSONObject(JsonDoc);
  try
    CustomerId := BodyObj.Get('customer_id', Int64(0));
    if CustomerId <= 0 then
      raise EUnprocessableEntity.Create('Field customer_id is required and must be positive.');

    if not (BodyObj.Find('items') is TJSONArray) then
      raise EUnprocessableEntity.Create('Field items must be a JSON array.');

    ItemsArr := TJSONArray(BodyObj.Find('items'));
    if ItemsArr.Count = 0 then
      raise EUnprocessableEntity.Create('A sale must contain at least one item.');

    Lease := RmsPool.Acquire;
    Cust := nil;
    ProductsToUpdate := TFPGObjectList<TProduct>.Create(True);
    ItemsToInsert := TFPGObjectList<TSaleItem>.Create(True);
    try
      // 1. Validate customer exists and is active
      QCust := TDeltaQuery<TCustomer>.Create(Lease);
      try
        Cust := QCust.FindById(CustomerId);
        if Cust = nil then
          raise ENotFound.CreateFmt('Customer #%d not found.', [CustomerId]);
        if not Cust.active.AsBoolean then
          raise EUnprocessableEntity.CreateFmt('Customer #%d is inactive.', [CustomerId]);
      finally
        QCust.Free;
      end;

      TotalAmount := 0.0;

      // 2. Validate every product and available stock
      for I := 0 to ItemsArr.Count - 1 do
      begin
        if not (ItemsArr[I] is TJSONObject) then
          raise EUnprocessableEntity.Create('Each element in items must be a JSON object.');

        ItemObj := TJSONObject(ItemsArr[I]);
        ProductId := ItemObj.Get('product_id', Int64(0));
        Qty := ItemObj.Get('quantity', 0.0);

        if (ProductId <= 0) or (Qty <= 0) then
          raise EUnprocessableEntity.Create('Each item requires positive product_id and quantity.');

        QProd := TDeltaQuery<TProduct>.Create(Lease);
        try
          Prod := QProd.FindById(ProductId);
          if Prod = nil then
            raise ENotFound.CreateFmt('Product #%d not found.', [ProductId]);

          if not Prod.active.AsBoolean then
          begin
            ProdName := Prod.name.AsString;
            Prod.Free;
            raise EUnprocessableEntity.CreateFmt('Product #%d ("%s") is inactive.', [ProductId, ProdName]);
          end;

          if Prod.stock_qty.AsFloat < Qty then
          begin
            ProdName := Prod.name.AsString;
            StockAvail := Prod.stock_qty.AsFloat;
            Prod.Free;
            raise EUnprocessableEntity.CreateFmt(
              'Insufficient stock for "%s". Available: %.2f, Requested: %.2f.',
              [ProdName, StockAvail, Qty]
            );
          end;

          UnitPrice := Prod.unit_price.AsFloat;
          LineTotal := UnitPrice * Qty;
          TotalAmount := TotalAmount + LineTotal;

          SaleItem := TSaleItem.Create;
          SaleItem.product_id.Value := ProductId;
          SaleItem.quantity.Value := Qty;
          SaleItem.unit_price.Value := UnitPrice;
          SaleItem.line_total.Value := LineTotal;
          ItemsToInsert.Add(SaleItem);

          Prod.stock_qty.Value := Prod.stock_qty.AsFloat - Qty;
          ProductsToUpdate.Add(Prod);
        finally
          QProd.Free;
        end;
      end;

      // 3. Validate customer credit limit
      if (Cust.credit_limit.AsFloat > 0) and (TotalAmount > Cust.credit_limit.AsFloat) then
        raise EUnprocessableEntity.CreateFmt(
          'Customer credit limit exceeded. Limit: %.2f, Sale total: %.2f.',
          [Cust.credit_limit.AsFloat, TotalAmount]
        );

      // 4. Atomic transaction: insert sale + items and deduct inventory
      Lease.StartTransaction;
      try
        Sale := TSale.Create;
        try
          Sale.sale_number.Value := Format('SALE-%s-%04d',
            [FormatDateTime('YYYYMMDD', Now), Random(9000) + 1000]);
          Sale.customer_id.Value := CustomerId;
          Sale.sale_date.Value := Now;
          Sale.total_amount.Value := TotalAmount;
          Sale.status.Value := SALE_STATUS_CONFIRMED;

          QSale := TDeltaQuery<TSale>.Create(Lease);
          try
            QSale.Insert(Sale);
          finally
            QSale.Free;
          end;

          CreatedSaleId := Sale.id.AsInt64;

          for I := 0 to ItemsToInsert.Count - 1 do
          begin
            ItemsToInsert[I].sale_id.Value := CreatedSaleId;
            QItem := TDeltaQuery<TSaleItem>.Create(Lease);
            try
              QItem.Insert(ItemsToInsert[I]);
            finally
              QItem.Free;
            end;
          end;

          for I := 0 to ProductsToUpdate.Count - 1 do
          begin
            QProd := TDeltaQuery<TProduct>.Create(Lease);
            try
              QProd.Update(ProductsToUpdate[I]);
            finally
              QProd.Free;
            end;
          end;

          Lease.Commit;
        finally
          Sale.Free;
        end;

        // Reload complete sale with items for response and SSE notification
        QSale := TDeltaQuery<TSale>.Create(Lease);
        try
          Sale := QSale.Include('items').FindById(CreatedSaleId);
          try
            LoadSaleItems(Lease, Sale);
            JsonBytes := TDeltaFastJsonStreamer.ModelToJson(Sale);
          finally
            Sale.Free;
          end;
        finally
          QSale.Free;
        end;

        // Publish real-time W3C SSE event to subscribed clients
        if Assigned(RmsEventBroker) then
          RmsEventBroker.Publish('sales', string(JsonBytes), 'TSaleCreated',
            'sale-' + IntToStr(CreatedSaleId));

        AResp.Code := HTTP_STATUS_CREATED;
        AResp.ContentType := MIME_APPLICATION_JSON;
        AResp.Content := JsonBytes;
      except
        Lease.Rollback;
        raise;
      end;
    finally
      Cust.Free;
      ItemsToInsert.Free;
      ProductsToUpdate.Free;
    end;
  finally
    BodyObj.Free;
  end;
end;

{ POST /api/v1/sales/:id/cancel - Cancel sale, restore stock, and publish SSE event }
procedure HandleCancelSale(AReq: TRequest; AResp: TResponse);
var
  SaleId: Int64;
  Lease: IDeltaORMEngine;
  QSale: TDeltaQuery<TSale>;
  QProd: TDeltaQuery<TProduct>;
  Sale: TSale;
  Item: TSaleItem;
  Prod: TProduct;
  JsonBytes: RawByteString;
  I: Integer;
begin
  SaleId := StrToInt64Def(AReq.RouteParams[PARAM_ID], 0);
  if SaleId <= 0 then
    raise EBadRequest.Create('Invalid sale identifier.');

  Lease := RmsPool.Acquire;
  QSale := TDeltaQuery<TSale>.Create(Lease);
  try
    Sale := QSale.Include('items').FindById(SaleId);
    if Sale = nil then
      raise ENotFound.CreateFmt('Sale #%d not found.', [SaleId]);
    try
      LoadSaleItems(Lease, Sale);
      if SameText(Sale.status.AsString, SALE_STATUS_CANCELLED) then
        raise EConflict.CreateFmt('Sale #%d is already cancelled.', [SaleId]);

      Lease.StartTransaction;
      try
        // 1. Restore stock for each sale item
        for I := 0 to Sale.items.Count - 1 do
        begin
          Item := TSaleItem(Sale.items[I]);
          QProd := TDeltaQuery<TProduct>.Create(Lease);
          try
            Prod := QProd.FindById(Item.product_id.AsInt64);
            if Prod <> nil then
            begin
              try
                Prod.stock_qty.Value := Prod.stock_qty.AsFloat + Item.quantity.AsFloat;
                QProd.Update(Prod);
              finally
                Prod.Free;
              end;
            end;
          finally
            QProd.Free;
          end;
        end;

        // 2. Mark sale as CANCELLED via fluent TDeltaQuery.Update
        Sale.status.Value := SALE_STATUS_CANCELLED;
        QSale.Update(Sale);

        Lease.Commit;

        JsonBytes := TDeltaFastJsonStreamer.ModelToJson(Sale);

        // Broadcast cancellation event over SSE
        if Assigned(RmsEventBroker) then
          RmsEventBroker.Publish('sales', string(JsonBytes), 'TSaleCancelled',
            'sale-cancel-' + IntToStr(SaleId));

        AResp.Code := HTTP_STATUS_OK;
        AResp.ContentType := MIME_APPLICATION_JSON;
        AResp.Content := JsonBytes;
      except
        Lease.Rollback;
        raise;
      end;
    finally
      Sale.Free;
    end;
  finally
    QSale.Free;
  end;
end;

{ GET /api/v1/events/sales - Real-time W3C SSE stream with heartbeat and Last-Event-ID replay }
procedure HandleSalesEventStream(AReq: TRequest; AResp: TResponse);
begin
  RmsEventBroker.ServeConnection(
    AReq,
    AResp,
    'sales',
    SSE_DEFAULT_HEARTBEAT_MS,
    True
  );
end;

procedure RegisterRmsStarterRoutes;
var
  SalesGroup: TSwaggerRouteGroup;
begin
  // Register DeltaModel OpenAPI 3.1 component schemas for custom routes
  SwaggerRouter.EnsureModel('TSaleItem', TSaleItem.SwaggerSchema);
  SwaggerRouter.EnsureModel('TSale', TSale.SwaggerSchema);

  // 1. System health endpoint
  SwaggerRouter.Get(PATH_HEALTH, @HandleHealth)
    .Tag(TAG_SYSTEM)
    .Summary('Service health and catalog counters')
    .Description('Returns service liveness, entity counts, and active SSE subscriber count.')
    .AddResponse(
      HTTP_STATUS_OK,
      'Health status payload',
      '{"type":"object","properties":{"status":{"type":"string"},"service":{"type":"string"},"products_count":{"type":"integer"},"customers_count":{"type":"integer"},"sales_count":{"type":"integer"},"sse_subscribers":{"type":"integer"}}}',
      'application/json'
    );

  // 2. Custom low-stock query (registered before CRUD /:id route)
  SwaggerRouter.Get(PATH_LOW_STOCK, @HandleLowStockProducts)
    .Tag(TAG_PRODUCTS)
    .Summary('List low-stock products')
    .Description('Uses type-safe TDeltaQuery predicates and a zero-alloc reusable cursor.')
    .QueryParam(PARAM_THRESHOLD, 'number', '10', 'Maximum stock quantity threshold')
    .AddResponse(
      HTTP_STATUS_OK,
      'Low-stock products list',
      '{"type":"object","properties":{"threshold":{"type":"number"},"count":{"type":"integer"},"data":{"type":"array","items":{"$ref":"#/components/schemas/TProduct"}}}}',
      'application/json'
    );

  // 3. Full CRUD for Products
  TZenithCrud<TProduct>.Create(PATH_PRODUCTS, RmsPool)
    .WithTag(TAG_PRODUCTS)
    .Register;

  // 4. Full CRUD for Customers
  TZenithCrud<TCustomer>.Create(PATH_CUSTOMERS, RmsPool)
    .WithTag(TAG_CUSTOMERS)
    .Register;

  // 5. Fluent Sales API group with RFC 9457 Problem Details
  SalesGroup := SwaggerRouter.Group(PATH_SALES)
    .Tag(TAG_SALES)
    .StandardProblems;

  SalesGroup.Get(PATH_SUB_ROOT, @HandleListSales)
    .Summary('List sales (paginated)')
    .Description('Returns paginated sales with optional type-safe status filter.')
    .QueryParam(PARAM_PAGE, 'integer', '1', 'Page number (1-based)')
    .QueryParam(PARAM_PAGE_SIZE, 'integer', '10', 'Items per page (max 100)')
    .QueryParam(PARAM_STATUS, 'string', '', 'Filter by status (CONFIRMED, CANCELLED)')
    .ProducesPaginated(HTTP_STATUS_OK, 'TSale', 'Paginated sales response');

  SalesGroup.Get(PATH_SUB_BY_ID, @HandleGetSaleById)
    .Summary('Get sale by ID')
    .Description('Returns a single sale including its line items via eager loading.')
    .PathParam(PARAM_ID, 'integer', 'Numeric sale ID')
    .Produces(HTTP_STATUS_OK, 'TSale', 'Sale with line items');

  SalesGroup.Post(PATH_SUB_ROOT, @HandleCreateSale)
    .Summary('Create a new sale')
    .Description('Validates stock and credit limit, commits atomically, and emits TSaleCreated via SSE.')
    .ConsumesJson('TSale', True, 'Sale payload with customer_id and items array')
    .Produces(HTTP_STATUS_CREATED, 'TSale', 'Created sale with line items');

  SalesGroup.Post(PATH_SUB_CANCEL, @HandleCancelSale)
    .Summary('Cancel a sale')
    .Description('Cancels the sale, restores inventory atomically, and emits TSaleCancelled via SSE.')
    .PathParam(PARAM_ID, 'integer', 'Numeric sale ID')
    .Produces(HTTP_STATUS_OK, 'TSale', 'Cancelled sale');

  // 6. Real-time W3C Server-Sent Events stream
  SwaggerRouter.Get(PATH_EVENTS_SALES, @HandleSalesEventStream)
    .Tag(TAG_EVENTS)
    .Summary('Subscribe to real-time sales events (W3C SSE)')
    .Description('Opens a persistent text/event-stream connection with automatic heartbeats and Last-Event-ID replay.')
    .AddResponse(
      HTTP_STATUS_OK,
      'W3C Server-Sent Events stream',
      '{"type":"string"}',
      'text/event-stream'
    );
end;

end.
