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
  Zenith.Crud,
  Zenith.Crud.Interceptor,
  Zenith.Security,
  Swagger4Laz,
  DeltaModel,
  DeltaModel.Generics,
  DeltaModel.ORM.Interfaces,
  DeltaModel.ORM.Connection,
  DeltaModel.ORM.Pool,
  DeltaModel.ORM.DML,
  DeltaModel.JsonStreamer,
  Order.Model;

procedure RegisterOrderDemoRoutes;

implementation

{ Resposta RFC 7807 Problem Details }
procedure SendProblemResponse(AResp: TResponse; AStatus: Integer; const ATitle, ADetail: string);
var
  Doc: TJSONObject;
begin
  Doc := TJSONObject.Create;
  try
    Doc.Add('type', 'https://tools.ietf.org/html/rfc7807');
    Doc.Add('title', ATitle);
    Doc.Add('status', AStatus);
    Doc.Add('detail', ADetail);
    AResp.Code := AStatus;
    AResp.ContentType := 'application/problem+json';
    AResp.Content := Doc.AsJSON;
  finally
    Doc.Free;
  end;
end;

{ GET /api/v1/orders - Listar Pedidos de Venda }
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
  Page := StrToIntDef(AReq.QueryFields.Values['page'], 1);
  if Page < 1 then Page := 1;
  PageSize := StrToIntDef(AReq.QueryFields.Values['page_size'], 10);
  if PageSize < 1 then PageSize := 10;
  if PageSize > 100 then PageSize := 100;

  StatusFilter := Trim(AReq.QueryFields.Values['status']);

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

        AResp.Code := 200;
        AResp.ContentType := 'application/json';
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

{ GET /api/v1/orders/:id - Obter Pedido com Itens }
procedure HandleGetOrderById(AReq: TRequest; AResp: TResponse);
var
  OrderId: Int64;
  Lease: IDeltaORMEngine;
  Q: TDeltaQuery<TSaleOrder>;
  Order: TSaleOrder;
  JsonBytes: RawByteString;
begin
  OrderId := StrToInt64Def(AReq.RouteParams['id'], 0);
  if OrderId <= 0 then
  begin
    SendProblemResponse(AResp, 400, 'Bad Request', 'Identificador de pedido inválido.');
    Exit;
  end;

  Lease := OrderPool.Acquire;
  Q := TDeltaQuery<TSaleOrder>.Create(Lease);
  try
    Order := Q.Include('items').FindById(OrderId);
    if Order = nil then
    begin
      SendProblemResponse(AResp, 404, 'Not Found', Format('Pedido #%d não encontrado.', [OrderId]));
      Exit;
    end;

    try
      JsonBytes := TDeltaFastJsonStreamer.ModelToJson(Order);
      AResp.Code := 200;
      AResp.ContentType := 'application/json';
      AResp.Content := JsonBytes;
    finally
      Order.Free;
    end;
  finally
    Q.Free;
  end;
end;

