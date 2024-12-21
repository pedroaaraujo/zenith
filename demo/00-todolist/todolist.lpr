program todolist;

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  Classes,
  Sysutils,
  fphttpapp,
  Zenith.App, Todo.Model, Todo.Route;

begin
  ZenithApp
    .SetTitle('ToDo List')
    .Run;
end.

