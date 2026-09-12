unit ufrmScriptPreview;

{ Shows the generated replay script before it is trusted with anything.

  The script is the whole persistence story, so being able to read it (and
  copy it somewhere else) matters more than it would for a throwaway dialog. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Clipbrd,
  BCPanel, BCButton, BCLabel, BCTypes, uTheme;

type

  { TfrmScriptPreview }

  TfrmScriptPreview = class(TForm)
    btnClose: TBCButton;
    btnCopy: TBCButton;
    btnSaveAs: TBCButton;
    dlgSave: TSaveDialog;
    lblHeading: TBCLabel;
    lblPath: TBCLabel;
    memScript: TMemo;
    pnlBottom: TBCPanel;
    pnlTop: TBCPanel;
    procedure btnCloseClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveAsClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  public
    procedure SetScript(const AText, APath: string);
  end;

implementation

{$R *.lfm}

{ TfrmScriptPreview }

procedure TfrmScriptPreview.FormCreate(Sender: TObject);
begin
  Color := clWindowBg;

  SkinPanel(pnlTop, pkHeader);
  SkinPanel(pnlBottom, pkHeader);
  SkinLabel(lblHeading, clTextBright, 18, True, bcaLeftCenter, clSurfaceAlt);
  SkinLabel(lblPath, clTextFaint, 12, False, bcaLeftCenter, clSurfaceAlt);

  SkinButton(btnCopy, bkNeutral);
  SkinButton(btnSaveAs, bkNeutral);
  SkinButton(btnClose, bkPrimary);

  memScript.Color := clWindowBg;
  memScript.Font.Name := 'Ubuntu Mono';
  memScript.Font.Height := 14;
  memScript.Font.Color := clText;
  memScript.ReadOnly := True;
  memScript.BorderStyle := bsNone;
end;

procedure TfrmScriptPreview.SetScript(const AText, APath: string);
begin
  memScript.Lines.Text := AText;
  lblPath.Caption := 'Written to ' + APath + ' when you Save or enable login re-apply';
end;

procedure TfrmScriptPreview.btnCopyClick(Sender: TObject);
begin
  Clipboard.AsText := memScript.Lines.Text;
  lblPath.Caption := 'Copied to clipboard';
end;

procedure TfrmScriptPreview.btnSaveAsClick(Sender: TObject);
begin
  dlgSave.FileName := 'lazrandr-layout.sh';
  if dlgSave.Execute then
  begin
    memScript.Lines.SaveToFile(dlgSave.FileName);
    lblPath.Caption := 'Saved to ' + dlgSave.FileName;
  end;
end;

procedure TfrmScriptPreview.btnCloseClick(Sender: TObject);
begin
  Close;
end;

end.
