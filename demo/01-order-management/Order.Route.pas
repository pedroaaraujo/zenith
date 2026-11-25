unit Order.Route;

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
  Zenith.Crud.Interceptor,
  Zenith.Security,
  Swagger4Laz,
  DeltaModel,
  DeltaModel.Generics,
  DeltaModel.ORM.Interfaces,
  DeltaModel.ORM.Pool,
  DeltaModel.ORM.DML,
  DeltaModel.JsonStreamer,
  Order.Model;

const
  { API Routes and Paths }
  PATH_PRODUCTS    = '/api/v1/products';
  PATH_CUSTOMERS   = '/api/v1/customers';
  PATH_ORDERS      = '/api/v1/orders';
  PATH_SUB_ROOT    = '';
  PATH_SUB_BY_ID   = '/:id';
  PATH_SUB_CANCEL  = '/:id/cancel';

  { Route and Query Parameters }
  PARAM_ID         = 'id';
  PARAM_PAGE       = 'page';
  PARAM_PAGE_SIZE  = 'page_size';
  PARAM_STATUS     = 'status';

  { Default Pagination }
  DEFAULT_PAGE      = 1;
  DEFAULT_PAGE_SIZE = 10;
  MAX_PAGE_SIZE     = 100;

  { Security Roles (RBAC) }
  ROLE_ADMIN = 'admin';

  { Swagger Tags }
  TAG_PRODUCTS  = 'Produtos';
  TAG_CUSTOMERS = 'Clientes';
  TAG_ORDERS    = 'Pedidos (RMS)';

  { Swagger Descriptions and Summaries }
  SUMMARY_LIST_ORDERS      = 'Listar pedidos de venda';
  DESC_LIST_ORDERS         = 'Retorna lista paginada de pedidos com opção de filtro por status';
  SUMMARY_GET_ORDER_BY_ID  = 'Obter pedido por ID';
  DESC_GET_ORDER_BY_ID     = 'Retorna dados detalhados do pedido incluindo a coleção de itens (Include eager loading)';
  SUMMARY_CREATE_ORDER     = 'Criar novo pedido de venda';
  DESC_CREATE_ORDER        = 'Valida estoque disponível dos produtos, limite de crédito do cliente e efetua a baixa de estoque atômica';
  SUMMARY_CANCEL_ORDER     = 'Cancelar pedido de venda';
  DESC_CANCEL_ORDER        = 'Cancela o pedido e estorna atomicamente o saldo de estoque dos produtos';

  DOC_PAYLOAD_ORDER        = 'Payload do pedido com customer_id e array de items';
  DOC_RESP_ORDER_CREATED   = 'Pedido criado com sucesso';
  DOC_RESP_ORDER_WITH_ITEMS= 'Pedido completo com itens';
  DOC_RESP_ORDER_CANCELLED = 'Pedido cancelado e estoque estornado';
  DOC_RESP_ORDERS_PAGINATED= 'Lista paginada de pedidos';
  DOC_PARAM_PAGE           = 'Número da página';
  DOC_PARAM_PAGE_SIZE      = 'Registros por página';
  DOC_PARAM_STATUS         = 'Filtrar por status (ex: CONFIRMED, CANCELLED)';
  DOC_PARAM_ID             = 'ID numérico do pedido';

  { RFC 7807 Validation and Error Messages }
  MSG_INVALID_ORDER_ID         = 'Identificador de pedido inválido.';
  MSG_ORDER_NOT_FOUND          = 'Pedido #%d não encontrado.';
  MSG_ORDER_ALREADY_CANCELLED  = 'O pedido #%d já se encontra cancelado.';
  MSG_EMPTY_REQUEST_BODY       = 'O corpo da requisição não pode ser vazio.';
  MSG_INVALID_JSON_PAYLOAD     = 'Erro ao processar JSON: %s';
  MSG_JSON_ROOT_MUST_BE_OBJECT = 'O payload raiz deve ser um objeto JSON.';
  MSG_CUSTOMER_ID_REQUIRED     = 'O campo customer_id é obrigatório e deve ser maior que zero.';
  MSG_ITEMS_PROPERTY_REQUIRED  = 'A propriedade items deve ser uma lista de itens.';
  MSG_ITEMS_CANNOT_BE_EMPTY    = 'O pedido deve conter ao menos 1 item na lista items.';
  MSG_ITEM_MUST_BE_OBJECT      = 'Cada item do pedido deve ser um objeto JSON.';
  MSG_ITEM_FIELDS_REQUIRED     = 'product_id e quantity positiva são obrigatórios em cada item.';
  MSG_CUSTOMER_NOT_FOUND       = 'Cliente #%d não encontrado.';
  MSG_PRODUCT_NOT_FOUND        = 'Produto #%d não encontrado.';
  MSG_PRODUCT_INACTIVE         = 'Produto #%d ("%s") encontra-se inativo.';
  MSG_INSUFFICIENT_STOCK       = 'Estoque insuficiente para o produto "%s". Disponível: %.2f, Solicitado: %.2f';
  MSG_CREDIT_LIMIT_EXCEEDED    = 'Limite de crédito do cliente excedido. Limite disponível: R$ %.2f, Total do pedido: R$ %.2f';

