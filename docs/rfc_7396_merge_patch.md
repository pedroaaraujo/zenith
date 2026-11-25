# RFC 7396 — JSON Merge Patch (`application/merge-patch+json`) & Dirty Fields

> **Normative Reference:** [IETF RFC 7396 — JSON Merge Patch](https://datatracker.ietf.org/doc/html/rfc7396)  
> **Libraries:** **DeltaModel ORM** (`DeltaModel.MergePatch`, `DeltaModel.SQLBuilder`, `DeltaModel.ORM.DML`) & **Zenith HTTP Framework** (`Zenith.MergePatch`)

---

## 1. Visão Geral

O suporte nativo à **RFC 7396 (JSON Merge Patch)** no ecossistema **DeltaModel + Zenith** permite atualizações parciais semânticas de documentos JSON e entidades persistidas em banco de dados com **rastreamento de campos modificados (*Dirty Fields*)**, garantindo:

1. **Conformidade integral com a Seção 2 e o Apêndice A da RFC 7396** (todos os 15 vetores normativos validados).
2. **Semântica tri-estado real**:
   - **Campo ausente no patch** → permanece intacto (`Dirty = False`), **nunca** aparece no `UPDATE`.
   - **Campo presente com valor** → atualizado e marcado como `Dirty = True`.
   - **Campo presente com `null`** → atribuído como `NULL` e marcado como `Dirty = True`, emitindo `col = :col` (vinculado como `NULL`) ou `col = NULL`.
3. **Geração de SQL DML mínimo**: `TDMSQLBuilder.CreatePartialUpdate` gera `UPDATE tabela SET ... WHERE pk = :pk` contendo **exclusivamente** as colunas marcadas como *dirty*. Quando `0` colunas são modificadas, nenhum comando `UPDATE` é emitido (no-op em `TUpdate.PatchObject`).
4. **Proteção de integridade**: chaves primárias (`dboPrimaryKey`), campos virtuais (`IsVirtual`), campos não atualizáveis (sem `dboUpdate`) e campos ocultos (`Visible = False`) são protegidos contra sobrescrita maliciosa.
5. **Negociação HTTP padronizada**: `Zenith.MergePatch` implementa o media type `application/merge-patch+json`, rejeição `415 Unsupported Media Type` e header `Accept-Patch` (RFC 5789).

---

## 2. Algoritmo Normativo RFC 7396 (`DeltaModel.MergePatch`)

A unit `DeltaModel.MergePatch` expõe o algoritmo normativo da Seção 2 da RFC 7396 para documentos JSON arbitrários, sem mutar os objetos de entrada (`ATarget` e `APatch` permanecem imutáveis):

```pascal
uses
  fpjson, DeltaModel.MergePatch;

var
  MergedJson: RawByteString;
begin
  MergedJson := MergePatch(
    '{"title":"Goodbye!","author":{"givenName":"John","familyName":"Doe"},"tags":["example","sample"],"content":"This will be unchanged"}',
    '{"title":"Hello!","phoneNumber":"+01-123-456-7890","author":{"familyName":null},"tags":["example"]}'
  );
  // Resultado:
  // {"title":"Hello!","author":{"givenName":"John"},"tags":["example"],"content":"This will be unchanged","phoneNumber":"+01-123-456-7890"}
end;
```

### Regras implementadas:
- **Objetos aninhados**: mesclagem recursiva chave a chave.
- **Valor `null` em objeto**: remove a chave correspondente no alvo (ou, em modelos ORM, define o campo como `NULL` e marca `Dirty = True`).
- **Arrays**: substituição atômica integral (nunca mesclagem por índice).
- **Alvo não-objeto com patch objeto**: descarta o alvo e inicializa `{}` antes de aplicar o patch.
- **Patch escalar, array ou `null`**: substitui integralmente o alvo.

---

## 3. Rastreamento de Dirty Fields no `TDeltaModel`

O rastreamento de *dirty fields* funciona de forma transparente tanto no **Estilo A (`TDeltaField` / `TDF*`)** quanto no **Estilo B (Fluent Class Schema & Propriedades Primitivas)**:

- **Bitmask O(1) (`FDirtyMask: UInt64`)** em `TDeltaModel` — zero alocação extra de heap para até 64 propriedades.
- **Propriedade `Dirty: Boolean`** em `TDeltaField` sincronizada automaticamente com `TDeltaModel`.
- **Hidratação limpa**: `TColumnBindingMap.BindRecord` (usado por `FromDataSet` e cursores `TQuery`) executa `ClearAllDirty` automaticamente ao carregar registros do banco.

### API de Dirty Fields em `TDeltaModel`

```pascal
function IsDirty(const APropName: string): Boolean; overload;
function IsDirty(APropIndex: Integer): Boolean; overload; inline;
procedure MarkDirty(const APropName: string); overload;
procedure MarkDirty(APropIndex: Integer); overload; inline;
procedure ClearDirty(const APropName: string); overload;
procedure ClearDirty(APropIndex: Integer); overload; inline;
procedure ClearAllDirty;
function HasDirtyFields: Boolean;
function DirtyFieldCount: Integer;
function GetDirtyFieldNames: TStringArray;
```

---

## 4. `ApplyMergePatch` e DML `UPDATE` Parcial

### 4.1. Aplicando Patch em Modelos (`TProduct`, `TUser`, `TDocument`)

```pascal
uses
  DeltaModel, DeltaModel.MergePatch, DeltaModel.SQLBuilder, DeltaModel.ORM.Persister;

var
  Product: TProduct;
  ModifiedCount: Integer;
  SQL: string;
begin
  Product := Query.FindById(42) as TProduct;
  try
    // Apenas "price" e "description" presentes no patch; demais 18 campos permanecem intocados
    ModifiedCount := ApplyMergePatch(Product, '{"price": 199.50, "description": null}');
    // ModifiedCount = 2
    // Product.price.Dirty = True
    // Product.description.Dirty = True, Product.description.IsNull = True
    // Product.name.Dirty = False

    SQL := TDMSQLBuilder.CreatePartialUpdate(Product, 'postgresql');
    // UPDATE products SET description = :description, price = :price WHERE (id = 42)

    // Persiste no banco executando apenas o UPDATE parcial e limpa dirty flags após sucesso
    TUpdate.PatchObject(Conn, Product);
  finally
    Product.Free;
  end;
end;
```

### 4.2. Opções de Controle (`TMergePatchOptions`)

| Opção | Comportamento |
|---|---|
| `[]` (padrão) | Protege PK ignorando silenciosamente tentativas de alteração; ignora chaves desconhecidas; preserva dirty flags prévios. |
| `mpoRejectPKOverwrite` | Lança `EDeltaMergePatchException` se o payload tentar alterar qualquer campo de chave primária. |
| `mpoRejectUnknownFields` | Lança `EDeltaMergePatchException` se o payload contiver chaves inexistentes no modelo. |
| `mpoClearDirtyBeforeApply` | Limpa o estado *dirty* antes de aplicar o novo patch. |

### 4.3. Geração de SQL Multi-Dialeto

- `TDMSQLBuilder.CreatePartialUpdate(Model, Dialect)` → retorna `''` se `0` campos estiverem *dirty*.
- `TDMSQLBuilder.CreatePartialUpdateReturning(Model, Dialect)`:
  - **PostgreSQL / SQLite / Firebird**: `UPDATE ... SET ... WHERE ... RETURNING *`
  - **MSSQL**: `UPDATE ... SET ... OUTPUT INSERTED.* WHERE ...`
  - **MySQL / Oracle**: `UPDATE ... SET ... WHERE ...`

---

## 5. Integração HTTP no Zenith (`Zenith.MergePatch`)

A unit `Zenith.MergePatch` fornece constantes e helpers independentes para handlers HTTP `PATCH`:

```pascal
uses
  HTTPDefs, Zenith.MergePatch, DeltaModel.ORM.DML;

procedure PatchProductHandler(ARequest: TRequest; AResponse: TResponse);
var
  Product: TProduct;
  ModifiedCount: Integer;
begin
  TZenithMergePatch.AdvertiseAcceptPatch(AResponse);

  Product := LoadProductById(ARequest.RouteParams['id']);
  try
    // Valida Content-Type: application/merge-patch+json (suporta "; charset=utf-8")
    // Lança EUnsupportedMediaType (415) se Content-Type for inválido
    ModifiedCount := TZenithMergePatch.ApplyToModel(ARequest, Product);

    if ModifiedCount > 0 then
      TUpdate.PatchObject(Engine, Product);

    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := Product.ToJson;
  finally
    Product.Free;
  end;
end;
```

### Constantes e Métodos Disponíveis

- `MIME_APPLICATION_MERGE_PATCH_JSON = 'application/merge-patch+json'`
- `HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE = 415`
- `EUnsupportedMediaType` (subclasse de `HTTPException`)
- `TZenithMergePatch.ExtractMediaType(AContentType)`
- `TZenithMergePatch.IsMergePatchContentType(AContentType)`
- `TZenithMergePatch.IsMergePatchRequest(ARequest)`
- `TZenithMergePatch.RequireMergePatchContentType(ARequest)`
- `TZenithMergePatch.ParsePatchPayload(ARequest)`
- `TZenithMergePatch.ParsePatchObject(ARequest)`
- `TZenithMergePatch.ApplyToModel(ARequest, AModel, AOptions)`
- `TZenithMergePatch.ApplyJson(ARequest, ATarget)`
- `TZenithMergePatch.AdvertiseAcceptPatch(AResponse)`

---

## 6. Testes e Benchmark de Desempenho

### Execução da Suíte FPCUnit Standalone

```bash
fpc -FE/tmp/dm_mp_build -FU/tmp/dm_mp_build \
  -Fusrc/deltamodel/src -Fusrc/deltamodel/src/orm -Fusrc/deltamodel/src/orm/dialects -Fusrc/deltamodel/src/orm/drivers \
  -Fusrc -Fusrc/deltamodel/tests/src \
  src/deltamodel/tests/test_merge_patch_runner.lpr

/tmp/dm_mp_build/test_merge_patch_runner -a --format=plain
```

### Resultados do Benchmark (10.000 iterações — `TProduct` com 20 campos, atualizando 1 campo)

| Métrica | RFC 7396 PATCH (`ApplyMergePatch` + `CreatePartialUpdate`) | Full PUT (`FromJson` + `CreateUpdate`) | Ganho |
|---|---:|---:|---:|
| Tempo total (10.000 ops) | **148.0 ms** | 686.0 ms | **4.64x mais rápido** |
| Vazão (*throughput*) | **67.568 ops/s** | 14.577 ops/s | **+363%** |
| Tamanho do SQL `UPDATE` gerado | **50 bytes** | 348 bytes | **-85.6%** |
| Delta de memória Heap (FPC) | **0 bytes** | 0 bytes | Zero memory leaks |
