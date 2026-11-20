# Suporte a Requisições Condicionais RFC 7232 / RFC 9110 (ETag, 304 e 412 OCC)

O ecossistema **Zenith + DeltaModel** implementa integralmente a especificação **RFC 7232** (*Hypertext Transfer Protocol (HTTP/1.1): Conditional Requests*, consolidada na **RFC 9110 Seção 13**), fornecendo:

1. **Validação de Cache (`304 Not Modified`)**: evita serialização e tráfego de rede redundantes em leituras (`GET`/`HEAD`) com corpo estritamente vazio e zero alocação de payload.
2. **Controle de Concorrência Otimista — OCC (`412 Precondition Failed`)**: previne o problema de *Lost Update* em operações de escrita (`PUT`, `PATCH`, `DELETE`), retornando respostas **RFC 9457 Problem Details** (`application/problem+json; charset=utf-8`).
3. **Precedência Normativa (RFC 7232 Seção 6)**: máquina de estados determinística avaliando `If-Match`, `If-Unmodified-Since`, `If-None-Match` e `If-Modified-Since`.

---

## 1. Arquitetura e Units

| Unit | Repositório | Responsabilidade |
| :--- | :--- | :--- |
| `DeltaModel.ETag` | `deltamodel/src/DeltaModel.ETag.pas` | Cálculo determinístico de ETag (`SHA-256` e `FNV-1a 64-bit`) para `TDeltaModel` (Estilo A `TDeltaField` e Estilo B primitivo com `NullMask`), formatação canônica, parser de listas quote-aware e comparações forte/fraca. |
| `Zenith.Preconditions` | `zenith/src/Zenith.Preconditions.pas` | Avaliação normativa RFC 7232 Seção 6, parser/formatador de datas HTTP RFC 7231 (`IMF-fixdate`, `RFC 850`, `asctime`), escrita de `304 Not Modified` e `412 Precondition Failed` (RFC 9457). |

---

## 2. Geração de ETag no DeltaModel (`DeltaModel.ETag`)

### 2.1 Cálculo Determinístico em Modelos

```pascal
uses
  DeltaModel, DeltaModel.ETag;

var
  Item: TItem;
  StrongTag, WeakTag, FastTag: string;
begin
  Item := TItem.Create;
  try
    Item.Id := 42;
    Item.Sku := 'SKU-001';
    Item.Title := 'Widget Alpha';
    Item.Price := 19.95;

    // ETag Forte com SHA-256 (padrão): "<64-hex>"
    StrongTag := Item.CalculateETag;

    // ETag Fraco com SHA-256: W/"<64-hex>"
    WeakTag := Item.CalculateWeakETag;

    // ETag Forte com FNV-1a 64-bit (zero alocação de buffer): "<16-hex>"
    FastTag := CalculateETag(Item, False, ehaFNV1a64);
  finally
    Item.Free;
  end;
end;
```

Características do gerador:
- **Suporte Dual (Estilo A e Estilo B)**: percorre propriedades publicadas via `TRTTICache`, suportando tanto `TDeltaField` quanto propriedades primitivas com `NullMask` (`IsNull`).
- **Segurança por Padrão**: campos com `Visible := False` (como hashes de senha ou segredos internos) são ignorados no cálculo do ETag, garantindo que o validador reflita exclusivamente a representação pública.
- **Independente de Locale**: valores numéricos, datas e strings são serializados em bytes canônicos (com normalização de `-0.0` para `+0.0`).

### 2.2 Comparações Normativas (RFC 7232 Seção 2.3.2)

| ETag 1 | ETag 2 | `StrongCompareETag` | `WeakCompareETag` |
| :--- | :--- | :---: | :---: |
| `"1"` | `"1"` | `True` | `True` |
| `W/"1"` | `W/"1"` | `False` | `True` |
| `W/"1"` | `"1"` | `False` | `True` |
| `"1"` | `W/"1"` | `False` | `True` |
| `"1"` | `"2"` | `False` | `False` |

- `If-Match` utiliza obrigatoriamente **comparação forte** (`StrongCompareETag`).
- `If-None-Match` utiliza obrigatoriamente **comparação fraca** (`WeakCompareETag`).
- O indicador fraco é estritamente sensível a maiúsculas (`W/`). `w/"1"` é rejeitado conforme a gramática da RFC 7232 Seção 2.3.
- O parser `ParseETagList` respeita aspas duplas (vírgulas dentro de `opaque-tag`, como `"a,b", "c"`, são preservadas intactas) e suporta o curinga `*`.

