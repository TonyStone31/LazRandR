unit ufrmGreeter;

{ The login manager half of persistence.

  Writing to /etc is not something to do behind a checkbox, so this is a
  dialog rather than a toggle: it names the manager it found, names both
  files it is going to write, and shows the exact script before anything is
  installed. The privileged step is a single pkexec call on an installer
  staged in the user's own config directory. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Clipbrd,
  BCPanel, BCButton, BCLabel, BCTypes, uTheme, uGreeter;

type

  { TfrmGreeter }

  TfrmGreeter = class(TForm)
    btnClose: TBCButton;
    btnCopy: TBCButton;
    btnInstall: TBCButton;
    btnRemove: TBCButton;
    lblDetect: TBCLabel;
    lblHeading: TBCLabel;
    lblPaths: TBCLabel;
    memScript: TMemo;
    pnlBottom: TBCPanel;
    pnlTop: TBCPanel;
    procedure btnCloseClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure btnInstallClick(Sender: TObject);
    procedure btnRemoveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FGreeter: TGreeterConfig;
    FLinkProvider: boolean;
    FSink, FSource: string;
    procedure RefreshState;
  public
    { Not owned: the caller keeps the TGreeterConfig alive. }
    procedure Setup(AGreeter: TGreeterConfig; ALinkProvider: boolean;
      const ASink, ASource: string);
  end;

implementation

{$R *.lfm}

{ TfrmGreeter }

procedure TfrmGreeter.FormCreate(Sender: TObject);
begin
  Color := clWindowBg;

  SkinPanel(pnlTop, pkHeader);
  SkinPanel(pnlBottom, pkHeader);
  SkinLabel(lblHeading, clTextBright, 18, True, bcaLeftCenter, clSurfaceAlt);
  SkinLabel(lblDetect, clText, 13, False, bcaLeftCenter, clSurfaceAlt);
  SkinLabel(lblPaths, clTextFaint, 12, False, bcaLeftTop, clSurfaceAlt);

  SkinButton(btnCopy, bkNeutral);
  SkinButton(btnRemove, bkDanger);
  SkinButton(btnInstall, bkPrimary);
  SkinButton(btnClose, bkNeutral);

  memScript.Color := clWindowBg;
  memScript.Font.Name := 'Ubuntu Mono';
  memScript.Font.Height := 14;
  memScript.Font.Color := clText;
  memScript.ReadOnly := True;
  memScript.BorderStyle := bsNone;
end;

procedure TfrmGreeter.Setup(AGreeter: TGreeterConfig; ALinkProvider: boolean;
  const ASink, ASource: string);
begin
  FGreeter := AGreeter;
  FLinkProvider := ALinkProvider;
  FSink := ASink;
  FSource := ASource;
  RefreshState;
end;

procedure TfrmGreeter.RefreshState;
var
  L: TStringList;
begin
  if FGreeter = nil then Exit;

  FGreeter.Detect;

  L := TStringList.Create;
  try
    FGreeter.BuildScript(L, FLinkProvider, FSink, FSource);
    memScript.Lines.Assign(L);
  finally
    L.Free;
  end;

  if not FGreeter.Supported then
  begin
    lblDetect.Caption := 'Login manager: ' + FGreeter.ManagerName +
      ' -- cannot be configured from here';
    lblPaths.Caption := FGreeter.WhyUnsupported;
    btnInstall.Enabled := False;
    btnRemove.Enabled := False;
    Exit;
  end;

  if FGreeter.Installed then
  begin
    lblDetect.Caption := 'Login manager: ' + FGreeter.ManagerName +
      '   --   hook is installed';
    btnInstall.Caption := 'Update hook';
  end
  else
  begin
    lblDetect.Caption := 'Login manager: ' + FGreeter.ManagerName +
      '   --   no hook installed, the greeter is on its own';
    btnInstall.Caption := 'Write to ' + FGreeter.ManagerName;
  end;

  lblPaths.Caption :=
    'Writes ' + FGreeter.TargetScriptPath + ' and ' + FGreeter.TargetConfPath +
    LineEnding +
    'Both are outside your home directory, so this asks for your password. ' +
    'The script logs to /var/log/lazrandr-greeter.log and always exits 0, ' +
    'so a failure cannot stop you logging in.';

  btnInstall.Enabled := True;
  btnRemove.Enabled := FGreeter.Installed;
end;

procedure TfrmGreeter.btnInstallClick(Sender: TObject);
var
  Err: string;
begin
  if FGreeter = nil then Exit;

  if FGreeter.Install(Err, FLinkProvider, FSink, FSource) then
  begin
    RefreshState;
    MessageDlg('Login screen configured',
      'The layout will now be applied on the greeter''s display before the ' +
      'login window is drawn.' + LineEnding + LineEnding +
      'Check it with a reboot rather than a logout: a logout reuses the X ' +
      'server that is already running, so it cannot show you whether the ' +
      'startup race is actually fixed.',
      mtInformation, [mbOK], 0);
  end
  else
    MessageDlg('Could not write the hook', Err, mtError, [mbOK], 0);
end;

procedure TfrmGreeter.btnRemoveClick(Sender: TObject);
var
  Err: string;
begin
  if FGreeter = nil then Exit;

  if MessageDlg('Remove the login screen hook?',
    'The greeter goes back to whatever layout the X server guesses at ' +
    'startup, which is what produced the mirrored login screen in the ' +
    'first place.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;

  if FGreeter.Remove(Err) then
    RefreshState
  else
    MessageDlg('Could not remove the hook', Err, mtError, [mbOK], 0);
end;

procedure TfrmGreeter.btnCopyClick(Sender: TObject);
begin
  Clipboard.AsText := memScript.Lines.Text;
  lblPaths.Caption := 'Script copied to the clipboard.';
end;

procedure TfrmGreeter.btnCloseClick(Sender: TObject);
begin
  Close;
end;

end.
