{
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2009 by the Free Pascal development team
    Zenith compatibility edition with expanded httproute
}
{$mode objfpc}
{$H+}

unit custhttpapp;

Interface

uses
  Classes, SysUtils, httpdefs, custweb, ssockets,  fphttpserver, sslbase;

Type
  TCustomHTTPApplication = Class;
  TFPHTTPServerHandler = Class;

  { TEmbeddedHttpServer }

  TEmbeddedHttpServer = Class(TFPCustomHttpServer)
  Private
    FWebHandler: TFPHTTPServerHandler;
  protected
    Procedure InitRequest(ARequest : TFPHTTPConnectionRequest); override;
    Procedure InitResponse(AResponse : TFPHTTPConnectionResponse); override;
    Property WebHandler : TFPHTTPServerHandler Read FWebHandler;
    Property Active;
    Property OnAcceptIdle;
    Property AcceptIdleTimeout;
  end;

  { TFPHTTPServerHandler }

  TFPHTTPServerHandler = class(TWebHandler)
  Private
    FOnRequestError: TRequestErrorHandler;
    FServer: TEmbeddedHTTPServer;
    function GetAllowConnect: TConnectQuery;
    function GetAddress: string;
    function GetHostName: String;
    function GetIdle: TNotifyEvent;
    function GetIDleTimeOut: Cardinal;
    function GetPort: Word;
    function GetQueueSize: Word;
    function GetThreaded: Boolean;
    function GetUseSSL: Boolean;
    procedure SetHostName(AValue: String);
    procedure SetIdle(AValue: TNotifyEvent);
    procedure SetIDleTimeOut(AValue: Cardinal);
    procedure SetOnAllowConnect(const AValue: TConnectQuery);
    procedure SetAddress(const AValue: string);
    procedure SetPort(const AValue: Word);
    procedure SetQueueSize(const AValue: Word);
    procedure SetThreaded(const AValue: Boolean);
    function GetLookupHostNames : Boolean;
    Procedure SetLookupHostnames(Avalue : Boolean);
    procedure SetUseSSL(AValue: Boolean);
  protected
    procedure HTTPHandleRequest(Sender: TObject; var ARequest: TFPHTTPConnectionRequest; var AResponse: TFPHTTPConnectionResponse); virtual;
    procedure HandleRequestError(Sender: TObject; E: Exception); virtual;
    Procedure InitRequest(ARequest : TRequest); override;
    Procedure InitResponse(AResponse : TResponse); override;
    function WaitForRequest(out ARequest : TRequest; out AResponse : TResponse) : boolean; override;
    Function CreateServer : TEmbeddedHttpServer; virtual;
  Public
    Procedure Run; override;
    Procedure Terminate; override;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    Property Address : string Read GetAddress Write SetAddress;
    Property Port : Word Read GetPort Write SetPort Default 80;
    Property QueueSize : Word Read GetQueueSize Write SetQueueSize Default 5;
    Property OnAllowConnect : TConnectQuery Read GetAllowConnect Write SetOnAllowConnect;
    property Threaded : Boolean read GetThreaded Write SetThreaded;
    Property OnRequestError : TRequestErrorHandler Read FOnRequestError Write FOnRequestError;
    Property LookupHostNames : Boolean Read GetLookupHostNames Write SetLookupHostNames;
    Property OnAcceptIdle : TNotifyEvent Read GetIdle Write SetIdle;
    Property AcceptIdleTimeout : Cardinal Read GetIDleTimeOut Write SetIDleTimeOut;
    Property UseSSL : Boolean Read GetUseSSL Write SetUseSSL;
    Property HostName : String Read GetHostName Write SetHostName;
    Property HTTPServer : TEmbeddedHttpServer Read FServer;
  end;

  { TCustomHTTPApplication }

  TCustomHTTPApplication = Class(TCustomWebApplication)
  private
    procedure FakeConnect;
    function GetCertificateData: TCertificateData;
    function GetHostName: String;
    function GetIdle: TNotifyEvent;
    function GetIDleTimeOut: Cardinal;
    function GetLookupHostNames : Boolean;
    function GetUseSSL: Boolean;
    procedure SetHostName(AValue: String);
    procedure SetIdle(AValue: TNotifyEvent);
    procedure SetIDleTimeOut(AValue: Cardinal);
    Procedure SetLookupHostnames(Avalue : Boolean);
    function GetAllowConnect: TConnectQuery;
    function GetAddress: String;
    function GetPort: Word;
    function GetQueueSize: Word;
    function GetThreaded: Boolean;
    procedure SetOnAllowConnect(const AValue: TConnectQuery);
    procedure SetAddress(const AValue: string);
    procedure SetPort(const AValue: Word);
    procedure SetQueueSize(const AValue: Word);
    procedure SetThreaded(const AValue: Boolean);
    procedure SetUseSSL(AValue: Boolean);
  protected
    function InitializeWebHandler: TWebHandler; override;
  Public
    procedure Terminate; override;
    Function HTTPHandler : TFPHTTPServerHandler;
    Property Address : string Read GetAddress Write SetAddress;
    Property Port : Word Read GetPort Write SetPort Default 80;
    Property QueueSize : Word Read GetQueueSize Write SetQueueSize Default 5;
    Property OnAllowConnect : TConnectQuery Read GetAllowConnect Write SetOnAllowConnect;
    property Threaded : Boolean read GetThreaded Write SetThreaded;
    Property LookupHostNames : Boolean Read GetLookupHostNames Write SetLookupHostNames;
    Property OnAcceptIdle : TNotifyEvent Read GetIdle Write SetIdle;
    Property AcceptIdleTimeout : Cardinal Read GetIDleTimeOut Write SetIDleTimeOut;
    Property UseSSL : Boolean Read GetUseSSL Write SetUseSSL;
    Property HostName : String Read GetHostName Write SetHostName;
    Property CertificateData : TCertificateData Read GetCertificateData;
  end;

