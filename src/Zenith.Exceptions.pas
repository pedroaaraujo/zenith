unit Zenith.Exceptions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  HTTPException = class(Exception)
  public
    constructor CreateFmt(const AFormat: string; const AArgs: array of const);
  end;

  EValidation = class(HTTPException);
  EConflict = class(HTTPException);
  EMissingRequiredField = class(HTTPException);
  EUnknownError = class(HTTPException);
  EUnknowError = EUnknownError; // Backward compatibility alias
  EUnauthorized = class(HTTPException);
  EForbidden = class(HTTPException);
  EResourceNotFound = class(HTTPException);
  ETooManyRequests = class(HTTPException);
  EServerError = class(HTTPException);
  EBadRequest = class(HTTPException);
  ENotFound = class(HTTPException);
  EUnprocessableEntity = class(HTTPException);

implementation

{ HTTPException }

constructor HTTPException.CreateFmt(const AFormat: string; const AArgs: array of const);
begin
  inherited Create(Format(AFormat, AArgs));
end;

end.
