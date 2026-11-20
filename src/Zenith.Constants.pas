unit Zenith.Constants;

{$mode ObjFPC}{$H+}

interface

const
  { HTTP Status Codes }
  HTTP_STATUS_OK                    = 200;
  HTTP_STATUS_CREATED               = 201;
  HTTP_STATUS_ACCEPTED              = 202;
  HTTP_STATUS_NO_CONTENT            = 204;
  HTTP_STATUS_BAD_REQUEST           = 400;
  HTTP_STATUS_UNAUTHORIZED          = 401;
  HTTP_STATUS_FORBIDDEN             = 403;
  HTTP_STATUS_NOT_FOUND             = 404;
  HTTP_STATUS_METHOD_NOT_ALLOWED    = 405;
  HTTP_STATUS_CONFLICT              = 409;
  HTTP_STATUS_UNPROCESSABLE_ENTITY  = 422;
  HTTP_STATUS_TOO_MANY_REQUESTS     = 429;
  HTTP_STATUS_INTERNAL_SERVER_ERROR = 500;
  HTTP_STATUS_NOT_IMPLEMENTED       = 501;
  HTTP_STATUS_BAD_GATEWAY           = 502;
  HTTP_STATUS_SERVICE_UNAVAILABLE   = 503;

  { HTTP Methods }
  HTTP_METHOD_GET     = 'GET';
  HTTP_METHOD_POST    = 'POST';
  HTTP_METHOD_PUT     = 'PUT';
  HTTP_METHOD_DELETE  = 'DELETE';
  HTTP_METHOD_PATCH   = 'PATCH';
  HTTP_METHOD_OPTIONS = 'OPTIONS';
  HTTP_METHOD_HEAD    = 'HEAD';

  { MIME Content Types }
  MIME_APPLICATION_JSON          = 'application/json';
  MIME_APPLICATION_CBOR          = 'application/cbor';
  MIME_APPLICATION_BSON          = 'application/bson';
  MIME_APPLICATION_XML           = 'application/xml';
  MIME_TEXT_XML                  = 'text/xml';
  MIME_TEXT_CSV                  = 'text/csv';
  MIME_APPLICATION_PROBLEM_JSON  = 'application/problem+json';
  MIME_APPLICATION_OCTET_STREAM  = 'application/octet-stream';
  MIME_MULTIPART_FORM_DATA       = 'multipart/form-data';
  MIME_TEXT_PLAIN                = 'text/plain';
  MIME_TEXT_HTML                 = 'text/html';

  { Common HTTP Headers }
  HEADER_CONTENT_TYPE       = 'Content-Type';
  HEADER_ACCEPT             = 'Accept';
  HEADER_ACCEPT_ENCODING    = 'Accept-Encoding';
  HEADER_CONTENT_ENCODING   = 'Content-Encoding';
  HEADER_AUTHORIZATION      = 'Authorization';
  HEADER_WWW_AUTHENTICATE   = 'WWW-Authenticate';
  HEADER_CONTENT_LENGTH     = 'Content-Length';
  HEADER_API_KEY            = 'X-API-Key';

  { Encodings }
  ENCODING_GZIP     = 'gzip';
  ENCODING_DEFLATE  = 'deflate';
  ENCODING_IDENTITY = 'identity';

implementation

end.
