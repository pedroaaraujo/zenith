unit Zenith.Core;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, custhttpapp, HTTPDefs, DeltaValidator, fpjson,
  Zenith.Exceptions, Zenith.MergePatch, Zenith.Log, Zenith.Consts, Zenith.Types, Zenith.Env, Zenith.Messages;

procedure ConfigureApplication(App: TCustomHTTPApplication);

implementation

procedure HandleExcept(E: Exception; AReq: TRequest; AResp: TResponse);
var
  Error, Title, Detail, LogLine: string;
  RequestPath: string;
  CallStack: string;
  I: Integer;
  QueryStart: SizeInt;
  UseZenithProblemJson: Boolean;
begin
  AResp.ContentType := 'application/problem+json; charset=utf-8';
  AResp.Contents.Clear;
  Error := 'server-error';
  Title := TitleInternalServerError;
  Detail := DetailInternalServerError;
  AResp.Code := StatusInternalServerError;
  UseZenithProblemJson := False;

  CallStack := '';

  if (E is EDeltaValidation) or (E is EValidation) then
  begin
    AResp.Code := StatusBadRequest;
    Error := 'validation-error';
    Title := TitleValidationError;
    Detail := E.Message;
  end
  else if E is EMissingRequiredField then
  begin
    AResp.Code := StatusBadRequest;
    Error := 'missing-required-field';
    Title := TitleMissingRequiredField;
    Detail := E.Message;
  end
  else if E is EUnauthorized then
  begin
    AResp.Code := StatusUnauthorized;
    Error := 'unauthorized';
    Title := TitleUnauthorized;
    if not E.Message.IsEmpty then
      Detail := E.Message
    else
      Detail := DetailUnauthorized;
  end
  else if E is EForbidden then
  begin
    AResp.Code := StatusForbidden;
    Error := 'forbidden';
    Title := TitleForbidden;
    if not E.Message.IsEmpty then
      Detail := E.Message
    else
      Detail := DetailForbidden;
  end
  else if (E is EResourceNotFound) or (E is ENotFound) then
  begin
    AResp.Code := StatusNotFound;
    Error := 'not-found';
    Title := TitleNotFound;
    if not E.Message.IsEmpty then
      Detail := E.Message
    else
      Detail := DetailNotFound;
  end
  else if E is ETooManyRequests then
  begin
    AResp.Code := StatusTooManyRequests;
    Error := 'too-many-requests';
    Title := TitleTooManyRequests;
    if not E.Message.IsEmpty then
      Detail := E.Message
    else
      Detail := DetailTooManyRequests;
  end
  else if E is EConflict then
  begin
    AResp.Code := StatusConflict;
    Error := 'conflict';
    Title := TitleConflict;
    if not E.Message.IsEmpty then
      Detail := E.Message
    else
      Detail := DetailConflict;
  end
  else if E is EBadRequest then
  begin
    AResp.Code := StatusBadRequest;
    Error := 'bad-request';
    Title := TitleBadRequest;
    Detail := E.Message;
  end
  else if E is EUnprocessableEntity then
  begin
    AResp.Code := StatusUnprocessableEntity;
    Error := 'unprocessable-entity';
    Title := TitleUnprocessableEntity;
    Detail := E.Message;
  end
  else if E is EUnsupportedMediaType then
  begin
    AResp.Code := StatusUnsupportedMediaType;
    Error := 'unsupported-media-type';
    Title := 'Unsupported Media Type';
    Detail := E.Message;
  end
  else if E is EServerError then
  begin
    AResp.Code := StatusInternalServerError;

    if GetEnvBool('ZENITH_ENABLE_DEBUG_INFO', False) then
    begin
      if Assigned(BackTraceStrFunc) then
        CallStack := CallStack + BackTraceStrFunc(ExceptAddr) + sLineBreak
      else
        CallStack := CallStack + HexStr(PtrUInt(ExceptAddr), SizeOf(PtrUInt) * 2) + sLineBreak;

      if ExceptFrameCount > 0 then
      begin
        for I := 0 to ExceptFrameCount - 1 do
        begin
          if Assigned(BackTraceStrFunc) then
            CallStack := CallStack + BackTraceStrFunc(ExceptFrames[I]) + sLineBreak
          else
            CallStack := CallStack + HexStr(PtrUInt(ExceptFrames[I]), SizeOf(PtrUInt) * 2) + sLineBreak;
        end;
      end;

      Detail := E.Message + sLineBreak + '--- Call Stack ---' + sLineBreak + CallStack;
      ZenithLogger.Error(E.ClassName + sLineBreak + Detail);
    end;
  end
  else if E is HTTPException then
  begin
    AResp.Code := StatusBadRequest;
    Error := 'bad-request';
    Title := TitleBadRequest;
    Detail := E.Message;
  end
  else if E is EZenithException then
  begin
    AResp.Code := EZenithException(E).StatusCode;
    AResp.ContentType := 'application/problem+json; charset=utf-8';
    AResp.Content := EZenithException(E).ToProblemJson;
    UseZenithProblemJson := True;
  end;

  if not UseZenithProblemJson then
    AResp.Content := TJsonError.ToJson(Error, Title, AResp.Code, Detail);

  RequestPath := AReq.URL;
  QueryStart := Pos('?', RequestPath);
  if QueryStart > 0 then
  begin
    Delete(RequestPath, QueryStart, MaxInt);
  end;

  LogLine := Format(
    'HTTP %d %s %s from %s',
    [AResp.Code, AReq.Method, RequestPath, AReq.RemoteAddress]
  );
  { Erros 5xx: registrar classe e mensagem no servidor (nunca no corpo da
    resposta, que permanece genérico fora do modo de depuração). }
  if AResp.Code >= 500 then
    LogLine := LogLine + ' - ' + E.ClassName + ': ' + E.Message;

  if ZenithLogger <> nil then
  begin
    try
      ZenithLogger.Error(LogLine);
    except
      { Logging failure must not prevent sending the problem response. }
    end;
  end;
  AResp.SendContent;
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
