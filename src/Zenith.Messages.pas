unit Zenith.Messages;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  { Supported locales for Zenith framework messages }
  TZenithLocale = (zlEnUS, zlPtBR, zlEsES);

procedure SetZenithLocale(ALocale: TZenithLocale);
function GetZenithLocale: TZenithLocale;
procedure SetZenithLocaleByName(const AName: string);
function GetZenithLocaleName: string;

// Standard RFC 7807 Problem Details Titles & Details
function TitleInternalServerError: string;
function DetailInternalServerError: string;

function TitleValidationError: string;
function DetailValidationError: string;

function TitleMissingRequiredField: string;
function DetailMissingRequiredField: string;

function TitleUnauthorized: string;
function DetailUnauthorized: string;

function TitleForbidden: string;
function DetailForbidden: string;

function TitleNotFound: string;
function DetailNotFound: string;

function TitleTooManyRequests: string;
function DetailTooManyRequests: string;

function TitleConflict: string;
function DetailConflict: string;

function TitleBadRequest: string;
function DetailBadRequest: string;

function TitleUnprocessableEntity: string;
function DetailUnprocessableEntity: string;

// Generic CRUD router messages and Swagger descriptions (TASK #1230 & i18n)
function MsgCrudInvalidId: string;
function MsgCrudInvalidSort(const AField: string): string;
function MsgCrudInvalidJson: string;
function MsgCrudCouldNotInsert: string;
function MsgCrudCouldNotUpdate: string;

function MsgCrudSummaryList(const ATag: string): string;
function MsgCrudParamPage: string;
function MsgCrudParamPageSize: string;
function MsgCrudParamSort: string;
function MsgCrudResponseListOK: string;
function MsgCrudResponseBadRequest: string;

function MsgCrudSummaryGetById(const ATag: string): string;
function MsgCrudParamId: string;
function MsgCrudResponseGetOK: string;

function MsgCrudSummaryCreate(const ATag: string): string;
function MsgCrudPayload: string;
function MsgCrudResponseCreated: string;
function MsgCrudResponseInvalidPayload: string;
function MsgCrudResponseValidation: string;

function MsgCrudSummaryUpdate(const ATag: string): string;
function MsgCrudResponseUpdated: string;

function MsgCrudSummaryDelete(const ATag: string): string;
function MsgCrudResponseDeleted: string;
function MsgCrudResponseUnauthorized: string;
function MsgCrudResponseForbidden: string;

implementation

var
  GCurrentLocale: TZenithLocale = zlEnUS;

