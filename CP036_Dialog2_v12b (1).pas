{$FORM TDialog2Form, Dialog2.sfm}
uses
  Classes, Graphics, Controls, Forms, Dialogs, StdCtrls;

// ============================================================
// CP-036 Pressure Devices by Comparison
// Test Point Wizard v12b — Dialog 2: Tolerance & Master Attributes
// Author: B. Wood
//
// Changes from v12:
//   - Added warning when tech overrides standard ASME grade
//     (4A through D, 5A) to Reading-based tolerance
//   - AR grades still hardcoded to Reading per ASME definition
//   - 3-2-3 still uses cbTolType freely
//   - Warning explains legitimate override scenarios
//     (deadweight tester, transducer spec, customer requirement)
// ============================================================

procedure edtMinChange(Sender: TObject);
begin
  if Trim(edtMin.Text) = '' then
    edtMin.Color := clYellow
  else
    edtMin.Color := clWhite;
end;

procedure Form2Create(Sender: TObject);
begin
  edtMin.Text := '0';
  edtMin.Color := clWhite;
  edtMasterRes.Text := '';

  cbTol.Items.Clear;
  cbTol.Items.Add('4A — ±0.10% FS');
  cbTol.Items.Add('3A — ±0.25% FS');
  cbTol.Items.Add('2A — ±0.50% FS');
  cbTol.Items.Add('1A — ±1.00% FS');
  cbTol.Items.Add('A — ±1.00% FS');
  cbTol.Items.Add('B — ±2.00% FS');
  cbTol.Items.Add('C — ±3.00% FS');
  cbTol.Items.Add('D — ±5.00% FS');
  cbTol.Items.Add('5A — ±0.05% FS');
  cbTol.Items.Add('5AR — ±0.05% of Reading');
  cbTol.Items.Add('4AR — ±0.10% of Reading');
  cbTol.Items.Add('3AR — ±0.25% of Reading');
  cbTol.Items.Add('2AR — ±0.50% of Reading');
  cbTol.Items.Add('AR — ±1.00% of Reading');
  cbTol.Items.Add('BR — ±2.00% of Reading');
  cbTol.Items.Add('3-2-3 — OCS Special Tolerance');

  cbTol.ItemIndex := 5;

  cbTolType.Items.Clear;
  cbTolType.Items.Add('F.S.');
  cbTolType.Items.Add('Reading');
  cbTolType.ItemIndex := 0;
end;

procedure btnCancelClick(Sender: TObject);
begin
  Close;
end;