procedure RegisterOrderDemoRoutes;

implementation

{ GET /api/v1/orders - List Sales Orders }
procedure HandleGetOrders(AReq: TRequest; AResp: TResponse);
var
  Page, PageSize, TotalRecords, TotalPages: Integer;
  StatusFilter: string;
  Lease: IDeltaORMEngine;
  Q: TDeltaQuery<TSaleOrder>;
  OrderList: TGDeltaModelList<TSaleOrder>;
  ResponseObj: TJSONObject;
  DataArray: TJSONArray;
  I: Integer;
  OrderJsonDoc: TJSONData;
begin
  Page := StrToIntDef(AReq.QueryFields.Values[PARAM_PAGE], DEFAULT_PAGE);
  if Page < 1 then Page := DEFAULT_PAGE;
  PageSize := StrToIntDef(AReq.QueryFields.Values[PARAM_PAGE_SIZE], DEFAULT_PAGE_SIZE);
  if PageSize < 1 then PageSize := DEFAULT_PAGE_SIZE;
  if PageSize > MAX_PAGE_SIZE then PageSize := MAX_PAGE_SIZE;

  StatusFilter := Trim(AReq.QueryFields.Values[PARAM_STATUS]);

  Lease := OrderPool.Acquire;
  Q := TDeltaQuery<TSaleOrder>.Create(Lease);
  try
    if not StatusFilter.IsEmpty then
      Q.Where('status = ' + QuotedStr(StatusFilter));

    TotalRecords := Q.Count;
    TotalPages := (TotalRecords + PageSize - 1) div PageSize;
    if TotalPages < 1 then TotalPages := 1;

    OrderList := Q
      .OrderBy('id DESC')
      .Limit(PageSize)
      .Offset((Page - 1) * PageSize)
      .All;
    try
      ResponseObj := TJSONObject.Create;
      try
        ResponseObj.Add('page', Page);
        ResponseObj.Add('page_size', PageSize);
        ResponseObj.Add('total_records', TotalRecords);
        ResponseObj.Add('total_pages', TotalPages);

        DataArray := TJSONArray.Create;
        ResponseObj.Add('data', DataArray);

        for I := 0 to OrderList.Count - 1 do
        begin
          OrderJsonDoc := GetJSON(TDeltaFastJsonStreamer.ModelToJson(OrderList[I]));
          DataArray.Add(OrderJsonDoc);
        end;

        AResp.Code := HTTP_STATUS_OK;
        AResp.ContentType := MIME_APPLICATION_JSON;
        AResp.Content := ResponseObj.AsJSON;
      finally
        ResponseObj.Free;
      end;
    finally
      OrderList.Free;
    end;
  finally
    Q.Free;
  end;
end;

{ GET /api/v1/orders/:id - Get Order with Items }
procedure HandleGetOrderById(AReq: TRequest; AResp: TResponse);
var
  OrderId: Int64;
  Lease: IDeltaORMEngine;
  Q: TDeltaQuery<TSaleOrder>;
  Order: TSaleOrder;
  JsonBytes: RawByteString;
begin
  OrderId := StrToInt64Def(AReq.RouteParams[PARAM_ID], 0);
  if OrderId <= 0 then
    raise EBadRequest.Create(MSG_INVALID_ORDER_ID);

  Lease := OrderPool.Acquire;
  Q := TDeltaQuery<TSaleOrder>.Create(Lease);
  try
    Order := Q.Include('items').FindById(OrderId);
    if Order = nil then
      raise ENotFound.CreateFmt(MSG_ORDER_NOT_FOUND, [OrderId]);

    try
      JsonBytes := TDeltaFastJsonStreamer.ModelToJson(Order);
      AResp.Code := HTTP_STATUS_OK;
      AResp.ContentType := MIME_APPLICATION_JSON;
      AResp.Content := JsonBytes;
    finally
      Order.Free;
    end;
  finally
    Q.Free;
  end;
