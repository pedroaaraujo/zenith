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

initialization
  if GetEnvironmentVariable('ZENITH_LOCALE') <> '' then
    SetZenithLocaleByName(GetEnvironmentVariable('ZENITH_LOCALE'))
  else
    GCurrentLocale := zlEnUS;

end.
