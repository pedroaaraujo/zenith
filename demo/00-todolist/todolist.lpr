program todolist;

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  Classes,
  Sysutils,
  SQLite3Conn,
  fphttpapp,
  Zenith.App, Todo.Model, Todo.Route;

begin
  InitializeTodoStore;
  { As rotas CRUD capturam o pool: registrar somente após criá-lo. }
  TTodoRouter.Register;
  ZenithApp
    .SetTitle('ToDo List')
    .Run;
end.
