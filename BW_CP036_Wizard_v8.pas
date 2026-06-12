{$FORM TDialog1Form, Dialog1.sfm}
uses
  Classes, Graphics, Controls, Forms, Dialogs, StdCtrls;

// ============================================================
// CP-036 Pressure Devices by Comparison
// Test Point Wizard — v8
// Author: B. Wood
//
// Changes from v7:
//   - Removed Reload Defaults button and btnLoadClick procedure
//   - Cleaner form — open, fill in blanks, generate
// ============================================================

// ============================================================
// PROCEDURE: edtFullScaleChange
// Clears yellow when tech types, restores yellow if blank
// ============================================================
procedure edtFullScaleChange(Sender: TObject);
begin
  if Trim(edtFullScale.Text) = '' then
    edtFullScale.Color := clYellow
  else
    edtFullScale.Color := clWhite;
end;

// ============================================================
// PROCEDURE: edtUnitsChange
// Clears yellow when tech types, restores yellow if blank
// ============================================================
procedure edtUnitsChange(Sender: TObject);
begin
  if Trim(edtUnits.Text) = '' then
    edtUnits.Color := clYellow
  else
    edtUnits.Color := clWhite;
end;

// ============================================================
// PROCEDURE: Form2Create
// Auto-populates fields on open and highlights blank fields
// ============================================================
procedure Form2Create(Sender: TObject);
var
  GageID   : string;
  Capacity : string;
  Units    : string;
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

  // Load Full Scale and highlight if blank
  Capacity := LookupEquipmentFieldText('ATTRIBUTE1');
  edtFullScale.Text := Capacity;
  if Capacity = '' then
    edtFullScale.Color := clYellow
  else
    edtFullScale.Color := clWhite;

  // Load Units and highlight if blank
  Units := LookupEquipmentFieldText('UNIT_MEASURE');
  edtUnits.Text := Units;
  if Units = '' then
    edtUnits.Color := clYellow
  else
    edtUnits.Color := clWhite;
end;

// ============================================================
// PROCEDURE: btnCancelClick
// ============================================================
procedure btnCancelClick(Sender: TObject);
begin
  Close;
end;

// ============================================================
// PROCEDURE: btnGenerateClick
// ============================================================
procedure btnGenerateClick(Sender: TObject);
var
  GageID      : string;
  Company     : string;
  FullScale   : Double;
  Units       : string;
  Grade       : string;
  TolPct      : Double;
  IsReading   : Boolean;
  Tol         : Double;
  Missing     : string;
  Points      : array[0..7] of Double;
  TolPlus     : array[0..7] of Double;
  TolMinus    : array[0..7] of Double;
  Descs       : array[0..7] of string;
  i           : Integer;
  Seq         : Integer;
  SQL         : string;
