# Zenith RMS Starter API Demo

A complete, production-ready Retail Management System (RMS) starter REST API built with **Zenith Framework**, **DeltaModel ORM**, **Swagger4Laz (OpenAPI 3.1)**, **TZenithThreadPool**, and native **W3C Server-Sent Events (`Zenith.SSE`)**.

## Features

- **Modern DeltaModel ORM** (zero deprecated methods):
  - Declarative entities: `TProduct`, `TCustomer`, `TSale`, and `TSaleItem` (1:N relation).
  - Type-safe fluent query filters (`Q.Where(Q.M.status.Eq(...))`, `Q.Where(Q.M.stock_qty.Lt(...))`).
  - Zero-allocation reusable cursors (`for Rec in Q.Cursor do ...`).
  - Automatic SQLite schema creation (`TDeltaORMSchema.PrepareDB`) and initial seed dataset.
- **Fluent Zenith Router + OpenAPI 3.1**:
  - Automatic CRUD endpoints via `TZenithCrud<T>` for Products and Customers.
  - Transactional Sales endpoints (`POST /api/v1/sales`, `POST /api/v1/sales/:id/cancel`) with stock validation, credit-limit enforcement, and atomic rollback.
  - Standard **RFC 9457 Problem Details** (`application/problem+json`) for validation and domain errors.
  - Interactive Swagger UI at `/docs` and OpenAPI 3.1 JSON spec at `/docs/openapi.json`.
- **High-Concurrency ThreadPool & Real-Time SSE**:
  - Configured with `TZenithThreadPool` (zero thread-per-request overhead).
  - Live `GET /api/v1/events/sales` W3C SSE stream emitting `TSaleCreated` and `TSaleCancelled` events with automatic `: ping` heartbeats and `Last-Event-ID` replay.

---

## Building & Running

### Option 1: Free Pascal Compiler (`fpc`)

Compile into a temporary build directory (keeps the repository tree clean):

```bash
mkdir -p /tmp/zenith_rms_build
fpc -MDelphi -Scghi -O2 \
  -Fu../../src \
  -Fu../../src/swagger4laz \
  -Fu../../src/deltamodel/src \
  -Fu. \
  -FE/tmp/zenith_rms_build \
  -FU/tmp/zenith_rms_build \
  rms_starter.lpr

# Run on default port 8080 (or override with PORT / ZENITH_PORT)
ZENITH_RMS_DATABASE=/tmp/zenith_rms_build/rms_starter.sqlite \
  /tmp/zenith_rms_build/rms_starter
```

### Option 2: Lazarus (`lazbuild`)

```bash
lazbuild rms_starter.lpi
./rms_starter
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` / `ZENITH_PORT` | `8080` | HTTP listen port |
| `ZENITH_THREADPOOL_WORKERS` | `16` | Number of pre-allocated ThreadPool workers |
| `ZENITH_RMS_DATABASE` | `./rms_starter.sqlite` | SQLite database file path |
| `ZENITH_RMS_DATABASE_URL` | `sqlite://<path>` | Full DeltaModel connection URL |

---

## Testing the API with `curl`

### 1. Health Check & OpenAPI Spec

```bash
curl -s http://127.0.0.1:8080/api/v1/health | jq .
curl -s http://127.0.0.1:8080/docs/openapi.json | jq '.info'
```

### 2. Products CRUD & Low-Stock Query

```bash
# List all products
curl -s http://127.0.0.1:8080/api/v1/products | jq .

# List low-stock products (stock_qty < 10)
curl -s "http://127.0.0.1:8080/api/v1/products/low-stock?threshold=10" | jq .

# Create a new product
curl -s -X POST http://127.0.0.1:8080/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "sku": "DOC-USB-C",
    "name": "Thunderbolt 4 Docking Station",
    "category": "Accessories",
    "unit_price": 249.90,
    "stock_qty": 20,
    "active": true
  }' | jq .
```

### 3. Customers CRUD

```bash
# List all customers
curl -s http://127.0.0.1:8080/api/v1/customers | jq .

# Create a new customer
curl -s -X POST http://127.0.0.1:8080/api/v1/customers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "BlueSky Enterprises",
    "tax_id": "US-99-1122334",
    "email": "finance@bluesky.example",
    "credit_limit": 30000.00,
    "active": true
  }' | jq .
```

### 4. Sales (Atomic Creation, Filtering, Detail & Cancellation)

```bash
# List confirmed sales (paginated)
curl -s "http://127.0.0.1:8080/api/v1/sales?page=1&page_size=10&status=CONFIRMED" | jq .

# Get a sale with eager-loaded items
curl -s http://127.0.0.1:8080/api/v1/sales/1 | jq .

# Create a new sale (validates stock & credit limit, deducts inventory, emits SSE event)
curl -s -X POST http://127.0.0.1:8080/api/v1/sales \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": 1,
    "items": [
      { "product_id": 1, "quantity": 1 },
      { "product_id": 3, "quantity": 2 }
    ]
  }' | jq .

# Cancel a sale (restores stock atomically and emits TSaleCancelled SSE event)
curl -s -X POST http://127.0.0.1:8080/api/v1/sales/3/cancel | jq .
```

### 5. Real-Time Sales Events (W3C Server-Sent Events)

Open a second terminal and subscribe to live sales events:

```bash
curl -N -H "Accept: text/event-stream" \
  http://127.0.0.1:8080/api/v1/events/sales
```

Whenever you create or cancel a sale in terminal 1, terminal 2 immediately receives `event: TSaleCreated` or `event: TSaleCancelled` frames! To test reconnection replay:

```bash
curl -N -H "Accept: text/event-stream" \
  -H "Last-Event-ID: sale-3" \
  http://127.0.0.1:8080/api/v1/events/sales
```
