unit Zenith.Consts;

{$mode ObjFPC}{$H+}

interface

const
  {$REGION CONTENTTYPE}
  ApplicationJson                   = 'application/json';
  ApplicationXml                    = 'application/xml';
  ApplicationYaml                   = 'application/x-yaml';
  TextPlain                         = 'text/plain';
  TextHtml                          = 'text/html';
  TextCsv                           = 'text/csv';
  ApplicationPdf                    = 'application/pdf';
  ApplicationOctetStream            = 'application/octet-stream';
  ImagePng                          = 'image/png';
  ImageJpeg                         = 'image/jpeg';
  ImageGif                          = 'image/gif';
  VideoMp4                          = 'video/mp4';
  AudioMpeg                         = 'audio/mpeg';
  MultipartFormData                 = 'multipart/form-data';
  ApplicationJavascript             = 'application/javascript';
  ApplicationFontWoff               = 'application/font-woff';
  ApplicationFontWoff2              = 'application/font-woff2';
  ApplicationEot                    = 'application/vnd.ms-fontobject';
  ApplicationOpentype               = 'application/font-otf';
  ApplicationTrueType               = 'application/font-ttf';
  ImageSvgXml                       = 'image/svg+xml';
  ImageWebp                         = 'image/webp';
  AudioOgg                          = 'audio/ogg';
  VideoOgg                          = 'video/ogg';
  VideoWebm                         = 'video/webm';
  TextCss                           = 'text/css';
  ApplicationZip                    = 'application/zip';
  ApplicationRar                    = 'application/x-rar-compressed';
  ApplicationGzip                   = 'application/gzip';
  ApplicationTar                    = 'application/x-tar';
  ApplicationJsonLd                 = 'application/ld+json';
  ApplicationGraphql                = 'application/graphql';
  TextXml                           = 'text/xml';
  TextMarkdown                      = 'text/markdown';
  ApplicationXhtmlXml               = 'application/xhtml+xml';
  ApplicationJsonPatchJson          = 'application/json-patch+json';
  ApplicationSoapXml                = 'application/soap+xml';
  ApplicationVndMsExcel             = 'application/vnd.ms-excel';
  ApplicationVndMsWord              = 'application/vnd.ms-word';
  ApplicationVndOpenxmlformatsOfficedocumentSpreadsheetmlSheet = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';  
  ApplicationVndOpenxmlformatsOfficedocumentWordprocessingmlDocument = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  {$ENDREGION}

  {$REGION STATUS}
  // 1xx - Informational
  StatusContinue                            = 100;         //[RFC7231, Section 6.2.1]
  StatusSwitchingProtocols                  = 101;         //[RFC7231, Section 6.2.2]
  StatusProcessing                          = 102;         //[RFC2518]
  StatusEarlyHints                          = 103;         //[RFC8297]

  // 2xx - Success
  StatusOK                                  = 200;         //[RFC7231, Section 6.3.1]
  StatusCreated                             = 201;         //[RFC7231, Section 6.3.2]
  StatusAccepted                            = 202;         //[RFC7231, Section 6.3.3]
  StatusNonAuthoritativeInformation         = 203;         //[RFC7231, Section 6.3.4]
  StatusNoContent                           = 204;         //[RFC7231, Section 6.3.5]
  StatusResetContent                        = 205;         //[RFC7231, Section 6.3.6]
  StatusPartialContent                      = 206;         //[RFC7233, Section 4.1]
  StatusMultiStatus                         = 207;         //[RFC4918]
  StatusAlreadyReported                     = 208;         //[RFC5842]
  StatusIMUsed                              = 226;         //[RFC3229]

  // 3xx - Redirection
  StatusMultipleChoices                     = 300;         //[RFC7231, Section 6.4.1]
  StatusMovedPermanently                    = 301;         //[RFC7231, Section 6.4.2]
  StatusFound                               = 302;         //[RFC7231, Section 6.4.3]
  StatusSeeOther                            = 303;         //[RFC7231, Section 6.4.4]
  StatusNotModified                         = 304;         //[RFC7232, Section 4.1]
  StatusUseProxy                            = 305;         //[RFC7231, Section 6.4.5]
  StatusTemporaryRedirect                   = 307;         //[RFC7231, Section 6.4.7]
  StatusPermanentRedirect                   = 308;         //[RFC7538]

  // 4xx - Client Errors
  StatusBadRequest                          = 400;         //[RFC7231, Section 6.5.1]
  StatusUnauthorized                        = 401;         //[RFC7235, Section 3.1]
  StatusPaymentRequired                     = 402;         //[RFC7231, Section 6.5.2]
  StatusForbidden                           = 403;         //[RFC7231, Section 6.5.3]
  StatusNotFound                            = 404;         //[RFC7231, Section 6.5.4]
  StatusMethodNotAllowed                    = 405;         //[RFC7231, Section 6.5.5]
  StatusNotAcceptable                       = 406;         //[RFC7231, Section 6.5.6]
  StatusProxyAuthenticationRequired         = 407;         //[RFC7235, Section 3.2]
  StatusRequestTimeout                      = 408;         //[RFC7231, Section 6.5.7]
  StatusConflict                            = 409;         //[RFC7231, Section 6.5.8]
  StatusGone                                = 410;         //[RFC7231, Section 6.5.9]
  StatusLengthRequired                      = 411;         //[RFC7231, Section 6.5.10]
  StatusPreconditionFailed                  = 412;         //[RFC7232, Section 4.2]
  StatusPayloadTooLarge                     = 413;         //[RFC7231, Section 6.5.11]
  StatusURITooLong                          = 414;         //[RFC7231, Section 6.5.12]
  StatusUnsupportedMediaType                = 415;         //[RFC7231, Section 6.5.13]
  StatusRangeNotSatisfiable                 = 416;         //[RFC7233, Section 4.4]
  StatusExpectationFailed                   = 417;         //[RFC7231, Section 6.5.14]
  StatusTooManyRequests                     = 429;

  // 5xx - Server Errors
  StatusInternalServerError                 = 500;         //[RFC7231, Section 6.6.1]
  StatusNotImplemented                      = 501;         //[RFC7231, Section 6.6.2]
  StatusBadGateway                          = 502;         //[RFC7231, Section 6.6.3]
  StatusServiceUnavailable                  = 503;         //[RFC7231, Section 6.6.4]
  StatusGatewayTimeout                      = 504;         //[RFC7231, Section 6.6.5]
  StatusHTTPVersionNotSupported             = 505;         //[RFC7231, Section 6.6.6]
  StatusInsufficientStorage                 = 507;         //[RFC4918]
  StatusLoopDetected                        = 508;         //[RFC5842]
  StatusNotExtended                         = 510;         //[RFC2774]
  StatusNetworkAuthenticationRequired       = 511;         //[RFC6585]
  {$ENDREGION}

implementation

end.
