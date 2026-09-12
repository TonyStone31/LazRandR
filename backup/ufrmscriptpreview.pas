unit ufrmScriptPreview;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Process, DateUtils;

type

  { TfrmScriptPreview }

  TfrmScriptPreview = class(TForm)
    Bevel1: TBevel;
    btnApplyScript: TButton;
    btnCancel: TButton;
    lblWarning: TLabel;
    lblNewScript: TLabel;
    lblSafetyScript: TLabel;
    memoNewScript: TMemo;
    memoSafetyScript: TMemo;
    pnlHeader: TPanel;
    pnlScriptsViewer: TPanel;
    procedure btnApplyScriptClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
  private
    FApplyScriptPath: string;
    FSafetyScriptPath: string;
  public
    procedure SetupPreview(const ApplyScriptPath, SafetyScriptPath, CurrentDE: string;
                          HasVirtualSplits, DESupportsVirtualMonitors: boolean);
    procedure ExecuteScripts;
  end;

var
  frmScriptPreview: TfrmScriptPreview;

implementation

{$R *.lfm}

{ TfrmScriptPreview }

procedure TfrmScriptPreview.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TfrmScriptPreview.btnApplyScriptClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

procedure TfrmScriptPreview.SetupPreview(const ApplyScriptPath, SafetyScriptPath, CurrentDE: string;
                                         HasVirtualSplits, DESupportsVirtualMonitors: boolean);
var
  ApplyScript, SafetyScript: TStringList;
begin
  FApplyScriptPath := ApplyScriptPath;
  FSafetyScriptPath := SafetyScriptPath;

  // Load scripts
  ApplyScript := TStringList.Create;
  SafetyScript := TStringList.Create;
  try
    ApplyScript.LoadFromFile(ApplyScriptPath);
    if FileExists(SafetyScriptPath) then
      SafetyScript.LoadFromFile(SafetyScriptPath)
    else
      SafetyScript.Add('# Safety script not found!');

    memoNewScript.Lines.Text := ApplyScript.Text;
    memoSafetyScript.Lines.Text := SafetyScript.Text;
  finally
    ApplyScript.Free;
    SafetyScript.Free;
  end;

  // Show/hide and configure warning label
  if HasVirtualSplits and (not DESupportsVirtualMonitors) then
  begin
    lblWarning.Visible := True;
    lblWarning.Caption := 'HAH! Yeah, your system isn''t gonna support this virtual split shit. Too bad!' + LineEnding +
                         'At least you didn''t write this entire fucking program before realizing "' + CurrentDE + '" cock-blocks you from doing such a useful feature. ' +
                         'Especially with huge monitors... what a waste of perfectly good screen real estate!' + LineEnding +
                         'Virtual splits EXCLUDED. If you REALLY need it, switch to a WM that isn''t broken: i3, sway, bspwm, awesome, or qtile.';
  end
  else
    lblWarning.Visible := False;
end;

procedure TfrmScriptPreview.ExecuteScripts;
var
  StartTime: TDateTime;
  TimeLeft: integer;
  CountdownForm: TForm;
  lblMessage, lblTimer: TLabel;
  btnKeep, btnRevert: TButton;
  KeepChanges: Boolean;
  Output: string;
begin
  // Execute the apply script
  RunCommand('/bin/bash', [FApplyScriptPath], Output);

  // Show countdown dialog
  KeepChanges := False;
  CountdownForm := TForm.Create(nil);
  try
    CountdownForm.Width := 450;
    CountdownForm.Height := 200;
    CountdownForm.Position := poScreenCenter;
    CountdownForm.BorderStyle := bsDialog;
    CountdownForm.Caption := 'Confirm Display Settings';

    lblMessage := TLabel.Create(CountdownForm);
    lblMessage.Parent := CountdownForm;
    lblMessage.Left := 20;
    lblMessage.Top := 20;
    lblMessage.Caption := 'Keep these display settings?';
    lblMessage.Font.Size := 12;

    lblTimer := TLabel.Create(CountdownForm);
    lblTimer.Parent := CountdownForm;
    lblTimer.Left := 20;
    lblTimer.Top := 60;
    lblTimer.Width := 410;
    lblTimer.Height := 40;
    lblTimer.AutoSize := False;
    lblTimer.WordWrap := True;
    lblTimer.Font.Size := 10;
    lblTimer.Alignment := taCenter;

    btnKeep := TButton.Create(CountdownForm);
    btnKeep.Parent := CountdownForm;
    btnKeep.Caption := 'Keep Changes';
    btnKeep.Left := 100;
    btnKeep.Top := 120;
    btnKeep.Width := 120;
    btnKeep.ModalResult := mrOK;

    btnRevert := TButton.Create(CountdownForm);
    btnRevert.Parent := CountdownForm;
    btnRevert.Caption := 'Revert Now';
    btnRevert.Left := 230;
    btnRevert.Top := 120;
    btnRevert.Width := 120;
    btnRevert.ModalResult := mrCancel;

    StartTime := Now;

    while True do
    begin
      TimeLeft := 30 - SecondsBetween(Now, StartTime);

      if TimeLeft <= 0 then
        Break;

      lblTimer.Caption := 'Reverting in ' + IntToStr(TimeLeft) + ' seconds...';
      Application.ProcessMessages;
      Sleep(100);

      if CountdownForm.ModalResult <> mrNone then
      begin
        if CountdownForm.ModalResult = mrOK then
          KeepChanges := True;
        Break;
      end;
    end;

    CountdownForm.Hide;

    // Revert if user didn't keep changes
    if not KeepChanges then
    begin
      RunCommand('/bin/bash', [FSafetyScriptPath], Output);
      ShowMessage('Reverted to safety configuration');
    end
    else
      ShowMessage('Display settings applied successfully!');

  finally
    CountdownForm.Free;
  end;
end;

end.
