program todolist;

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  Classes,
  Sysutils,
  fphttpapp,
  Zenith.App, Todo.Model;

begin
  ZenithApp
    .SetTitle('ToDo List')
    .Run;
end.

