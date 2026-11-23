unit Zenith.Constants;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

const
  { ========================================================================= }
  { HTTP Status Codes (RFC 9110 / RFC 4918 / RFC 6585 / RFC 8297)             }
  { ========================================================================= }

  { 1xx - Informational }
  HTTP_STATUS_CONTINUE                        = 100;
  HTTP_STATUS_SWITCHING_PROTOCOLS             = 101;
  HTTP_STATUS_PROCESSING                      = 102;
  HTTP_STATUS_EARLY_HINTS                     = 103;

  { 2xx - Success }
  HTTP_STATUS_OK                              = 200;
  HTTP_STATUS_CREATED                         = 201;
  HTTP_STATUS_ACCEPTED                        = 202;
  HTTP_STATUS_NON_AUTHORITATIVE_INFORMATION   = 203;
  HTTP_STATUS_NO_CONTENT                      = 204;
  HTTP_STATUS_RESET_CONTENT                   = 205;
  HTTP_STATUS_PARTIAL_CONTENT                 = 206;
  HTTP_STATUS_MULTI_STATUS                    = 207;
  HTTP_STATUS_ALREADY_REPORTED                = 208;
  HTTP_STATUS_IM_USED                         = 226;

  { 3xx - Redirection }
  HTTP_STATUS_MULTIPLE_CHOICES                = 300;
  HTTP_STATUS_MOVED_PERMANENTLY               = 301;
  HTTP_STATUS_FOUND                           = 302;
  HTTP_STATUS_SEE_OTHER                       = 303;
  HTTP_STATUS_NOT_MODIFIED                    = 304;
  HTTP_STATUS_USE_PROXY                       = 305;
  HTTP_STATUS_TEMPORARY_REDIRECT              = 307;
  HTTP_STATUS_PERMANENT_REDIRECT              = 308;

  { 4xx - Client Errors }
  HTTP_STATUS_BAD_REQUEST                     = 400;
  HTTP_STATUS_UNAUTHORIZED                    = 401;
  HTTP_STATUS_PAYMENT_REQUIRED                = 402;
  HTTP_STATUS_FORBIDDEN                       = 403;
  HTTP_STATUS_NOT_FOUND                       = 404;
  HTTP_STATUS_METHOD_NOT_ALLOWED              = 405;
  HTTP_STATUS_NOT_ACCEPTABLE                  = 406;
  HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED   = 407;
  HTTP_STATUS_REQUEST_TIMEOUT                 = 408;
  HTTP_STATUS_CONFLICT                        = 409;
  HTTP_STATUS_GONE                            = 410;
  HTTP_STATUS_LENGTH_REQUIRED                 = 411;
  HTTP_STATUS_PRECONDITION_FAILED             = 412;
  HTTP_STATUS_PAYLOAD_TOO_LARGE               = 413;
  HTTP_STATUS_URI_TOO_LONG                    = 414;
  HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE          = 415;
  HTTP_STATUS_RANGE_NOT_SATISFIABLE           = 416;
  HTTP_STATUS_EXPECTATION_FAILED              = 417;
  HTTP_STATUS_IM_A_TEAPOT                     = 418;
  HTTP_STATUS_MISDIRECTED_REQUEST             = 421;
  HTTP_STATUS_UNPROCESSABLE_ENTITY            = 422;
  HTTP_STATUS_LOCKED                          = 423;
  HTTP_STATUS_FAILED_DEPENDENCY               = 424;
  HTTP_STATUS_TOO_EARLY                       = 425;
  HTTP_STATUS_UPGRADE_REQUIRED                = 426;
  HTTP_STATUS_PRECONDITION_REQUIRED           = 428;
  HTTP_STATUS_TOO_MANY_REQUESTS               = 429;
  HTTP_STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE = 431;
  HTTP_STATUS_UNAVAILABLE_FOR_LEGAL_REASONS   = 451;

  { 5xx - Server Errors }
  HTTP_STATUS_INTERNAL_SERVER_ERROR           = 500;
  HTTP_STATUS_NOT_IMPLEMENTED                 = 501;
  HTTP_STATUS_BAD_GATEWAY                     = 502;
  HTTP_STATUS_SERVICE_UNAVAILABLE             = 503;
  HTTP_STATUS_GATEWAY_TIMEOUT                 = 504;
  HTTP_STATUS_HTTP_VERSION_NOT_SUPPORTED      = 505;
  HTTP_STATUS_VARIANT_ALSO_NEGOTIATES         = 506;
  HTTP_STATUS_INSUFFICIENT_STORAGE            = 507;
  HTTP_STATUS_LOOP_DETECTED                   = 508;
  HTTP_STATUS_NOT_EXTENDED                    = 510;
  HTTP_STATUS_NETWORK_AUTHENTICATION_REQUIRED = 511;

  { ========================================================================= }
  { HTTP Methods (RFC 9110 / RFC 5789)                                        }
  { ========================================================================= }
  HTTP_METHOD_GET     = 'GET';
  HTTP_METHOD_POST    = 'POST';
  HTTP_METHOD_PUT     = 'PUT';
  HTTP_METHOD_DELETE  = 'DELETE';
  HTTP_METHOD_PATCH   = 'PATCH';
  HTTP_METHOD_OPTIONS = 'OPTIONS';
  HTTP_METHOD_HEAD    = 'HEAD';
  HTTP_METHOD_TRACE   = 'TRACE';
  HTTP_METHOD_CONNECT = 'CONNECT';

  { ========================================================================= }
  { MIME Media Types (RFC 8259 / RFC 8949 / RFC 7396 / RFC 9457 / SSE)        }
  { ========================================================================= }
  MIME_APPLICATION_JSON            = 'application/json';
  MIME_APPLICATION_JSON_UTF8       = 'application/json; charset=utf-8';
  MIME_APPLICATION_CBOR            = 'application/cbor';
  MIME_APPLICATION_BSON            = 'application/bson';
  MIME_APPLICATION_XML             = 'application/xml';
  MIME_TEXT_XML                    = 'text/xml';
  MIME_TEXT_CSV                    = 'text/csv';
  MIME_APPLICATION_MERGE_PATCH     = 'application/merge-patch+json';
  MIME_APPLICATION_JSON_PATCH      = 'application/json-patch+json';
  MIME_APPLICATION_PROBLEM_JSON    = 'application/problem+json';
  MIME_APPLICATION_PROBLEM_JSON_UTF8 = 'application/problem+json; charset=utf-8';
  MIME_APPLICATION_PROBLEM_CBOR    = 'application/problem+cbor';
  MIME_APPLICATION_PROBLEM_XML     = 'application/problem+xml';
  MIME_TEXT_EVENT_STREAM           = 'text/event-stream';
  MIME_APPLICATION_OCTET_STREAM    = 'application/octet-stream';
  MIME_MULTIPART_FORM_DATA         = 'multipart/form-data';
  MIME_APPLICATION_FORM_URLENCODED = 'application/x-www-form-urlencoded';
  MIME_TEXT_PLAIN                  = 'text/plain';
  MIME_TEXT_HTML                   = 'text/html';
  MIME_APPLICATION_PDF             = 'application/pdf';

  { ========================================================================= }
  { Standard HTTP Headers (RFC 9110 / RFC 9111 / W3C Trace Context / SSE)     }
  { ========================================================================= }
  HEADER_CONTENT_TYPE        = 'Content-Type';
  HEADER_ACCEPT              = 'Accept';
  HEADER_ACCEPT_ENCODING     = 'Accept-Encoding';
  HEADER_CONTENT_ENCODING    = 'Content-Encoding';
  HEADER_AUTHORIZATION       = 'Authorization';
  HEADER_WWW_AUTHENTICATE    = 'WWW-Authenticate';
  HEADER_CONTENT_LENGTH      = 'Content-Length';
  HEADER_API_KEY             = 'X-API-Key';
  HEADER_ETAG                = 'ETag';
  HEADER_IF_MATCH            = 'If-Match';
  HEADER_IF_NONE_MATCH       = 'If-None-Match';
  HEADER_IF_MODIFIED_SINCE   = 'If-Modified-Since';
  HEADER_IF_UNMODIFIED_SINCE = 'If-Unmodified-Since';
  HEADER_IDEMPOTENCY_KEY     = 'Idempotency-Key';
  HEADER_IDEMPOTENT_REPLAYED = 'Idempotent-Replayed';
  HEADER_LAST_EVENT_ID       = 'Last-Event-ID';
  HEADER_TRACEPARENT         = 'Traceparent';
  HEADER_TRACESTATE          = 'Tracestate';
  HEADER_RETRY_AFTER         = 'Retry-After';
  HEADER_ALLOW               = 'Allow';
  HEADER_CACHE_CONTROL       = 'Cache-Control';
  HEADER_LOCATION            = 'Location';
  HEADER_VARY                = 'Vary';
  HEADER_X_REQUEST_ID        = 'X-Request-ID';
  HEADER_X_CORRELATION_ID    = 'X-Correlation-ID';
  HEADER_X_FORWARDED_FOR     = 'X-Forwarded-For';
  HEADER_X_FORWARDED_PROTO   = 'X-Forwarded-Proto';
  HEADER_X_FORWARDED_PREFIX  = 'X-Forwarded-Prefix';

  { ========================================================================= }
  { Content Encodings                                                         }
  { ========================================================================= }
  ENCODING_GZIP     = 'gzip';
  ENCODING_DEFLATE  = 'deflate';
  ENCODING_BROTLI   = 'br';
  ENCODING_ZSTD     = 'zstd';
  ENCODING_IDENTITY = 'identity';

  { ========================================================================= }
  { RFC 9457 Problem Details Defaults                                         }
  { ========================================================================= }
  PROBLEM_TYPE_ABOUT_BLANK = 'about:blank';
  PROBLEM_TYPE_PREFIX      = 'urn:zenith:problem:';

