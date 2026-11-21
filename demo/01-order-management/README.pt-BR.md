# Zenith RMS Starter — API REST de Gestão de Pedidos

🌐 **Idioma / Language:** [Português](README.pt-BR.md) | [English](README.md) | [Español](README.es-ES.md)

---

Exemplo corporativo completo demonstrando o **Zenith HTTP Framework**, o ORM **DeltaModel** e o **Swagger4Laz (OpenAPI 3.1)** na construção de uma API REST para Varejo e Gestão de Pedidos (RMS Starter) em Object Pascal moderno (Free Pascal / Lazarus).

---

## 🚀 Destaques Arquiteturais

- **Framework HTTP Zenith**: Servidor HTTP assíncrono em puro Free Pascal com roteamento de alta performance e streaming JSON de custo zero.
- **DeltaModel ORM**:
  - Configuração declarativa de esquemas com migrações automáticas via `TDeltaORMSchema.PrepareDB`.
  - Banco de dados SQLite embarcado (`orders.sqlite`) com pool de conexões de alto rendimento (`TDeltaConnectionPool`).
  - Serialização JSON ultrarrápida (zero-DOM) com `TDeltaFastJsonStreamer`.
  - Relacionamento relacional 1:N (`TSaleOrder` $\rightarrow$ `TSaleOrderItem`) com carregamento adiantado (*eager loading*) via `Include('items')`.
- **RBAC Declarativo & Segurança**:
  - `TZRBACPolicy<TProduct>` com proteção de mutações (`caCreate`, `caUpdate`, `caDelete`) exclusivas para o perfil `admin`, mantendo as consultas (`caRead`, `caList`) abertas ao público.
- **Swagger4Laz (OpenAPI 3.1 & RFC 7807)**:
  - Agrupamento fluente de rotas via `SwaggerRouter.Group('/api/v1/orders')`.
  - Contratos estritos no OpenAPI 3.1 (`SetSummary`, `SetDescription`, `QueryParam`, `PathParam`, `Produces`, `ProducesPaginated`, `ConsumesJson`).
  - Respostas canônicas de erro no padrão RFC 7807 Problem Details (`application/problem+json`).
- **Atomicidade Transacional nas Regras de Negócio**:
  - Criação de pedidos com verificação de limite de crédito do cliente, checagem de estoque dos produtos, decremento de estoque e inserção do cabeçalho e itens em transação atômica ACID.
  - Cancelamento de pedidos com estorno automático do estoque dos produtos.

---

## 📦 Modelos de Domínio

| Modelo | Tabela | Descrição |
|---|---|---|
| `TProduct` | `products` | Catálogo de produtos com SKU/código, descrição, preço unitário, estoque disponível e status ativo. |
| `TCustomer` | `customers` | Cadastro de clientes com CNPJ/CPF, e-mail de faturamento e limite de crédito corporativo. |
| `TSaleOrder` | `sale_orders` | Cabeçalho do pedido de venda com número sequencial, cliente, data, valor total, status e coleção 1:N de itens. |
| `TSaleOrderItem` | `sale_order_items` | Itens de venda vinculados ao pedido com código do produto, quantidade faturada, preço unitário e valor total da linha. |

---

## 🛠️ Compilação e Execução

### Pré-requisitos
- Free Pascal Compiler 3.2.x+ e Lazarus IDE (ou ferramenta de linha de comando `lazbuild`).
- Biblioteca nativa do SQLite 3 (`libsqlite3.so` no Linux ou `sqlite3.dll` no Windows).

### Compilação

#### Opção 1: Free Pascal Compiler (`fpc`)

Compile diretamente com `fpc` utilizando um diretório temporário para manter o repositório limpo:

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

#### Opção 2: Lazarus (`lazbuild`)

```bash
lazbuild demo/01-order-management/order_management.lpi
```

### Execução
Execute o binário diretamente:
```bash
ZENITH_ORDER_DATABASE=/tmp/zenith_order_build/orders.sqlite \
  /tmp/zenith_order_build/order_management
```

*Por padrão, o servidor escuta na porta `8080` (ou na porta configurada nas variáveis de ambiente `PORT` ou `ZENITH_PORT`).*

Para definir uma porta personalizada:
```bash
PORT=8090 ./zenith/demo/01-order-management/order_management
```

Ao iniciar, a demonstração cria o arquivo de banco `orders.sqlite` e popula automaticamente produtos, clientes e pedidos de teste caso a base esteja vazia.

---

## 📖 Documentação Interativa & Swagger UI

Com o servidor em execução, acesse:
- **Swagger UI Interativo**: [http://localhost:8080/docs](http://localhost:8080/docs)
- **Especificação OpenAPI 3.1 JSON**: [http://localhost:8080/openapi.json](http://localhost:8080/openapi.json)

---

## 📡 Exemplos Práticos com cURL

### 1. Catálogo de Produtos (`/api/v1/products`)
- **GET `/api/v1/products`** — Listagem de produtos (pública):
  ```bash
  curl -s http://localhost:8080/api/v1/products
  ```
- **POST `/api/v1/products`** — Cadastrar produto (*Requer perfil `admin` via RBAC*):
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
- **GET `/api/v1/customers`** — Listar clientes cadastrados:
  ```bash
  curl -s http://localhost:8080/api/v1/customers
  ```
- **POST `/api/v1/customers`** — Cadastrar novo cliente:
  ```bash
  curl -X POST http://localhost:8080/api/v1/customers \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Tech Corp Soluções Digitais Ltda",
      "document": "11.222.333/0001-44",
      "email": "financeiro@techcorp.io",
      "credit_limit": 75000.00
    }'
  ```

### 3. Pedidos de Venda e Gestão RMS (`/api/v1/orders`)
- **GET `/api/v1/orders`** — Listar pedidos paginados com filtro por status:
  ```bash
  curl -s "http://localhost:8080/api/v1/orders?page=1&page_size=10&status=CONFIRMED"
  ```
- **GET `/api/v1/orders/1`** — Obter pedido com itens vinculados (eager loading):
  ```bash
  curl -s http://localhost:8080/api/v1/orders/1
  ```
- **POST `/api/v1/orders`** — Emitir pedido de venda (validação atômica de crédito e estoque):
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
- **POST `/api/v1/orders/:id/cancel`** — Cancelar pedido e estornar saldo de estoque:
  ```bash
  curl -X POST http://localhost:8080/api/v1/orders/1/cancel
  ```

---

## 🛡️ Licença

Componente do ecossistema **Zenith Framework** sob licença MIT.
