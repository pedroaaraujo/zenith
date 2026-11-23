unit Telemetry.Model;

{
  Zenith WebSocket Demo - Agnostic Domain Models
  Demonstrates TChatMessage and TSensorTelemetry serialized as CBOR / BSON over WebSocket.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DeltaModel, DeltaModel.Fields;

type
  { TChatMessage: Realtime chat payload }
  TChatMessage = class(TDeltaModel)
  private
    FRoomId: TDFStringNull;
    FSender: TDFStringNull;
    FBody: TDFStringNull;
    FSequence: TDFInt64Null;
  published
    property room_id: TDFStringNull read FRoomId write FRoomId;
    property sender: TDFStringNull read FSender write FSender;
    property body: TDFStringNull read FBody write FBody;
    property sequence: TDFInt64Null read FSequence write FSequence;
  end;

  { TSensorTelemetry: IoT telemetry payload for binary CBOR/BSON streaming }
  TSensorTelemetry = class(TDeltaModel)
  private
    FDeviceId: TDFStringNull;
    FTemperature: TDFDoubleNull;
    FHumidity: TDFDoubleNull;
    FBatteryPct: TDFIntNull;
    FOnline: TDFBooleanNull;
  published
    property device_id: TDFStringNull read FDeviceId write FDeviceId;
    property temperature: TDFDoubleNull read FTemperature write FTemperature;
    property humidity: TDFDoubleNull read FHumidity write FHumidity;
    property battery_pct: TDFIntNull read FBatteryPct write FBatteryPct;
    property online: TDFBooleanNull read FOnline write FOnline;
  end;

implementation

end.
