unit Todo.Model;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DeltaModel, DeltaModel.Fields, DeltaValidator,
  DeltaModel.ORM.Connection, DeltaModel.ORM.Pool;

type
  TTodoInsert = class(TDeltaModel)
  private
    FDescription: TDFStringRequired;
  published
    property description: TDFStringRequired read FDescription write FDescription;
  public
    class procedure ConfigureSchema(ASchema: TDeltaModelSchema); override;
  end;

  TTodo = class(TTodoInsert)
  private
    FDone: TDFBooleanRequired;
    FId: TDFIntRequired;
  published
    property done: TDFBooleanRequired read FDone write FDone;
    property id: TDFIntRequired read FId write FId;
  public
    procedure AfterConstruction; override;
    class procedure ConfigureSchema(ASchema: TDeltaModelSchema); override;
  end;

procedure InitializeTodoStore;

var
  TodoPool: TDeltaConnectionPool;

implementation

uses
  Zenith.Env, DeltaModel.ORM.Schema;

class procedure TTodoInsert.ConfigureSchema(ASchema: TDeltaModelSchema);
begin
  inherited ConfigureSchema(ASchema);
  ASchema.Field('description').MinLength(2);
end;

procedure TTodo.AfterConstruction;
begin
  inherited AfterConstruction;
  TableName := 'todo';
  id.DBOptions := [dboPrimaryKey, dboAutoInc];
end;

class procedure TTodo.ConfigureSchema(ASchema: TDeltaModelSchema);
begin
  inherited ConfigureSchema(ASchema);
  ASchema.Table('todo');
  ASchema.Field('id').AsPK.AutoInc;
  ASchema.Field('description').MinLength(2);
end;

procedure InitializeTodoStore;
var
  DatabaseURL, DatabasePath: string;
  Engine: TDeltaORMEngine;
  Schema: TDeltaORMSchema;
begin
  if Assigned(TodoPool) then
    Exit;

  DatabasePath := GetEnvVariable('ZENITH_TODO_DATABASE',
    ExtractFilePath(ParamStr(0)) + 'todo.sqlite');
  DatabaseURL := GetEnvVariable('ZENITH_TODO_DATABASE_URL',
    'sqlite://' + ExpandFileName(DatabasePath));

  Engine := TDeltaORMEngine.Create(DatabaseURL);
  try
    Engine.Connection.Open;
    Schema := TDeltaORMSchema.Create(Engine);
    try
      Schema.RegisterModel(TTodo);
      Schema.PrepareDB(True);
    finally
      Schema.Free;
    end;
  finally
    Engine.Free;
  end;

  TodoPool := TDeltaConnectionPool.Create(DatabaseURL, 1, 10);
end;

finalization
  TodoPool.Free;

end.