Implementation

{ TEmbeddedHttpServer }

procedure TEmbeddedHttpServer.InitRequest(ARequest: TFPHTTPConnectionRequest);
begin
  WebHandler.InitRequest(ARequest);
end;

procedure TEmbeddedHttpServer.InitResponse(AResponse: TFPHTTPConnectionResponse);
begin
  WebHandler.InitResponse(AResponse);
end;

{ TCustomHTTPApplication }

function TCustomHTTPApplication.GetIdle: TNotifyEvent;
begin
  Result:=HTTPHandler.OnAcceptIdle;
end;

function TCustomHTTPApplication.GetIDleTimeOut: Cardinal;
begin
  Result:=HTTPHandler.AcceptIdleTimeout;
end;

function TCustomHTTPApplication.GetLookupHostNames : Boolean;
begin
  Result:=HTTPHandler.LookupHostNames;
end;

function TCustomHTTPApplication.GetUseSSL: Boolean;
begin
  Result:=HTTPHandler.UseSSL;
end;

procedure TCustomHTTPApplication.SetHostName(AValue: String);
begin
  HTTPHandler.HostName:=aValue;
end;

procedure TCustomHTTPApplication.SetIdle(AValue: TNotifyEvent);
begin
  HTTPHandler.OnAcceptIdle:=AValue;
end;

procedure TCustomHTTPApplication.SetIDleTimeOut(AValue: Cardinal);
begin
  HTTPHandler.AcceptIdleTimeOut:=AValue;
end;

procedure TCustomHTTPApplication.SetLookupHostnames(Avalue: Boolean);
begin
  HTTPHandler.LookupHostNames:=AValue;
end;

function TCustomHTTPApplication.GetAllowConnect: TConnectQuery;
begin
  Result:=HTTPHandler.OnAllowConnect;
end;

function TCustomHTTPApplication.GetAddress: String;
begin
  Result:=HTTPHandler.Address;
end;

function TCustomHTTPApplication.GetPort: Word;
begin
  Result:=HTTPHandler.Port;
end;

function TCustomHTTPApplication.GetQueueSize: Word;
begin
  Result:=HTTPHandler.QueueSize;
end;

function TCustomHTTPApplication.GetThreaded: Boolean;
begin
  Result:=HTTPHandler.Threaded;
end;

procedure TCustomHTTPApplication.SetOnAllowConnect(const AValue: TConnectQuery);
begin
  HTTPHandler.OnAllowConnect:=AValue;
end;

procedure TCustomHTTPApplication.SetAddress(const AValue: string);
begin
  HTTPHandler.Address:=Avalue;
end;

procedure TCustomHTTPApplication.SetPort(const AValue: Word);
begin
  HTTPHandler.Port:=Avalue;
end;

procedure TCustomHTTPApplication.SetQueueSize(const AValue: Word);
begin
  HTTPHandler.QueueSize:=Avalue;
end;

procedure TCustomHTTPApplication.SetThreaded(const AValue: Boolean);
begin
  HTTPHandler.Threaded:=Avalue;
end;

procedure TCustomHTTPApplication.SetUseSSL(AValue: Boolean);
begin
  HTTPHandler.UseSSL:=aValue;
end;

function TCustomHTTPApplication.InitializeWebHandler: TWebHandler;
begin
  Result:=TFPHTTPServerHandler.Create(Self);
end;

function TCustomHTTPApplication.HTTPHandler: TFPHTTPServerHandler;
begin
  Result:=Webhandler as TFPHTTPServerHandler;
end;

procedure TCustomHTTPApplication.FakeConnect;
begin
  try
    TInetSocket.Create('localhost',Self.Port).Free;
  except
  end;
end;

function TCustomHTTPApplication.GetCertificateData: TCertificateData;
begin
  Result:=HTTPHandler.HTTPServer.CertificateData;
end;

function TCustomHTTPApplication.GetHostName: String;
begin
  Result:=HTTPHandler.HostName;
end;