procedure btnGenerateClick(Sender: TObject);
var
  GageID      : string;
  Company     : string;
  MaxVal      : Double;
  MinVal      : Double;
  FullRange   : Double;
  Units       : string;
  Resolution  : Integer;
  ResText     : string;
  TolText     : string;
  Grade       : string;
  TolType     : string;
  TolPct      : Double;
  IsReading   : Boolean;
  Is323       : Boolean;
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

  Missing := '';

  if Trim(edtMin.Text) = '' then
  begin
    Missing := Missing + '  - Minimum Value' + #13;
    edtMin.Color := clYellow;
  end
  else
    edtMin.Color := clWhite;

  if cbTol.ItemIndex < 0 then
    Missing := Missing + '  - ASME Grade / Tolerance' + #13;

  if cbTolType.ItemIndex < 0 then
    Missing := Missing + '  - Tolerance Type' + #13;

  if Missing <> '' then
  begin
    ShowMessage(
      'The following required fields must be completed before ' +
      'test points can be generated:' + #13 + #13 +
      Missing
    );
    Exit;
  end;

  GageID  := LocatingEquipmentID;
  Company := LocatingEquipmentCompany;
  MaxVal  := StrToFloat(LookupEquipmentFieldText('ATTRIBUTE1'));
  Units   := LookupEquipmentFieldText('UNIT_MEASURE');
  MinVal  := StrToFloat(edtMin.Text);

  if Trim(edtMasterRes.Text) <> '' then
    ResText := Trim(edtMasterRes.Text)
  else
    ResText := LookupEquipmentFieldText('ATTRIBUTE2');

  if Pos('.', ResText) > 0 then
    Resolution := Length(ResText) - Pos('.', ResText)
  else
    Resolution := 0;

  FullRange := MaxVal - MinVal;

  if MaxVal <= MinVal then
  begin
    ShowMessage(
      'Maximum value must be greater than Minimum value.' + #13 +
      'Please correct and try again.'
    );
    edtMin.Color := clYellow;
    Exit;
  end;

  TolText := cbTol.Text;
  if Pos(' ', TolText) > 0 then
    Grade := Copy(TolText, 1, Pos(' ', TolText) - 1)
  else
    Grade := TolText;

  TolType   := cbTolType.Text;
  IsReading := False;
  Is323     := False;
  TolPct    := 0.0200;

  DateStr := ReturnFromSQL('SELECT FORMAT(GETDATE(), ''MMddyyyy'')');
  TabName := 'AL-CP036-' + DateStr;

  // ── Grade to tolerance mapping ────────────────────────────
  // AR grades are always Reading per ASME definition
  if Grade = '3-2-3' then
    Is323 := True
  else if Grade = '4A'  then TolPct := 0.0010
  else if Grade = '3A'  then TolPct := 0.0025
  else if Grade = '2A'  then TolPct := 0.0050
  else if Grade = '1A'  then TolPct := 0.0100
  else if Grade = 'A'   then TolPct := 0.0100
  else if Grade = 'B'   then TolPct := 0.0200
  else if Grade = 'C'   then TolPct := 0.0300
  else if Grade = 'D'   then TolPct := 0.0500
  else if Grade = '5A'  then TolPct := 0.0005
  else if Grade = '5AR' then begin TolPct := 0.0005; IsReading := True; end
  else if Grade = '4AR' then begin TolPct := 0.0010; IsReading := True; end
  else if Grade = '3AR' then begin TolPct := 0.0025; IsReading := True; end
  else if Grade = '2AR' then begin TolPct := 0.0050; IsReading := True; end
  else if Grade = 'AR'  then begin TolPct := 0.0100; IsReading := True; end
  else if Grade = 'BR'  then begin TolPct := 0.0200; IsReading := True; end;

  // ── Tolerance type override handling ──────────────────────
  // AR grades: always Reading, cbTolType ignored
  // 3-2-3: cbTolType applies freely, no warning needed
  // Standard grades (4A-D, 5A): warn if tech selects Reading
  //   Legitimate overrides: deadweight tester, transducer
  //   manufacturer spec, or explicit customer requirement
  if (not IsReading) and (not Is323) and (TolType = 'Reading') then
  begin
    ShowMessage(
      'WARNING: Grade ' + Grade + ' is defined as Full Scale by ASME.' + #13 +
      'Reading-based tolerance has been applied as requested.' + #13 + #13 +
      'This override is appropriate for: deadweight testers, ' +
      'transducer manufacturer specs, or explicit customer requirements.' + #13 + #13 +
      'If this was unintentional, change Tolerance Type to F.S. and regenerate.'
    );
    IsReading := True;
  end;

  if (not IsReading) and (not Is323) then
    Tol := FullRange * TolPct;

  // ── Define test points ────────────────────────────────────
  Points[0] := MinVal + (0.20 * FullRange);  Descs[0] := '20% of Full Scale (Ascending)';
  Points[1] := MinVal + (0.40 * FullRange);  Descs[1] := '40% of Full Scale (Ascending)';
  Points[2] := MinVal + (0.60 * FullRange);  Descs[2] := '60% of Full Scale (Ascending)';
  Points[3] := MinVal + (0.80 * FullRange);  Descs[3] := '80% of Full Scale (Ascending)';
  Points[4] := MinVal + (1.00 * FullRange);  Descs[4] := '100% of Full Scale (Ascending)';
  Points[5] := MinVal + (0.60 * FullRange);  Descs[5] := '60% of Full Scale (Descending)';
  Points[6] := MinVal + (0.40 * FullRange);  Descs[6] := '40% of Full Scale (Descending)';
  Points[7] := MinVal;                        Descs[7] := 'Return to Zero (Descending)';

  // ── Calculate tolerances per point ───────────────────────
  for i := 0 to 7 do
  begin
    if Points[i] = MinVal then
    begin
      TolPlus[i]  := 0;
      TolMinus[i] := 0;
    end
    else if Is323 then
    begin
      if TolType = 'F.S.' then
      begin
        if (Points[i] < MinVal + (FullRange * 0.33)) or
           (Points[i] > MinVal + (FullRange * 0.66)) then
        begin
          TolPlus[i]  := Points[i] + (FullRange * 0.03);
          TolMinus[i] := Points[i] - (FullRange * 0.03);
        end
        else
        begin
          TolPlus[i]  := Points[i] + (FullRange * 0.02);
          TolMinus[i] := Points[i] - (FullRange * 0.02);
        end;
      end
      else
      begin
        if (Points[i] < MinVal + (FullRange * 0.33)) or
           (Points[i] > MinVal + (FullRange * 0.66)) then
        begin
          TolPlus[i]  := Points[i] + (Points[i] * 0.03);
          TolMinus[i] := Points[i] - (Points[i] * 0.03);
        end
        else
        begin
          TolPlus[i]  := Points[i] + (Points[i] * 0.02);
          TolMinus[i] := Points[i] - (Points[i] * 0.02);
        end;
      end;
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

  RunSQL(
    'DELETE FROM TESTPNTS ' +
    'WHERE GAGE_SN = ''' + GageID + ''' ' +
    'AND COMPANY = ''' + Company + ''' ' +
    'AND CAL_TYPE = ''' + TabName + ''''
  );

  Seq := 1;
  for i := 0 to 7 do
  begin
    SQL :=
      'INSERT INTO TESTPNTS ' +
      '(COMPANY, GAGE_SN, LINE_NO, LINE_DESCRIPTION, ' +
      'LINE_STANDARD, TOLERANCE1, TOLERANCE2, UNIT_MEASURE, ' +
      'NUM_RESOLUTION, CAL_TYPE) ' +
      'VALUES (' +
      '''' + Company + ''', ' +
      '''' + GageID + ''', ' +
      IntToStr(Seq) + ', ' +
      '''' + Descs[i] + ''', ' +
      FormatFloat('0.######', Points[i]) + ', ' +
      FormatFloat('0.######', TolPlus[i]) + ', ' +
      FormatFloat('0.######', TolMinus[i]) + ', ' +
      '''' + Units + ''', ' +
      IntToStr(Resolution) + ', ' +
      '''' + TabName + ''')';
    RunSQL(SQL);
    Seq := Seq + 1;
  end;

  RunSQL(
    'UPDATE GAGES SET CAL_TYPE = ''' + TabName + ''' ' +
    'WHERE GAGE_SN = ''' + GageID + ''' ' +
    'AND COMPANY = ''' + Company + ''''
  );

  RefreshTestPointsGrid;

  ShowMessage(
    'Test points written successfully.' + #13 +
    'Gage ID    : ' + GageID + #13 +
    'Company    : ' + Company + #13 +
    'Grade/Tol  : ' + Grade + #13 +
    'Tol Type   : ' + TolType + #13 +
    'Range      : ' + edtMin.Text + ' to ' + LookupEquipmentFieldText('ATTRIBUTE1') + ' ' + Units + #13 +
    'Resolution : ' + ResText + #13 +
    'Tab        : ' + TabName + #13 +
    '8 test point rows written.'
  );

  Close;
end;

begin
end.
