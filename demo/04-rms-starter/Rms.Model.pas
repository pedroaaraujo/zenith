{
    Zenith Framework - RMS Starter Demo (Models & SQLite Store)
    Defines DeltaModel entities (TProduct, TCustomer, TSale, TSaleItem)
    using the modern fluent TDeltaQuery<T> API with zero deprecated methods.
}

unit Rms.Model;

{$mode Delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  DeltaModel,
  DeltaModel.Fields,
  DeltaModel.Generics,
  DeltaModel.ORM.Connection,
  DeltaModel.ORM.Pool,
  DeltaModel.ORM.Schema,
  Zenith.SSE;

const
  { Sale status constants }
  SALE_STATUS_DRAFT     = 'DRAFT';
  SALE_STATUS_CONFIRMED = 'CONFIRMED';
  SALE_STATUS_CANCELLED = 'CANCELLED';

  { Database table names }
  TABLE_PRODUCTS   = 'products';
  TABLE_CUSTOMERS  = 'customers';
  TABLE_SALES      = 'sales';
  TABLE_SALE_ITEMS = 'sale_items';

type
  TSaleItem = class;

  { TProduct - Retail catalog item }
  TProduct = class(TDeltaModel)
  private
    FId: TDFInt64Null;
    FSku: TDFStringRequired;
    FName: TDFStringRequired;
    FCategory: TDFStringNull;
    FUnitPrice: TDFDoubleRequired;
    FStockQty: TDFDoubleRequired;
    FActive: TDFBooleanRequired;
  public
    procedure Configure; override;
  published
    property id: TDFInt64Null read FId write FId;
    property sku: TDFStringRequired read FSku write FSku;
    property name: TDFStringRequired read FName write FName;
    property category: TDFStringNull read FCategory write FCategory;
    property unit_price: TDFDoubleRequired read FUnitPrice write FUnitPrice;
    property stock_qty: TDFDoubleRequired read FStockQty write FStockQty;
    property active: TDFBooleanRequired read FActive write FActive;
  end;

  { TCustomer - Retail customer record }
  TCustomer = class(TDeltaModel)
  private
    FId: TDFInt64Null;
    FName: TDFStringRequired;
    FTaxId: TDFStringNull;
    FEmail: TDFStringNull;
    FCreditLimit: TDFDoubleRequired;
    FActive: TDFBooleanRequired;
  public
    procedure Configure; override;
  published
    property id: TDFInt64Null read FId write FId;
    property name: TDFStringRequired read FName write FName;
    property tax_id: TDFStringNull read FTaxId write FTaxId;
    property email: TDFStringNull read FEmail write FEmail;
    property credit_limit: TDFDoubleRequired read FCreditLimit write FCreditLimit;
    property active: TDFBooleanRequired read FActive write FActive;
  end;

  { TSale - Sales order header with 1:N items relation }
  TSale = class(TDeltaModel)
  private
    FId: TDFInt64Null;
    FSaleNumber: TDFStringRequired;
    FCustomerId: TDFInt64Required;
    FSaleDate: TDFDateTimeRequired;
    FTotalAmount: TDFDoubleRequired;
    FStatus: TDFStringRequired;
    FItems: TDFHasMany;
  public
    procedure Configure; override;
  published
    property id: TDFInt64Null read FId write FId;
    property sale_number: TDFStringRequired read FSaleNumber write FSaleNumber;
    property customer_id: TDFInt64Required read FCustomerId write FCustomerId;
    property sale_date: TDFDateTimeRequired read FSaleDate write FSaleDate;
    property total_amount: TDFDoubleRequired read FTotalAmount write FTotalAmount;
    property status: TDFStringRequired read FStatus write FStatus;
    property items: TDFHasMany read FItems write FItems;
  end;

  { TSaleItem - Individual line item belonging to a TSale }
  TSaleItem = class(TDeltaModel)
  private
    FId: TDFInt64Null;
    FSaleId: TDFInt64Required;
    FProductId: TDFInt64Required;
    FQuantity: TDFDoubleRequired;
    FUnitPrice: TDFDoubleRequired;
    FLineTotal: TDFDoubleRequired;
  public
    procedure Configure; override;
  published
    property id: TDFInt64Null read FId write FId;
    property sale_id: TDFInt64Required read FSaleId write FSaleId;
    property product_id: TDFInt64Required read FProductId write FProductId;
    property quantity: TDFDoubleRequired read FQuantity write FQuantity;
    property unit_price: TDFDoubleRequired read FUnitPrice write FUnitPrice;
    property line_total: TDFDoubleRequired read FLineTotal write FLineTotal;
  end;

procedure InitializeRmsStore;
procedure SeedRmsDatabaseIfEmpty(Engine: TDeltaORMEngine);

var
  RmsPool: TDeltaConnectionPool;
  RmsEventBroker: TZSSEBroker;

implementation

uses
  Zenith.Env;

{ TProduct }

procedure TProduct.Configure;
begin
  inherited Configure;
  TableName := TABLE_PRODUCTS;
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
  sku.Size := 40;
  name.Size := 160;
  category.Size := 60;
end;

{ TCustomer }

procedure TCustomer.Configure;
begin
  inherited Configure;
  TableName := TABLE_CUSTOMERS;
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
  name.Size := 160;
  tax_id.Size := 32;
  email.Size := 120;
end;

{ TSale }

procedure TSale.Configure;
begin
  inherited Configure;
  TableName := TABLE_SALES;
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
  sale_number.Size := 32;
  status.Size := 20;
  items.References(TSaleItem, 'sale_id', 'id');
end;

{ TSaleItem }

procedure TSaleItem.Configure;
begin
  inherited Configure;
  TableName := TABLE_SALE_ITEMS;
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
end;

{ SeedRmsDatabaseIfEmpty }

procedure SeedRmsDatabaseIfEmpty(Engine: TDeltaORMEngine);
  procedure InsertProduct(const ASku, AName, ACategory: string; APrice, AStock: Double);
  var
    P: TProduct;
    Q: TDeltaQuery<TProduct>;
  begin
    P := TProduct.Create;
    Q := TDeltaQuery<TProduct>.Create(Engine);
    try
      P.sku.Value := ASku;
      P.name.Value := AName;
      P.category.Value := ACategory;
      P.unit_price.Value := APrice;
      P.stock_qty.Value := AStock;
      P.active.Value := True;
      Q.Insert(P);
    finally
      Q.Free;
      P.Free;
    end;
  end;

  procedure InsertCustomer(const AName, ATaxId, AEmail: string; ACreditLimit: Double);
  var
    C: TCustomer;
    Q: TDeltaQuery<TCustomer>;
  begin
    C := TCustomer.Create;
    Q := TDeltaQuery<TCustomer>.Create(Engine);
    try
      C.name.Value := AName;
      C.tax_id.Value := ATaxId;
      C.email.Value := AEmail;
      C.credit_limit.Value := ACreditLimit;
      C.active.Value := True;
      Q.Insert(C);
    finally
      Q.Free;
      C.Free;
    end;
  end;

  procedure InsertSaleItem(ASaleId, AProductId: Int64; AQty, APrice: Double);
  var
    Item: TSaleItem;
    Q: TDeltaQuery<TSaleItem>;
  begin
    Item := TSaleItem.Create;
    Q := TDeltaQuery<TSaleItem>.Create(Engine);
    try
      Item.sale_id.Value := ASaleId;
      Item.product_id.Value := AProductId;
      Item.quantity.Value := AQty;
      Item.unit_price.Value := APrice;
      Item.line_total.Value := AQty * APrice;
      Q.Insert(Item);
    finally
      Q.Free;
      Item.Free;
    end;
  end;

var
  QProduct: TDeltaQuery<TProduct>;
  QSale: TDeltaQuery<TSale>;
  ProdCount: Int64;
  S: TSale;
begin
  QProduct := TDeltaQuery<TProduct>.Create(Engine);
  try
    ProdCount := QProduct.Count;
  finally
    QProduct.Free;
  end;

  if ProdCount > 0 then
    Exit;

  WriteLn('[Seed] Populating initial RMS catalog, customers, and sample sales...');
  Engine.StartTransaction;
  try
    // Sample products (including one low-stock item for /low-stock demonstration)
    InsertProduct('LAP-PRO-15', 'Workstation Laptop Pro 15 (32GB RAM, 1TB NVMe)', 'Computers', 1899.00, 14.0);
    InsertProduct('MON-UW-32', 'UltraWide Monitor 32" QHD IPS 100Hz', 'Displays', 449.00, 28.0);
    InsertProduct('KEY-MECH-75', 'Wireless Mechanical Keyboard 75% Tactile', 'Peripherals', 129.00, 42.0);
    InsertProduct('MOU-ERGO-8K', 'Ergonomic Wireless Mouse 8000 DPI', 'Peripherals', 89.00, 4.0);
    InsertProduct('HDS-ANC-05', 'Studio Noise-Cancelling Wireless Headset', 'Audio', 349.00, 19.0);

    // Sample customers
    InsertCustomer('Northwind Retail LLC', 'US-45-9081234', 'purchasing@northwind.example', 25000.00);
    InsertCustomer('Contoso Logistics Inc.', 'US-88-3310921', 'orders@contoso.example', 75000.00);
    InsertCustomer('Apex Distribution Group', 'US-12-7745019', 'supply@apexdist.example', 10000.00);

    // Sample sale #1
    S := TSale.Create;
    QSale := TDeltaQuery<TSale>.Create(Engine);
    try
      S.sale_number.Value := 'SALE-2026-0001';
      S.customer_id.Value := 1;
      S.sale_date.Value := Now - 2;
      S.total_amount.Value := 2348.00;
      S.status.Value := SALE_STATUS_CONFIRMED;
      QSale.Insert(S);
      InsertSaleItem(S.id.AsInt64, 1, 1, 1899.00);
      InsertSaleItem(S.id.AsInt64, 2, 1, 449.00);
    finally
      QSale.Free;
      S.Free;
    end;

    // Sample sale #2
    S := TSale.Create;
    QSale := TDeltaQuery<TSale>.Create(Engine);
    try
      S.sale_number.Value := 'SALE-2026-0002';
      S.customer_id.Value := 2;
      S.sale_date.Value := Now - 1;
      S.total_amount.Value := 698.00;
      S.status.Value := SALE_STATUS_CONFIRMED;
      QSale.Insert(S);
      InsertSaleItem(S.id.AsInt64, 5, 2, 349.00);
    finally
      QSale.Free;
      S.Free;
    end;

    Engine.Commit;
    WriteLn('[Seed] Initial RMS dataset ready.');
  except
    Engine.Rollback;
    raise;
  end;
end;

procedure InitializeRmsStore;
var
  DatabaseURL, DatabasePath: string;
  Engine: TDeltaORMEngine;
  Schema: TDeltaORMSchema;
begin
  if not Assigned(RmsEventBroker) then
    RmsEventBroker := TZSSEBroker.Create(200);

  if Assigned(RmsPool) then
    Exit;

  DatabasePath := GetEnvVariable('ZENITH_RMS_DATABASE',
    ExtractFilePath(ParamStr(0)) + 'rms_starter.sqlite');
  DatabaseURL := GetEnvVariable('ZENITH_RMS_DATABASE_URL',
    'sqlite://' + ExpandFileName(DatabasePath));

  Engine := TDeltaORMEngine.Create(DatabaseURL);
  try
    Engine.Connection.Open;
    Schema := TDeltaORMSchema.Create(Engine);
    try
      Schema.RegisterModel(TProduct);
      Schema.RegisterModel(TCustomer);
      Schema.RegisterModel(TSale);
      Schema.RegisterModel(TSaleItem);
      Schema.PrepareDB(True);
    finally
      Schema.Free;
    end;

    SeedRmsDatabaseIfEmpty(Engine);
  finally
    Engine.Free;
  end;

  RmsPool := TDeltaConnectionPool.Create(DatabaseURL, 1, 10);
end;

finalization
  FreeAndNil(RmsEventBroker);
  FreeAndNil(RmsPool);

end.