const
  STR_LOCALE_NAMES: array[TZenithLocale] of string = ('en-US', 'pt-BR', 'es-ES');

  STR_TITLE_INTERNAL_ERROR: array[TZenithLocale] of string = (
    'Could not complete the operation.',
    'Não foi possível executar a operação.',
    'No se pudo completar la operación.'
  );
  STR_DETAIL_INTERNAL_ERROR: array[TZenithLocale] of string = (
    'An internal server error occurred.',
    'Ocorreu um erro interno no servidor.',
    'Ocurrió un error interno del servidor.'
  );

  STR_TITLE_VALIDATION_ERROR: array[TZenithLocale] of string = (
    'Data validation failed.',
    'Falha na validação dos dados.',
    'Falló la validación de los datos.'
  );
  STR_DETAIL_VALIDATION_ERROR: array[TZenithLocale] of string = (
    'One or more fields contain invalid values.',
    'Um ou mais campos contêm valores inválidos.',
    'Uno o más campos contienen valores no válidos.'
  );

  STR_TITLE_MISSING_REQUIRED: array[TZenithLocale] of string = (
    'Missing required field.',
    'Campo obrigatório ausente.',
    'Campo obligatorio ausente.'
  );
  STR_DETAIL_MISSING_REQUIRED: array[TZenithLocale] of string = (
    'A required field was not provided in the request.',
    'Um campo obrigatório não foi fornecido na requisição.',
    'No se proporcionó un campo obligatorio en la solicitud.'
  );

  STR_TITLE_UNAUTHORIZED: array[TZenithLocale] of string = (
    'Unauthorized.',
    'Não autorizado.',
    'No autorizado.'
  );
  STR_DETAIL_UNAUTHORIZED: array[TZenithLocale] of string = (
    'The provided credentials are invalid or missing.',
    'As credenciais informadas são inválidas ou ausentes.',
    'Las credenciales proporcionadas son inválidas o faltan.'
  );

  STR_TITLE_FORBIDDEN: array[TZenithLocale] of string = (
    'Forbidden.',
    'Acesso não permitido.',
    'Acceso prohibido.'
  );
  STR_DETAIL_FORBIDDEN: array[TZenithLocale] of string = (
    'You do not have permission to access this resource.',
    'Você não tem permissão para acessar este recurso.',
    'No tiene permiso para acceder a este recurso.'
  );

  STR_TITLE_NOT_FOUND: array[TZenithLocale] of string = (
    'Resource not found.',
    'Recurso não encontrado.',
    'Recurso no encontrado.'
  );
  STR_DETAIL_NOT_FOUND: array[TZenithLocale] of string = (
    'The requested resource could not be found.',
    'O recurso solicitado não pôde ser encontrado.',
    'No se pudo encontrar el recurso solicitado.'
  );

  STR_TITLE_TOO_MANY_REQUESTS: array[TZenithLocale] of string = (
    'Rate limit exceeded.',
    'Limite de requisições atingido.',
    'Límite de peticiones excedido.'
  );
  STR_DETAIL_TOO_MANY_REQUESTS: array[TZenithLocale] of string = (
    'Too many requests sent in a given amount of time.',
    'Muitas requisições enviadas em um determinado período de tempo.',
    'Demasiadas solicitudes enviadas en un período de tiempo determinado.'
  );

  STR_TITLE_CONFLICT: array[TZenithLocale] of string = (
    'Conflict in provided data.',
    'Conflito nos dados informados.',
    'Conflicto en los datos proporcionados.'
  );
  STR_DETAIL_CONFLICT: array[TZenithLocale] of string = (
    'The request could not be processed due to a conflict with current state.',
    'A requisição não pôde ser processada devido a conflito com o estado atual.',
    'La solicitud no pudo procesarse debido a un conflicto con el estado actual.'
  );

  STR_TITLE_BAD_REQUEST: array[TZenithLocale] of string = (
    'Bad request.',
    'Requisição inválida.',
    'Solicitud incorrecta.'
  );
  STR_DETAIL_BAD_REQUEST: array[TZenithLocale] of string = (
    'The request could not be understood or was malformed.',
    'A requisição não pôde ser compreendida ou está mal formatada.',
    'La solicitud no pudo entenderse o estaba mal formada.'
  );

  STR_TITLE_UNPROCESSABLE: array[TZenithLocale] of string = (
    'Unprocessable entity.',
    'Entidade improcessável.',
    'Entidad no procesable.'
  );
  STR_DETAIL_UNPROCESSABLE: array[TZenithLocale] of string = (
    'The request was well-formed but contains semantic errors.',
    'A requisição está bem formatada mas contém erros semânticos.',
    'La solicitud estaba bien formada pero contiene errores semánticos.'
  );

  // CRUD router messages
  STR_CRUD_INVALID_ID: array[TZenithLocale] of string = (
    'Invalid resource ID.',
    'Identificador de recurso inválido.',
    'Identificador de recurso no válido.'
  );

  STR_CRUD_INVALID_JSON: array[TZenithLocale] of string = (
    'Request body must contain valid JSON: ',
    'O corpo da requisição deve conter JSON válido: ',
    'El cuerpo de la solicitud debe contener JSON válido: '
  );

  STR_CRUD_COULD_NOT_INSERT: array[TZenithLocale] of string = (
    'Could not insert resource.',
    'Não foi possível inserir o recurso.',
    'No se pudo insertar el recurso.'
  );

  STR_CRUD_COULD_NOT_UPDATE: array[TZenithLocale] of string = (
    'Could not update resource.',
    'Não foi possível atualizar o recurso.',
    'No se pudo actualizar el recurso.'
  );

  STR_CRUD_PARAM_PAGE: array[TZenithLocale] of string = (
    'Page number',
    'Número da página',
    'Número de página'
  );

  STR_CRUD_PARAM_PAGE_SIZE: array[TZenithLocale] of string = (
    'Records per page',
    'Registros por página',
    'Registros por página'
  );

  STR_CRUD_PARAM_SORT: array[TZenithLocale] of string = (
    'Comma-separated model fields; prefix with "-" or suffix with " desc" for descending order',
    'Campos do modelo separados por vírgula; prefixe com "-" ou use " desc" para ordem decrescente',
    'Campos del modelo separados por coma; anteponga "-" o use " desc" para orden descendente'
  );

  STR_CRUD_INVALID_SORT: array[TZenithLocale] of string = (
    'Invalid sort field: "%s".',
    'Campo de ordenação inválido: "%s".',
    'Campo de ordenación no válido: "%s".'
  );

  STR_CRUD_RESPONSE_LIST_OK: array[TZenithLocale] of string = (
    'Successful operation',
    'Operação realizada com sucesso',
    'Operación exitosa'
  );

  STR_CRUD_RESPONSE_BAD_REQUEST: array[TZenithLocale] of string = (
    'Invalid query parameters',
    'Parâmetros de consulta inválidos',
    'Parámetros de consulta no válidos'
  );

  STR_CRUD_PARAM_ID: array[TZenithLocale] of string = (
    'Resource ID',
    'Identificador do recurso',
    'Identificador del recurso'
  );

  STR_CRUD_RESPONSE_GET_OK: array[TZenithLocale] of string = (
    'Resource found',
    'Recurso encontrado',
    'Recurso encontrado'
  );

  STR_CRUD_PAYLOAD: array[TZenithLocale] of string = (
    'Resource payload',
    'Dados do recurso',
    'Datos del recurso'
  );

  STR_CRUD_RESPONSE_CREATED: array[TZenithLocale] of string = (
    'Resource created',
    'Recurso criado com sucesso',
    'Recurso creado con éxito'
  );

  STR_CRUD_RESPONSE_INVALID_PAYLOAD: array[TZenithLocale] of string = (
    'Invalid payload',
    'Carga útil inválida',
    'Carga útil no válida'
  );

  STR_CRUD_RESPONSE_VALIDATION: array[TZenithLocale] of string = (
    'Validation failed',
    'Falha na validação',
    'Falló la validación'
  );

  STR_CRUD_RESPONSE_UPDATED: array[TZenithLocale] of string = (
    'Resource updated',
    'Recurso atualizado com sucesso',
    'Recurso actualizado con éxito'
  );

  STR_CRUD_RESPONSE_DELETED: array[TZenithLocale] of string = (
    'Resource deleted',
    'Recurso excluído com sucesso',
    'Recurso eliminado con éxito'
  );

  STR_CRUD_RESPONSE_UNAUTHORIZED: array[TZenithLocale] of string = (
    'Unauthorized',
    'Não autenticado',
    'No autenticado'
  );

  STR_CRUD_RESPONSE_FORBIDDEN: array[TZenithLocale] of string = (
    'Forbidden',
    'Acesso negado',
    'Acceso denegado'
  );