end;

{ POST /api/v1/orders - Create Order with Stock and Credit Validation }
procedure HandleCreateOrder(AReq: TRequest; AResp: TResponse);
var
  JsonDoc: TJSONData;
  BodyObj: TJSONObject;
  ItemsArray: TJSONArray;
  CustomerId: Int64;
  Lease: IDeltaORMEngine;
  QCust: TDeltaQuery<TCustomer>;
  QProd: TDeltaQuery<TProduct>;
  QOrder: TDeltaQuery<TSaleOrder>;
  QItem: TDeltaQuery<TSaleOrderItem>;
  Cust: TCustomer;
  Prod: TProduct;
  Order: TSaleOrder;
  OrderItem: TSaleOrderItem;
  I: Integer;
  ItemData: TJSONObject;
  ProdId: Int64;
  Qty, LinePrice, LineTotal, TotalAmount: Double;
  ItemsToInsert: TFPGObjectList<TSaleOrderItem>;
  ProductsToUpdate: TFPGObjectList<TProduct>;
  JsonBytes: RawByteString;
  ProdName: string;
  StockAvail: Double;
begin
  if Trim(AReq.Content).IsEmpty then
    raise EBadRequest.Create(MSG_EMPTY_REQUEST_BODY);

  try
    JsonDoc := GetJSON(AReq.Content);
  except
    on E: Exception do
      raise EBadRequest.CreateFmt(MSG_INVALID_JSON_PAYLOAD, [E.Message]);
  end;

  if not (JsonDoc is TJSONObject) then
  begin
    JsonDoc.Free;
    raise EBadRequest.Create(MSG_JSON_ROOT_MUST_BE_OBJECT);
  end;

  BodyObj := TJSONObject(JsonDoc);
  try
    CustomerId := BodyObj.Get('customer_id', Int64(0));
    if CustomerId <= 0 then
      raise EUnprocessableEntity.Create(MSG_CUSTOMER_ID_REQUIRED);

    if not (BodyObj.Find('items') is TJSONArray) then
      raise EUnprocessableEntity.Create(MSG_ITEMS_PROPERTY_REQUIRED);

    ItemsArray := TJSONArray(BodyObj.Find('items'));
    if ItemsArray.Count = 0 then
      raise EUnprocessableEntity.Create(MSG_ITEMS_CANNOT_BE_EMPTY);

    Lease := OrderPool.Acquire;

    Cust := nil;
    ProductsToUpdate := TFPGObjectList<TProduct>.Create(True);
    ItemsToInsert := TFPGObjectList<TSaleOrderItem>.Create(True);
    try
      // 1. Validate Customer
      QCust := TDeltaQuery<TCustomer>.Create(Lease);
      try
        Cust := QCust.FindById(CustomerId);
        if Cust = nil then
          raise ENotFound.CreateFmt(MSG_CUSTOMER_NOT_FOUND, [CustomerId]);
      finally
        QCust.Free;
      end;

      TotalAmount := 0.0;

      // 2. Validate each Product and Stock
      for I := 0 to ItemsArray.Count - 1 do
      begin
        if not (ItemsArray[I] is TJSONObject) then
          raise EUnprocessableEntity.Create(MSG_ITEM_MUST_BE_OBJECT);

        ItemData := TJSONObject(ItemsArray[I]);
        ProdId := ItemData.Get('product_id', Int64(0));
        Qty := ItemData.Get('quantity', 0.0);

        if (ProdId <= 0) or (Qty <= 0) then
          raise EUnprocessableEntity.Create(MSG_ITEM_FIELDS_REQUIRED);

        QProd := TDeltaQuery<TProduct>.Create(Lease);
        try
          Prod := QProd.FindById(ProdId);
          if Prod = nil then
            raise ENotFound.CreateFmt(MSG_PRODUCT_NOT_FOUND, [ProdId]);

          if not Prod.active.AsBoolean then
          begin
            ProdName := Prod.name.AsString;
            Prod.Free;
            raise EUnprocessableEntity.CreateFmt(MSG_PRODUCT_INACTIVE, [ProdId, ProdName]);
          end;

          if Prod.stock.AsFloat < Qty then
          begin
            ProdName := Prod.name.AsString;
            StockAvail := Prod.stock.AsFloat;
            Prod.Free;
            raise EUnprocessableEntity.CreateFmt(MSG_INSUFFICIENT_STOCK, [ProdName, StockAvail, Qty]);
          end;

          LinePrice := Prod.price.AsFloat;
          LineTotal := LinePrice * Qty;
          TotalAmount := TotalAmount + LineTotal;

          // Prepare item for insertion
          OrderItem := TSaleOrderItem.Create;
          OrderItem.product_id.Value := ProdId;
          OrderItem.quantity.Value := Qty;
          OrderItem.unit_price.Value := LinePrice;
          OrderItem.total_price.Value := LineTotal;
          ItemsToInsert.Add(OrderItem);

          // Update stock balance in memory
          Prod.stock.Value := Prod.stock.AsFloat - Qty;
          ProductsToUpdate.Add(Prod);
        finally
          QProd.Free;
        end;
      end;

      // 3. Validate Customer Credit Limit
      if (Cust.credit_limit.AsFloat > 0) and (TotalAmount > Cust.credit_limit.AsFloat) then
        raise EUnprocessableEntity.CreateFmt(MSG_CREDIT_LIMIT_EXCEEDED, [Cust.credit_limit.AsFloat, TotalAmount]);

      // 4. Atomic Commit (Single Transaction)
      Lease.StartTransaction;
      try
        Order := TSaleOrder.Create;
        try
          Order.order_number.Value := Format('PED-%s-%04d', [FormatDateTime('YYYYMMDD', Now), Random(9000) + 1000]);
          Order.customer_id.Value := CustomerId;
          Order.order_date.Value := Now;
          Order.total_amount.Value := TotalAmount;
          Order.status.Value := ORDER_STATUS_CONFIRMED;

          QOrder := TDeltaQuery<TSaleOrder>.Create(Lease);
          try
            QOrder.Insert(Order);
          finally
            QOrder.Free;
          end;

          // Insert Items with FK order_id
          for I := 0 to ItemsToInsert.Count - 1 do
          begin
            ItemsToInsert[I].order_id.Value := Order.id.AsInt64;
            QItem := TDeltaQuery<TSaleOrderItem>.Create(Lease);
            try
              QItem.Insert(ItemsToInsert[I]);
            finally
              QItem.Free;
            end;
          end;

          // Update product stock
          for I := 0 to ProductsToUpdate.Count - 1 do
            TUpdate.UpdateObject(Lease, ProductsToUpdate[I]);

          Lease.Commit;

          // Reload complete order with eager loading for response
          QOrder := TDeltaQuery<TSaleOrder>.Create(Lease);
          try
            Order.Free;
            Order := QOrder.Include('items').FindById(Order.id.AsInt64);
            JsonBytes := TDeltaFastJsonStreamer.ModelToJson(Order);

            AResp.Code := HTTP_STATUS_CREATED;
            AResp.ContentType := MIME_APPLICATION_JSON;
            AResp.Content := JsonBytes;
          finally
            QOrder.Free;
          end;
        finally
          Order.Free;
        end;
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

