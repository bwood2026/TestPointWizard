{$FORM TDialog1Form, Dialog1.sfm}

uses
  Classes, Graphics, Controls, Forms, Dialogs, StdCtrls;

// ============================================================
// CONSTANTS
// ============================================================
// Maximum number of attributes any instrument type will have.
// Declared here so arrays are sized consistently throughout.
// Increase if an instrument type ever exceeds 20 attributes.
const
  MAX_ATTRS = 20;

  // Maximum number of test point rows any wizard will generate.
  // Pressure gauge uses 8. Size generously for future types.
  MAX_POINTS = 30;

// ============================================================
// PROCEDURE: btnCancelClick
// Closes the wizard without writing anything.
// ============================================================
procedure btnCancelClick(Sender: TObject);
begin
  Close;
end;

// ============================================================
// PROCEDURE: btnLoadClick
// Triggered when the technician enters a Gage ID and clicks
// Load (or presses the Load button after typing the ID).
//
// Responsibilities:
//   1. Validate the Gage ID input
//   2. Resolve Company from GAGES table
//   3. Resolve Attribute Type from ATTRIBUTETYPE table
//   4. Load attribute captions from ATTRIBUTETYPE
//   5. Load attribute values from ATTRIBUTELIST
//   6. Store originals for change detection
//   7. Populate visible form fields
//
// NOTE: Form must have the following controls:
//   edtGageID       - TEdit   - technician types Gage ID here
//   lblAttrType     - TLabel  - displays resolved attribute type
//   lblStatus       - TLabel  - displays load status messages
//   edtAttr0..19    - TEdit   - dynamically populated attribute fields
//   lblAttr0..19    - TLabel  - captions for each attribute field
//   btnGenerate     - TButton - disabled until load succeeds
// ============================================================
procedure btnLoadClick(Sender: TObject);
var
  GageID      : string;
  Company     : string;
  AttrType    : string;
  AttrCount   : Integer;
  CountStr    : string;
  AttrNum     : string;
  Caption     : string;
  Value       : string;
  i           : Integer;
  SQL         : string;

  // Arrays to hold attribute data loaded from database.
  // AttrNames    = field captions (e.g. 'Resolution')
  // AttrValues   = current stored values (may be blank)
  // AttrOriginals= snapshot of values at load time for change detection
  // AttrNums     = the ATTRIBUTE_NUM key for each row (for UPDATE later)
  AttrNames     : array[0..MAX_ATTRS - 1] of string;
  AttrValues    : array[0..MAX_ATTRS - 1] of string;
  AttrOriginals : array[0..MAX_ATTRS - 1] of string;
  AttrNums      : array[0..MAX_ATTRS - 1] of string;