procedure SetZenithLocale(ALocale: TZenithLocale);
begin
  GCurrentLocale := ALocale;
end;

function GetZenithLocale: TZenithLocale;
begin
  Result := GCurrentLocale;
end;

procedure SetZenithLocaleByName(const AName: string);
var
  S: string;
begin
  S := LowerCase(Trim(AName));
  if (S = 'pt') or (S = 'pt-br') or (S = 'pt_br') or (S = 'portuguese') then
    GCurrentLocale := zlPtBR
  else if (S = 'es') or (S = 'es-es') or (S = 'es_es') or (S = 'spanish') then
    GCurrentLocale := zlEsES
  else
    GCurrentLocale := zlEnUS;
end;

function GetZenithLocaleName: string;
begin
  Result := STR_LOCALE_NAMES[GCurrentLocale];
end;

function TitleInternalServerError: string;
begin
  Result := STR_TITLE_INTERNAL_ERROR[GCurrentLocale];
end;

function DetailInternalServerError: string;
begin
  Result := STR_DETAIL_INTERNAL_ERROR[GCurrentLocale];
end;

function TitleValidationError: string;
begin
  Result := STR_TITLE_VALIDATION_ERROR[GCurrentLocale];
end;

function DetailValidationError: string;
begin
  Result := STR_DETAIL_VALIDATION_ERROR[GCurrentLocale];