type
  { Typed namespaces for expressive code (Clean Code) }

  THttpStatus = record
  public const
    { 1xx }
    Continue                      = HTTP_STATUS_CONTINUE;
    SwitchingProtocols            = HTTP_STATUS_SWITCHING_PROTOCOLS;
    Processing                    = HTTP_STATUS_PROCESSING;
    EarlyHints                    = HTTP_STATUS_EARLY_HINTS;
    { 2xx }
    OK                            = HTTP_STATUS_OK;
    Created                       = HTTP_STATUS_CREATED;
    Accepted                      = HTTP_STATUS_ACCEPTED;
    NonAuthoritativeInformation   = HTTP_STATUS_NON_AUTHORITATIVE_INFORMATION;
    NoContent                     = HTTP_STATUS_NO_CONTENT;
    ResetContent                  = HTTP_STATUS_RESET_CONTENT;
    PartialContent                = HTTP_STATUS_PARTIAL_CONTENT;
    MultiStatus                   = HTTP_STATUS_MULTI_STATUS;
    AlreadyReported               = HTTP_STATUS_ALREADY_REPORTED;
    IMUsed                        = HTTP_STATUS_IM_USED;
    { 3xx }
    MultipleChoices               = HTTP_STATUS_MULTIPLE_CHOICES;
    MovedPermanently              = HTTP_STATUS_MOVED_PERMANENTLY;
    Found                         = HTTP_STATUS_FOUND;
    SeeOther                      = HTTP_STATUS_SEE_OTHER;
    NotModified                   = HTTP_STATUS_NOT_MODIFIED;
    UseProxy                      = HTTP_STATUS_USE_PROXY;
    TemporaryRedirect             = HTTP_STATUS_TEMPORARY_REDIRECT;
    PermanentRedirect             = HTTP_STATUS_PERMANENT_REDIRECT;
    { 4xx }
    BadRequest                    = HTTP_STATUS_BAD_REQUEST;
    Unauthorized                  = HTTP_STATUS_UNAUTHORIZED;
    PaymentRequired               = HTTP_STATUS_PAYMENT_REQUIRED;
    Forbidden                     = HTTP_STATUS_FORBIDDEN;
    NotFound                      = HTTP_STATUS_NOT_FOUND;
    MethodNotAllowed              = HTTP_STATUS_METHOD_NOT_ALLOWED;
    NotAcceptable                 = HTTP_STATUS_NOT_ACCEPTABLE;
    ProxyAuthenticationRequired   = HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED;
    RequestTimeout                = HTTP_STATUS_REQUEST_TIMEOUT;
    Conflict                      = HTTP_STATUS_CONFLICT;
    Gone                          = HTTP_STATUS_GONE;
    LengthRequired                = HTTP_STATUS_LENGTH_REQUIRED;
    PreconditionFailed            = HTTP_STATUS_PRECONDITION_FAILED;
    PayloadTooLarge               = HTTP_STATUS_PAYLOAD_TOO_LARGE;
    UriTooLong                    = HTTP_STATUS_URI_TOO_LONG;
    UnsupportedMediaType          = HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE;
    RangeNotSatisfiable           = HTTP_STATUS_RANGE_NOT_SATISFIABLE;
    ExpectationFailed             = HTTP_STATUS_EXPECTATION_FAILED;
    ImATeapot                     = HTTP_STATUS_IM_A_TEAPOT;
    MisdirectedRequest            = HTTP_STATUS_MISDIRECTED_REQUEST;
    UnprocessableEntity           = HTTP_STATUS_UNPROCESSABLE_ENTITY;
    Locked                        = HTTP_STATUS_LOCKED;
    FailedDependency              = HTTP_STATUS_FAILED_DEPENDENCY;
    TooEarly                      = HTTP_STATUS_TOO_EARLY;
    UpgradeRequired               = HTTP_STATUS_UPGRADE_REQUIRED;
    PreconditionRequired          = HTTP_STATUS_PRECONDITION_REQUIRED;
    TooManyRequests               = HTTP_STATUS_TOO_MANY_REQUESTS;
    RequestHeaderFieldsTooLarge   = HTTP_STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE;
    UnavailableForLegalReasons    = HTTP_STATUS_UNAVAILABLE_FOR_LEGAL_REASONS;
    { 5xx }
    InternalServerError           = HTTP_STATUS_INTERNAL_SERVER_ERROR;
    NotImplemented                = HTTP_STATUS_NOT_IMPLEMENTED;
    BadGateway                    = HTTP_STATUS_BAD_GATEWAY;
    ServiceUnavailable            = HTTP_STATUS_SERVICE_UNAVAILABLE;
    GatewayTimeout                = HTTP_STATUS_GATEWAY_TIMEOUT;
    HttpVersionNotSupported       = HTTP_STATUS_HTTP_VERSION_NOT_SUPPORTED;
    VariantAlsoNegotiates         = HTTP_STATUS_VARIANT_ALSO_NEGOTIATES;
    InsufficientStorage           = HTTP_STATUS_INSUFFICIENT_STORAGE;
    LoopDetected                  = HTTP_STATUS_LOOP_DETECTED;
    NotExtended                   = HTTP_STATUS_NOT_EXTENDED;
    NetworkAuthenticationRequired = HTTP_STATUS_NETWORK_AUTHENTICATION_REQUIRED;
  end;

  TMediaType = record
  public const
    Json           = MIME_APPLICATION_JSON;
    JsonUtf8       = MIME_APPLICATION_JSON_UTF8;
    Cbor           = MIME_APPLICATION_CBOR;
    Bson           = MIME_APPLICATION_BSON;
    Xml            = MIME_APPLICATION_XML;
    TextXml        = MIME_TEXT_XML;
    Csv            = MIME_TEXT_CSV;
    MergePatch     = MIME_APPLICATION_MERGE_PATCH;
    JsonPatch      = MIME_APPLICATION_JSON_PATCH;
    ProblemJson    = MIME_APPLICATION_PROBLEM_JSON;
    ProblemJsonUtf8 = MIME_APPLICATION_PROBLEM_JSON_UTF8;
    ProblemCbor    = MIME_APPLICATION_PROBLEM_CBOR;
    ProblemXml     = MIME_APPLICATION_PROBLEM_XML;
    EventStream    = MIME_TEXT_EVENT_STREAM;
    OctetStream    = MIME_APPLICATION_OCTET_STREAM;
    MultipartForm  = MIME_MULTIPART_FORM_DATA;
    FormUrlEncoded = MIME_APPLICATION_FORM_URLENCODED;
    TextPlain      = MIME_TEXT_PLAIN;
    TextHtml       = MIME_TEXT_HTML;
    Pdf            = MIME_APPLICATION_PDF;
  end;

  THttpHeader = record
  public const
    ContentType       = HEADER_CONTENT_TYPE;
    Accept            = HEADER_ACCEPT;
    AcceptEncoding    = HEADER_ACCEPT_ENCODING;
    ContentEncoding   = HEADER_CONTENT_ENCODING;
    Authorization     = HEADER_AUTHORIZATION;
    WwwAuthenticate   = HEADER_WWW_AUTHENTICATE;
    ContentLength     = HEADER_CONTENT_LENGTH;
    ApiKey            = HEADER_API_KEY;
    ETag              = HEADER_ETAG;
    IfMatch           = HEADER_IF_MATCH;
    IfNoneMatch       = HEADER_IF_NONE_MATCH;
    IfModifiedSince   = HEADER_IF_MODIFIED_SINCE;
    IfUnmodifiedSince = HEADER_IF_UNMODIFIED_SINCE;
    IdempotencyKey    = HEADER_IDEMPOTENCY_KEY;
    IdempotentReplayed = HEADER_IDEMPOTENT_REPLAYED;
    LastEventId       = HEADER_LAST_EVENT_ID;
    Traceparent       = HEADER_TRACEPARENT;
    Tracestate        = HEADER_TRACESTATE;
    RetryAfter        = HEADER_RETRY_AFTER;
    Allow             = HEADER_ALLOW;
    CacheControl      = HEADER_CACHE_CONTROL;
    Location          = HEADER_LOCATION;
    Vary              = HEADER_VARY;
    XRequestId        = HEADER_X_REQUEST_ID;
    XCorrelationId    = HEADER_X_CORRELATION_ID;
    XForwardedFor     = HEADER_X_FORWARDED_FOR;
    XForwardedProto   = HEADER_X_FORWARDED_PROTO;
    XForwardedPrefix  = HEADER_X_FORWARDED_PREFIX;
  end;

  THttpMethod = record
  public const
    Get     = HTTP_METHOD_GET;
    Post    = HTTP_METHOD_POST;
    Put     = HTTP_METHOD_PUT;
    Delete  = HTTP_METHOD_DELETE;
    Patch   = HTTP_METHOD_PATCH;
    Options = HTTP_METHOD_OPTIONS;
    Head    = HTTP_METHOD_HEAD;
    Trace   = HTTP_METHOD_TRACE;
    Connect = HTTP_METHOD_CONNECT;
  end;

