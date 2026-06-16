{$FORM TDialog1Form, Dialog1.sfm}
uses
  Classes, Graphics, Controls, Forms, Dialogs, StdCtrls;

// ============================================================
// CP-036 Pressure Devices by Comparison
// Test Point Wizard — v10
// Author: B. Wood
//
// Changes from v9:
//   - Grade dropdown items now show grade + tolerance display
//     e.g. "B — ±2.00% FS", "5AR — ±0.05% of Reading"
//   - Grade defaults to B on form load
//   - Tab name format changed from AL_MMDDYYYY to AL-CP036-MMDDYYYY
// ============================================================

procedure edtFullScaleChange(Sender: TObject);
begin
  if Trim(edtFullScale.Text) = '' then
    edtFullScale.Color := clYellow
  else
    edtFullScale.Color := clWhite;
end;

procedure edtUnitsChange(Sender: TObject);
begin
  if Trim(edtUnits.Text) = '' then
    edtUnits.Color := clYellow
  else
    edtUnits.Color := clWhite;
end;

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

  Capacity := LookupEquipmentFieldText('ATTRIBUTE1');
  edtFullScale.Text := Capacity;
  if Capacity = '' then
    edtFullScale.Color := clYellow
  else
    edtFullScale.Color := clWhite;

  Units := LookupEquipmentFieldText('UNIT_MEASURE');
  edtUnits.Text := Units;
  if Units = '' then
    edtUnits.Color := clYellow
  else
    edtUnits.Color := clWhite;

  // ── Populate grade dropdown with grade + tolerance display ──
  // B40.1 Dial / Analog grades (% of Full Scale)
  cboGrade.Items.Clear;
  cboGrade.Items.Add('4A — ±0.10% FS');
  cboGrade.Items.Add('3A — ±0.25% FS');
  cboGrade.Items.Add('2A — ±0.50% FS');
  cboGrade.Items.Add('1A — ±1.00% FS');
  cboGrade.Items.Add('A — ±1.00% FS');
  cboGrade.Items.Add('B — ±2.00% FS');
  cboGrade.Items.Add('C — ±3.00% FS');
  cboGrade.Items.Add('D — ±5.00% FS');
  // B40.7 Digital span-based
  cboGrade.Items.Add('5A — ±0.05% FS');
  // B40.7 Digital reading-based
  cboGrade.Items.Add('5AR — ±0.05% of Reading');
  cboGrade.Items.Add('4AR — ±0.10% of Reading');
  cboGrade.Items.Add('3AR — ±0.25% of Reading');
  cboGrade.Items.Add('2AR — ±0.50% of Reading');
  cboGrade.Items.Add('AR — ±1.00% of Reading');
  cboGrade.Items.Add('BR — ±2.00% of Reading');

  // ── Default to Grade B ────────────────────────────────────
  // AL default procedure tolerance per Joe Gunn direction
  cboGrade.ItemIndex := 5;  // 'B — ±2.00% FS' is index 5
end;

procedure btnCancelClick(Sender: TObject);
begin
  Close;
end;

procedure btnGenerateClick(Sender: TObject);
var
  GageID      : string;
  Company     : string;
  FullScale   : Double;
  Units       : string;
  GradeText   : string;
  Grade       : string;
  TolPct      : Double;
  IsReading   : Boolean;
  Tol         : Double;
  Missing     : string;
  DateStr     : string;
  TabName     : string;
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

  Units     := edtUnits.Text;

  // ── Extract grade code from dropdown text ─────────────────
  // Dropdown text is e.g. "B — ±2.00% FS" — extract just "B"
  GradeText := cboGrade.Text;
  if Pos(' ', GradeText) > 0 then
    Grade := Copy(GradeText, 1, Pos(' ', GradeText) - 1)
  else
    Grade := GradeText;

  // ── Build dated tab name ──────────────────────────────────
  // Format: AL-CP036-MMDDYYYY e.g. AL-CP036-06122026
  DateStr := ReturnFromSQL('SELECT FORMAT(GETDATE(), ''MMddyyyy'')');
  TabName := 'AL-CP036-' + DateStr;

  // ── Grade to tolerance percentage mapping ─────────────────
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

  // ── Define test points ────────────────────────────────────
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

  // ── Clear existing rows for this tab only ─────────────────
  ReturnFromSQL(
    'DELETE FROM TESTPNTS ' +
    'WHERE GAGE_SN = ''' + GageID + ''' ' +
    'AND COMPANY = ''' + Company + ''' ' +
    'AND CAL_TYPE = ''' + TabName + ''''
  );

  // ── Insert new test point rows ────────────────────────────
  Seq := 1;
  for i := 0 to 7 do
  begin
    SQL :=
      'INSERT INTO TESTPNTS ' +
      '(COMPANY, GAGE_SN, LINE_NO, LINE_DESCRIPTION, ' +
      'LINE_STANDARD, TOLERANCE1, TOLERANCE2, UNIT_MEASURE, CAL_TYPE) ' +
      'VALUES (' +
      '''' + Company + ''', ' +
      '''' + GageID + ''', ' +
      IntToStr(Seq) + ', ' +
      '''' + Descs[i] + ''', ' +
      FormatFloat('0.######', Points[i]) + ', ' +
      FormatFloat('0.######', TolPlus[i]) + ', ' +
      FormatFloat('0.######', TolMinus[i]) + ', ' +
      '''' + Units + ''', ' +
      '''' + TabName + ''')';
    ReturnFromSQL(SQL);
    Seq := Seq + 1;
  end;

  // ── Set new tab as default on equipment record ────────────
  ReturnFromSQL(
    'UPDATE GAGES SET CAL_TYPE = ''' + TabName + ''' ' +
    'WHERE GAGE_SN = ''' + GageID + ''' ' +
    'AND COMPANY = ''' + Company + ''''
  );

  // ── Refresh the test points grid ─────────────────────────
  RefreshTestPointsGrid;

  // ── Confirm and close ─────────────────────────────────────
  ShowMessage(
    'Test points written successfully.' + #13 +
    'Gage ID : ' + GageID + #13 +
    'Company : ' + Company + #13 +
    'Grade   : ' + Grade + #13 +
    'Tab     : ' + TabName + #13 +
    '8 test point rows written.'
  );

  Close;
end;

begin
end.