end;

function TitleMissingRequiredField: string;
begin
  Result := STR_TITLE_MISSING_REQUIRED[GCurrentLocale];
end;

function DetailMissingRequiredField: string;
begin
  Result := STR_DETAIL_MISSING_REQUIRED[GCurrentLocale];
end;

function TitleUnauthorized: string;
begin
  Result := STR_TITLE_UNAUTHORIZED[GCurrentLocale];
end;

function DetailUnauthorized: string;
begin
  Result := STR_DETAIL_UNAUTHORIZED[GCurrentLocale];
end;

function TitleForbidden: string;
begin
  Result := STR_TITLE_FORBIDDEN[GCurrentLocale];
end;

function DetailForbidden: string;
begin
  Result := STR_DETAIL_FORBIDDEN[GCurrentLocale];
end;

function TitleNotFound: string;
begin
  Result := STR_TITLE_NOT_FOUND[GCurrentLocale];
end;

function DetailNotFound: string;
begin
  Result := STR_DETAIL_NOT_FOUND[GCurrentLocale];
end;

function TitleTooManyRequests: string;
begin
  Result := STR_TITLE_TOO_MANY_REQUESTS[GCurrentLocale];
end;

function DetailTooManyRequests: string;
begin
  Result := STR_DETAIL_TOO_MANY_REQUESTS[GCurrentLocale];
end;

function TitleConflict: string;
begin
  Result := STR_TITLE_CONFLICT[GCurrentLocale];
end;

function DetailConflict: string;
begin
  Result := STR_DETAIL_CONFLICT[GCurrentLocale];
end;

function TitleBadRequest: string;
begin
  Result := STR_TITLE_BAD_REQUEST[GCurrentLocale];
end;

function DetailBadRequest: string;
begin
  Result := STR_DETAIL_BAD_REQUEST[GCurrentLocale];
end;

function TitleUnprocessableEntity: string;
begin
  Result := STR_TITLE_UNPROCESSABLE[GCurrentLocale];
end;

function DetailUnprocessableEntity: string;
begin
  Result := STR_DETAIL_UNPROCESSABLE[GCurrentLocale];
end;

function MsgCrudInvalidId: string;
begin
  Result := STR_CRUD_INVALID_ID[GCurrentLocale];
end;

function MsgCrudInvalidSort(const AField: string): string;
begin
  Result := Format(STR_CRUD_INVALID_SORT[GCurrentLocale], [AField]);
end;

function MsgCrudInvalidJson: string;
begin
  Result := STR_CRUD_INVALID_JSON[GCurrentLocale];
end;

function MsgCrudCouldNotInsert: string;
begin
  Result := STR_CRUD_COULD_NOT_INSERT[GCurrentLocale];
end;

function MsgCrudCouldNotUpdate: string;
begin
  Result := STR_CRUD_COULD_NOT_UPDATE[GCurrentLocale];
end;