{ POST /api/v1/orders/:id/cancel - Cancel Order and Restore Stock }
procedure HandleCancelOrder(AReq: TRequest; AResp: TResponse);
var
  OrderId: Int64;
  Lease: IDeltaORMEngine;
  QOrder: TDeltaQuery<TSaleOrder>;
  QProd: TDeltaQuery<TProduct>;
  Order: TSaleOrder;
  Item: TSaleOrderItem;
  Prod: TProduct;
  I: Integer;
  JsonBytes: RawByteString;
begin
  OrderId := StrToInt64Def(AReq.RouteParams[PARAM_ID], 0);
  if OrderId <= 0 then
    raise EBadRequest.Create(MSG_INVALID_ORDER_ID);

  Lease := OrderPool.Acquire;
  QOrder := TDeltaQuery<TSaleOrder>.Create(Lease);
  try
    Order := QOrder.Include('items').FindById(OrderId);
    if Order = nil then
      raise ENotFound.CreateFmt(MSG_ORDER_NOT_FOUND, [OrderId]);

    try
      if SameText(Order.status.AsString, ORDER_STATUS_CANCELLED) then
        raise EBadRequest.CreateFmt(MSG_ORDER_ALREADY_CANCELLED, [OrderId]);

      Lease.StartTransaction;
      try
        // 1. Revert item stock
        for I := 0 to Order.items.Count - 1 do
        begin
          Item := TSaleOrderItem(Order.items[I]);
          QProd := TDeltaQuery<TProduct>.Create(Lease);
          try
            Prod := QProd.FindById(Item.product_id.AsInt64);
            if Prod <> nil then
            begin
              try
                Prod.stock.Value := Prod.stock.AsFloat + Item.quantity.AsFloat;
                TUpdate.UpdateObject(Lease, Prod);
              finally
                Prod.Free;
              end;
            end;
          finally
            QProd.Free;
          end;
        end;

        // 2. Update order status
        Order.status.Value := ORDER_STATUS_CANCELLED;
        TUpdate.UpdateObject(Lease, Order);

        Lease.Commit;

        JsonBytes := TDeltaFastJsonStreamer.ModelToJson(Order);
        AResp.Code := HTTP_STATUS_OK;
        AResp.ContentType := MIME_APPLICATION_JSON;
        AResp.Content := JsonBytes;
      except
        Lease.Rollback;
        raise;
      end;
    finally
      Order.Free;
    end;
  finally
    QOrder.Free;
  end;
