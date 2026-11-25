unit Todo.Model;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DeltaModel, DeltaModel.Fields, DeltaValidator,
  DeltaModel.ORM.Interfaces, DeltaModel.ORM.Pool;

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
  Zenith.Env, DeltaModel.ORM.Registry, DeltaModel.ORM.Dialects,
  DeltaModel.ORM.Driver.SQLDB, DeltaModel.ORM.Schema;

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
  Conn: IDeltaConnection;
  Schema: TDeltaORMSchema;
begin
  if Assigned(TodoPool) then
    Exit;

  DatabasePath := GetEnvVariable('ZENITH_TODO_DATABASE',
    ExtractFilePath(ParamStr(0)) + 'todo.sqlite');
  DatabaseURL := GetEnvVariable('ZENITH_TODO_DATABASE_URL',
    'sqlite://' + ExpandFileName(DatabasePath));

  Conn := TDeltaORM.Connect(DatabaseURL);
  try
    Schema := TDeltaORMSchema.Create(Conn);
    try
      Schema.RegisterModel(TTodo);
      Schema.PrepareDB(True);
    finally
      Schema.Free;
    end;
  finally
    Conn.Disconnect;
    Conn := nil;
  end;

  TodoPool := TDeltaConnectionPool.Create(DatabaseURL, 1, 10);
end;

finalization
  TodoPool.Free;

end.
