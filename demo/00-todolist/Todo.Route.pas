unit Todo.Route;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, Zenith.App, Zenith.Consts, Todo.Model, DeltaModel;

type

  { TTodoRouter }

  TTodoRouter = class
  public
    class procedure Register;
  end;

implementation

{ TTodoRouter }

procedure GetTodo(ARequest: TRequest; AResponse: TResponse);
var
  Obj: TTodoResponse;
begin
  Obj := TTodoResponse.Create;
  try
    Obj.id := ARequest.RouteParams['id'].ToInteger;
    Obj.description := 'Run Zenith Demo';
    Obj.done := True;

    AResponse.Code := StatusOK;
    AResponse.Content := Obj.ToJson;
  finally
    Obj.Free;
  end;
end;

procedure GetAllTodo(ARequest: TRequest; AResponse: TResponse);
var
  List: TDeltaModelList;
  Obj: TTodoResponse;
begin
  List := TDeltaModelList.Create;
  try
    List.SetDeltaModelClass(TTodoResponse);
    repeat
      Obj := TTodoResponse.Create;
      Obj.id := List.Records.Count + 1;
      Obj.description := 'ToDo Demo ' + Obj.id.ToString;
      Obj.done := False;
      List.Records.Add(Obj);
    until List.Records.Count = 20;

    AResponse.Code := StatusOK;
    AResponse.Content := List.ToJson;
  finally
    List.Free;
  end;
end;

class procedure TTodoRouter.Register;
begin
  Router
    .Get('/todo', @GetAllTodo)
    .AddTags('ToDo')
    .AddResponse(StatusOK, 'Get All ToDo''s', TTodoResponse.SwaggerSchema(True));

  Router
    .Get('/todo/:id', @GetTodo)
    .AddTags('ToDo')
    .AddPathParam('id', True)
    .AddResponse(StatusOK, 'Get ToDo by Id', TTodoResponse.SwaggerSchema());
end;

initialization
  TTodoRouter.Register;
end.

