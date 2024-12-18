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
      AInstance: string = ''): string;
  end;

implementation

class function TJsonError.ToJson(AType, ATitle: string; AStatus: Integer;
  ADetail: string; AInstance: string): string;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.Strings['type'] := AType;
    Json.Strings['title'] := ATitle;
    Json.Int64s['status'] := AStatus;

    if not ADetail.IsEmpty then
      Json.Strings['detail'] := ADetail;

    if not AInstance.IsEmpty then
      Json.Strings['instance'] := AInstance;

    Result := Json.AsJSON;
  finally
    Json.Free;
  end;
end;

end.

