uses
  Classes, Graphics, Controls, Forms, Dialogs, Dialog1, Unit1;

var
  Dialog1Form : TDialog1Form;
  Dialog2Form : TDialog2Form;

begin
  Dialog1Form := TDialog1Form.Create(Application);
  try
    Dialog1Form.ShowModal;
  finally
    Dialog1Form.Free;
  end;

  Dialog2Form := TDialog2Form.Create(Application);
  try
    Dialog2Form.ShowModal;
  finally
    Dialog2Form.Free;
  end;
end.
