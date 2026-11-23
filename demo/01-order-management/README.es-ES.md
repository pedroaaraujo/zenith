# Zenith RMS Starter — API REST de Gestión de Pedidos

🌐 **Idioma / Language:** [Español](README.es-ES.md) | [English](README.md) | [Português](README.pt-BR.md)

---

Demostración empresarial completa del **Framework HTTP Zenith**, el ORM **DeltaModel** y **Swagger4Laz (OpenAPI 3.1)** para la creación de una API REST de Comercio y Gestión de Pedidos (RMS Starter) en Object Pascal moderno (Free Pascal / Lazarus).

---

## 🚀 Aspectos Arquitectónicos Destacados

- **Framework HTTP Zenith**: Servidor HTTP asíncrono en Free Pascal puro con enrutamiento de alto rendimiento y serialización JSON sin consumo adicional de memoria.
- **DeltaModel ORM**:
  - Configuración declarativa de esquemas con migraciones automáticas mediante `TDeltaORMSchema.PrepareDB`.
  - Motor de base de datos SQLite embebido (`orders.sqlite`) con pool de conexiones de alto rendimiento (`TDeltaConnectionPool`).
  - Serialización directa JSON de alto rendimiento (zero-DOM) con `TDeltaFastJsonStreamer`.
  - Relación 1:N (`TSaleOrder` $\rightarrow$ `TSaleOrderItem`) con carga anticipada (*eager loading*) mediante `Include('items')`.
- **RBAC Declarativo y Seguridad**:
  - `TZRBACPolicy<TProduct>` para restringir las mutaciones de productos (`caCreate`, `caUpdate`, `caDelete`) exclusivamente al rol `admin`, permitiendo consultas públicas de lectura (`caRead`, `caList`).
- **Swagger4Laz (OpenAPI 3.1 y RFC 7807)**:
  - Agrupación fluida de rutas con `SwaggerRouter.Group('/api/v1/orders')`.
  - Contratos formales OpenAPI 3.1 (`SetSummary`, `SetDescription`, `QueryParam`, `PathParam`, `Produces`, `ProducesPaginated`, `ConsumesJson`).
  - Respuestas estandarizadas de error en formato RFC 7807 Problem Details (`application/problem+json`).
- **Atomicidad Transaccional**:
  - Creación de pedidos con validación de límite de crédito del cliente, comprobación de existencias en catálogo, descuento de stock e inserción de cabecera y líneas en una transacción atómica ACID.
  - Cancelación de pedidos con reincorporación automática del stock de los productos.

---

## 📦 Modelos de Dominio

| Modelo | Tabla | Descripción |
|---|---|---|
| `TProduct` | `products` | Catálogo de productos con código SKU, descripción, precio unitario, existencias en inventario y estado activo. |
| `TCustomer` | `customers` | Registro de clientes con número de identificación fiscal, correo electrónico y límite de crédito corporativo. |
| `TSaleOrder` | `sale_orders` | Cabecera del pedido de venta con número de pedido, cliente asociado, fecha, importe total, estado y relación 1:N de ítems. |
| `TSaleOrderItem` | `sale_order_items` | Líneas de detalle del pedido con identificador de producto, cantidad, precio unitario y total de línea. |

---

## 🛠️ Compilación y Ejecución

### Requisitos previos
- Free Pascal Compiler 3.2.x+ y Lazarus IDE (o la herramienta de consola `lazbuild`).
- Biblioteca compartida de SQLite 3 (`libsqlite3.so` en Linux o `sqlite3.dll` en Windows).

### Compilación

#### Opción 1: Free Pascal Compiler (`fpc`)

Compile directamente con `fpc` utilizando un directorio temporal para mantener limpio el repositorio:

```bash
mkdir -p /tmp/zenith_order_build
cd demo/01-order-management

fpc -MDelphi -Scghi -O2 \
  -FE/tmp/zenith_order_build \
  -FU/tmp/zenith_order_build \
  -Fu../../src \
  -Fu../../src/deltamodel/src \
  -Fu../../src/swagger4laz \
  -Fu. \
  order_management.lpr
```

#### Opción 2: Lazarus (`lazbuild`)

```bash
lazbuild demo/01-order-management/order_management.lpi
```

### Ejecución
Inicie el ejecutable compilado:
```bash
ZENITH_ORDER_DATABASE=/tmp/zenith_order_build/orders.sqlite \
  /tmp/zenith_order_build/order_management
```

*Por defecto, el servicio se vincula al puerto `8080` (o al indicado en las variables de entorno `PORT` o `ZENITH_PORT`).*

Para definir un puerto diferente:
```bash
PORT=8090 ./zenith/demo/01-order-management/order_management
```

Al iniciarse por primera vez, la aplicación genera la base de datos `orders.sqlite` e inserta automáticamente registros iniciales de productos, clientes y pedidos de prueba.

---

## 📖 Documentación Swagger UI

Con el servidor en funcionamiento, acceda a:
- **Swagger UI Interactivo**: [http://localhost:8080/docs](http://localhost:8080/docs)
- **Especificación OpenAPI 3.1 JSON**: [http://localhost:8080/openapi.json](http://localhost:8080/openapi.json)

---

## 📡 Ejemplos Prácticos con cURL

### 1. Catálogo de Productos (`/api/v1/products`)
- **GET `/api/v1/products`** — Listar productos disponibles (público):
  ```bash
  curl -s http://localhost:8080/api/v1/products
  ```
- **POST `/api/v1/products`** — Crear nuevo producto (*Requiere rol `admin` mediante RBAC*):
  ```bash
  curl -X POST http://localhost:8080/api/v1/products \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer <token-admin>" \
    -d '{
      "code": "SSD-2TB",
      "name": "SSD Kingston NV3 2TB NVMe M.2 6000MB/s",
      "price": 849.90,
      "stock": 50.0,
      "active": true
    }'
  ```

### 2. Clientes Corporativos (`/api/v1/customers`)
- **GET `/api/v1/customers`** — Listar clientes:
  ```bash
  curl -s http://localhost:8080/api/v1/customers
  ```
- **POST `/api/v1/customers`** — Registrar nuevo cliente:
  ```bash
  curl -X POST http://localhost:8080/api/v1/customers \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Tech Corp Soluciones Digitales S.L.",
      "document": "B-12345678",
      "email": "administracion@techcorp.es",
      "credit_limit": 75000.00
    }'
  ```

### 3. Pedidos de Venta y Gestión RMS (`/api/v1/orders`)
- **GET `/api/v1/orders`** — Listado paginado de pedidos con filtro de estado:
  ```bash
  curl -s "http://localhost:8080/api/v1/orders?page=1&page_size=10&status=CONFIRMED"
  ```
- **GET `/api/v1/orders/1`** — Consultar pedido con carga inmediata de líneas asociadas:
  ```bash
  curl -s http://localhost:8080/api/v1/orders/1
  ```
- **POST `/api/v1/orders`** — Registrar pedido (con validación de límite de crédito y existencias):
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
- **POST `/api/v1/orders/:id/cancel`** — Cancelar pedido y reponer existencias en inventario:
  ```bash
  curl -X POST http://localhost:8080/api/v1/orders/1/cancel
  ```

---

## 🛡️ Licencia

Parte del ecosistema **Zenith Framework** bajo Licencia MIT.