begin

  // ----------------------------------------------------------
  // BLOCK 2: GAGE ID VALIDATION
  // ----------------------------------------------------------

  GageID := Trim(edtGageID.Text);

  // Check 1 — blank field
  if GageID = '' then
  begin
    ShowMessage('Please enter a Gage ID before loading.');
    Exit;
  end;

  // Check 2 — does this ID exist in the database?
  Company := ReturnFromSQL(
    'SELECT TOP 1 COMPANY FROM GAGES WHERE GAGE_SN = ''' + GageID + ''''
  );

  if Company = '' then
  begin
    ShowMessage(
      'Gage ID "' + GageID + '" was not found in the system.' + #13 +
      'Please check the ID and try again.'
    );
    Exit;
  end;

  // Check 3 — does this equipment have an attribute type defined?
  // *** CONFIRM: Exact query against live record may need adjustment.
  // ATTRIBUTETYPE is keyed on COMPANY + ATTRIBUTE_TYPE.
  // We need to find which ATTRIBUTE_TYPE is assigned to this specific
  // piece of equipment. This may come from the GAGES table itself
  // (a field linking to ATTRIBUTETYPE) or from ATTRIBUTELIST.
  // The query below assumes GAGES has an ATTRIBUTE_TYPE field.
  // If not, this query will need to be revised once table confirmed.
  AttrType := ReturnFromSQL(
    'SELECT TOP 1 ATTRIBUTE_TYPE FROM ATTRIBUTELIST ' +
    'WHERE COMPANY = ''' + Company + ''' ' +
    'AND GAGE_SN = ''' + GageID + ''''
  );

  if AttrType = '' then
  begin
    ShowMessage(
      'No attribute type found for Gage ID "' + GageID + '".' + #13 +
      'Please configure the equipment attributes in IndySoft before ' +
      'using this wizard.'
    );
    Exit;
  end;

  // ----------------------------------------------------------
  // BLOCK 3: LOAD ATTRIBUTE STRUCTURE (captions from ATTRIBUTETYPE)
  // ----------------------------------------------------------

  // *** CONFIRM: ATTRIBUTETYPE stores captions as ATTRIBUTE1_CAPTION
  // through ATTRIBUTE8_CAPTION (string fields). There are also
  // NUM_ATTRIBUTE1_CAPTION through NUM_ATTRIBUTE8_CAPTION for numeric
  // attributes. The query below loads string captions only.
  // Adjust if numeric attribute captions also need to be loaded.

  // For now load up to 8 string captions (matches data dictionary).
  // We check each one — blank caption means that slot is not used.
  AttrCount := 0;

  for i := 1 to 8 do
  begin
    AttrNum := IntToStr(i);

    Caption := ReturnFromSQL(
      'SELECT ATTRIBUTE' + AttrNum + '_CAPTION ' +
      'FROM ATTRIBUTETYPE ' +
      'WHERE COMPANY = ''' + Company + ''' ' +
      'AND ATTRIBUTE_TYPE = ''' + AttrType + ''''
    );

    if Caption <> '' then
    begin
      AttrNames[AttrCount] := Caption;
      AttrNums[AttrCount]  := AttrNum;
      AttrCount            := AttrCount + 1;
    end;
  end;

  if AttrCount = 0 then
  begin
    ShowMessage(
      'Attribute type "' + AttrType + '" has no fields defined.' + #13 +
      'Please check the attribute configuration in IndySoft.'
    );
    Exit;
  end;

  // ----------------------------------------------------------
  // BLOCK 4: LOAD EXISTING VALUES (from ATTRIBUTELIST)
  // ----------------------------------------------------------

  for i := 0 to AttrCount - 1 do
  begin
    // *** CONFIRM: ATTRIBUTELIST stores values keyed on
    // COMPANY + ATTRIBUTE_TYPE + ATTRIBUTE_NUM + ATTRIBUTE_VALUE.
    // The ATTRIBUTE_NUM here should match the caption number
    // loaded above. Verify this mapping against a live record.
    Value := ReturnFromSQL(
      'SELECT TOP 1 ATTRIBUTE_VALUE ' +
      'FROM ATTRIBUTELIST ' +
      'WHERE COMPANY = ''' + Company + ''' ' +
      'AND ATTRIBUTE_TYPE = ''' + AttrType + ''' ' +
      'AND ATTRIBUTE_NUM = ''' + AttrNums[i] + ''' ' +
      'AND GAGE_SN = ''' + GageID + ''''
    );

    AttrValues[i]    := Value;
    AttrOriginals[i] := Value;  // snapshot for change detection
  end;

  // ----------------------------------------------------------
  // BLOCK 5: POPULATE FORM FIELDS
  // ----------------------------------------------------------
  // NOTE: This section populates up to MAX_ATTRS edit/label pairs.
  // The form must have controls named edtAttr0..edtAttr19
  // and lblAttr0..lblAttr19. Controls beyond AttrCount are hidden.
  // This approach requires the form to be pre-built with 20 pairs.
  // If dynamic control creation is available in this environment
  // it could be used instead, but that is unproven — static pairs
  // are the safe approach.

  // Hide all pairs first, then show only what we need.
  // (Assumes Visible property is available on controls.)
  // If Visible is not supported, leave all visible and blank unused ones.

  // Populate the attribute type label
  lblAttrType.Caption := 'Attribute Type: ' + AttrType;
  lblStatus.Caption   := 'Loaded ' + IntToStr(AttrCount) + ' attribute(s) for ' + GageID;

  // Pair 0
  if AttrCount > 0 then
  begin
    lblAttr0.Caption := AttrNames[0] + ':';
    edtAttr0.Text    := AttrValues[0];
    if AttrValues[0] = '' then
      edtAttr0.Hint  := 'No default found - please enter a value';
  end;

  // Pair 1
  if AttrCount > 1 then
  begin
    lblAttr1.Caption := AttrNames[1] + ':';
    edtAttr1.Text    := AttrValues[1];
  end;

  // Pair 2
  if AttrCount > 2 then
  begin
    lblAttr2.Caption := AttrNames[2] + ':';
    edtAttr2.Text    := AttrValues[2];
  end;

  // Pair 3
  if AttrCount > 3 then
  begin
    lblAttr3.Caption := AttrNames[3] + ':';
    edtAttr3.Text    := AttrValues[3];
  end;

  // Pair 4
  if AttrCount > 4 then
  begin
    lblAttr4.Caption := AttrNames[4] + ':';
    edtAttr4.Text    := AttrValues[4];
  end;

  // Pair 5
  if AttrCount > 5 then
  begin
    lblAttr5.Caption := AttrNames[5] + ':';
    edtAttr5.Text    := AttrValues[5];
  end;

  // Pair 6
  if AttrCount > 6 then
  begin
    lblAttr6.Caption := AttrNames[6] + ':';
    edtAttr6.Text    := AttrValues[6];
  end;

  // Pair 7
  if AttrCount > 7 then
  begin
    lblAttr7.Caption := AttrNames[7] + ':';
    edtAttr7.Text    := AttrValues[7];
  end;

  // Enable the Generate button now that load succeeded
  btnGenerate.Enabled := True;

  // Store GageID and Company in hidden fields so Generate can use them
  // without re-querying. Form must have these hidden TEdit controls.
  edtResolvedGageID.Text  := GageID;
  edtResolvedCompany.Text := Company;
  edtResolvedAttrType.Text := AttrType;
  edtResolvedAttrCount.Text := IntToStr(AttrCount);

  // Store originals in hidden fields for change detection in Generate.
  // One hidden TEdit per slot named edtOrig0..edtOrig7.
  if AttrCount > 0 then edtOrig0.Text := AttrOriginals[0];
  if AttrCount > 1 then edtOrig1.Text := AttrOriginals[1];
  if AttrCount > 2 then edtOrig2.Text := AttrOriginals[2];
  if AttrCount > 3 then edtOrig3.Text := AttrOriginals[3];
  if AttrCount > 4 then edtOrig4.Text := AttrOriginals[4];
  if AttrCount > 5 then edtOrig5.Text := AttrOriginals[5];
  if AttrCount > 6 then edtOrig6.Text := AttrOriginals[6];
  if AttrCount > 7 then edtOrig7.Text := AttrOriginals[7];

  // Store AttrNums in hidden fields so Generate knows which
  // ATTRIBUTE_NUM to UPDATE for each position.
  if AttrCount > 0 then edtAttrNum0.Text := AttrNums[0];
  if AttrCount > 1 then edtAttrNum1.Text := AttrNums[1];
  if AttrCount > 2 then edtAttrNum2.Text := AttrNums[2];
  if AttrCount > 3 then edtAttrNum3.Text := AttrNums[3];
  if AttrCount > 4 then edtAttrNum4.Text := AttrNums[4];
  if AttrCount > 5 then edtAttrNum5.Text := AttrNums[5];
  if AttrCount > 6 then edtAttrNum6.Text := AttrNums[6];
  if AttrCount > 7 then edtAttrNum7.Text := AttrNums[7];

end;

// ============================================================
// PROCEDURE: btnGenerateClick
// Triggered when the technician clicks Generate.
//
// Responsibilities:
//   1. Rebuild working arrays from form fields
//   2. Validate all attribute values
//   3. Detect changes against originals
//   4. Prompt for confirmation if changes exist
//   5. Write attributes back to ATTRIBUTELIST
//   6. Clear existing test points from TESTPNTS
//   7. Calculate test points (instrument-specific logic here)
//   8. Insert test point rows into TESTPNTS
//   9. Confirm and close
// ============================================================
procedure btnGenerateClick(Sender: TObject);
var
  GageID    : string;
  Company   : string;
  AttrType  : string;
  AttrCount : Integer;
  i         : Integer;
  SQL       : string;
  Seq       : Integer;
  Changed   : Boolean;
  NumVal    : Double;

  // Rebuild working arrays from form state
  AttrValues    : array[0..MAX_ATTRS - 1] of string;
  AttrOriginals : array[0..MAX_ATTRS - 1] of string;
  AttrNums      : array[0..MAX_ATTRS - 1] of string;
  AttrNames     : array[0..MAX_ATTRS - 1] of string;

  // Test point arrays — pressure gauge uses 8 rows max
  // Adjust MAX_POINTS constant at top for other instrument types
  Points    : array[0..MAX_POINTS - 1] of Double;
  TolPlus   : array[0..MAX_POINTS - 1] of Double;
  TolMinus  : array[0..MAX_POINTS - 1] of Double;
  Descs     : array[0..MAX_POINTS - 1] of string;
  PointCount: Integer;

  // Instrument-specific working variables (pressure gauge example)
  FullScale : Double;
  Tol       : Double;
  Units     : string;
  Grade     : string;

begin

  // ----------------------------------------------------------
  // Recover resolved values from hidden form fields
  // (set by btnLoadClick earlier in the session)
  // ----------------------------------------------------------
  GageID    := edtResolvedGageID.Text;
  Company   := edtResolvedCompany.Text;
  AttrType  := edtResolvedAttrType.Text;
  AttrCount := StrToIntDef(edtResolvedAttrCount.Text, 0);

  if GageID = '' then
  begin
    ShowMessage('Please use the Load button first to load equipment data.');
    Exit;
  end;

  if AttrCount = 0 then
  begin
    ShowMessage('No attributes loaded. Please click Load before Generate.');
    Exit;
  end;

  // ----------------------------------------------------------
  // Rebuild working arrays from current form field values
  // ----------------------------------------------------------
  if AttrCount > 0 then
  begin
    AttrValues[0]    := edtAttr0.Text;
    AttrOriginals[0] := edtOrig0.Text;
    AttrNums[0]      := edtAttrNum0.Text;
    AttrNames[0]     := lblAttr0.Caption;
  end;
  if AttrCount > 1 then
  begin
    AttrValues[1]    := edtAttr1.Text;
    AttrOriginals[1] := edtOrig1.Text;
    AttrNums[1]      := edtAttrNum1.Text;
    AttrNames[1]     := lblAttr1.Caption;
  end;
  if AttrCount > 2 then
  begin
    AttrValues[2]    := edtAttr2.Text;
    AttrOriginals[2] := edtOrig2.Text;
    AttrNums[2]      := edtAttrNum2.Text;
    AttrNames[2]     := lblAttr2.Caption;
  end;
  if AttrCount > 3 then
  begin
    AttrValues[3]    := edtAttr3.Text;
    AttrOriginals[3] := edtOrig3.Text;
    AttrNums[3]      := edtAttrNum3.Text;
    AttrNames[3]     := lblAttr3.Caption;
  end;
  if AttrCount > 4 then
  begin
    AttrValues[4]    := edtAttr4.Text;
    AttrOriginals[4] := edtOrig4.Text;
    AttrNums[4]      := edtAttrNum4.Text;
    AttrNames[4]     := lblAttr4.Caption;
  end;
  if AttrCount > 5 then
  begin
    AttrValues[5]    := edtAttr5.Text;
    AttrOriginals[5] := edtOrig5.Text;
    AttrNums[5]      := edtAttrNum5.Text;
    AttrNames[5]     := lblAttr5.Caption;
  end;
  if AttrCount > 6 then
  begin
    AttrValues[6]    := edtAttr6.Text;
    AttrOriginals[6] := edtOrig6.Text;
    AttrNums[6]      := edtAttrNum6.Text;
    AttrNames[6]     := lblAttr6.Caption;
  end;
  if AttrCount > 7 then
  begin
    AttrValues[7]    := edtAttr7.Text;
    AttrOriginals[7] := edtOrig7.Text;
    AttrNums[7]      := edtAttrNum7.Text;
    AttrNames[7]     := lblAttr7.Caption;
  end;

  // ----------------------------------------------------------
  // BLOCK 7: VALIDATION
  // Run all checks before writing anything.
  // ----------------------------------------------------------

  for i := 0 to AttrCount - 1 do
  begin
    // Blank check — required field cannot be empty
    if Trim(AttrValues[i]) = '' then
    begin
      ShowMessage(
        AttrNames[i] + ' cannot be blank.' + #13 +
        'Please enter a value before generating test points.'
      );
      Exit;
    end;
  end;

  // Instrument-specific validation.
  // The section below is written for pressure gauges (ASME B40.100).
  // Replace or extend this block for other instrument types.
  // The attribute positions (0, 1, 2, 3) below assume:
  //   AttrValues[0] = Full Scale (numeric)
  //   AttrValues[1] = Units (string)
  //   AttrValues[2] = ASME Grade (string - 'Grade A' or 'Grade 2A')
  //   AttrValues[3] = Resolution (numeric)
  // *** CONFIRM these positions match your actual ATTRIBUTETYPE
  // caption order for the pressure gauge attribute type.

  // Full scale must be a valid positive number
  if not TryStrToFloat(AttrValues[0], NumVal) then
  begin
    ShowMessage(AttrNames[0] + ' must be a valid number.');
    Exit;
  end;
  if NumVal <= 0 then
  begin
    ShowMessage(AttrNames[0] + ' must be greater than zero.');
    Exit;
  end;
  FullScale := NumVal;

  // Units must not be blank (already caught above, but store it)
  Units := AttrValues[1];

  // Grade must be one of the expected values
  Grade := AttrValues[2];
  if (Grade <> 'Grade A') and (Grade <> 'Grade 2A') then
  begin
    ShowMessage(
      AttrNames[2] + ' must be either "Grade A" or "Grade 2A".' + #13 +
      'Please correct and try again.'
    );
    Exit;
  end;

  // Resolution must be a valid positive number
  if not TryStrToFloat(AttrValues[3], NumVal) then
  begin
    ShowMessage(AttrNames[3] + ' must be a valid number.');
    Exit;
  end;
  if NumVal <= 0 then
  begin
    ShowMessage(AttrNames[3] + ' must be greater than zero.');
    Exit;
  end;

  // Calculate tolerance from grade (ASME B40.100 Table 1)
  if Grade = 'Grade A' then
    Tol := FullScale * 0.01       // 1.0% of full scale
  else
    Tol := FullScale * 0.005;     // 0.5% of full scale (Grade 2A)

  // Relationship check — tolerance must not be tighter than resolution
  if Tol < StrToFloat(AttrValues[3]) then
  begin
    ShowMessage(
      'Calculated tolerance (' + FormatFloat('0.######', Tol) + ') ' +
      'is tighter than the entered resolution (' + AttrValues[3] + ').' + #13 +
      'Please check the values and try again.'
    );
    Exit;
  end;

  // ----------------------------------------------------------
  // BLOCK 8: CHANGE DETECTION AND CONFIRMATION
  // ----------------------------------------------------------
  Changed := False;
  for i := 0 to AttrCount - 1 do
  begin
    if AttrValues[i] <> AttrOriginals[i] then
    begin
      Changed := True;
      Break;
    end;
  end;

  if Changed then
  begin
    if MessageDlg(
      'You have modified one or more default equipment parameters.' + #13 +
      'This will update the equipment record in IndySoft.' + #13 + #13 +
      'Do you want to continue?',
      mtConfirmation, [mbYes, mbNo], 0) = mrNo then
    begin
      // Revert form fields to originals
      if AttrCount > 0 then edtAttr0.Text := AttrOriginals[0];
      if AttrCount > 1 then edtAttr1.Text := AttrOriginals[1];
      if AttrCount > 2 then edtAttr2.Text := AttrOriginals[2];
      if AttrCount > 3 then edtAttr3.Text := AttrOriginals[3];
      if AttrCount > 4 then edtAttr4.Text := AttrOriginals[4];
      if AttrCount > 5 then edtAttr5.Text := AttrOriginals[5];
      if AttrCount > 6 then edtAttr6.Text := AttrOriginals[6];
      if AttrCount > 7 then edtAttr7.Text := AttrOriginals[7];
      Exit;
    end;
  end;

  // ----------------------------------------------------------
  // BLOCK 9: WRITE ATTRIBUTES BACK TO EQUIPMENT RECORD
  // *** CONFIRM: This UPDATE assumes a row already exists in
  // ATTRIBUTELIST for each ATTRIBUTE_NUM. If the record is
  // brand new (State 3 — completely blank), an INSERT may be
  // needed instead. Logic below attempts UPDATE first; if zero
  // rows affected it falls through to INSERT.
  // IndySoft's ReturnFromSQL does not return affected row count
  // so we handle this by checking if the original was blank.
  // ----------------------------------------------------------
  for i := 0 to AttrCount - 1 do
  begin
    if AttrOriginals[i] <> '' then
    begin
      // Row exists — UPDATE
      SQL :=
        'UPDATE ATTRIBUTELIST SET ATTRIBUTE_VALUE = ''' + AttrValues[i] + ''' ' +
        'WHERE COMPANY = ''' + Company + ''' ' +
        'AND GAGE_SN = ''' + GageID + ''' ' +
        'AND ATTRIBUTE_TYPE = ''' + AttrType + ''' ' +
        'AND ATTRIBUTE_NUM = ''' + AttrNums[i] + '''';
    end
    else
    begin
      // Row did not exist — INSERT
      // *** CONFIRM ATTRIBUTELIST schema allows GAGE_SN as a key field.
      // The data dictionary shows COMPANY, ATTRIBUTE_TYPE, ATTRIBUTE_NUM,
      // ATTRIBUTE_VALUE as the four columns. GAGE_SN may need to be
      // confirmed as part of the key before this INSERT is finalized.
      SQL :=
        'INSERT INTO ATTRIBUTELIST (COMPANY, GAGE_SN, ATTRIBUTE_TYPE, ATTRIBUTE_NUM, ATTRIBUTE_VALUE) ' +
        'VALUES (' +
        '''' + Company + ''', ' +
        '''' + GageID + ''', ' +
        '''' + AttrType + ''', ' +
        '''' + AttrNums[i] + ''', ' +
        '''' + AttrValues[i] + ''')';
    end;
    ReturnFromSQL(SQL);
  end;

  // ----------------------------------------------------------
  // BLOCK 10: CLEAR EXISTING TEST POINTS
  // ----------------------------------------------------------
  ReturnFromSQL(
    'DELETE FROM TESTPNTS ' +
    'WHERE GAGE_SN = ''' + GageID + ''' ' +
    'AND COMPANY = ''' + Company + ''''
  );

  // ----------------------------------------------------------
  // BLOCK 11: CALCULATE TEST POINTS
  // Pressure gauge — ASME B40.100
  // 5 ascending + 3 descending = 8 rows total
  // Ascending:  20 / 40 / 60 / 80 / 100% of full scale
  // Descending: 60 / 40% + return to zero
  // ----------------------------------------------------------
  PointCount := 8;

  Points[0] := FullScale * 0.20;  Descs[0] := '20% of Full Scale (Ascending)';
  Points[1] := FullScale * 0.40;  Descs[1] := '40% of Full Scale (Ascending)';
  Points[2] := FullScale * 0.60;  Descs[2] := '60% of Full Scale (Ascending)';
  Points[3] := FullScale * 0.80;  Descs[3] := '80% of Full Scale (Ascending)';
  Points[4] := FullScale * 1.00;  Descs[4] := '100% of Full Scale (Ascending)';
  Points[5] := FullScale * 0.60;  Descs[5] := '60% of Full Scale (Descending)';
  Points[6] := FullScale * 0.40;  Descs[6] := '40% of Full Scale (Descending)';
  Points[7] := 0;                  Descs[7] := 'Return to Zero (Descending)';

  // Tolerance is uniform across all rows for pressure gauges
  for i := 0 to PointCount - 1 do
  begin
    TolPlus[i]  := Points[i] + Tol;
    TolMinus[i] := Points[i] - Tol;
  end;

  // ----------------------------------------------------------
  // BLOCK 12: INSERT TEST POINT ROWS INTO TESTPNTS
  // ----------------------------------------------------------
  Seq := 1;
  for i := 0 to PointCount - 1 do
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

  // ----------------------------------------------------------
  // BLOCK 13: CONFIRM AND CLOSE
  // ----------------------------------------------------------
  ShowMessage(
    'Test points written successfully.' + #13 +
    'Gage ID : ' + GageID + #13 +
    'Company : ' + Company + #13 +
    'Type    : ' + AttrType + #13 +
    IntToStr(PointCount) + ' test point rows written.'
  );

  Close;

end;

// ============================================================
// Entry point — required by Project Designer
// ============================================================
begin
end.