function MsgCrudSummaryList(const ATag: string): string;
begin
  case GCurrentLocale of
    zlPtBR: Result := 'Listar registros de ' + ATag;
    zlEsES: Result := 'Listar registros de ' + ATag;
  else
    Result := 'List ' + ATag + ' records';
  end;
end;

function MsgCrudParamPage: string;
begin
  Result := STR_CRUD_PARAM_PAGE[GCurrentLocale];
end;

function MsgCrudParamPageSize: string;
begin
  Result := STR_CRUD_PARAM_PAGE_SIZE[GCurrentLocale];
end;

function MsgCrudParamSort: string;
begin
  Result := STR_CRUD_PARAM_SORT[GCurrentLocale];
end;

function MsgCrudResponseListOK: string;
begin
  Result := STR_CRUD_RESPONSE_LIST_OK[GCurrentLocale];
end;

function MsgCrudResponseBadRequest: string;
begin
  Result := STR_CRUD_RESPONSE_BAD_REQUEST[GCurrentLocale];
end;

function MsgCrudSummaryGetById(const ATag: string): string;
begin
  case GCurrentLocale of
    zlPtBR: Result := 'Obter ' + ATag + ' por ID';
    zlEsES: Result := 'Obtener ' + ATag + ' por ID';
  else
    Result := 'Get ' + ATag + ' by ID';
  end;
end;

function MsgCrudParamId: string;
begin
  Result := STR_CRUD_PARAM_ID[GCurrentLocale];
end;

function MsgCrudResponseGetOK: string;
begin
  Result := STR_CRUD_RESPONSE_GET_OK[GCurrentLocale];
end;

function MsgCrudSummaryCreate(const ATag: string): string;
begin
  case GCurrentLocale of
    zlPtBR: Result := 'Criar novo(a) ' + ATag;
    zlEsES: Result := 'Crear nuevo(a) ' + ATag;
  else
    Result := 'Create new ' + ATag;
  end;
end;

function MsgCrudPayload: string;
begin
  Result := STR_CRUD_PAYLOAD[GCurrentLocale];
end;

function MsgCrudResponseCreated: string;
begin
  Result := STR_CRUD_RESPONSE_CREATED[GCurrentLocale];
end;

function MsgCrudResponseInvalidPayload: string;
begin
  Result := STR_CRUD_RESPONSE_INVALID_PAYLOAD[GCurrentLocale];
end;

function MsgCrudResponseValidation: string;
begin
  Result := STR_CRUD_RESPONSE_VALIDATION[GCurrentLocale];
end;

function MsgCrudSummaryUpdate(const ATag: string): string;
begin
  case GCurrentLocale of
    zlPtBR: Result := 'Atualizar ' + ATag + ' existente';
    zlEsES: Result := 'Actualizar ' + ATag + ' existente';
  else
    Result := 'Update existing ' + ATag;
  end;
end;

function MsgCrudResponseUpdated: string;
begin
  Result := STR_CRUD_RESPONSE_UPDATED[GCurrentLocale];
end;

function MsgCrudSummaryDelete(const ATag: string): string;
begin
  case GCurrentLocale of
    zlPtBR: Result := 'Excluir ' + ATag + ' por ID';
    zlEsES: Result := 'Eliminar ' + ATag + ' por ID';
  else
    Result := 'Delete ' + ATag + ' by ID';
  end;
end;

function MsgCrudResponseDeleted: string;
begin
  Result := STR_CRUD_RESPONSE_DELETED[GCurrentLocale];
end;

function MsgCrudResponseUnauthorized: string;
begin
  Result := STR_CRUD_RESPONSE_UNAUTHORIZED[GCurrentLocale];
end;

function MsgCrudResponseForbidden: string;
begin
  Result := STR_CRUD_RESPONSE_FORBIDDEN[GCurrentLocale];
end;

initialization
  if GetEnvironmentVariable('ZENITH_LOCALE') <> '' then
    SetZenithLocaleByName(GetEnvironmentVariable('ZENITH_LOCALE'))
  else
    GCurrentLocale := zlEnUS;

end.
