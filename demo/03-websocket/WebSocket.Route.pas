unit WebSocket.Route;

{
  Zenith WebSocket Demo - Routes & Hub Handlers
  Exposes:
    - GET  /auth/cwt     : Issues a demo RFC 8392 CWT token (Base64URL)
    - GET  /ws/chat      : RFC 6455 Text & CBOR chat hub with permessage-deflate
    - GET  /ws/telemetry : CWT-authenticated binary CBOR/BSON telemetry stream
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, HTTPDefs,
  Zenith.App,
  Zenith.Security.CWT,
  Zenith.WebSocket,
  Telemetry.Model;

procedure RegisterWebSocketRoutes;

implementation

var
  ChatHub: TZWebSocketHub;
  TelemetryHub: TZWebSocketHub;

procedure IssueDemoCwtToken(ARequest: TRequest; AResponse: TResponse);
var
  Payload: TCWTPayload;
  NowUnix: Int64;
  TokenB64: string;
begin
  NowUnix := DateTimeToUnix(Now, False);
  Payload := TCWTPayload.Create;
  try
    Payload.iss := 'zenith-ws-demo';
    Payload.sub := 'demo-operator';
    Payload.aud := 'zenith-realtime';
    Payload.iat := NowUnix;
    Payload.exp := NowUnix + 3600;
    Payload.role := 'OPERATOR';
    TokenB64 := TCWT.GenerateTokenBase64Url(Payload);
  finally
    Payload.Free;
  end;

  AResponse.Code := 200;
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.Content := Format('{"token":"%s","type":"CWT"}', [TokenB64]);
end;

procedure RunChatSession(AConn: TZWebSocketConnection);
var
  Msg: TZWebSocketMessage;
  ChatModel: TChatMessage;
begin
  ChatHub.RegisterConnection(AConn);
  try
    AConn.SendText('{"event":"connected","id":"' + AConn.Id + '"}');
    while AConn.ReadMessage(Msg) do
    begin
      if Msg.MessageType = wsMsgText then
        ChatHub.BroadcastText(Msg.AsText, AConn)
      else
      begin
        ChatModel := TChatMessage.Create;
        try
          TZWebSocketConnection.DecodeBytesToModel(Msg.Payload, ChatModel, wsBinCbor);
          ChatHub.BroadcastModelCbor(ChatModel, AConn);
        finally
          ChatModel.Free;
        end;
      end;
    end;
  finally
    ChatHub.UnregisterConnection(AConn);
  end;
end;

procedure RunTelemetrySession(AConn: TZWebSocketConnection);
var
  Msg: TZWebSocketMessage;
  Sample: TSensorTelemetry;
  FormatKind: TZWebSocketBinaryFormat;
begin
  TelemetryHub.RegisterConnection(AConn);
  try
    if SameText(AConn.SubProtocol, 'telemetry.bson') then
      FormatKind := wsBinBson
    else
      FormatKind := wsBinCbor;

    while AConn.ReadMessage(Msg) do
    begin
      if Msg.MessageType = wsMsgBinary then
      begin
        Sample := TSensorTelemetry.Create;
        try
          TZWebSocketConnection.DecodeBytesToModel(Msg.Payload, Sample, FormatKind);
          if FormatKind = wsBinBson then
            TelemetryHub.BroadcastModelBson(Sample, AConn)
          else
            TelemetryHub.BroadcastModelCbor(Sample, AConn);
        finally
          Sample.Free;
        end;
      end;
    end;
  finally
    TelemetryHub.UnregisterConnection(AConn);
  end;
end;

procedure ChatWsEndpoint(ARequest: TRequest; AResponse: TResponse);
begin
  TZWebSocketUpgrade.Accept(
    ARequest,
    AResponse,
    @RunChatSession,
    'chat.v1, chat.cbor',
    True,  // Allow RFC 7692 permessage-deflate
    False  // Public chat endpoint
  );
end;

procedure TelemetryWsEndpoint(ARequest: TRequest; AResponse: TResponse);
begin
  TZWebSocketUpgrade.Accept(
    ARequest,
    AResponse,
    @RunTelemetrySession,
    'telemetry.cbor, telemetry.bson',
    True,  // Allow RFC 7692 permessage-deflate
    True   // Require valid RFC 8392 CWT token on handshake
  );
end;

procedure RegisterWebSocketRoutes;
begin
  Router.Get('/auth/cwt', @IssueDemoCwtToken);
  Router.Get('/ws/chat', @ChatWsEndpoint);
  Router.Get('/ws/telemetry', @TelemetryWsEndpoint);
end;

initialization
  ChatHub := TZWebSocketHub.Create;
  TelemetryHub := TZWebSocketHub.Create;

finalization
  FreeAndNil(TelemetryHub);
  FreeAndNil(ChatHub);

end.
