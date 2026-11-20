unit Zenith.Security;

{$IFDEF FPC}
  {$mode Delphi}{$H+}
{$ENDIF}

interface

uses
  Classes, SysUtils, HTTPDefs, fpjson, jsonparser;

type
  { Agnostic Security Context }
  TZSecurityContext = record
    IsAuthenticated: Boolean;
    Subject: string;
    Roles: TStringList;
    Permissions: TStringList;
    Attributes: TJSONObject;

    function HasRole(const ARole: string): Boolean;
    function HasPermission(const APermission: string): Boolean;
    function GetAttribute(const AKey: string; const ADef: string = ''): string;
    function GetAttributeInt64(const AKey: string; const ADef: Int64 = 0): Int64;
    function GetAttributeBool(const AKey: string; const ADef: Boolean = False): Boolean;
    procedure FreeInternalObjects;

    class function CreateAnonymous: TZSecurityContext; static;
    class function CreateAuthenticated(const ASubject: string): TZSecurityContext; static;
  end;

  { Security Context Resolver Interface }
  IZenithSecurityResolver = interface
    ['{7D9A4C62-12D8-4687-B2A8-4D2A90F845C2}']
    function Resolve(ARequest: TRequest): TZSecurityContext;
  end;

  { Default Bearer JWT Resolver }
  TZJWTBearerResolver = class(TInterfacedObject, IZenithSecurityResolver)
  public
    function Resolve(ARequest: TRequest): TZSecurityContext;
  end;

procedure SetZenithSecurityResolver(AResolver: IZenithSecurityResolver);
function GetZenithSecurityResolver: IZenithSecurityResolver;

implementation

uses
  Zenith.Auth.JWT;

var
  GDefaultSecurityResolver: IZenithSecurityResolver = nil;

procedure SetZenithSecurityResolver(AResolver: IZenithSecurityResolver);
begin
  GDefaultSecurityResolver := AResolver;
end;

function GetZenithSecurityResolver: IZenithSecurityResolver;
begin
  Result := GDefaultSecurityResolver;
end;

{ TZSecurityContext }

function TZSecurityContext.HasRole(const ARole: string): Boolean;
var
  Target: string;
begin
  if not IsAuthenticated or not Assigned(Roles) then
    Exit(False);
  Target := Trim(ARole);
  if Target.IsEmpty then
    Exit(False);
  if Roles.IndexOf('*') >= 0 then
    Exit(True);
  Result := Roles.IndexOf(Target) >= 0;
end;

function TZSecurityContext.HasPermission(const APermission: string): Boolean;
var
  Target: string;
begin
  if not IsAuthenticated or not Assigned(Permissions) then
    Exit(False);
  Target := Trim(APermission);
  if Target.IsEmpty then
    Exit(False);
  if (Permissions.IndexOf('*') >= 0) or (Permissions.IndexOf('ALL') >= 0) then
    Exit(True);
  Result := Permissions.IndexOf(Target) >= 0;
end;

function TZSecurityContext.GetAttribute(const AKey: string; const ADef: string): string;
var
  Data: TJSONData;
begin
  Result := ADef;
  if not Assigned(Attributes) then
    Exit;
  Data := Attributes.Find(AKey);
  if (Data <> nil) and (Data.JSONType <> jtNull) then
    Result := Data.AsString;
end;

function TZSecurityContext.GetAttributeInt64(const AKey: string; const ADef: Int64): Int64;
var
  Data: TJSONData;
begin
  Result := ADef;
  if not Assigned(Attributes) then
    Exit;
  Data := Attributes.Find(AKey);
  if (Data <> nil) and (Data.JSONType <> jtNull) then
  begin
    case Data.JSONType of
      jtNumber: Result := Data.AsInt64;
      jtString: TryStrToInt64(Data.AsString, Result);
    else
      Result := ADef;
    end;
  end;
end;

function TZSecurityContext.GetAttributeBool(const AKey: string; const ADef: Boolean): Boolean;
var
  Data: TJSONData;
begin
  Result := ADef;
  if not Assigned(Attributes) then
    Exit;
  Data := Attributes.Find(AKey);
  if (Data <> nil) and (Data.JSONType <> jtNull) then
    Result := Data.AsBoolean;
