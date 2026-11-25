unit Order.Model;

{$mode Delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  DeltaModel,
  DeltaModel.Fields,
  DeltaModel.Generics,
  DeltaModel.ORM.Interfaces,
  DeltaModel.ORM.Pool,
  DeltaModel.ORM.Schema;

const
  { Sales Order Status (RMS Starter) }
  ORDER_STATUS_DRAFT     = 'DRAFT';
  ORDER_STATUS_CONFIRMED = 'CONFIRMED';
  ORDER_STATUS_CANCELLED = 'CANCELLED';

  { Table Names }
  TABLE_PRODUCTS         = 'products';
  TABLE_CUSTOMERS        = 'customers';
  TABLE_SALE_ORDERS      = 'sale_orders';
  TABLE_SALE_ORDER_ITEMS = 'sale_order_items';

type
  TSaleOrderItem = class;

  { TProduct - Product Catalog }
  TProduct = class(TDeltaModel)
  private
    FId: TDFInt64Null;
    FCode: TDFStringRequired;
    FName: TDFStringRequired;
    FPrice: TDFDoubleRequired;
    FStock: TDFDoubleRequired;
    FActive: TDFBooleanRequired;
  public
    procedure Configure; override;
  published
    property id: TDFInt64Null read FId write FId;
    property code: TDFStringRequired read FCode write FCode;
    property name: TDFStringRequired read FName write FName;
    property price: TDFDoubleRequired read FPrice write FPrice;
    property stock: TDFDoubleRequired read FStock write FStock;
    property active: TDFBooleanRequired read FActive write FActive;
  end;

  { TCustomer - Customer Registry }
  TCustomer = class(TDeltaModel)
  private
    FId: TDFInt64Null;
    FName: TDFStringRequired;
    FDocument: TDFStringNull;
    FEmail: TDFStringNull;
    FCreditLimit: TDFDoubleRequired;
  public
    procedure Configure; override;
  published
    property id: TDFInt64Null read FId write FId;
    property name: TDFStringRequired read FName write FName;
    property document: TDFStringNull read FDocument write FDocument;
    property email: TDFStringNull read FEmail write FEmail;
    property credit_limit: TDFDoubleRequired read FCreditLimit write FCreditLimit;
  end;

  { TSaleOrder - Sales Order with 1:N Relationship }
  TSaleOrder = class(TDeltaModel)
  private
    FId: TDFInt64Null;
    FOrderNumber: TDFStringRequired;
    FCustomerId: TDFInt64Required;
    FOrderDate: TDFDateTimeRequired;
    FTotalAmount: TDFDoubleRequired;
    FStatus: TDFStringRequired;
    FItems: TDFHasMany;
  public
    procedure Configure; override;
  published
    property id: TDFInt64Null read FId write FId;
    property order_number: TDFStringRequired read FOrderNumber write FOrderNumber;
    property customer_id: TDFInt64Required read FCustomerId write FCustomerId;
    property order_date: TDFDateTimeRequired read FOrderDate write FOrderDate;
    property total_amount: TDFDoubleRequired read FTotalAmount write FTotalAmount;
    property status: TDFStringRequired read FStatus write FStatus;
    property items: TDFHasMany read FItems write FItems;
  end;

  { TSaleOrderItem - Sales Order Line Item }
  TSaleOrderItem = class(TDeltaModel)
  private
    FId: TDFInt64Null;
    FOrderId: TDFInt64Required;
    FProductId: TDFInt64Required;
    FQuantity: TDFDoubleRequired;
    FUnitPrice: TDFDoubleRequired;
    FTotalPrice: TDFDoubleRequired;
  public
    procedure Configure; override;
  published
    property id: TDFInt64Null read FId write FId;
    property order_id: TDFInt64Required read FOrderId write FOrderId;
    property product_id: TDFInt64Required read FProductId write FProductId;
    property quantity: TDFDoubleRequired read FQuantity write FQuantity;
    property unit_price: TDFDoubleRequired read FUnitPrice write FUnitPrice;
    property total_price: TDFDoubleRequired read FTotalPrice write FTotalPrice;
  end;

procedure InitializeOrderStore;
procedure SeedDatabaseIfEmpty(const AConn: IDeltaConnection);

var
  OrderPool: TDeltaConnectionPool;

implementation

uses
  Zenith.Env,
  DeltaModel.ORM.Registry,
  DeltaModel.ORM.Dialects,
  DeltaModel.ORM.Driver.SQLDB;

{ TProduct }

procedure TProduct.Configure;
begin
  inherited Configure;
  TableName := TABLE_PRODUCTS;
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
  code.Size := 50;
  name.Size := 150;
end;

{ TCustomer }

procedure TCustomer.Configure;
begin
  inherited Configure;
  TableName := TABLE_CUSTOMERS;
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
  name.Size := 150;
  document.Size := 30;
  email.Size := 100;
end;

{ TSaleOrder }

procedure TSaleOrder.Configure;
begin
  inherited Configure;
  TableName := TABLE_SALE_ORDERS;
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
  order_number.Size := 30;
  status.Size := 20;
  items.References(TSaleOrderItem);
end;

{ TSaleOrderItem }

procedure TSaleOrderItem.Configure;
begin
  inherited Configure;
  TableName := TABLE_SALE_ORDER_ITEMS;
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
end;

{ SeedDatabaseIfEmpty }

procedure SeedDatabaseIfEmpty(const AConn: IDeltaConnection);
var
  QProduct: TDeltaQuery<TProduct>;
  QCustomer: TDeltaQuery<TCustomer>;
  QOrder: TDeltaQuery<TSaleOrder>;
  QItem: TDeltaQuery<TSaleOrderItem>;
  ProdCount: Integer;
  P: TProduct;
  C: TCustomer;
  O: TSaleOrder;
  Itm: TSaleOrderItem;
begin
  QProduct := TDeltaQuery<TProduct>.Create(AConn);
  try
    ProdCount := QProduct.Count;
  finally
    QProduct.Free;
  end;

  if ProdCount = 0 then
  begin
    WriteLn('[Seed] Inserindo catálogo de produtos de demonstração...');
    AConn.StartTransaction;
    try
      // Produto 1
      P := TProduct.Create;
      try
        P.code.Value := 'NOTE-001';
        P.name.Value := 'Notebook Dell XPS 15 (Core i7, 32GB RAM, 1TB NVMe)';
        P.price.Value := 8999.00;
        P.stock.Value := 15.0;
        P.active.Value := True;
        QProduct := TDeltaQuery<TProduct>.Create(AConn);
        try
          QProduct.Insert(P);
        finally
          QProduct.Free;
        end;
      finally
        P.Free;
      end;

      // Produto 2
      P := TProduct.Create;
      try
        P.code.Value := 'MON-027';
        P.name.Value := 'Monitor UltraWide LG 29" IPS Full HD 75Hz';
        P.price.Value := 1250.00;
        P.stock.Value := 30.0;
        P.active.Value := True;
        QProduct := TDeltaQuery<TProduct>.Create(AConn);
        try
          QProduct.Insert(P);
        finally
          QProduct.Free;
        end;
      finally
        P.Free;
      end;

      // Produto 3
      P := TProduct.Create;
      try
        P.code.Value := 'TECL-RGB';
        P.name.Value := 'Teclado Mecânico Keychron K2 Wireless Switch Brown';
        P.price.Value := 580.00;
        P.stock.Value := 45.0;
        P.active.Value := True;
        QProduct := TDeltaQuery<TProduct>.Create(AConn);
        try
          QProduct.Insert(P);
        finally
          QProduct.Free;
        end;
      finally
        P.Free;
      end;

      // Produto 4
      P := TProduct.Create;
      try
        P.code.Value := 'MOUSE-MX';
        P.name.Value := 'Mouse Sem Fio Logitech MX Master 3S Darkfield 8K';
        P.price.Value := 650.00;
        P.stock.Value := 25.0;
        P.active.Value := True;
        QProduct := TDeltaQuery<TProduct>.Create(AConn);
        try
          QProduct.Insert(P);
        finally
          QProduct.Free;
        end;
      finally
        P.Free;
      end;

      // Produto 5
      P := TProduct.Create;
      try
        P.code.Value := 'FONE-NC';
        P.name.Value := 'Headset Sony WH-1000XM5 com Cancelamento de Ruído';
        P.price.Value := 2199.00;
        P.stock.Value := 18.0;
        P.active.Value := True;
        QProduct := TDeltaQuery<TProduct>.Create(AConn);
        try
          QProduct.Insert(P);
        finally
          QProduct.Free;
        end;
      finally
        P.Free;
      end;

      WriteLn('[Seed] Inserindo clientes corporativos de demonstração...');
      // Customer 1
      C := TCustomer.Create;
      try
        C.name.Value := 'Acme Soluções Tecnológicas Ltda';
        C.document.Value := '12.345.678/0001-90';
        C.email.Value := 'contato@acmetech.com.br';
        C.credit_limit.Value := 50000.00;
        QCustomer := TDeltaQuery<TCustomer>.Create(AConn);
        try
          QCustomer.Insert(C);
        finally
          QCustomer.Free;
        end;
      finally
        C.Free;
      end;

      // Customer 2
      C := TCustomer.Create;
      try
        C.name.Value := 'Global Logística & Distribuição S.A.';
        C.document.Value := '98.765.432/0001-10';
        C.email.Value := 'compras@globallog.com.br';
        C.credit_limit.Value := 120000.00;
        QCustomer := TDeltaQuery<TCustomer>.Create(AConn);
        try
          QCustomer.Insert(C);
        finally
          QCustomer.Free;
        end;
      finally
        C.Free;
      end;

      // Customer 3
      C := TCustomer.Create;
      try
        C.name.Value := 'Dr. Roberto Silveira Santos';
        C.document.Value := '123.456.789-00';
        C.email.Value := 'roberto.silveira@consultoria.med.br';
        C.credit_limit.Value := 15000.00;
        QCustomer := TDeltaQuery<TCustomer>.Create(AConn);
        try
          QCustomer.Insert(C);
        finally
          QCustomer.Free;
        end;
      finally
        C.Free;
      end;

      WriteLn('[Seed] Inserindo pedidos de venda iniciais com itens (RMS)...');
      // Order 1: Open for Acme
      O := TSaleOrder.Create;
      try
        O.order_number.Value := 'ORD-2026-0001';
        O.customer_id.Value := 1;
        O.order_date.Value := Now - 2;
        O.total_amount.Value := 10249.00;
        O.status.Value := ORDER_STATUS_CONFIRMED;
        QOrder := TDeltaQuery<TSaleOrder>.Create(AConn);
        try
          QOrder.Insert(O);
        finally
          QOrder.Free;
        end;

        // Item 1: 1 Notebook (8999.00)
        Itm := TSaleOrderItem.Create;
        try
          Itm.order_id.Value := 1;
          Itm.product_id.Value := 1;
          Itm.quantity.Value := 1;
          Itm.unit_price.Value := 8999.00;
          Itm.total_price.Value := 8999.00;
          QItem := TDeltaQuery<TSaleOrderItem>.Create(AConn);
          try
            QItem.Insert(Itm);
          finally
            QItem.Free;
          end;
        finally
          Itm.Free;
        end;

        // Item 2: 1 Monitor (1250.00)
        Itm := TSaleOrderItem.Create;
        try
          Itm.order_id.Value := 1;
          Itm.product_id.Value := 2;
          Itm.quantity.Value := 1;
          Itm.unit_price.Value := 1250.00;
          Itm.total_price.Value := 1250.00;
          QItem := TDeltaQuery<TSaleOrderItem>.Create(AConn);
          try
            QItem.Insert(Itm);
          finally
            QItem.Free;
          end;
        finally
          Itm.Free;
        end;
      finally
        O.Free;
      end;

      // Order 2: For Global Logistics
      O := TSaleOrder.Create;
      try
        O.order_number.Value := 'ORD-2026-0002';
        O.customer_id.Value := 2;
        O.order_date.Value := Now - 1;
        O.total_amount.Value := 4398.00;
        O.status.Value := ORDER_STATUS_CONFIRMED;
        QOrder := TDeltaQuery<TSaleOrder>.Create(AConn);
        try
          QOrder.Insert(O);
        finally
          QOrder.Free;
        end;

        // Item 1: 2 Headsets (2199.00 * 2 = 4398.00)
        Itm := TSaleOrderItem.Create;
        try
          Itm.order_id.Value := 2;
          Itm.product_id.Value := 5;
          Itm.quantity.Value := 2;
          Itm.unit_price.Value := 2199.00;
          Itm.total_price.Value := 4398.00;
          QItem := TDeltaQuery<TSaleOrderItem>.Create(AConn);
          try
            QItem.Insert(Itm);
          finally
            QItem.Free;
          end;
        finally
          Itm.Free;
        end;
      finally
        O.Free;
      end;

      AConn.Commit;
      WriteLn('[Seed] Carga inicial concluída com sucesso!');
    except
      AConn.Rollback;
      raise;
    end;
  end;
end;

procedure InitializeOrderStore;
var
  DatabaseURL, DatabasePath: string;
  Conn: IDeltaConnection;
  Schema: TDeltaORMSchema;
begin
  if Assigned(OrderPool) then
    Exit;

  DatabasePath := GetEnvVariable('ZENITH_ORDER_DATABASE',
    ExtractFilePath(ParamStr(0)) + 'orders.sqlite');
  DatabaseURL := GetEnvVariable('ZENITH_ORDER_DATABASE_URL',
    'sqlite://' + ExpandFileName(DatabasePath));

  Conn := TDeltaORM.Connect(DatabaseURL);
  try
    Schema := TDeltaORMSchema.Create(Conn);
    try
      Schema.RegisterModel(TProduct);
      Schema.RegisterModel(TCustomer);
      Schema.RegisterModel(TSaleOrder);
      Schema.RegisterModel(TSaleOrderItem);
      Schema.PrepareDB(True);
    finally
      Schema.Free;
    end;

    SeedDatabaseIfEmpty(Conn);
  finally
    Conn.Disconnect;
    Conn := nil;
  end;

  OrderPool := TDeltaConnectionPool.Create(DatabaseURL, 1, 10);
end;

finalization
  FreeAndNil(OrderPool);

end.
