unit Zenith.Exceptions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  HTTPException = class(Exception);

  EValidation = class(HTTPException);
  EMissingRequiredField = class(HTTPException);
  EUnknowError = class(HTTPException);
  EUnauthorized = class(HTTPException);
  EForbidden = class(HTTPException);
  EResourceNotFound = class(HTTPException);
  ETooManyRequests= class(HTTPException);
  EServerError = class(HTTPException);
  EBadRequest = class(HTTPException);
  ENotFound = class(HTTPException);

implementation

end.