begin

  // ── Re-grab context ──────────────────────────────────────
  GageID  := LocatingEquipmentID;
  Company := LocatingEquipmentCompany;

  if GageID = '' then
  begin
    ShowMessage('Could not determine the current equipment record. Please close and try again.');
    Exit;
  end;

  // ── Consolidated validation ───────────────────────────────
  Missing := '';

  if Trim(edtFullScale.Text) = '' then
  begin
    Missing := Missing + '  - Full Scale Value' + #13;
    edtFullScale.Color := clYellow;
  end
  else
    edtFullScale.Color := clWhite;

  if Trim(edtUnits.Text) = '' then
  begin
    Missing := Missing + '  - Unit of Measure' + #13;
    edtUnits.Color := clYellow;
  end
  else
    edtUnits.Color := clWhite;

  if cboGrade.ItemIndex < 0 then
    Missing := Missing + '  - ASME Grade' + #13;

  if Missing <> '' then
  begin
    ShowMessage(
      'The following required fields must be completed before ' +
      'test points can be generated:' + #13 + #13 +
      Missing
    );
    Exit;
  end;

  // ── Numeric validation ────────────────────────────────────
  FullScale := StrToFloat(edtFullScale.Text);

  if FullScale <= 0 then
  begin
    ShowMessage(
      'Full Scale value must be greater than zero.' + #13 +
      'Please correct and try again.'
    );
    edtFullScale.Color := clYellow;
    Exit;
  end;

  Units := edtUnits.Text;
  Grade := cboGrade.Text;

  // ── Grade to tolerance percentage mapping ────────────────
  IsReading := False;
  TolPct    := 0.0200;

  // B40.1 Dial type grades
  if      Grade = '4A'  then TolPct := 0.0010
  else if Grade = '3A'  then TolPct := 0.0025
  else if Grade = '2A'  then TolPct := 0.0050
  else if Grade = '1A'  then TolPct := 0.0100
  else if Grade = 'A'   then TolPct := 0.0100
  else if Grade = 'B'   then TolPct := 0.0200
  else if Grade = 'C'   then TolPct := 0.0300
  else if Grade = 'D'   then TolPct := 0.0500
  // B40.7 Digital span-based grades
  else if Grade = '5A'  then TolPct := 0.0005
  // B40.7 Digital reading-based grades (R suffix)
  else if Grade = '5AR' then begin TolPct := 0.0005; IsReading := True; end
  else if Grade = '4AR' then begin TolPct := 0.0010; IsReading := True; end
  else if Grade = '3AR' then begin TolPct := 0.0025; IsReading := True; end
  else if Grade = '2AR' then begin TolPct := 0.0050; IsReading := True; end
  else if Grade = 'AR'  then begin TolPct := 0.0100; IsReading := True; end
  else if Grade = 'BR'  then begin TolPct := 0.0200; IsReading := True; end;

  if not IsReading then
    Tol := FullScale * TolPct;

  // ── Define test points ───────────────────────────────────
  Points[0] := 0.20 * FullScale;  Descs[0] := '20% of Full Scale (Ascending)';
  Points[1] := 0.40 * FullScale;  Descs[1] := '40% of Full Scale (Ascending)';
  Points[2] := 0.60 * FullScale;  Descs[2] := '60% of Full Scale (Ascending)';
  Points[3] := 0.80 * FullScale;  Descs[3] := '80% of Full Scale (Ascending)';
  Points[4] := 1.00 * FullScale;  Descs[4] := '100% of Full Scale (Ascending)';
  Points[5] := 0.60 * FullScale;  Descs[5] := '60% of Full Scale (Descending)';
  Points[6] := 0.40 * FullScale;  Descs[6] := '40% of Full Scale (Descending)';
  Points[7] := 0.00;              Descs[7] := 'Return to Zero (Descending)';

  // ── Calculate tolerances per point ───────────────────────
  for i := 0 to 7 do
  begin
    if Points[i] = 0 then
    begin
      TolPlus[i]  := 0;
      TolMinus[i] := 0;
    end
    else if IsReading then
    begin
      Tol         := Points[i] * TolPct;
      TolPlus[i]  := Points[i] + Tol;
      TolMinus[i] := Points[i] - Tol;
    end
    else
    begin
      TolPlus[i]  := Points[i] + Tol;
      TolMinus[i] := Points[i] - Tol;
    end;
  end;

  // ── Write attributes back to equipment record ─────────────
  SetEquipmentFieldText('ATTRIBUTE1', edtFullScale.Text);
  SetEquipmentFieldText('UNIT_MEASURE', edtUnits.Text);

  // ── Clear existing test points ───────────────────────────
  ReturnFromSQL(
    'DELETE FROM TESTPNTS ' +
    'WHERE GAGE_SN = ''' + GageID + ''' ' +
    'AND COMPANY = ''' + Company + ''''
  );

  // ── Insert new test point rows ───────────────────────────
  Seq := 1;
  for i := 0 to 7 do
  begin
    SQL :=
      'INSERT INTO TESTPNTS ' +
      '(COMPANY, GAGE_SN, LINE_NO, LINE_DESCRIPTION, ' +
      'LINE_STANDARD, TOLERANCE1, TOLERANCE2, UNIT_MEASURE) ' +
      'VALUES (' +
      '''' + Company + ''', ' +
      '''' + GageID + ''', ' +
      IntToStr(Seq) + ', ' +
      '''' + Descs[i] + ''', ' +
      FormatFloat('0.######', Points[i]) + ', ' +
      FormatFloat('0.######', TolPlus[i]) + ', ' +
      FormatFloat('0.######', TolMinus[i]) + ', ' +
      '''' + Units + ''')';
    ReturnFromSQL(SQL);
    Seq := Seq + 1;
  end;

  // ── Refresh the test points grid ─────────────────────────
  RefreshTestPointsGrid;

  // ── Confirm and close ────────────────────────────────────
  ShowMessage(
    'Test points written successfully.' + #13 +
    'Gage ID : ' + GageID + #13 +
    'Company : ' + Company + #13 +
    'Grade   : ' + Grade + #13 +
    '8 test point rows written.'
  );

  Close;
end;

begin
end.
