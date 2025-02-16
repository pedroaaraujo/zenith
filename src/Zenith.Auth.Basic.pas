unit Zenith.Auth.Basic;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, base64;

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
  SL: TStringList;
begin
  if FAuth.IsEmpty then
    Exit;

  SL := TStringList.Create;
  try
    SL.Delimiter := ':';
    SL.StrictDelimiter := True;
    SL.DelimitedText := DecodeStringBase64(FAuth);
    FUser := Sl.Strings[0];
    FPassword := Sl.Strings[1];
  finally
    SL.Free;
  end;
end;

constructor TBasicAuthorization.Create(Auth: string);
begin
  FAuth := Auth.Replace('Basic ', EmptyStr, [rfIgnoreCase]);
  Extract;
end;

end.

