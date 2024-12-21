unit Todo.Model;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DeltaModel;

type
  TTodo = class(TDeltaModel)
  published
    id: Integer;
    description: string;
  end;

implementation

end.

