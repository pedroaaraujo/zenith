unit Todo.Model;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DeltaModel, DeltaValidator;

type

  { TTodoInsert }

  TTodoInsert = class(TDeltaModel)
  private
    Fdescription: string;
  published
    property description: string read Fdescription write Fdescription;
  public
    procedure Validate; virtual;
  end;

  TTodo = class(TTodoInsert)
  private
    Fdone: Boolean;
  published
    property done: Boolean read Fdone write Fdone;
  public
    procedure Validate; override;
  end;

  { TTodoResponse }

  TTodoResponse = class(TTodo)
  private
    Fid: Integer;
  published
    property id: Integer read Fid write Fid;
  end;

implementation

{ TTodoInsert }

procedure TTodoInsert.Validate;
begin
  Validator.Clear;

  Validator
    .AddField('Todo.Description', Self.description)
    .AddValidator(TValidatorItemMinLength.Create(2));
end;

procedure TTodo.Validate;
begin
  inherited Validate;
end;

end.