{ POST /api/v1/orders - Criar Pedido com Validação de Estoque e Crédito }
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
begin
  if Trim(AReq.Content).IsEmpty then
  begin
    SendProblemResponse(AResp, 400, 'Bad Request', 'O corpo da requisição não pode ser vazio.');
    Exit;
  end;

  try
    JsonDoc := GetJSON(AReq.Content);
  except
    on E: Exception do
    begin
      SendProblemResponse(AResp, 400, 'Invalid JSON', 'Erro ao processar JSON: ' + E.Message);
      Exit;
    end;
  end;

  if not (JsonDoc is TJSONObject) then
  begin
    JsonDoc.Free;
    SendProblemResponse(AResp, 400, 'Invalid JSON', 'O payload raiz deve ser um objeto JSON.');
    Exit;
  end;

  BodyObj := TJSONObject(JsonDoc);
  try
    CustomerId := BodyObj.Get('customer_id', Int64(0));
    if CustomerId <= 0 then
    begin
      SendProblemResponse(AResp, 422, 'Validation Error', 'O campo customer_id é obrigatório e deve ser maior que zero.');
      Exit;
    end;

    if not (BodyObj.Find('items') is TJSONArray) then
    begin
      SendProblemResponse(AResp, 422, 'Validation Error', 'A propriedade items deve ser uma lista de itens.');
      Exit;
    end;

    ItemsArray := TJSONArray(BodyObj.Find('items'));
    if ItemsArray.Count = 0 then
    begin
      SendProblemResponse(AResp, 422, 'Validation Error', 'O pedido deve conter ao menos 1 item na lista items.');
      Exit;
    end;

    Lease := OrderPool.Acquire;

    // 1. Validar Cliente
    QCust := TDeltaQuery<TCustomer>.Create(Lease);
    try
      Cust := QCust.FindById(CustomerId);
      if Cust = nil then
      begin
        SendProblemResponse(AResp, 404, 'Customer Not Found', Format('Cliente #%d não encontrado.', [CustomerId]));
        Exit;
      end;
    finally
      QCust.Free;
    end;

    ProductsToUpdate := TFPGObjectList<TProduct>.Create(True);
    ItemsToInsert := TFPGObjectList<TSaleOrderItem>.Create(True);
    try
      TotalAmount := 0.0;

      // 2. Validar cada Produto e Estoque
      for I := 0 to ItemsArray.Count - 1 do
      begin
        if not (ItemsArray[I] is TJSONObject) then
        begin
          SendProblemResponse(AResp, 422, 'Validation Error', 'Cada item do pedido deve ser um objeto JSON.');
          Exit;
        end;
        ItemData := TJSONObject(ItemsArray[I]);
        ProdId := ItemData.Get('product_id', Int64(0));
        Qty := ItemData.Get('quantity', 0.0);

        if (ProdId <= 0) or (Qty <= 0) then
        begin
          SendProblemResponse(AResp, 422, 'Validation Error', 'product_id e quantity positiva são obrigatórios em cada item.');
          Exit;
        end;

        QProd := TDeltaQuery<TProduct>.Create(Lease);
        try
          Prod := QProd.FindById(ProdId);
          if Prod = nil then
          begin
            SendProblemResponse(AResp, 404, 'Product Not Found', Format('Produto #%d não encontrado.', [ProdId]));
            Exit;
          end;

          if not Prod.active.AsBoolean then
          begin
            Prod.Free;
            SendProblemResponse(AResp, 422, 'Product Inactive', Format('Produto #%d encontra-se inativo.', [ProdId]));
            Exit;
          end;

          if Prod.stock.AsFloat < Qty then
          begin
            Prod.Free;
            SendProblemResponse(AResp, 422, 'Insufficient Stock',
              Format('Estoque insuficiente para o produto "%s". Disponível: %.2f, Solicitado: %.2f',
              [Prod.name.AsString, Prod.stock.AsFloat, Qty]));
            Exit;
          end;

          LinePrice := Prod.price.AsFloat;
          LineTotal := LinePrice * Qty;
          TotalAmount := TotalAmount + LineTotal;

          // Prepara item para inserção
          OrderItem := TSaleOrderItem.Create;
          OrderItem.product_id.Value := ProdId;
          OrderItem.quantity.Value := Qty;
          OrderItem.unit_price.Value := LinePrice;
          OrderItem.total_price.Value := LineTotal;
          ItemsToInsert.Add(OrderItem);

          // Atualiza saldo de estoque na memória
          Prod.stock.Value := Prod.stock.AsFloat - Qty;
          ProductsToUpdate.Add(Prod);
        finally
          QProd.Free;
        end;
      end;

      // 3. Validar Limite de Crédito do Cliente
      if (Cust.credit_limit.AsFloat > 0) and (TotalAmount > Cust.credit_limit.AsFloat) then
      begin
        SendProblemResponse(AResp, 422, 'Credit Limit Exceeded',
          Format('Limite de crédito do cliente excedido. Limite disponível: R$ %.2f, Total do pedido: R$ %.2f',
          [Cust.credit_limit.AsFloat, TotalAmount]));
        Exit;
      end;

      // 4. Gravação Atômica (Transação Única)
      Lease.StartTransaction;
      try
        Order := TSaleOrder.Create;
        try
          Order.order_number.Value := Format('PED-%s-%04d', [FormatDateTime('YYYYMMDD', Now), Random(9000) + 1000]);
          Order.customer_id.Value := CustomerId;
          Order.order_date.Value := Now;
          Order.total_amount.Value := TotalAmount;
          Order.status.Value := 'CONFIRMED';

          QOrder := TDeltaQuery<TSaleOrder>.Create(Lease);
          try
            QOrder.Insert(Order);
          finally
            QOrder.Free;
          end;

          // Inserir Itens com FK order_id
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

          // Atualizar estoque dos produtos
          for I := 0 to ProductsToUpdate.Count - 1 do
            TUpdate.UpdateObject(Lease, ProductsToUpdate[I]);

          Lease.Commit;

          // Recarregar pedido completo com eager loading para resposta
          QOrder := TDeltaQuery<TSaleOrder>.Create(Lease);
          try
            Order.Free;
            Order := QOrder.Include('items').FindById(Order.id.AsInt64);
            JsonBytes := TDeltaFastJsonStreamer.ModelToJson(Order);

            AResp.Code := 201;
            AResp.ContentType := 'application/json';
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

