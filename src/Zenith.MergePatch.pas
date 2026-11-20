{
  Zenith Framework - RFC 7396 JSON Merge Patch HTTP Support

  Provides Content-Type negotiation, payload parsing and model patching helpers
  for HTTP PATCH endpoints using `application/merge-patch+json` (RFC 7396).
}

unit Zenith.MergePatch;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpjson, jsonparser,
  DeltaModel, DeltaModel.MergePatch, Zenith.Exceptions;

const
  { RFC 7396 registered media type }
  MIME_APPLICATION_MERGE_PATCH_JSON = 'application/merge-patch+json';
  HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE = 415;

type
  EUnsupportedMediaType = class(HTTPException);

  { TZenithMergePatch - HTTP helpers for RFC 7396 PATCH handlers }
  TZenithMergePatch = class
  public
    { Extracts the bare media type from a Content-Type header (stripping parameters like "; charset=utf-8"). }
    class function ExtractMediaType(const AContentType: string): string; static;

    { Checks whether a Content-Type string matches application/merge-patch+json. }
    class function IsMergePatchContentType(const AContentType: string): Boolean; static;

    { Checks whether an HTTP request carries Content-Type: application/merge-patch+json. }
    class function IsMergePatchRequest(ARequest: TRequest): Boolean; static;

    { Validates Content-Type header; raises EUnsupportedMediaType if not application/merge-patch+json. }
    class procedure RequireMergePatchContentType(ARequest: TRequest); static;

    { Parses the request body as an arbitrary RFC 7396 JSON patch value (caller owns result). }
    class function ParsePatchPayload(ARequest: TRequest): TJSONData; static;

    { Parses the request body ensuring it is a JSON object suitable for model patching (caller owns result). }
    class function ParsePatchObject(ARequest: TRequest): TJSONObject; static;

    { Validates Content-Type, parses body, and applies RFC 7396 Merge Patch to AModel.
      Returns the number of dirty fields modified. }
    class function ApplyToModel(ARequest: TRequest; AModel: TDeltaModel;
      AOptions: TMergePatchOptions = []): Integer; static;

    { Validates Content-Type, parses body, and applies RFC 7396 Merge Patch to ATarget JSON.
      Returns a newly allocated merged TJSONData owned by the caller. }
    class function ApplyJson(ARequest: TRequest; ATarget: TJSONData): TJSONData; static;

    { Sets Accept-Patch response header advertising application/merge-patch+json support (RFC 5789). }
    class procedure AdvertiseAcceptPatch(AResponse: TResponse); static;
  end;

implementation

class function TZenithMergePatch.ExtractMediaType(const AContentType: string): string;
var
  SemiPos: SizeInt;
begin
  Result := Trim(AContentType);
  SemiPos := Pos(';', Result);
  if SemiPos > 0 then
    Result := Trim(Copy(Result, 1, SemiPos - 1));
  Result := LowerCase(Result);
end;

class function TZenithMergePatch.IsMergePatchContentType(const AContentType: string): Boolean;
begin
  Result := ExtractMediaType(AContentType) = MIME_APPLICATION_MERGE_PATCH_JSON;
end;

class function TZenithMergePatch.IsMergePatchRequest(ARequest: TRequest): Boolean;
begin
  if ARequest = nil then
    Exit(False);
  Result := IsMergePatchContentType(ARequest.ContentType);
end;

class procedure TZenithMergePatch.RequireMergePatchContentType(ARequest: TRequest);
begin
  if not IsMergePatchRequest(ARequest) then
    raise EUnsupportedMediaType.CreateFmt(
      'Unsupported Content-Type "%s". Expected "%s" (RFC 7396).',
      [ARequest.ContentType, MIME_APPLICATION_MERGE_PATCH_JSON]
    );
end;

class function TZenithMergePatch.ParsePatchPayload(ARequest: TRequest): TJSONData;
var
  Body: RawByteString;
begin
  if ARequest = nil then
    raise EBadRequest.Create('HTTP request cannot be nil.');

  RequireMergePatchContentType(ARequest);

  Body := Trim(ARequest.Content);
  if Body = '' then
    raise EBadRequest.Create('Empty RFC 7396 merge-patch payload.');

  try
    Result := GetJSON(Body, False);
  except
    on E: Exception do
      raise EBadRequest.CreateFmt('Invalid JSON in merge-patch payload: %s', [E.Message]);
  end;

  if Result = nil then
    raise EBadRequest.Create('Invalid JSON in merge-patch payload.');
end;

class function TZenithMergePatch.ParsePatchObject(ARequest: TRequest): TJSONObject;
var
  Data: TJSONData;
begin
  Data := ParsePatchPayload(ARequest);
  if not (Data is TJSONObject) then
  begin
    Data.Free;
    raise EBadRequest.Create('RFC 7396 model merge-patch payload must be a JSON object.');
  end;
  Result := TJSONObject(Data);
end;

class function TZenithMergePatch.ApplyToModel(ARequest: TRequest;
  AModel: TDeltaModel; AOptions: TMergePatchOptions): Integer;
var
  PatchObj: TJSONObject;
begin
  if AModel = nil then
    raise EBadRequest.Create('Target model cannot be nil.');

  PatchObj := ParsePatchObject(ARequest);
  try
    try
      Result := ApplyMergePatch(AModel, PatchObj, AOptions);
    except
      on E: EDeltaMergePatchException do
        raise EBadRequest.Create(E.Message);
    end;
  finally
    PatchObj.Free;
  end;
end;

class function TZenithMergePatch.ApplyJson(ARequest: TRequest;
  ATarget: TJSONData): TJSONData;
var
  PatchData: TJSONData;
begin
  PatchData := ParsePatchPayload(ARequest);
  try
    Result := MergePatch(ATarget, PatchData);
  finally
    PatchData.Free;
  end;
end;

class procedure TZenithMergePatch.AdvertiseAcceptPatch(AResponse: TResponse);
begin
  if AResponse <> nil then
    AResponse.SetCustomHeader('Accept-Patch', MIME_APPLICATION_MERGE_PATCH_JSON);
end;

end.
