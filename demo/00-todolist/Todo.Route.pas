unit Todo.Route;

{$mode Delphi}{$H+}

interface

uses
  Classes, SysUtils,
  Zenith.App, Zenith.Crud,
  Todo.Model, DeltaModel.ORM.Pool;

type
  TTodoRouter = class
  public
    class procedure Register;
  end;

implementation

class procedure TTodoRouter.Register;
begin
  TZenithCrud<TTodo>.Register('/todo', 'ToDo', TodoPool);
end;

initialization
  TTodoRouter.Register;

end.