end;

procedure TZSecurityContext.FreeInternalObjects;
begin
  if Assigned(Roles) then
  begin
    Roles.Free;
    Roles := nil;
  end;
  if Assigned(Permissions) then
  begin
    Permissions.Free;
    Permissions := nil;
  end;
  if Assigned(Attributes) then
  begin
    Attributes.Free;
    Attributes := nil;
  end;
end;

class function TZSecurityContext.CreateAnonymous: TZSecurityContext;
begin
  Result.IsAuthenticated := False;
  Result.Subject := '';
  Result.Roles := TStringList.Create;
  Result.Roles.CaseSensitive := False;
  Result.Permissions := TStringList.Create;
  Result.Permissions.CaseSensitive := False;
  Result.Attributes := TJSONObject.Create;
end;

class function TZSecurityContext.CreateAuthenticated(const ASubject: string): TZSecurityContext;
begin
  Result.IsAuthenticated := True;
  Result.Subject := ASubject;
  Result.Roles := TStringList.Create;
  Result.Roles.CaseSensitive := False;
  Result.Permissions := TStringList.Create;
  Result.Permissions.CaseSensitive := False;
  Result.Attributes := TJSONObject.Create;
end;

{ TZJWTBearerResolver }

function TZJWTBearerResolver.Resolve(ARequest: TRequest): TZSecurityContext;
var
  AuthHeader, Token, SubjectVal: string;
  Payload: TPayLoad;
  PayloadJson: TJSONObject;
  JsonItem: TJSONData;
  I: Integer;
begin
  Result := TZSecurityContext.CreateAnonymous;

  AuthHeader := ARequest.Authorization;
  if AuthHeader.IsEmpty then
    AuthHeader := ARequest.GetCustomHeader('Authorization');

  AuthHeader := Trim(AuthHeader);
  if not AuthHeader.StartsWith('Bearer ', True) then
    Exit;

  Token := Trim(Copy(AuthHeader, 8, MaxInt));
  if Token.IsEmpty then
    Exit;

  try
    Payload := TJWT.ValidadeToken(Token);
    if Payload = nil then
      Exit;

    try
      PayloadJson := GetJSON(Payload.ToJson) as TJSONObject;
      try
        if PayloadJson.Find('sub') <> nil then
          SubjectVal := PayloadJson.Strings['sub']
        else if PayloadJson.Find('user') <> nil then
          SubjectVal := PayloadJson.Strings['user']
        else if PayloadJson.Find('id') <> nil then
          SubjectVal := PayloadJson.Get('id', '')
        else
          SubjectVal := '';

        Result.IsAuthenticated := True;
        Result.Subject := SubjectVal;

        JsonItem := PayloadJson.Find('roles');
        if JsonItem <> nil then
        begin
          if JsonItem.JSONType = jtArray then
          begin
            for I := 0 to TJSONArray(JsonItem).Count - 1 do
              Result.Roles.Add(TJSONArray(JsonItem).Strings[I]);
          end
          else if JsonItem.JSONType = jtString then
            Result.Roles.CommaText := JsonItem.AsString;
        end
        else
        begin
          JsonItem := PayloadJson.Find('role');
          if (JsonItem <> nil) and (JsonItem.JSONType = jtString) then
            Result.Roles.Add(JsonItem.AsString);
        end;

        JsonItem := PayloadJson.Find('permissions');
        if JsonItem <> nil then
        begin
          if JsonItem.JSONType = jtArray then
          begin
            for I := 0 to TJSONArray(JsonItem).Count - 1 do
              Result.Permissions.Add(TJSONArray(JsonItem).Strings[I]);
          end
          else if JsonItem.JSONType = jtString then
            Result.Permissions.CommaText := JsonItem.AsString;
        end;

        Result.Attributes.Free;
        Result.Attributes := PayloadJson.Clone as TJSONObject;
      finally
        PayloadJson.Free;
      end;
    finally
      Payload.Free;
    end;
  except
    // Resolves to anonymous on invalid/expired token
  end;
end;

end.