end;

procedure RegisterOrderDemoRoutes;
var
  ProductRBAC: TZRBACPolicy<TProduct>;
  Group: TSwaggerRouteGroup;
begin
  // 1. Product CRUD with declarative RBAC policy
  ProductRBAC := TZRBACPolicy<TProduct>.Create;
  ProductRBAC
    .AllowRoles(caCreate, [ROLE_ADMIN])
    .AllowRoles(caUpdate, [ROLE_ADMIN])
    .AllowRoles(caDelete, [ROLE_ADMIN]);

  TZenithCrud<TProduct>.Create(PATH_PRODUCTS, OrderPool)
    .WithTag(TAG_PRODUCTS)
    .WithRBAC(ProductRBAC)
    .Register;

  // 2. Customers CRUD
  TZenithCrud<TCustomer>.Create(PATH_CUSTOMERS, OrderPool)
    .WithTag(TAG_CUSTOMERS)
    .Register;

  // 3. RMS Orders API with fluent TSwaggerRouteGroup
  Group := SwaggerRouter.Group(PATH_ORDERS)
    .Tag(TAG_ORDERS)
    .StandardProblems;

  Group.Get(PATH_SUB_ROOT, @HandleGetOrders)
    .Summary(SUMMARY_LIST_ORDERS)
    .Description(DESC_LIST_ORDERS)
    .QueryParam(PARAM_PAGE, 'integer', '1', DOC_PARAM_PAGE)
    .QueryParam(PARAM_PAGE_SIZE, 'integer', '10', DOC_PARAM_PAGE_SIZE)
    .QueryParam(PARAM_STATUS, 'string', '', DOC_PARAM_STATUS)
    .ProducesPaginated(HTTP_STATUS_OK, 'TSaleOrder', DOC_RESP_ORDERS_PAGINATED);

  Group.Get(PATH_SUB_BY_ID, @HandleGetOrderById)
    .Summary(SUMMARY_GET_ORDER_BY_ID)
    .Description(DESC_GET_ORDER_BY_ID)
    .PathParam(PARAM_ID, 'integer', DOC_PARAM_ID)
    .Produces(HTTP_STATUS_OK, 'TSaleOrder', DOC_RESP_ORDER_WITH_ITEMS);

  Group.Post(PATH_SUB_ROOT, @HandleCreateOrder)
    .Summary(SUMMARY_CREATE_ORDER)
    .Description(DESC_CREATE_ORDER)
    .ConsumesJson('TSaleOrder', True, DOC_PAYLOAD_ORDER)
    .Produces(HTTP_STATUS_CREATED, 'TSaleOrder', DOC_RESP_ORDER_CREATED);

  Group.Post(PATH_SUB_CANCEL, @HandleCancelOrder)
    .Summary(SUMMARY_CANCEL_ORDER)
    .Description(DESC_CANCEL_ORDER)
    .PathParam(PARAM_ID, 'integer', DOC_PARAM_ID)
    .Produces(HTTP_STATUS_OK, 'TSaleOrder', DOC_RESP_ORDER_CANCELLED);
end;

end.
