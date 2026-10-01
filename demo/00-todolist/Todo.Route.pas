unit Todo.Route;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, Zenith.App, Zenith.Consts, Zenith.Exceptions,
  Todo.Model, DeltaModel, DeltaModel.ORM.Pool, DeltaModel.ORM.DML;

type
  TTodoRouter = class
  public
    class procedure Register;
  end;

implementation

function ParseTodoId(ARequest: TRequest): Integer;
begin
  if not TryStrToInt(ARequest.RouteParams['id'], Result) or (Result < 1) then
    raise EBadRequest.Create('ID de tarefa inválido.');
end;

procedure GetTodo(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
  Todo: TTodo;
begin
  Lease := TodoPool.Acquire;
  Todo := TTodo(Lease.Find(TTodo, ParseTodoId(ARequest)));
  try
    if Todo = nil then
      raise EResourceNotFound.Create('Tarefa não encontrada.');
    AResponse.Code := StatusOK;
    AResponse.Content := Todo.ToJson;
  finally
    Todo.Free;
  end;
end;

procedure GetAllTodo(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
  Query: TQuery;
  List: TDeltaModelList;
begin
  Lease := TodoPool.Acquire;
  Query := Lease.Query(TTodo);
  try
    List := Query.All;
    try
      AResponse.Code := StatusOK;
      AResponse.Content := List.ToJson;
    finally
      List.Free;
    end;
  finally
    Query.Free;
  end;
end;

procedure CreateTodo(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
  Todo: TTodo;
  Input: TTodoInsert;
begin
  Input := TTodoInsert.Create;
  try
    try
      Input.FromJson(ARequest.Content);
    except
      on E: Exception do
        raise EBadRequest.Create('O corpo deve conter um JSON válido.');
    end;
    Input.Validate;

    Lease := TodoPool.Acquire;
    Todo := TTodo.Create;
    try
      Todo.description.Value := Input.description.Value;
      Todo.done.Value := False;
      if not Lease.Save(Todo) then
        raise EServerError.Create('Não foi possível salvar a tarefa.');
      AResponse.Code := StatusCreated;
      AResponse.Content := Todo.ToJson;
    finally
      Todo.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure DeleteTodo(ARequest: TRequest; AResponse: TResponse);
var
  Lease: IDeltaPooledEngine;
begin
  Lease := TodoPool.Acquire;
  if not Lease.DeleteById(TTodo, ParseTodoId(ARequest)) then
    raise EResourceNotFound.Create('Tarefa não encontrada.');
  AResponse.Code := StatusNoContent;
end;

class procedure TTodoRouter.Register;
begin
  Router
    .Get('/todo', @GetAllTodo)
    .AddTags('ToDo')
    .AddResponse(StatusOK, 'Lista de tarefas', TTodo.SwaggerSchema(True));

  Router
    .Get('/todo/:id', @GetTodo)
    .AddTags('ToDo')
    .AddPathParam('id', True, 'integer', '1', 'ID da tarefa')
    .AddResponse(StatusOK, 'Tarefa encontrada', TTodo.SwaggerSchema())
    .AddResponse(StatusNotFound, 'Tarefa não encontrada');

  Router
    .Post('/todo', @CreateTodo)
    .AddTags('ToDo')
    .SetBodyContent(TTodoInsert.SwaggerSchema(), True)
    .AddResponse(StatusCreated, 'Tarefa criada', TTodo.SwaggerSchema())
    .AddResponse(StatusBadRequest, 'Dados inválidos');

  Router
    .Delete('/todo/:id', @DeleteTodo)
    .AddTags('ToDo')
    .AddPathParam('id', True, 'integer', '1', 'ID da tarefa')
    .AddResponse(StatusNoContent, 'Tarefa removida')
    .AddResponse(StatusNotFound, 'Tarefa não encontrada');
end;

initialization
  TTodoRouter.Register;

end.