procedure TCustomHTTPApplication.Terminate;
begin
  inherited Terminate;
  if Threaded And (AcceptIdleTimeout=0) then
    FakeConnect;
end;

{ TFPHTTPServerHandler }

procedure TFPHTTPServerHandler.HandleRequestError(Sender: TObject; E: Exception);
begin
  Try
    If Assigned(FOnRequestError) then
      FOnRequestError(Sender,E)
    else
      Log(etError,Format('Error (%s) handling request : %s',[E.ClassName,E.Message]));
  except
  end;
end;

procedure TFPHTTPServerHandler.HTTPHandleRequest(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
begin
  try
    DoHandleRequest(ARequest,AResponse);
  finally  
    ARequest:=Nil;
    AResponse:=Nil;
  end;    
  if Assigned(OnIdle) then
    OnIdle(Self);
end;

function TFPHTTPServerHandler.GetLookupHostNames : Boolean;
begin
  Result:=FServer.LookupHostNames;
end;

procedure TFPHTTPServerHandler.SetLookupHostnames(Avalue: Boolean);
begin
  FServer.LookupHostNames:=AValue;
end;

procedure TFPHTTPServerHandler.SetUseSSL(AValue: Boolean);
begin
  FServer.UseSSL:=aValue;
end;

function TFPHTTPServerHandler.GetAllowConnect: TConnectQuery;
begin
  Result:=FServer.OnAllowConnect;
end;

function TFPHTTPServerHandler.GetAddress: string;
begin
  Result:=FServer.Address;
end;

function TFPHTTPServerHandler.GetHostName: String;
begin
  Result:=FServer.CertificateData.HostName;
end;

function TFPHTTPServerHandler.GetIdle: TNotifyEvent;
begin
  Result:=FServer.OnAcceptIdle;
end;

function TFPHTTPServerHandler.GetIDleTimeOut: Cardinal;
begin
  Result:=FServer.AcceptIdleTimeout;
end;

function TFPHTTPServerHandler.GetPort: Word;
begin
  Result:=FServer.Port;
end;

function TFPHTTPServerHandler.GetQueueSize: Word;
begin
  Result:=FServer.QueueSize;
end;

function TFPHTTPServerHandler.GetThreaded: Boolean;
begin
  Result:=FServer.Threaded;
end;

function TFPHTTPServerHandler.GetUseSSL: Boolean;
begin
  Result:=FServer.UseSSL;
end;

procedure TFPHTTPServerHandler.SetHostName(AValue: String);
begin
  FServer.CertificateData.HostName:=aValue;
end;

procedure TFPHTTPServerHandler.SetIdle(AValue: TNotifyEvent);
begin
  FServer.OnAcceptIdle:=AValue;
end;

procedure TFPHTTPServerHandler.SetIDleTimeOut(AValue: Cardinal);
begin
  FServer.AcceptIdleTimeOut:=AValue;
end;

procedure TFPHTTPServerHandler.SetOnAllowConnect(const AValue: TConnectQuery);
begin
  FServer.OnAllowConnect:=Avalue;
end;

procedure TFPHTTPServerHandler.SetAddress(const AValue: string);
begin
  FServer.Address:=AValue;
end;

procedure TFPHTTPServerHandler.SetPort(const AValue: Word);
begin
  FServer.Port:=Avalue;
end;

procedure TFPHTTPServerHandler.SetQueueSize(const AValue: Word);
begin
  FServer.QueueSize:=Avalue;
end;

procedure TFPHTTPServerHandler.SetThreaded(const AValue: Boolean);
begin
  FServer.Threaded:=AValue;
end;

procedure TFPHTTPServerHandler.InitRequest(ARequest: TRequest);
begin
  inherited InitRequest(ARequest);
end;

procedure TFPHTTPServerHandler.InitResponse(AResponse: TResponse);
begin
  inherited InitResponse(AResponse);
end;

function TFPHTTPServerHandler.WaitForRequest(out ARequest : TRequest;
  out AResponse : TResponse): boolean;
begin
  Result:=False;
  ARequest:=Nil;
  AResponse:=Nil;
end;

function TFPHTTPServerHandler.CreateServer: TEmbeddedHttpServer;
begin
  Result:=TEmbeddedHttpServer.Create(Self);
end;

procedure TFPHTTPServerHandler.Run;
begin
  Fserver.Active:=True;
end;

procedure TFPHTTPServerHandler.Terminate;
begin
  Inherited;
  if Assigned(FServer) then
    Fserver.Active:=False;
end;

constructor TFPHTTPServerHandler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FServer:=CreateServer;
  FServer.FWebHandler:=Self;
  FServer.OnRequest:=@HTTPHandleRequest;
  Fserver.OnRequestError:=@HandleRequestError;
end;

destructor TFPHTTPServerHandler.Destroy;
begin
  if Assigned(FServer) then
    begin
    FServer.Active:=False;
    FreeAndNil(FServer);
    end;
  inherited Destroy;
end;

end.
