unit Zenith.Auth.Basic;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, base64, Zenith.Exceptions;

type
  { TBasicAuthorization }

  TBasicAuthorization = class
  private
    FAuth: string;
    FPassword: string;
    FUser: string;
    procedure Extract;
  public
    property User: string read FUser;
    property Password: string read FPassword;
    constructor Create(Auth: string);
  end;

implementation

{ TBasicAuthorization }

procedure TBasicAuthorization.Extract;
var
  Decoded: string;
  P: SizeInt;
begin
  FUser := '';
  FPassword := '';
  if FAuth.IsEmpty then
    Exit;

  { RFC 7617: user-id não contém ":", mas a senha pode conter. Separar
    somente no primeiro ":" e rejeitar credenciais sem separador. }
  try
    Decoded := DecodeStringBase64(FAuth, True);
  except
    raise EUnauthorized.Create('Invalid Basic credentials');
  end;
  P := Pos(':', Decoded);
  if P = 0 then
    raise EUnauthorized.Create('Invalid Basic credentials');
  FUser := Copy(Decoded, 1, P - 1);
  FPassword := Copy(Decoded, P + 1, MaxInt);
end;

constructor TBasicAuthorization.Create(Auth: string);
begin
  FAuth := Trim(Auth);
  if FAuth.StartsWith('Basic ', True) then
    FAuth := Trim(Copy(FAuth, 7, MaxInt));
  Extract;
end;

end.

