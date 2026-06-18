{$FORM TDialog1Form, Dialog1.sfm}
uses
  Classes, Graphics, Controls, Forms, Dialogs, StdCtrls;

// ============================================================
// CP-036 Pressure Devices by Comparison
// Test Point Wizard v12 — Dialog 1: UUT Parameters
// Author: B. Wood
//
// Collects and validates UUT parameters. Writes attributes
// back to equipment record on Continue. Tech can override
// any auto-populated value.
//
// Fields auto-populated from equipment record:
//   ATTRIBUTE1  = Capacity (Maximum Value)
//   ATTRIBUTE2  = Resolution
//   UNIT_MEASURE = Units
//
// Minimum value moved to Dialog 2 to avoid cross-unit
// variable scoping limitations in Project Designer.
// ============================================================

procedure edtMaxChange(Sender: TObject);
begin
  if Trim(edtMax.Text) = '' then
    edtMax.Color := clYellow
  else
    edtMax.Color := clWhite;
end;

procedure edtUnitsChange(Sender: TObject);
begin
  if Trim(edtUnits.Text) = '' then
    edtUnits.Color := clYellow
  else
    edtUnits.Color := clWhite;
end;

procedure edtResolutionChange(Sender: TObject);
begin
  if Trim(edtResolution.Text) = '' then
    edtResolution.Color := clYellow
  else
    edtResolution.Color := clWhite;
end;

procedure Form2Create(Sender: TObject);
var
  GageID     : string;
  Capacity   : string;
  Units      : string;
  Resolution : string;
begin
  GageID := LocatingEquipmentID;
  edtGageID.Text := GageID;

  if GageID = '' then
  begin
    ShowMessage(
      'Could not determine the current equipment record.' + #13 +
      'Please close and relaunch the wizard from an equipment record.'
    );
    Exit;
  end;

  Capacity := LookupEquipmentFieldText('ATTRIBUTE1');
  edtMax.Text := Capacity;
  if Capacity = '' then
    edtMax.Color := clYellow
  else
    edtMax.Color := clWhite;

  Units := LookupEquipmentFieldText('UNIT_MEASURE');
  edtUnits.Text := Units;
  if Units = '' then
    edtUnits.Color := clYellow
  else
    edtUnits.Color := clWhite;

  Resolution := LookupEquipmentFieldText('ATTRIBUTE2');
  edtResolution.Text := Resolution;
  if Resolution = '' then
    edtResolution.Color := clYellow
  else
    edtResolution.Color := clWhite;
end;

procedure btnContinueClick(Sender: TObject);
var
  MaxVal  : Double;
  Missing : string;
begin

  Missing := '';

  if Trim(edtMax.Text) = '' then
  begin
    Missing := Missing + '  - Maximum Value' + #13;
    edtMax.Color := clYellow;
  end
  else
    edtMax.Color := clWhite;

  if Trim(edtUnits.Text) = '' then
  begin
    Missing := Missing + '  - Unit of Measure' + #13;
    edtUnits.Color := clYellow;
  end
  else
    edtUnits.Color := clWhite;

  if Trim(edtResolution.Text) = '' then
  begin
    Missing := Missing + '  - Resolution' + #13;
    edtResolution.Color := clYellow;
  end
  else
    edtResolution.Color := clWhite;

  if Missing <> '' then
  begin
    ShowMessage(
      'The following required fields must be completed before ' +
      'continuing:' + #13 + #13 +
      Missing
    );
    Exit;
  end;

  MaxVal := StrToFloat(edtMax.Text);

  if MaxVal <= 0 then
  begin
    ShowMessage('Maximum value must be greater than zero.');
    edtMax.Color := clYellow;
    Exit;
  end;

  // Write validated values back to equipment record
  // Dialog 2 re-reads these directly from the record
  SetEquipmentFieldText('ATTRIBUTE1', edtMax.Text);
  SetEquipmentFieldText('ATTRIBUTE2', edtResolution.Text);
  SetEquipmentFieldText('UNIT_MEASURE', edtUnits.Text);

  Close;
end;

begin
end.
