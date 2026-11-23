# Zenith Framework — ToDo List REST API Demo (`00-todolist`)

A minimal, production-ready REST API demonstration built with **Zenith HTTP Framework**, **DeltaModel ORM**, and **Swagger4Laz (OpenAPI 3.1)** in Object Pascal (Free Pascal / Lazarus).

---

## 🚀 Overview & Features

- **Declarative Domain Models (`Todo.Model.pas`)**:
  - `TTodoInsert` and `TTodo` extending `TDeltaModel` with typed fields (`TDFIntRequired`, `TDFStringRequired`, `TDFBooleanRequired`).
  - Automatic SQLite schema provisioning via `TDeltaORMSchema.PrepareDB`.
  - High-concurrency connection pooling via `TDeltaConnectionPool`.
- **Zero-Boilerplate REST CRUD (`Todo.Route.pas`)**:
  - One-line REST endpoint registration using `TZenithCrud<TTodo>.Create('/todo', TodoPool).WithTag('ToDo').Register`.
  - Automatically exposes `GET /todo`, `GET /todo/:id`, `POST /todo`, `PUT /todo/:id`, and `DELETE /todo/:id`.
- **Built-in OpenAPI 3.1 & Swagger UI**:
  - Interactive Swagger documentation served at `/docs` and OpenAPI 3.1 JSON specification at `/docs/openapi.json` (or `/openapi.json`).

---

## 🛠️ Build & Run

### Prerequisites
- Free Pascal Compiler (`fpc` 3.2.2+) and/or Lazarus (`lazbuild`).
- SQLite 3 shared library (`libsqlite3.so` on Linux, `sqlite3.dll` on Windows).

### Option 1: Compile with Free Pascal Compiler (`fpc`)

Compile into a temporary directory to keep the repository clean:

```bash
mkdir -p /tmp/zenith_todolist_build
cd demo/00-todolist

fpc -MObjFPC -Scghi -O2 \
  -FE/tmp/zenith_todolist_build \
  -FU/tmp/zenith_todolist_build \
  -Fu../../src \
  -Fu../../src/deltamodel/src \
  -Fu../../src/swagger4laz \
  -Fu. \
  todolist.lpr
```

### Option 2: Compile with Lazarus (`lazbuild`)

```bash
lazbuild demo/00-todolist/todolist.lpi
```

### Running the Server

```bash
ZENITH_TODO_DATABASE=/tmp/zenith_todolist_build/todo.sqlite \
  /tmp/zenith_todolist_build/todolist
```

By default, the HTTP server listens on port `8080`.

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `ZENITH_TODO_DATABASE` | `./todo.sqlite` | Path to the SQLite database file |
| `ZENITH_TODO_DATABASE_URL` | `sqlite://<path>` | Full DeltaModel connection URL |

---

## 📡 API Endpoints & `curl` Examples

### 1. Create a ToDo Item (`POST /todo`)

```bash
curl -s -X POST http://localhost:8080/todo \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Write OpenAPI 3.1 documentation",
    "done": false
  }'
```

### 2. List All ToDo Items (`GET /todo`)

```bash
curl -s http://localhost:8080/todo
```

### 3. Get a ToDo Item by ID (`GET /todo/:id`)

```bash
curl -s http://localhost:8080/todo/1
```

### 4. Update a ToDo Item (`PUT /todo/:id`)

```bash
curl -s -X PUT http://localhost:8080/todo/1 \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "description": "Write OpenAPI 3.1 documentation",
    "done": true
  }'
```

### 5. Delete a ToDo Item (`DELETE /todo/:id`)

```bash
curl -s -X DELETE http://localhost:8080/todo/1
```

---

## 📖 Interactive Documentation

With the server running, open in your browser:
- **Swagger UI**: `http://localhost:8080/docs`

---

## 🛡️ License

Part of the **Zenith Framework** ecosystem under the MIT License.