{ POST /api/v1/orders/:id/cancel - Cancelar Pedido e Estornar Estoque }
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
  OrderId := StrToInt64Def(AReq.RouteParams['id'], 0);
  if OrderId <= 0 then
  begin
    SendProblemResponse(AResp, 400, 'Bad Request', 'Identificador de pedido inválido.');
    Exit;
  end;

  Lease := OrderPool.Acquire;
  QOrder := TDeltaQuery<TSaleOrder>.Create(Lease);
  try
    Order := QOrder.Include('items').FindById(OrderId);
    if Order = nil then
    begin
      SendProblemResponse(AResp, 404, 'Not Found', Format('Pedido #%d não encontrado.', [OrderId]));
      Exit;
    end;

    try
      if SameText(Order.status.AsString, 'CANCELLED') then
      begin
        SendProblemResponse(AResp, 400, 'Order Already Cancelled', 'O pedido já se encontra cancelado.');
        Exit;
      end;

      Lease.StartTransaction;
      try
        // 1. Estornar estoque dos itens
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

        // 2. Atualizar status do pedido
        Order.status.Value := 'CANCELLED';
        TUpdate.UpdateObject(Lease, Order);

        Lease.Commit;

        JsonBytes := TDeltaFastJsonStreamer.ModelToJson(Order);
        AResp.Code := 200;
        AResp.ContentType := 'application/json';
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
  // 1. CRUD de Produtos com política RBAC declarativa
  ProductRBAC := TZRBACPolicy<TProduct>.Create;
  ProductRBAC
    .AllowRoles(caCreate, ['admin'])
    .AllowRoles(caUpdate, ['admin'])
    .AllowRoles(caDelete, ['admin']);

  TZenithCrud<TProduct>.Create('/api/v1/products', OrderPool)
    .WithTag('Produtos')
    .WithRBAC(ProductRBAC)
    .Register;

  // 2. CRUD de Clientes
  TZenithCrud<TCustomer>.Create('/api/v1/customers', OrderPool)
    .WithTag('Clientes')
    .Register;

  // 3. RMS Orders API com TSwaggerRouteGroup fluente
  Group := SwaggerRouter.Group('/api/v1/orders');
  Group.Tag('Pedidos (RMS)');

  Group.Get('', @HandleGetOrders)
    .SetSummary('Listar pedidos de venda')
    .SetDescription('Retorna lista paginada de pedidos com opção de filtro por status')
    .QueryParam('page', 'integer', '1', 'Número da página')
    .QueryParam('page_size', 'integer', '10', 'Registros por página')
    .QueryParam('status', 'string', '', 'Filtrar por status (ex: CONFIRMED, CANCELLED)')
    .ProducesPaginated(200, 'TSaleOrder', 'Lista paginada de pedidos')
    .ProducesStandardProblems;

  Group.Get('/:id', @HandleGetOrderById)
    .SetSummary('Obter pedido por ID')
    .SetDescription('Retorna dados detalhados do pedido incluindo a coleção de itens (Include eager loading)')
    .PathParam('id', 'integer', 'ID numérico do pedido')
    .Produces(200, 'TSaleOrder', 'Pedido completo com itens')
    .ProducesStandardProblems;

  Group.Post('', @HandleCreateOrder)
    .SetSummary('Criar novo pedido de venda')
    .SetDescription('Valida estoque disponível dos produtos, limite de crédito do cliente e efetua a baixa de estoque atômica')
    .ConsumesJson('TSaleOrder', True, 'Payload do pedido com customer_id e array de items')
    .Produces(201, 'TSaleOrder', 'Pedido criado com sucesso')
    .ProducesStandardProblems;

  Group.Post('/:id/cancel', @HandleCancelOrder)
    .SetSummary('Cancelar pedido de venda')
    .SetDescription('Cancela o pedido e estorna atomicamente o saldo de estoque dos produtos')
    .PathParam('id', 'integer', 'ID numérico do pedido')
    .Produces(200, 'TSaleOrder', 'Pedido cancelado e estoque estornado')
    .ProducesStandardProblems;
end;

initialization
  RegisterOrderDemoRoutes;

end.
