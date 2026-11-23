{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 1999-2000 by the Free Pascal development team
    Zenith compatibility edition with expanded httproute
}
{$mode objfpc}
{$H+}
unit fphttpapp;

interface

uses SysUtils,Classes, custhttpapp;

Type
  THTTPApplication = Class(TCustomHTTPApplication)
  end;

Var
  Application : THTTPApplication;
  ShowCleanUpErrors : Boolean = False;
  
Implementation

uses CustApp;

Procedure InitHTTP;
begin
  Application:=THTTPApplication.Create(Nil);
  if not assigned(CustomApplication) then
    CustomApplication := Application;
end;

Procedure DoneHTTP;
begin
  if CustomApplication=Application then
    CustomApplication := nil;
  try  
    FreeAndNil(Application);
  except
    if ShowCleanUpErrors then
      Raise;
  end;
end;

Initialization
  InitHTTP;
  
Finalization
  DoneHTTP;
  
end.
