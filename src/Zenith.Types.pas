unit Zenith.Types;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type

  { TJsonError }

  TJsonError = class
  public
    class function ToJson(AType, ATitle: string; AStatus: Integer; ADetail: string = '';
      AInstance: string = ''): RawByteString;
  end;

implementation

class function TJsonError.ToJson(AType, ATitle: string; AStatus: Integer;
  ADetail: string; AInstance: string): RawByteString;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.Strings['type'] := AType;
    Json.Strings['title'] := ATitle;
    Json.Integers['status'] := AStatus;

    if not ADetail.IsEmpty then
      Json.Strings['detail'] := ADetail;

    if not AInstance.IsEmpty then
      Json.Strings['instance'] := AInstance;

    {$IFDEF MSWINDOWS}
    Result := Utf8ToAnsi(UTF8Encode(Json.AsJSON));
    {$ELSE}
    Result := Json.AsJSON;
    {$ENDIF}
  finally
    Json.Free;
  end;
end;

end.

