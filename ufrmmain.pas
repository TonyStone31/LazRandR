unit ufrmMain;

{ LazRandR main window.

  The layout canvas is created at runtime into pnlCanvasHost: it is a custom
  control that lives in this project rather than in an installed package, so
  putting it directly on the form would stop the LFM opening in the Lazarus
  designer. Everything else on the form is a real streamed component. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Math, LCLType,
  BCPanel, BCButton, BCLabel, BCTypes,
  uDisplayTypes, uXRandR, uTouch, uProfiles, uTheme, uLayoutCanvas,
  ufrmScriptPreview, ufrmIdentify;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    btnIdentify: TBCButton;
    btnLoadProfile: TBCButton;
    btnMapSelected: TBCButton;
    btnPreview: TBCButton;
    btnReload: TBCButton;
    btnRevert: TBCButton;
    btnSaveProfile: TBCButton;
    btnToggleDevice: TBCButton;
    btnApply: TBCButton;
    cboProfile: TComboBox;
    cboRate: TComboBox;
    cboResolution: TComboBox;
    cboRotation: TComboBox;
    cboTouchDevice: TComboBox;
    cboTouchOutput: TComboBox;
    chkAutostart: TCheckBox;
    chkEnabled: TCheckBox;
    chkPrimary: TCheckBox;
    lblAutoHint: TBCLabel;
    lblDevCap: TBCLabel;
    lblMapCap: TBCLabel;
    lblOutName: TBCLabel;
    lblRateCap: TBCLabel;
    lblResCap: TBCLabel;
    lblRotCap: TBCLabel;
    lblSecDisplay: TBCLabel;
    lblSecSave: TBCLabel;
    lblSecTouch: TBCLabel;
    lblStatus: TBCLabel;
    lblSubtitle: TBCLabel;
    lblTitle: TBCLabel;
    lblTouchInfo: TBCLabel;
    pnlCanvasHost: TPanel;
    pnlFooter: TBCPanel;
    pnlHeader: TBCPanel;
    pnlSide: TBCPanel;
    timHotplug: TTimer;
    timIdentify: TTimer;
    procedure btnApplyClick(Sender: TObject);
    procedure btnIdentifyClick(Sender: TObject);
    procedure btnLoadProfileClick(Sender: TObject);
    procedure btnMapSelectedClick(Sender: TObject);
    procedure btnPreviewClick(Sender: TObject);
    procedure btnReloadClick(Sender: TObject);
    procedure btnRevertClick(Sender: TObject);
    procedure btnSaveProfileClick(Sender: TObject);
    procedure btnToggleDeviceClick(Sender: TObject);
    procedure cboRateChange(Sender: TObject);
    procedure cboResolutionChange(Sender: TObject);
    procedure cboRotationChange(Sender: TObject);
    procedure cboTouchDeviceChange(Sender: TObject);
    procedure cboTouchOutputChange(Sender: TObject);
    procedure chkAutostartChange(Sender: TObject);
    procedure chkEnabledChange(Sender: TObject);
    procedure chkPrimaryChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure timHotplugTimer(Sender: TObject);
    procedure timIdentifyTimer(Sender: TObject);
  private
    FXR: TXRandR;
    FTouch: TTouchManager;
    FStore: TProfileStore;
    FCanvas: TLayoutCanvas;
    FLoading: boolean;          // guards combo OnChange while repopulating
    FTopology: string;          // last seen hardware signature, for hotplug
    FIdentForms: array of TfrmIdentify;

    procedure ApplyTheming;
    procedure ReloadAll;
    procedure RefreshProfileList;
    procedure PopulateSide;
    procedure PopulateTouchPanel;
    procedure UpdateToggleCaption;
    procedure UpdateStatus;
    procedure SetStatus(const S: string; Col: TColor);
    function SelectedOutput: integer;

    procedure CanvasChanged(Sender: TObject);
    procedure CanvasCommit(Sender: TObject);
    procedure CanvasSelect(Sender: TObject; OutputIndex: integer);

    procedure DestroyIdentifiers;
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'LazRandR — Display & Touch';
  Color := clWindowBg;
  Font.Name := UIFont;

  FXR := TXRandR.Create;
  FTouch := TTouchManager.Create(FXR);
  FStore := TProfileStore.Create(FXR, FTouch);
  FStore.EnsureDirs;

  FCanvas := TLayoutCanvas.Create(Self);
  FCanvas.Parent := pnlCanvasHost;
  FCanvas.Align := alClient;
  FCanvas.OnChanged := @CanvasChanged;
  FCanvas.OnCommit := @CanvasCommit;
  FCanvas.OnSelect := @CanvasSelect;

  { The BGRAControls panels and our canvas all repaint on every resize;
    without this the window tears while being dragged. }
  DoubleBuffered := True;
  pnlCanvasHost.DoubleBuffered := True;
  pnlSide.DoubleBuffered := True;
  pnlHeader.DoubleBuffered := True;
  pnlFooter.DoubleBuffered := True;

  ApplyTheming;

  cboRotation.Items.Clear;
  cboRotation.Items.Add(RotationCaptions[rotNormal]);
  cboRotation.Items.Add(RotationCaptions[rotRight]);
  cboRotation.Items.Add(RotationCaptions[rotInverted]);
  cboRotation.Items.Add(RotationCaptions[rotLeft]);

  ReloadAll;

  chkAutostart.Checked := FStore.AutostartInstalled;
  RefreshProfileList;

  FTopology := FXR.TopologyFingerprint;
  timHotplug.Enabled := True;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  DestroyIdentifiers;
  FStore.Free;
  FTouch.Free;
  FXR.Free;
end;

procedure TfrmMain.ApplyTheming;
begin
  SkinPanel(pnlHeader, pkHeader);
  SkinPanel(pnlFooter, pkHeader);
  SkinPanel(pnlSide, pkSurface);
  SkinPlainPanel(pnlCanvasHost, pkWindow);

  SkinLabel(lblTitle, clTextBright, 25, True, bcaLeftCenter, clSurfaceAlt);
  SkinLabel(lblSubtitle, clTextDim, 13, False, bcaLeftCenter, clSurfaceAlt);
  SkinLabel(lblStatus, clTextDim, 14, False, bcaRightCenter, clSurfaceAlt);

  SkinLabel(lblSecDisplay, clAccentHi, 12, True, bcaLeftCenter, clSurface);
  SkinLabel(lblSecTouch, clTouchHi, 12, True, bcaLeftCenter, clSurface);
  SkinLabel(lblSecSave, clWarn, 12, True, bcaLeftCenter, clSurface);

  SkinLabel(lblOutName, clTextBright, 19, True, bcaLeftCenter, clSurface);
  SkinLabel(lblResCap, clTextDim, 12, False, bcaLeftCenter, clSurface);
  SkinLabel(lblRateCap, clTextDim, 12, False, bcaLeftCenter, clSurface);
  SkinLabel(lblRotCap, clTextDim, 12, False, bcaLeftCenter, clSurface);
  SkinLabel(lblDevCap, clTextDim, 12, False, bcaLeftCenter, clSurface);
  SkinLabel(lblMapCap, clTextDim, 12, False, bcaLeftCenter, clSurface);
  SkinLabel(lblTouchInfo, clTextDim, 12, False, bcaLeftTop, clSurface);
  SkinLabel(lblAutoHint, clTextFaint, 11, False, bcaLeftTop, clSurface);
  lblTouchInfo.FontEx.WordBreak := True;
  lblAutoHint.FontEx.WordBreak := True;
  lblTouchInfo.FontEx.SingleLine := False;
  lblAutoHint.FontEx.SingleLine := False;

  SkinButton(btnApply, bkPrimary, 16);
  SkinButton(btnRevert, bkGhost);
  SkinButton(btnIdentify, bkNeutral);
  SkinButton(btnReload, bkNeutral);
  SkinButton(btnPreview, bkNeutral);
  SkinButton(btnMapSelected, bkNeutral, 13);
  SkinButton(btnToggleDevice, bkNeutral, 13);
  SkinButton(btnSaveProfile, bkNeutral, 13);
  SkinButton(btnLoadProfile, bkNeutral, 13);

  SkinCombo(cboResolution);
  SkinCombo(cboRate);
  SkinCombo(cboRotation);
  SkinCombo(cboTouchDevice);
  SkinCombo(cboTouchOutput);
  SkinCombo(cboProfile);

  SkinCheck(chkEnabled);
  SkinCheck(chkPrimary);
  SkinCheck(chkAutostart);
end;

procedure TfrmMain.SetStatus(const S: string; Col: TColor);
begin
  lblStatus.Caption := S;
  lblStatus.FontEx.Color := Col;
end;

procedure TfrmMain.ReloadAll;
var
  i: integer;
begin
  if not FXR.Refresh then
  begin
    SetStatus('xrandr failed — ' + FXR.LastError, clDanger);
    Exit;
  end;
  FXR.RefreshProviders;
  FTouch.Refresh;

  FCanvas.Attach(FXR, FTouch);

  { Land on something useful rather than an empty side panel. }
  if FCanvas.SelectedIndex < 0 then
  begin
    if FXR.ConnectedOutputCount > 0 then
      for i := 0 to High(FXR.Outputs) do
        if FXR.Outputs[i].Connected and FXR.Outputs[i].DesiredEnabled then
        begin
          FCanvas.SelectOutput(i);
          Break;
        end;
  end;

  PopulateSide;
  PopulateTouchPanel;
  UpdateStatus;
end;

function TfrmMain.SelectedOutput: integer;
begin
  Result := FCanvas.SelectedIndex;
  if (Result < 0) or (Result > High(FXR.Outputs)) then
    Result := -1;
end;

procedure TfrmMain.PopulateSide;
var
  Idx, i, SelRes, SelRate: integer;
  ResStr, RStr: string;
  Seen: TStringList;
begin
  Idx := SelectedOutput;
  FLoading := True;
  try
    cboResolution.Items.Clear;
    cboRate.Items.Clear;

    if Idx < 0 then
    begin
      lblOutName.Caption := 'No display selected';
      cboResolution.Enabled := False;
      cboRate.Enabled := False;
      cboRotation.Enabled := False;
      chkEnabled.Enabled := False;
      chkPrimary.Enabled := False;
      chkEnabled.Checked := False;
      chkPrimary.Checked := False;
      Exit;
    end;

    lblOutName.Caption := FXR.Outputs[Idx].Name;
    cboResolution.Enabled := True;
    cboRate.Enabled := True;
    cboRotation.Enabled := True;
    chkEnabled.Enabled := True;
    chkPrimary.Enabled := True;

    { Distinct resolutions, in the order xrandr lists them (highest first). }
    Seen := TStringList.Create;
    try
      Seen.Sorted := True;
      Seen.Duplicates := dupIgnore;
      SelRes := -1;
      for i := 0 to High(FXR.Outputs[Idx].Modes) do
      begin
        ResStr := Format('%d x %d', [FXR.Outputs[Idx].Modes[i].Width,
          FXR.Outputs[Idx].Modes[i].Height]);
        if Seen.IndexOf(ResStr) >= 0 then Continue;
        Seen.Add(ResStr);
        cboResolution.Items.AddObject(ResStr,
          TObject(PtrInt(FXR.Outputs[Idx].Modes[i].Width * 100000 +
                         FXR.Outputs[Idx].Modes[i].Height)));
        if (FXR.Outputs[Idx].Modes[i].Width = FXR.Outputs[Idx].DesiredModeW) and
           (FXR.Outputs[Idx].Modes[i].Height = FXR.Outputs[Idx].DesiredModeH) then
          SelRes := cboResolution.Items.Count - 1;
      end;
      cboResolution.ItemIndex := SelRes;
    finally
      Seen.Free;
    end;

    { Rates available at the chosen resolution. }
    SelRate := -1;
    for i := 0 to High(FXR.Outputs[Idx].Modes) do
    begin
      if (FXR.Outputs[Idx].Modes[i].Width <> FXR.Outputs[Idx].DesiredModeW) or
         (FXR.Outputs[Idx].Modes[i].Height <> FXR.Outputs[Idx].DesiredModeH) then
        Continue;
      RStr := RateToStr(FXR.Outputs[Idx].Modes[i].Rate) + ' Hz';
      if FXR.Outputs[Idx].Modes[i].IsPreferred then
        RStr := RStr + '  (preferred)';
      cboRate.Items.Add(RStr);
      if SameRate(FXR.Outputs[Idx].Modes[i].Rate, FXR.Outputs[Idx].DesiredRate) then
        SelRate := cboRate.Items.Count - 1;
    end;
    cboRate.ItemIndex := SelRate;

    cboRotation.ItemIndex := Ord(FXR.Outputs[Idx].DesiredRotation);
    chkEnabled.Checked := FXR.Outputs[Idx].DesiredEnabled;
    chkPrimary.Checked := FXR.Outputs[Idx].DesiredPrimary;
  finally
    FLoading := False;
  end;
end;

procedure TfrmMain.PopulateTouchPanel;
var
  i, SelDev: integer;
  Cap: string;
begin
  FLoading := True;
  try
    SelDev := cboTouchDevice.ItemIndex;
    cboTouchDevice.Items.Clear;

    for i := 0 to High(FTouch.Devices) do
      if FTouch.Devices[i].Enabled then
        cboTouchDevice.Items.Add(Format('%s  [%s]',
          [FTouch.Devices[i].Name, DeviceKindNames[FTouch.Devices[i].Kind]]))
      else
        cboTouchDevice.Items.Add(Format('%s  [%s — OFF]',
          [FTouch.Devices[i].Name, DeviceKindNames[FTouch.Devices[i].Kind]]));

    if Length(FTouch.Devices) = 0 then
    begin
      lblTouchInfo.Caption :=
        'No touch or stylus devices found. Plug the panel in and press Reload.';
      cboTouchDevice.Enabled := False;
      cboTouchOutput.Enabled := False;
      btnMapSelected.Enabled := False;
      btnToggleDevice.Enabled := False;
    end
    else
    begin
      if Length(FTouch.Devices) = 1 then
        Cap := '1 device found.'
      else
        Cap := Format('%d devices found.', [Length(FTouch.Devices)]);
      lblTouchInfo.Caption := Cap +
        ' Confining a device stops it reporting across the whole desktop.';
      cboTouchDevice.Enabled := True;
      cboTouchOutput.Enabled := True;
      btnMapSelected.Enabled := True;
      btnToggleDevice.Enabled := True;
      if (SelDev < 0) or (SelDev >= cboTouchDevice.Items.Count) then
        SelDev := 0;
      cboTouchDevice.ItemIndex := SelDev;
    end;
    UpdateToggleCaption;

    { Target list: whole desktop, then every connected output. }
    cboTouchOutput.Items.Clear;
    cboTouchOutput.Items.Add('Whole desktop (unconfined)');
    for i := 0 to High(FXR.Outputs) do
      if FXR.Outputs[i].Connected then
        cboTouchOutput.Items.Add(FXR.Outputs[i].Name);

    cboTouchOutput.ItemIndex := 0;
    if (cboTouchDevice.ItemIndex >= 0) and
       (cboTouchDevice.ItemIndex <= High(FTouch.Devices)) then
    begin
      i := cboTouchOutput.Items.IndexOf(
        FTouch.Devices[cboTouchDevice.ItemIndex].DesiredOutput);
      if i > 0 then cboTouchOutput.ItemIndex := i;
    end;
  finally
    FLoading := False;
  end;
end;

procedure TfrmMain.UpdateToggleCaption;
var
  D: integer;
begin
  D := cboTouchDevice.ItemIndex;
  if (D < 0) or (D > High(FTouch.Devices)) then
  begin
    btnToggleDevice.Caption := 'Disable';
    Exit;
  end;
  if FTouch.Devices[D].Enabled then
    btnToggleDevice.Caption := 'Disable'
  else
    btnToggleDevice.Caption := 'Enable';
end;

procedure TfrmMain.btnToggleDeviceClick(Sender: TObject);
var
  D: integer;
  Output: string;
begin
  D := cboTouchDevice.ItemIndex;
  if (D < 0) or (D > High(FTouch.Devices)) then Exit;

  if not FTouch.SetDeviceEnabled(D, not FTouch.Devices[D].Enabled, Output) then
  begin
    MessageDlg('xinput failed', Output, mtError, [mbOK], 0);
    Exit;
  end;

  if FTouch.Devices[D].Enabled then
    SetStatus('Enabled ' + FTouch.Devices[D].Name, clOkay)
  else
    SetStatus('Disabled ' + FTouch.Devices[D].Name, clWarn);

  FTouch.Refresh;
  PopulateTouchPanel;
  FCanvas.Invalidate;
end;

procedure TfrmMain.timHotplugTimer(Sender: TObject);
var
  Now_: string;
begin
  Now_ := FXR.TopologyFingerprint;
  if (Now_ = '') or (Now_ = FTopology) then Exit;
  FTopology := Now_;

  { Never throw away edits the user has not applied yet -- just tell them. }
  if FXR.HasPendingChanges or FTouch.HasPendingChanges then
  begin
    SetStatus('Hardware changed — press Reload to pick it up', clWarn);
    Exit;
  end;

  ReloadAll;
  SetStatus('Hardware change detected — reloaded', clOkay);
end;

procedure TfrmMain.UpdateStatus;
var
  W, H: integer;
  Sink: string;
begin
  FXR.DesiredScreenSize(W, H);

  if FXR.GrowthBlocked and ((W > FXR.ScreenW) or (H > FXR.ScreenH)) then
  begin
    { Tell them now rather than after they have spent a minute arranging it. }
    SetStatus(Format('Layout needs %d × %d — X screen is capped at %d × %d ' +
      'and cannot grow (see Apply for the fix)',
      [W, H, FXR.ScreenW, FXR.ScreenH]), clDanger);
  end
  else if FXR.HasPendingChanges or FTouch.HasPendingChanges then
  begin
    SetStatus(Format('Unapplied changes  ·  virtual desktop %d × %d', [W, H]), clWarn);
  end
  else
  begin
    Sink := FXR.FindSinkProvider;
    if Sink <> '' then
      SetStatus(Format('%d displays  ·  %d × %d  ·  PRIME sink "%s" available',
        [FXR.ConnectedOutputCount, W, H, Sink]), clTextDim)
    else
      SetStatus(Format('%d displays  ·  virtual desktop %d × %d',
        [FXR.ConnectedOutputCount, W, H]), clTextDim);
  end;
end;

procedure TfrmMain.CanvasChanged(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TfrmMain.CanvasCommit(Sender: TObject);
begin
  { A drag can switch a screen on or off via the inactive tray, so the side
    panel has to catch up -- but only once the drag is over, not on every
    mouse move. }
  PopulateSide;
  UpdateStatus;
end;

procedure TfrmMain.CanvasSelect(Sender: TObject; OutputIndex: integer);
begin
  PopulateSide;
end;

{ ---- side panel events ---- }

procedure TfrmMain.cboResolutionChange(Sender: TObject);
var
  Idx, Packed_, i: integer;
  BestRate: double;
begin
  if FLoading then Exit;
  Idx := SelectedOutput;
  if (Idx < 0) or (cboResolution.ItemIndex < 0) then Exit;

  Packed_ := PtrInt(cboResolution.Items.Objects[cboResolution.ItemIndex]);
  FXR.Outputs[Idx].DesiredModeW := Packed_ div 100000;
  FXR.Outputs[Idx].DesiredModeH := Packed_ mod 100000;

  { Pick the fastest rate this resolution actually offers. }
  BestRate := 0;
  for i := 0 to High(FXR.Outputs[Idx].Modes) do
    if (FXR.Outputs[Idx].Modes[i].Width = FXR.Outputs[Idx].DesiredModeW) and
       (FXR.Outputs[Idx].Modes[i].Height = FXR.Outputs[Idx].DesiredModeH) and
       (FXR.Outputs[Idx].Modes[i].Rate > BestRate) then
      BestRate := FXR.Outputs[Idx].Modes[i].Rate;
  if BestRate > 0 then
    FXR.Outputs[Idx].DesiredRate := BestRate;

  PopulateSide;
  FCanvas.Rebuild;
  UpdateStatus;
end;

procedure TfrmMain.cboRateChange(Sender: TObject);
var
  Idx, i, n: integer;
begin
  if FLoading then Exit;
  Idx := SelectedOutput;
  if (Idx < 0) or (cboRate.ItemIndex < 0) then Exit;

  n := -1;
  for i := 0 to High(FXR.Outputs[Idx].Modes) do
  begin
    if (FXR.Outputs[Idx].Modes[i].Width <> FXR.Outputs[Idx].DesiredModeW) or
       (FXR.Outputs[Idx].Modes[i].Height <> FXR.Outputs[Idx].DesiredModeH) then
      Continue;
    Inc(n);
    if n = cboRate.ItemIndex then
    begin
      FXR.Outputs[Idx].DesiredRate := FXR.Outputs[Idx].Modes[i].Rate;
      Break;
    end;
  end;
  UpdateStatus;
end;

procedure TfrmMain.cboRotationChange(Sender: TObject);
var
  Idx: integer;
begin
  if FLoading then Exit;
  Idx := SelectedOutput;
  if (Idx < 0) or (cboRotation.ItemIndex < 0) then Exit;
  FXR.Outputs[Idx].DesiredRotation := TRotation(cboRotation.ItemIndex);
  FCanvas.Rebuild;
  UpdateStatus;
end;

procedure TfrmMain.chkEnabledChange(Sender: TObject);
var
  Idx: integer;
begin
  if FLoading then Exit;
  Idx := SelectedOutput;
  if Idx < 0 then Exit;
  FXR.Outputs[Idx].DesiredEnabled := chkEnabled.Checked;
  FCanvas.Rebuild;
  UpdateStatus;
end;

procedure TfrmMain.chkPrimaryChange(Sender: TObject);
var
  Idx, i: integer;
begin
  if FLoading then Exit;
  Idx := SelectedOutput;
  if Idx < 0 then Exit;

  { Exactly one output can be primary. }
  if chkPrimary.Checked then
    for i := 0 to High(FXR.Outputs) do
      FXR.Outputs[i].DesiredPrimary := (i = Idx)
  else
    FXR.Outputs[Idx].DesiredPrimary := False;

  FCanvas.Rebuild;
  UpdateStatus;
end;

{ ---- touch events ---- }

procedure TfrmMain.cboTouchDeviceChange(Sender: TObject);
var
  D, i: integer;
begin
  if FLoading then Exit;
  D := cboTouchDevice.ItemIndex;
  if (D < 0) or (D > High(FTouch.Devices)) then Exit;

  FLoading := True;
  try
    cboTouchOutput.ItemIndex := 0;
    i := cboTouchOutput.Items.IndexOf(FTouch.Devices[D].DesiredOutput);
    if i > 0 then cboTouchOutput.ItemIndex := i;
  finally
    FLoading := False;
  end;
  UpdateToggleCaption;
end;

procedure TfrmMain.cboTouchOutputChange(Sender: TObject);
var
  D: integer;
begin
  if FLoading then Exit;
  D := cboTouchDevice.ItemIndex;
  if (D < 0) or (D > High(FTouch.Devices)) then Exit;

  if cboTouchOutput.ItemIndex <= 0 then
    FTouch.Devices[D].DesiredOutput := ''
  else
    FTouch.Devices[D].DesiredOutput := cboTouchOutput.Items[cboTouchOutput.ItemIndex];

  FCanvas.Invalidate;
  UpdateStatus;
end;

procedure TfrmMain.btnMapSelectedClick(Sender: TObject);
var
  Idx, D, i: integer;
begin
  Idx := SelectedOutput;
  D := cboTouchDevice.ItemIndex;
  if Idx < 0 then
  begin
    MessageDlg('LazRandR', 'Select a display on the canvas first.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  if (D < 0) or (D > High(FTouch.Devices)) then Exit;

  FTouch.Devices[D].DesiredOutput := FXR.Outputs[Idx].Name;
  FLoading := True;
  try
    i := cboTouchOutput.Items.IndexOf(FXR.Outputs[Idx].Name);
    if i >= 0 then cboTouchOutput.ItemIndex := i;
  finally
    FLoading := False;
  end;
  FCanvas.Invalidate;
  UpdateStatus;
end;

{ ---- footer events ---- }

procedure TfrmMain.btnApplyClick(Sender: TObject);
var
  Output, Err: string;
  OK: boolean;
begin
  Screen.Cursor := crHourGlass;
  try
    OK := FXR.Apply(Output);
    if not OK then
    begin
      SetStatus('Apply failed', clDanger);
      if (Pos('RRSetScreenSize', Output) > 0) or
         (Pos('BadMatch', Output) > 0) then
        MessageDlg('Cannot resize the X screen',
          'xrandr could not grow the virtual desktop to fit this layout.' +
          LineEnding + LineEnding +
          'The NVIDIA driver fixes the maximum X screen size when X starts, ' +
          'so a layout that needs a larger desktop than the current one is ' +
          'refused at runtime -- even though every output supports it.' +
          LineEnding + LineEnding +
          'Fix: add a large enough Virtual line to the Display subsection of ' +
          'the Screen section in /etc/X11/xorg.conf, then restart X. For ' +
          'example:' + LineEnding + LineEnding +
          '    SubSection "Display"' + LineEnding +
          '        Depth 24' + LineEnding +
          '        Virtual 8760 2160' + LineEnding +
          '    EndSubSection' + LineEnding + LineEnding +
          'Raw error:' + LineEnding + Output,
          mtError, [mbOK], 0)
      else
        MessageDlg('xrandr failed', Output, mtError, [mbOK], 0);
      Exit;
    end;

    { Geometry moved, so every confined device needs its matrix recomputed
      against the new screen size before it means anything. }
    FXR.Refresh;
    FTouch.ApplyAll(Output);

    FXR.Refresh;
    FTouch.Refresh;
    FCanvas.Attach(FXR, FTouch);
    PopulateSide;
    PopulateTouchPanel;

    { Keep the replay script in step with what is now on screen. }
    FStore.WriteScript(Err, False, '', '');

    UpdateStatus;
    SetStatus('Applied', clOkay);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TfrmMain.btnRevertClick(Sender: TObject);
begin
  FXR.RevertDesired;
  FTouch.ResolveCurrentMapping;
  FCanvas.Rebuild;
  PopulateSide;
  PopulateTouchPanel;
  UpdateStatus;
end;

procedure TfrmMain.btnReloadClick(Sender: TObject);
begin
  ReloadAll;
  SetStatus('Reloaded from X server', clTextDim);
end;

procedure TfrmMain.btnPreviewClick(Sender: TObject);
var
  L: TStringList;
  F: TfrmScriptPreview;
begin
  L := TStringList.Create;
  try
    FStore.BuildScript(L, False, '', '');
    F := TfrmScriptPreview.Create(Self);
    try
      F.SetScript(L.Text, FStore.ScriptPath);
      F.ShowModal;
    finally
      F.Free;
    end;
  finally
    L.Free;
  end;
end;

procedure TfrmMain.btnIdentifyClick(Sender: TObject);
var
  i, n, LW, LH: integer;
  F: TfrmIdentify;
begin
  DestroyIdentifiers;

  n := 0;
  for i := 0 to High(FXR.Outputs) do
  begin
    if not FXR.Outputs[i].Active then Continue;
    LW := FXR.Outputs[i].LogicalW;
    LH := FXR.Outputs[i].LogicalH;

    F := TfrmIdentify.Create(nil);
    F.Configure(IntToStr(FXR.DisplayOrdinal(i)), FXR.Outputs[i].Name,
      Format('%d × %d', [LW, LH]),
      FXR.Outputs[i].X, FXR.Outputs[i].Y, LW, LH);
    F.Show;

    SetLength(FIdentForms, n + 1);
    FIdentForms[n] := F;
    Inc(n);
  end;

  timIdentify.Enabled := n > 0;
end;

procedure TfrmMain.timIdentifyTimer(Sender: TObject);
begin
  timIdentify.Enabled := False;
  DestroyIdentifiers;
end;

procedure TfrmMain.DestroyIdentifiers;
var
  i: integer;
begin
  for i := 0 to High(FIdentForms) do
    if FIdentForms[i] <> nil then
    begin
      FIdentForms[i].Close;
      FIdentForms[i].Free;
      FIdentForms[i] := nil;
    end;
  SetLength(FIdentForms, 0);
end;

{ ---- persistence events ---- }

procedure TfrmMain.RefreshProfileList;
var
  Keep: string;
begin
  Keep := cboProfile.Text;
  FStore.ListProfiles(cboProfile.Items);
  cboProfile.Text := Keep;
end;

procedure TfrmMain.btnSaveProfileClick(Sender: TObject);
var
  ProfName, Err: string;
begin
  ProfName := Trim(cboProfile.Text);
  if ProfName = '' then
    ProfName := InputBox('Save profile', 'Name for this layout:', 'default');
  ProfName := Trim(ProfName);
  if ProfName = '' then Exit;

  if not FStore.SaveProfile(ProfName, Err) then
  begin
    MessageDlg('Save failed', Err, mtError, [mbOK], 0);
    Exit;
  end;

  if not FStore.WriteScript(Err, False, '', '') then
  begin
    MessageDlg('Script write failed', Err, mtError, [mbOK], 0);
    Exit;
  end;

  RefreshProfileList;
  cboProfile.Text := Name;
  SetStatus('Saved profile "' + Name + '" and replay script', clOkay);
end;

procedure TfrmMain.btnLoadProfileClick(Sender: TObject);
var
  ProfName, Err: string;
begin
  ProfName := Trim(cboProfile.Text);
  if ProfName = '' then Exit;

  if not FStore.LoadProfile(ProfName, Err) then
  begin
    MessageDlg('Load failed', Err, mtError, [mbOK], 0);
    Exit;
  end;

  FCanvas.Rebuild;
  PopulateSide;
  PopulateTouchPanel;
  UpdateStatus;
  SetStatus('Loaded "' + Name + '" — press Apply to activate', clWarn);
end;

procedure TfrmMain.chkAutostartChange(Sender: TObject);
var
  Err: string;
begin
  if FLoading then Exit;

  if chkAutostart.Checked then
  begin
    if not FStore.WriteScript(Err, False, '', '') then
    begin
      MessageDlg('Script write failed', Err, mtError, [mbOK], 0);
      chkAutostart.Checked := False;
      Exit;
    end;
    if not FStore.InstallAutostart(Err) then
    begin
      MessageDlg('Autostart failed', Err, mtError, [mbOK], 0);
      chkAutostart.Checked := False;
      Exit;
    end;
    SetStatus('Will re-apply at login', clOkay);
  end
  else
  begin
    FStore.RemoveAutostart(Err);
    SetStatus('Login re-apply disabled', clTextDim);
  end;
end;

end.
