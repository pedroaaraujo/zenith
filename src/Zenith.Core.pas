unit Zenith.Core;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, custhttpapp, HTTPDefs, fpjson,

  Zenith.Exceptions, Zenith.Log, Zenith.Consts, Zenith.Types, Zenith.Env;

procedure ConfigureApplication(App: TCustomHTTPApplication);

implementation

procedure HandleExcept(E: Exception; AReq: TRequest; AResp: TResponse);
var
  Json: TJSONObject;
  Error, Title: string;
begin
  Json := TJSONObject.Create;
  try
    AResp.ContentType := ApplicationJson;
    AResp.Contents.Clear;

    if E is HTTPException then
    begin
      AResp.Code := StatusBadRequest;
      Title := 'Não foi possível executar a operação.';
      Error := 'UNKNOWN_ERROR';
      if E is EValidation then
      begin
        AResp.Code := StatusBadRequest;
        Error := 'VALIDATION_ERROR';
        Title := 'Não foi possível executar a operação.';
      end
      else
      if E is EMissingRequiredField then
      begin
        AResp.Code := StatusBadRequest;
        Error := 'MISSING_REQUIRED_FIELD_ERROR';
        Title := 'Não foi possível executar a operação.';
      end
      else
      if E is EUnknowError then
      begin
        AResp.Code := StatusBadRequest;
        Error := 'UNKNOWN_ERROR';
        Title := 'Não foi possível executar a operação.';
      end
      else
      if E is EUnauthorized then
      begin
        AResp.Code := StatusUnauthorized;
        Error := 'UNAUTHORIZED';
        Title := 'Não autorizado.';
      end;
      if E is EForbidden then
      begin
        AResp.Code := StatusForbidden;
        Title := 'Não permitido.';
        Error := 'FORBIDDEN';
      end
      else
      if E is EResourceNotFound then
      begin
        AResp.Code := StatusNotFound;
        Error := 'RESOURCE_NOT_FOUND';
        Title := 'Não encontrado.';
      end
      else
      if E is ETooManyRequests then
      begin
        AResp.Code := StatusTooManyRequests;
        Error := 'TOO_MANY_REQUESTS';
        Title := 'Limite de requisições atingido.';
      end
      else
      if E is EServerError then
      begin
        AResp.Code := StatusInternalServerError;
        Error := 'SERVER_ERROR';
        Title := 'Não foi possível executar a operação.';
      end
      else
      if E is EBadRequest then
      begin
        AResp.Code := StatusBadRequest;
        Error := 'VALIDATION_ERROR';
        Title := 'Falha na validação de regras de negócio.';
      end
      else
      if E is ENotFound then
      begin
        AResp.Code := StatusNotFound;
        Error := 'NOT_FOUND';
        Title := 'Não encontrado.';
      end;
      AResp.Contents.Text := TJsonError.ToJson(
        Error,
        Title,
        AResp.Code,
        {$IFDEF WINDOWS}
        Utf8ToAnsi((E as HTTPException).Message),
        {$ELSE}
        (E as HTTPException).Message,
        {$ENDIF}
        EmptyStr
      );
    end
    else
    begin
      AResp.Code := StatusInternalServerError;
      AResp.Contents.Add(
        TJsonError.ToJson(
          'SERVER_ERROR',
          'Não foi possível executar a operação.',
          AResp.Code,
          E.Message
        )
      );
    end;

    ZenithLogger.Error(
      Concat(
        'Request: ',
        AResp.Request.RemoteAddress, ' ',
        AResp.Request.Method + ' ',
        AResp.Request.URL, ' ',
        AResp.Request.Content,
        sLineBreak +
       'Response: ', AResp.Contents.Text
      )
    );
    AResp.SendContent;
  finally
    Json.Free;
  end;
end;

procedure ApplicationOnShowRequestException(AResponse: TResponse; AnException: Exception; var handled: boolean);
begin
  handled := True;
  HandleExcept(AnException, AResponse.Request, AResponse);
end;

procedure ConfigureApplication(App: TCustomHTTPApplication);
begin
  App.OnShowRequestException := @ApplicationOnShowRequestException;
end;

end.
