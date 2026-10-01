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
  ZenithApp
    .SetTitle('ToDo List')
    .Run;
end.
