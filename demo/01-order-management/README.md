# Zenith RMS Starter — Order Management REST API

🌐 **Language / Idioma:** [English](README.md) | [Português](README.pt-BR.md) | [Español](README.es-ES.md)

---

A comprehensive enterprise-grade demonstration of **Zenith HTTP Framework**, **DeltaModel ORM**, and **Swagger4Laz (OpenAPI 3.1)** showcasing a full-featured Retail & Order Management (RMS Starter) backend in modern Object Pascal (Free Pascal / Lazarus).

---

## 🚀 Key Highlights & Architecture

- **High Performance HTTP Framework**: Pure Free Pascal async HTTP runtime with native routing and zero-overhead JSON streaming.
- **DeltaModel ORM**:
  - Declarative schema configuration with automatic migrations via `TDeltaORMSchema.PrepareDB`.
  - Embedded SQLite database engine (`orders.sqlite`) with connection pooling (`TDeltaConnectionPool`).
  - High performance zero-DOM streaming with `TDeltaFastJsonStreamer`.
  - 1:N relational modeling (`TSaleOrder` $\rightarrow$ `TSaleOrderItem`) with eager loading (`Include('items')`).
- **Declarative RBAC & Security**:
  - `TZRBACPolicy<TProduct>` protecting product mutations (`caCreate`, `caUpdate`, `caDelete`) restricted to the `admin` role, while allowing public read operations (`caRead`, `caList`).
- **Swagger4Laz (OpenAPI 3.1 & RFC 7807)**:
  - Fluent Route Grouping via `SwaggerRouter.Group('/api/v1/orders')`.
  - Strict OpenAPI 3.1 contract metadata (`Summary`, `Description`, `QueryParam`, `PathParam`, `Produces`, `ProducesPaginated`, `ConsumesJson`).
  - Native RFC 7807 Problem Details error responses (`application/problem+json`).
- **Business Transaction Atomicity**:
  - Sales order creation validates customer credit limits, checks product availability, decrements stock in memory, and persists both order and order line items within an ACID transaction.
  - Sales order cancellation reverses product stock levels atomically.

---

## 📦 Domain Models

| Model | Table | Description |
|---|---|---|
| `TProduct` | `products` | Products catalog with SKU/code, description, price, available stock and active flag. |
| `TCustomer` | `customers` | Customers master data with tax document, email, and credit limit. |
| `TSaleOrder` | `sale_orders` | Sales orders header with sequential number, customer reference, date, total amount, status and 1:N items collection. |
| `TSaleOrderItem` | `sale_order_items` | Sales order line items referencing product, quantity, unit price, and line total. |

---

## 🛠️ Build & Run

### Prerequisites
- Free Pascal Compiler 3.2.x+ and Lazarus IDE (or `lazbuild` CLI).
- SQLite 3 runtime library (`libsqlite3.so` on Linux or `sqlite3.dll` on Windows).

### Compilation
```bash
lazbuild zenith/demo/01-order-management/order_management.lpi
```

### Execution
Run the standalone executable:
```bash
./zenith/demo/01-order-management/order_management
```

*By default, the server binds to port `8080` (or the port defined by the `PORT` / `ZENITH_PORT` environment variables).*

To specify a custom port:
```bash
PORT=8090 ./zenith/demo/01-order-management/order_management
```

Upon startup, the demo automatically initializes the SQLite schema (`orders.sqlite`) and seeds sample products, customers, and orders.

---

## 📖 API Documentation & Swagger UI

Once the server is running:
- **Interactive Swagger UI**: [http://localhost:8080/docs](http://localhost:8080/docs)
- **OpenAPI 3.1 JSON Specification**: [http://localhost:8080/openapi.json](http://localhost:8080/openapi.json)

---

## 📡 Endpoints & cURL Examples

### 1. Products Catalog (`/api/v1/products`)
- **GET `/api/v1/products`** — List all products (public):
  ```bash
  curl -s http://localhost:8080/api/v1/products
  ```
- **POST `/api/v1/products`** — Create product (*Requires `admin` role via RBAC*):
  ```bash
  curl -X POST http://localhost:8080/api/v1/products \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer <admin-token>" \
    -d '{
      "code": "SSD-2TB",
      "name": "SSD Kingston NV3 2TB NVMe M.2 6000MB/s",
      "price": 849.90,
      "stock": 50.0,
      "active": true
    }'
  ```

### 2. Customers (`/api/v1/customers`)
- **GET `/api/v1/customers`** — List registered customers:
  ```bash
  curl -s http://localhost:8080/api/v1/customers
  ```
- **POST `/api/v1/customers`** — Register a new customer:
  ```bash
  curl -X POST http://localhost:8080/api/v1/customers \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Tech Corp Soluções Digitais",
      "document": "11.222.333/0001-44",
      "email": "financeiro@techcorp.io",
      "credit_limit": 75000.00
    }'
  ```

### 3. Orders & RMS Workflow (`/api/v1/orders`)
- **GET `/api/v1/orders`** — Paginated orders with status filter:
  ```bash
  curl -s "http://localhost:8080/api/v1/orders?page=1&page_size=10&status=CONFIRMED"
  ```
- **GET `/api/v1/orders/1`** — Get order with eager loading of line items:
  ```bash
  curl -s http://localhost:8080/api/v1/orders/1
  ```
- **POST `/api/v1/orders`** — Create order (validates stock & credit limit):
  ```bash
  curl -X POST http://localhost:8080/api/v1/orders \
    -H "Content-Type: application/json" \
    -d '{
      "customer_id": 1,
      "items": [
        { "product_id": 1, "quantity": 1 },
        { "product_id": 4, "quantity": 2 }
      ]
    }'
  ```
- **POST `/api/v1/orders/:id/cancel`** — Cancel order and reverse product stock:
  ```bash
  curl -X POST http://localhost:8080/api/v1/orders/1/cancel
  ```

---

## 🛡️ License

Part of the **Zenith Framework** and **Prism ERP** ecosystem under MIT License.