---

## 3. Avaliação de Pré-condições no Zenith (`Zenith.Preconditions`)

### 3.1 Precedência Normativa (RFC 7232 Seção 6)

1. **`If-Match`** (se presente):
   - Avalia via comparação forte (`*` exige que o recurso exista).
   - Se falso → **`412 Precondition Failed`** (RFC 9457).
   - Se verdadeiro → **ignora `If-Unmodified-Since`** e avança para o passo 3.
2. **`If-Unmodified-Since`** (somente se `If-Match` estiver ausente):
   - Datas HTTP inválidas são ignoradas conforme RFC 7232 §3.4.
   - Comparação com resolução de 1 segundo (`TruncateToHTTPSeconds`).
   - Se `LastModified > IfUnmodifiedSince` → **`412 Precondition Failed`**.
3. **`If-None-Match`** (se presente):
   - Avalia via comparação fraca (`*` casa se o recurso existir).
   - Se casar em `GET` ou `HEAD` → **`304 Not Modified`** (corpo vazio, cabeçalhos `ETag` e `Last-Modified` preservados).
   - Se casar em métodos de escrita (`PUT`, `PATCH`, `POST`, `DELETE`) → **`412 Precondition Failed`** (útil para criação exclusiva com `If-None-Match: *`).
   - Se não casar → **ignora `If-Modified-Since`** e prossegue com a requisição.
4. **`If-Modified-Since`** (somente para `GET`/`HEAD` quando `If-None-Match` estiver ausente):
   - Datas HTTP inválidas são ignoradas.
   - Se `LastModified <= IfModifiedSince` → **`304 Not Modified`**.

### 3.2 Uso em Handlers HTTP do Zenith

#### Leitura com Cache (`GET /items/:id`)

```pascal
procedure HandleGetItem(AReq: TRequest; AResp: TResponse);
var
  Item: TItem;
begin
  Item := LoadItemFromDatabase(AReq.RouteParams['id']);
  try
    // Calcula o ETag, valida If-None-Match / If-Modified-Since e emite 304 automaticamente
    if not TZenithPreconditions.CheckModel(AReq, AResp, Item, False, Item.UpdatedAt) then
      Exit;

    // Cabeçalhos ETag e Last-Modified já foram preenchidos em AResp
    AResp.Code := StatusOK;
    AResp.ContentType := ApplicationJson;
    AResp.Content := Item.ToJson;
  finally
    Item.Free;
  end;
end;
```

#### Escrita com OCC (`PUT /items/:id`)

```pascal
procedure HandleUpdateItem(AReq: TRequest; AResp: TResponse);
var
  CurrentItem: TItem;
begin
  CurrentItem := LoadItemFromDatabase(AReq.RouteParams['id']);
  try
    // Valida If-Match / If-Unmodified-Since; retorna 412 Problem Details se divergente
    if not TZenithPreconditions.CheckModel(AReq, AResp, CurrentItem, False, CurrentItem.UpdatedAt) then
      Exit;

    // Aplica alterações e persiste com segurança contra Lost Update
    CurrentItem.FromJson(AReq.Content);
    SaveItemToDatabase(CurrentItem);

    TZenithPreconditions.SetValidators(AResp, CurrentItem.CalculateETag, CurrentItem.UpdatedAt);
    AResp.Code := StatusOK;
    AResp.ContentType := ApplicationJson;
    AResp.Content := CurrentItem.ToJson;
  finally
    CurrentItem.Free;
  end;
end;
```

### 3.3 Formato da Resposta `412 Precondition Failed` (RFC 9457)

```http
HTTP/1.1 412 Precondition Failed
Content-Type: application/problem+json; charset=utf-8
ETag: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

{
  "type": "https://tools.ietf.org/html/rfc7232#section-4.2",
  "title": "Precondition Failed",
  "status": 412,
  "detail": "Resource entity tag does not match the If-Match precondition."
}
```

---

## 4. Datas HTTP (RFC 7231 Seção 7.1.1.1)

As funções `FormatHTTPDate` e `TryParseHTTPDate` são 100% independentes do locale do sistema operacional e aceitam os três formatos normativos:

- **IMF-fixdate (canônico de saída)**: `Sun, 06 Nov 1994 08:49:37 GMT`
- **RFC 850 (legado)**: `Sunday, 06-Nov-94 08:49:37 GMT`
- **ANSI C `asctime()`**: `Sun Nov  6 08:49:37 1994`
