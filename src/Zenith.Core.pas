unit Zenith.Core;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, custhttpapp, HTTPDefs, DeltaValidator, fpjson,

  Zenith.Exceptions, Zenith.Log, Zenith.Consts, Zenith.Types, Zenith.Env;

procedure ConfigureApplication(App: TCustomHTTPApplication);

implementation

procedure HandleExcept(E: Exception; AReq: TRequest; AResp: TResponse);
var
  Error, Title, Detail, LogLine: string;
  RequestPath: string;
  CallStack: string;
  I: Integer;
  QueryStart: SizeInt;
begin
  AResp.ContentType := 'application/problem+json';
  AResp.Contents.Clear;
  Error := 'server-error';
  Title := 'Não foi possível executar a operação.';
  Detail := 'Ocorreu um erro interno.';
  AResp.Code := StatusInternalServerError;

  CallStack := '';

  if E is EDeltaValidation then
  begin
    AResp.Code := StatusBadRequest;
    Error := 'validation-error';
    Title := 'Falha na validação dos dados.';
    Detail := E.Message;
  end
  else if E is EValidation then
  begin
    AResp.Code := StatusBadRequest;
    Error := 'validation-error';
    Title := 'Falha na validação dos dados.';
    Detail := E.Message;
  end
  else if E is EMissingRequiredField then
  begin
    AResp.Code := StatusBadRequest;
    Error := 'missing-required-field';
    Title := 'Campo obrigatório ausente.';
    Detail := E.Message;
  end
  else if E is EUnauthorized then
  begin
    AResp.Code := StatusUnauthorized;
    Error := 'unauthorized';
    Title := 'Não autorizado.';
    Detail := 'As credenciais informadas são inválidas.';
  end
  else if E is EForbidden then
  begin
    AResp.Code := StatusForbidden;
    Error := 'forbidden';
    Title := 'Acesso não permitido.';
    Detail := E.Message;
  end
  else if (E is EResourceNotFound) or (E is ENotFound) then
  begin
    AResp.Code := StatusNotFound;
    Error := 'not-found';
    Title := 'Recurso não encontrado.';
    Detail := E.Message;
  end
  else if E is ETooManyRequests then
  begin
    AResp.Code := StatusTooManyRequests;
    Error := 'too-many-requests';
    Title := 'Limite de requisições atingido.';
    Detail := E.Message;
  end
  else if E is EConflict then
  begin
    AResp.Code := StatusConflict;
    Error := 'conflict';
    Title := 'Conflito nos dados informados.';
    Detail := E.Message;
  end
  else if E is EBadRequest then
  begin
    AResp.Code := StatusBadRequest;
    Error := 'bad-request';
    Title := 'Requisição inválida.';
    Detail := E.Message;
  end
  else if E is EServerError then
  begin
    AResp.Code := StatusInternalServerError;

    if GetEnvVariable('ZENITH_ENABLE_DEBUG_INFO', 'N').Equals('S') then
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
  end;

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
