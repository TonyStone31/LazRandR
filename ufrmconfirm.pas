unit ufrmConfirm;

{ "Keep these settings?" with a countdown.

  A display change can leave you looking at a black screen, a mode the panel
  cannot sync, or a primary output that no longer exists -- at which point
  the tool that caused it is unreachable and the only way out is a TTY. So
  every geometry change is provisional: it reverts on its own unless someone
  confirms, from this machine, that the result is actually visible. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, ExtCtrls,
  BCPanel, BCButton, BCLabel, BCTypes, uTheme;

type

  { TfrmConfirm }

  TfrmConfirm = class(TForm)
    btnKeep: TBCButton;
    btnRevert: TBCButton;
    lblCountdown: TBCLabel;
    lblDetail: TBCLabel;
    lblHeading: TBCLabel;
    pnlBody: TBCPanel;
    timTick: TTimer;
    procedure btnKeepClick(Sender: TObject);
    procedure btnRevertClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure timTickTimer(Sender: TObject);
  private
    FRemaining: integer;
    procedure Redraw;
  public
    { Centre on Pref (normally the main window). Falls back to Safe -- the
      primary output -- when Pref's centre is not on any active screen, since
      a change can move or kill the screen the app was sitting on and an
      unreachable confirmation prompt is worse than none. }
    function RunOn(const Pref, Safe: TRect; Seconds: integer): TModalResult;
  end;

implementation

{$R *.lfm}

procedure TfrmConfirm.FormCreate(Sender: TObject);
begin
  Color := clWindowBg;
  SkinPanel(pnlBody, pkRaised);
  pnlBody.Border.Style := bboSolid;
  pnlBody.Border.Color := clWarn;
  pnlBody.Border.Width := 2;
  pnlBody.Rounding.RoundX := 10;
  pnlBody.Rounding.RoundY := 10;

  SkinLabel(lblHeading, clTextBright, 21, True, bcaLeftCenter, clRaised);
  SkinLabel(lblDetail, clTextDim, 13, False, bcaLeftTop, clRaised);
  SkinLabel(lblCountdown, clWarn, 17, True, bcaLeftCenter, clRaised);
  lblDetail.FontEx.WordBreak := True;
  lblDetail.FontEx.SingleLine := False;

  SkinButton(btnKeep, bkPrimary, 16);
  SkinButton(btnRevert, bkDanger, 16);
end;

procedure TfrmConfirm.Redraw;
begin
  if FRemaining = 1 then
    lblCountdown.Caption := 'Reverting in 1 second'
  else
    lblCountdown.Caption := Format('Reverting in %d seconds', [FRemaining]);
end;

function TfrmConfirm.RunOn(const Pref, Safe: TRect; Seconds: integer): TModalResult;
var
  R: TRect;
begin
  FRemaining := Seconds;
  Redraw;

  lblDetail.Caption :=
    'If you can read this, the new layout is working. Nothing is saved ' +
    'until you confirm — if this window is not where you can see it, just ' +
    'wait and everything goes back to how it was.';

  R := Pref;
  if (R.Right - R.Left <= 0) or (R.Bottom - R.Top <= 0) then
    R := Safe;
  if (R.Right - R.Left > 0) and (R.Bottom - R.Top > 0) then
    SetBounds(R.Left + ((R.Right - R.Left) - Width) div 2,
              R.Top + ((R.Bottom - R.Top) - Height) div 2, Width, Height);

  timTick.Enabled := True;
  try
    Result := ShowModal;
  finally
    timTick.Enabled := False;
  end;
end;

procedure TfrmConfirm.timTickTimer(Sender: TObject);
begin
  Dec(FRemaining);
  if FRemaining <= 0 then
  begin
    timTick.Enabled := False;
    ModalResult := mrCancel;      // nobody confirmed -- put it back
    Exit;
  end;
  Redraw;
end;

procedure TfrmConfirm.btnKeepClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TfrmConfirm.btnRevertClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

end.
