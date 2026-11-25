unit Bench.Model;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DeltaModel, DeltaModel.Fields;

type
  TBenchItem = class(TDeltaModel)
  private
    FId: TDFIntRequired;
    FName: TDFStringRequired;
    FPrice: TDFFloatRequired;
    FActive: TDFBooleanRequired;
  published
    property id: TDFIntRequired read FId write FId;
    property name: TDFStringRequired read FName write FName;
    property price: TDFFloatRequired read FPrice write FPrice;
    property active: TDFBooleanRequired read FActive write FActive;
  end;

  TBenchItemList = specialize TGDeltaModelList<TBenchItem>;

  TBenchMessage = class(TDeltaModel)
  private
    FMessage: TDFStringRequired;
  published
    property message: TDFStringRequired read FMessage write FMessage;
  end;

implementation

end.