{ Utilities for HTTP status code classification and standard reason phrases }
function HttpStatusReasonPhrase(AStatusCode: Integer): string;
function IsHttpStatusInformational(AStatusCode: Integer): Boolean; inline;
function IsHttpStatusSuccess(AStatusCode: Integer): Boolean; inline;
function IsHttpStatusRedirection(AStatusCode: Integer): Boolean; inline;
function IsHttpStatusClientError(AStatusCode: Integer): Boolean; inline;
function IsHttpStatusServerError(AStatusCode: Integer): Boolean; inline;

implementation

function HttpStatusReasonPhrase(AStatusCode: Integer): string;
begin
  case AStatusCode of
    { 1xx }
    HTTP_STATUS_CONTINUE:                        Result := 'Continue';
    HTTP_STATUS_SWITCHING_PROTOCOLS:             Result := 'Switching Protocols';
    HTTP_STATUS_PROCESSING:                      Result := 'Processing';
    HTTP_STATUS_EARLY_HINTS:                     Result := 'Early Hints';
    { 2xx }
    HTTP_STATUS_OK:                              Result := 'OK';
    HTTP_STATUS_CREATED:                         Result := 'Created';
    HTTP_STATUS_ACCEPTED:                        Result := 'Accepted';
    HTTP_STATUS_NON_AUTHORITATIVE_INFORMATION:   Result := 'Non-Authoritative Information';
    HTTP_STATUS_NO_CONTENT:                      Result := 'No Content';
    HTTP_STATUS_RESET_CONTENT:                   Result := 'Reset Content';
    HTTP_STATUS_PARTIAL_CONTENT:                 Result := 'Partial Content';
    HTTP_STATUS_MULTI_STATUS:                    Result := 'Multi-Status';
    HTTP_STATUS_ALREADY_REPORTED:                Result := 'Already Reported';
    HTTP_STATUS_IM_USED:                         Result := 'IM Used';
    { 3xx }
    HTTP_STATUS_MULTIPLE_CHOICES:                Result := 'Multiple Choices';
    HTTP_STATUS_MOVED_PERMANENTLY:               Result := 'Moved Permanently';
    HTTP_STATUS_FOUND:                           Result := 'Found';
    HTTP_STATUS_SEE_OTHER:                       Result := 'See Other';
    HTTP_STATUS_NOT_MODIFIED:                    Result := 'Not Modified';
    HTTP_STATUS_USE_PROXY:                       Result := 'Use Proxy';
    HTTP_STATUS_TEMPORARY_REDIRECT:              Result := 'Temporary Redirect';
    HTTP_STATUS_PERMANENT_REDIRECT:              Result := 'Permanent Redirect';
    { 4xx }
    HTTP_STATUS_BAD_REQUEST:                     Result := 'Bad Request';
    HTTP_STATUS_UNAUTHORIZED:                    Result := 'Unauthorized';
    HTTP_STATUS_PAYMENT_REQUIRED:                Result := 'Payment Required';
    HTTP_STATUS_FORBIDDEN:                       Result := 'Forbidden';
    HTTP_STATUS_NOT_FOUND:                       Result := 'Not Found';
    HTTP_STATUS_METHOD_NOT_ALLOWED:              Result := 'Method Not Allowed';
    HTTP_STATUS_NOT_ACCEPTABLE:                  Result := 'Not Acceptable';
    HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED:   Result := 'Proxy Authentication Required';
    HTTP_STATUS_REQUEST_TIMEOUT:                 Result := 'Request Timeout';
    HTTP_STATUS_CONFLICT:                        Result := 'Conflict';
    HTTP_STATUS_GONE:                            Result := 'Gone';
    HTTP_STATUS_LENGTH_REQUIRED:                 Result := 'Length Required';
    HTTP_STATUS_PRECONDITION_FAILED:             Result := 'Precondition Failed';
    HTTP_STATUS_PAYLOAD_TOO_LARGE:               Result := 'Payload Too Large';
    HTTP_STATUS_URI_TOO_LONG:                    Result := 'URI Too Long';
    HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE:          Result := 'Unsupported Media Type';
    HTTP_STATUS_RANGE_NOT_SATISFIABLE:           Result := 'Range Not Satisfiable';
    HTTP_STATUS_EXPECTATION_FAILED:              Result := 'Expectation Failed';
    HTTP_STATUS_IM_A_TEAPOT:                     Result := 'I''m a Teapot';
    HTTP_STATUS_MISDIRECTED_REQUEST:             Result := 'Misdirected Request';
    HTTP_STATUS_UNPROCESSABLE_ENTITY:            Result := 'Unprocessable Entity';
    HTTP_STATUS_LOCKED:                          Result := 'Locked';
    HTTP_STATUS_FAILED_DEPENDENCY:               Result := 'Failed Dependency';
    HTTP_STATUS_TOO_EARLY:                       Result := 'Too Early';
    HTTP_STATUS_UPGRADE_REQUIRED:                Result := 'Upgrade Required';
    HTTP_STATUS_PRECONDITION_REQUIRED:           Result := 'Precondition Required';
    HTTP_STATUS_TOO_MANY_REQUESTS:               Result := 'Too Many Requests';
    HTTP_STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE: Result := 'Request Header Fields Too Large';
    HTTP_STATUS_UNAVAILABLE_FOR_LEGAL_REASONS:   Result := 'Unavailable For Legal Reasons';
    { 5xx }
    HTTP_STATUS_INTERNAL_SERVER_ERROR:           Result := 'Internal Server Error';
    HTTP_STATUS_NOT_IMPLEMENTED:                 Result := 'Not Implemented';
    HTTP_STATUS_BAD_GATEWAY:                     Result := 'Bad Gateway';
    HTTP_STATUS_SERVICE_UNAVAILABLE:             Result := 'Service Unavailable';
    HTTP_STATUS_GATEWAY_TIMEOUT:                 Result := 'Gateway Timeout';
    HTTP_STATUS_HTTP_VERSION_NOT_SUPPORTED:      Result := 'HTTP Version Not Supported';
    HTTP_STATUS_VARIANT_ALSO_NEGOTIATES:         Result := 'Variant Also Negotiates';
    HTTP_STATUS_INSUFFICIENT_STORAGE:            Result := 'Insufficient Storage';
    HTTP_STATUS_LOOP_DETECTED:                   Result := 'Loop Detected';
    HTTP_STATUS_NOT_EXTENDED:                    Result := 'Not Extended';
    HTTP_STATUS_NETWORK_AUTHENTICATION_REQUIRED: Result := 'Network Authentication Required';
  else
    Result := 'Unknown Status';
  end;
end;

function IsHttpStatusInformational(AStatusCode: Integer): Boolean;
begin
  Result := (AStatusCode >= 100) and (AStatusCode <= 199);
end;

function IsHttpStatusSuccess(AStatusCode: Integer): Boolean;
begin
  Result := (AStatusCode >= 200) and (AStatusCode <= 299);
end;

function IsHttpStatusRedirection(AStatusCode: Integer): Boolean;
begin
  Result := (AStatusCode >= 300) and (AStatusCode <= 399);
end;

function IsHttpStatusClientError(AStatusCode: Integer): Boolean;
begin
  Result := (AStatusCode >= 400) and (AStatusCode <= 499);
end;

function IsHttpStatusServerError(AStatusCode: Integer): Boolean;
begin
  Result := (AStatusCode >= 500) and (AStatusCode <= 599);
end;

end.
