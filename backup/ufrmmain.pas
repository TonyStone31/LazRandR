unit ufrmMain;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  Controls,
  Dialogs,
  Forms,
  Graphics,
  StdCtrls,
  SysUtils,
  ExtCtrls,
  Grids,
  StrUtils,
  Types,
  Process,
  FileUtil,
  DateUtils,
  BaseUnix,
  Math,
  Menus,
  ufrmScriptPreview,
  XRandrManager,
  uDrawingUtils;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnApply: TButton;
    btnReloadContainer: TButton;
    lblMessageAboutDisplays: TLabel;
    lstMonitors: TListBox;
    pnlMonitorContainer: TPanel;
    sgMonitorDetails: TStringGrid;
    procedure btnApplyClick(Sender: TObject);
    procedure tnReloadClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure lstMonitorsClick(Sender: TObject);
    procedure pnlDispArClick(Sender: TObject);
    procedure pnlDispArMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pnlDispArMouseEnter(Sender: TObject);
    procedure pnlDispArMouseLeave(Sender: TObject);
    procedure pnlDispArMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pnlDispArMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pnlDispArPaint(Sender: TObject);
    procedure sgMonitorDetailsSelectCell(Sender: TObject; aCol, aRow: integer; var CanSelect: boolean);
  private
    PanelsMoved: boolean;
    XRManager: TXRandrManager;
    procedure ShowScriptPreview;
    procedure FlashDisplayNumber(MonitorIndex: integer);
    procedure MonitorLabelClick(Sender: TObject);
    procedure MonitorBadgePaint(Sender: TObject);
    procedure MonitorPrimaryCheckboxClick(Sender: TObject);
    procedure MonitorRotationButtonClick(Sender: TObject);
    procedure MonitorResolutionComboChange(Sender: TObject);
    procedure MonitorRefreshRateComboChange(Sender: TObject);
    procedure MonitorPopupMenuClick(Sender: TObject);
    procedure BuildMonitorPopupMenu(MonitorIndex: integer);
  public
    procedure CreateMonitorPanel(const i: integer);
    procedure UpdateEdgeHighlights;
    procedure InitializeMonitorPanels;
    procedure mouseMVpanel(var pnl: TPanel; const Y: integer; const X: integer; var Shift: TShiftState);
    procedure PositionPanelsToMatchMonitors;
    procedure SnapHighLightsAll(enbld: boolean);

  end;

var
  Form1: TForm1;
  MonitorPanels: array of TPanel;
  MonitorPanelLabels: array of TLabel;
  MonitorLabelContainers: array of TPanel;
  MonitorPrimaryCheckboxes: array of TCheckBox;
  MonitorSplitModes: array of TSplitMode;
  MonitorRotationButtons: array of TButton;
  MonitorResolutionCombos: array of TComboBox;
  MonitorRefreshRateCombos: array of TComboBox;
  MonitorPopupMenus: array of TPopupMenu;
  MonitorBadgeRotations: array of integer; // Rotation angles: 0, 90, 180, 270

  // Maps Screen.Monitors[i] index to XRandrOutputs[j] index
  MonitorToXRandrMap: array of Integer;

  EdgeHighlightVisibleTop: array of boolean;
  EdgeHighlightVisibleBottom: array of boolean;
  EdgeHighlightVisibleLeft: array of boolean;
  EdgeHighlightVisibleRight: array of boolean;



  scaleLObyXY: double;
  scaleTocntrX, scaleTocntrY: integer;
  scaleTocntrXYi: integer;


  IsPanelMoving: boolean = False;
  IsPanelSnapped: boolean = False;
  mmDownSx, mmDownSy: integer;



const
  SNAP_THRESHOLD_PIXELS: integer = 12; // distance from other edge threshhold i guess

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  MonitorCoords: array of TPoint;
  i: integer;
begin
  PanelsMoved := False;
  btnApply.Enabled := False;

  // Configure string grid
  sgMonitorDetails.DefaultDrawing := True;
  sgMonitorDetails.Flat := True;
  sgMonitorDetails.GridLineWidth := 0;
  sgMonitorDetails.Options := sgMonitorDetails.Options + [goEditing, goAlwaysShowEditor];
  sgMonitorDetails.ColCount := 2;
  sgMonitorDetails.FixedCols := 0;

  // Set up columns for proper picklist support
  sgMonitorDetails.Columns.Clear;
  sgMonitorDetails.Columns.Add.Width := 200;  // Property column
  sgMonitorDetails.Columns.Add.Width := 300;  // Value column (100 wider as requested)

  // Initialize XRandR manager
  XRManager := TXRandrManager.Create;
  XRManager.ParseXRandrOutput;

  // Build monitor mapping
  SetLength(MonitorCoords, Screen.MonitorCount);
  for i := 0 to Screen.MonitorCount - 1 do
  begin
    MonitorCoords[i].X := Screen.Monitors[i].Left;
    MonitorCoords[i].Y := Screen.Monitors[i].Top;
  end;
  SetLength(MonitorToXRandrMap, Screen.MonitorCount);
  XRManager.BuildMonitorToXRandrMapping(MonitorCoords, MonitorToXRandrMap);

  InitializeMonitorPanels;
  PositionPanelsToMatchMonitors;

  // Show virtual monitor support message
  if not XRManager.DESupportsVirtualMonitors then
  begin
    lblMessageAboutDisplays.Caption :=
      'WARNING: Virtual monitor splits NOT supported on ' + XRManager.CurrentDE + '! ' +
      'Your DE ignores virtual monitors - windows won''t snap to them. ' +
      'Try i3, sway, bspwm, awesome, or qtile for working splits.';
    lblMessageAboutDisplays.Font.Color := clRed;
    lblMessageAboutDisplays.Visible := True;
  end
  else
  begin
    lblMessageAboutDisplays.Caption :=
      'Virtual monitor splits are supported on ' + XRManager.CurrentDE + '. You can split displays into 2x2, 3x3 grids.';
    lblMessageAboutDisplays.Font.Color := clGreen;
    lblMessageAboutDisplays.Visible := True;
  end;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  XRManager.Free;
end;

procedure TForm1.tnReloadClick(Sender: TObject);
begin
  PositionPanelsToMatchMonitors;
end;

procedure TForm1.lstMonitorsClick(Sender: TObject);
var
  MonitorIndex: integer;
  XRandrIndex: integer;
  i: integer;
begin
  if AnsiContainsText(lstMonitors.Items[lstMonitors.ItemIndex], 'fake') then exit;

  MonitorIndex := lstMonitors.ItemIndex;  // This is Screen.Monitors index
  XRandrIndex := MonitorToXRandrMap[MonitorIndex];  // Map to XRManager output index

  if (XRandrIndex >= 0) and (XRandrIndex < XRManager.GetOutputCount) then
  begin
    // Set up the grid - fixed rows for settings
    sgMonitorDetails.RowCount := 6;

    // Display current info
    sgMonitorDetails.Cells[0, 0] := 'Output';
    sgMonitorDetails.Cells[1, 0] := XRManager.GetOutput(XRandrIndex).Name;

    // Resolution (row 1)
    sgMonitorDetails.Cells[0, 1] := 'Resolution';
    sgMonitorDetails.Cells[1, 1] := XRManager.GetOutput(XRandrIndex).CurrentMode;

    // Refresh Rate (row 2)
    sgMonitorDetails.Cells[0, 2] := 'Refresh Rate';
    sgMonitorDetails.Cells[1, 2] := XRManager.GetOutput(XRandrIndex).CurrentRefreshRate;

    // Rotation (row 3)
    sgMonitorDetails.Cells[0, 3] := 'Rotation';
    sgMonitorDetails.Cells[1, 3] := XRManager.GetOutput(XRandrIndex).Rotation;

    // Position (row 4)
    sgMonitorDetails.Cells[0, 4] := 'Position';
    sgMonitorDetails.Cells[1, 4] :=
      IntToStr(XRManager.GetOutput(XRandrIndex).XPos) + 'x' + IntToStr(XRManager.GetOutput(XRandrIndex).YPos);

    // Primary status (row 5)
    sgMonitorDetails.Cells[0, 5] := 'Primary';
    if XRManager.GetOutput(XRandrIndex).Primary then
      sgMonitorDetails.Cells[1, 5] := 'Yes'
    else
      sgMonitorDetails.Cells[1, 5] := 'No';
  end;
end;

procedure TForm1.sgMonitorDetailsSelectCell(Sender: TObject; aCol, aRow: integer; var CanSelect: boolean);
var
  MonitorIndex: integer;
  XRandrIndex: integer;
  i: integer;
begin
  CanSelect := True;

  // Only set up picklists for column 1 (value column)
  if aCol <> 1 then exit;

  MonitorIndex := lstMonitors.ItemIndex;  // This is Screen.Monitors index
  if (MonitorIndex < 0) or (MonitorIndex >= Length(MonitorToXRandrMap)) then exit;

  XRandrIndex := MonitorToXRandrMap[MonitorIndex];  // Map to XRManager output index
  if (XRandrIndex < 0) or (XRandrIndex >= XRManager.GetOutputCount) then exit;

  // Clear previous picklist
  sgMonitorDetails.Columns[1].PickList.Clear;
  sgMonitorDetails.Columns[1].ButtonStyle := cbsAuto;

  // Set picklist based on row
  case aRow of
    1: // Resolution
    begin
      if XRManager.GetOutput(XRandrIndex).AvailableModes <> nil then
      begin
        for i := 0 to XRManager.GetOutput(XRandrIndex).AvailableModes.Count - 1 do
          sgMonitorDetails.Columns[1].PickList.Add(XRManager.GetOutput(XRandrIndex).AvailableModes[i]);
        if sgMonitorDetails.Columns[1].PickList.Count > 0 then
          sgMonitorDetails.Columns[1].ButtonStyle := cbsPickList;
      end;
    end;

    3: // Rotation
    begin
      sgMonitorDetails.Columns[1].PickList.Add('normal');
      sgMonitorDetails.Columns[1].PickList.Add('left');
      sgMonitorDetails.Columns[1].PickList.Add('right');
      sgMonitorDetails.Columns[1].PickList.Add('inverted');
      sgMonitorDetails.Columns[1].ButtonStyle := cbsPickList;
    end;
  end;
end;

procedure TForm1.pnlDispArClick(Sender: TObject);
var
  i: integer;
  pnl: TPanel;
begin
  pnl := Sender as TPanel;

  for i := 0 to Length(MonitorPanels) - 1 do
  begin
    //find the display clicked and set listindex
    if pnl.Handle = MonitorPanels[i].Handle then
    begin
      lstMonitors.ItemIndex := i;
      lstMonitorsClick(Sender);
      exit;
    end;
  end;
end;

procedure TForm1.pnlDispArMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  pnl: TPanel;
begin
  pnl := Sender as TPanel;
  IsPanelMoving := True;
  mmDownSx := x;
  mmDownSy := y;
  screen.Cursor := crSizeAll;
end;

procedure TForm1.pnlDispArMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  pnl: TPanel;
  i: integer;
begin
  SnapHighLightsAll(False);
  screen.Cursor := crSizeAll;

  if IsPanelMoving then
  begin
    PanelsMoved := True;
    btnApply.Enabled := True;
    IsPanelMoving := False;
  end;
end;

procedure TForm1.pnlDispArMouseEnter(Sender: TObject);
var
  pnl: TPanel;
begin
  pnl := Sender as TPanel;
  pnl.BevelInner := bvRaised;
  pnl.BringToFront;
  screen.Cursor := crSizeAll;
end;

procedure TForm1.pnlDispArMouseLeave(Sender: TObject);
var
  pnl: TPanel;
begin
  pnl := Sender as TPanel;
  pnl.BevelInner := bvNone;
  screen.Cursor := crDefault;
end;

procedure TForm1.pnlDispArMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  pnl: TPanel;
  i: integer;
  SnapsTH, SnapsTL, SnapsBH, SnapsBL, SnapsLH, SnapsLL, SnapsRH, SnapsRL: array of integer;

  snapRect: TRect;
begin
  pnl := Sender as TPanel;

  SnapHighLightsAll(False);

  mouseMVpanel(pnl, Y, X, Shift);
  snapRect := pnl.BoundsRect;


  SetLength(SnapsTH, Length(MonitorPanels));
  SetLength(SnapsTL, Length(MonitorPanels));
  SetLength(SnapsBH, Length(MonitorPanels));
  SetLength(SnapsBL, Length(MonitorPanels));
  SetLength(SnapsLH, Length(MonitorPanels));
  SetLength(SnapsLL, Length(MonitorPanels));
  SetLength(SnapsRH, Length(MonitorPanels));
  SetLength(SnapsRL, Length(MonitorPanels));

  if (Shift = [ssLeft]) and (IsPanelMoving) then
  begin
    // establish all ranges where snapping needs to happen
    for i := 0 to Length(MonitorPanels) - 1 do
    begin
      SnapsTH[i] := MonitorPanels[i].BoundsRect.Top + SNAP_THRESHOLD_PIXELS;
      SnapsTL[i] := MonitorPanels[i].BoundsRect.Top - SNAP_THRESHOLD_PIXELS;
      SnapsBH[i] := MonitorPanels[i].BoundsRect.Bottom + SNAP_THRESHOLD_PIXELS;
      SnapsBL[i] := MonitorPanels[i].BoundsRect.Bottom - SNAP_THRESHOLD_PIXELS;
      SnapsLH[i] := MonitorPanels[i].BoundsRect.Left + SNAP_THRESHOLD_PIXELS;
      SnapsLL[i] := MonitorPanels[i].BoundsRect.Left - SNAP_THRESHOLD_PIXELS;
      SnapsRH[i] := MonitorPanels[i].BoundsRect.Right + SNAP_THRESHOLD_PIXELS;
      SnapsRL[i] := MonitorPanels[i].BoundsRect.Right - SNAP_THRESHOLD_PIXELS;
    end;

    for i := 0 to Length(MonitorPanels) - 1 do
    begin
      // dont want it to try to snap to itself
      if pnl = MonitorPanels[i] then
      begin
        Continue;
      end;

      // try to snap a TOP to a TOP
      if (pnl.BoundsRect.Top < SnapsTH[i]) and (pnl.BoundsRect.Top > SnapsTL[i]) then
      begin
        snapRect.Top := MonitorPanels[i].Top;
        EdgeHighlightVisibleTop[i] := True;
      end;

      // try to snap a TOP to a BOTTOM
      if (pnl.BoundsRect.Top < SnapsBH[i]) and (pnl.BoundsRect.Top > SnapsBL[i]) then
      begin
        snapRect.Top := MonitorPanels[i].BoundsRect.Bottom;
        EdgeHighlightVisibleBottom[i] := True;
      end;

      // try to snap to a BOTTOM to a TOP
      if (pnl.BoundsRect.Bottom < SnapsTH[i]) and (pnl.BoundsRect.Bottom > SnapsTL[i]) then
      begin
        snapRect.Top := MonitorPanels[i].Top - pnl.Height;
        EdgeHighlightVisibleTop[i] := True;
      end;

      // try to snap a BOTTOM to a BOTTOM
      if (pnl.BoundsRect.Bottom < SnapsBH[i]) and (pnl.BoundsRect.Bottom > SnapsBL[i]) then
      begin
        snapRect.Top := MonitorPanels[i].BoundsRect.Bottom - pnl.Height;
        EdgeHighlightVisibleBottom[i] := True;
      end;

      // try to snap a LEFT to a LEFT
      if (pnl.BoundsRect.Left < SnapsLH[i]) and (pnl.BoundsRect.Left > SnapsLL[i]) then
      begin
        snapRect.Left := MonitorPanels[i].BoundsRect.Left;
        EdgeHighlightVisibleLeft[i] := True;
      end;

      // try to snap a LEFT to a Right
      if (pnl.BoundsRect.Left < SnapsRH[i]) and (pnl.BoundsRect.Left > SnapsRL[i]) then
      begin
        snapRect.Left := MonitorPanels[i].BoundsRect.Right;
        EdgeHighlightVisibleRight[i] := True;
      end;

      // try to snap a RIGHT to a LEFT
      if (pnl.BoundsRect.Right < SnapsLH[i]) and (pnl.BoundsRect.Right > SnapsLL[i]) then
      begin
        snapRect.Left := MonitorPanels[i].BoundsRect.left - pnl.Width;
        EdgeHighlightVisibleLeft[i] := True;
      end;

      // try to snap a RIGHT to a RIGHT
      if (pnl.BoundsRect.Right < SnapsRH[i]) and (pnl.BoundsRect.Right > SnapsRL[i]) then
      begin
        snapRect.Left := MonitorPanels[i].BoundsRect.Right - pnl.Width;
        EdgeHighlightVisibleRight[i] := True;
      end;

    end;

  end;
  pnl.SetBounds(snapRect.Left, snapRect.Top, pnl.Width, pnl.Height);

  UpdateEdgeHighlights;

end;

procedure TForm1.pnlDispArPaint(Sender: TObject);
var
  pnl: TPanel;
  i: integer;
  SplitMode: TSplitMode;
  MidX, MidY: integer;
  ThirdX, ThirdY, TwoThirdX, TwoThirdY: integer;
begin
  pnl := Sender as TPanel;

  // Find which monitor panel this is
  for i := 0 to Length(MonitorPanels) - 1 do
  begin
    if MonitorPanels[i] = pnl then
    begin
      SplitMode := MonitorSplitModes[i];

      with pnl.Canvas do
      begin
        Brush.Style := bsClear;
        Pen.Style := psSolid;
        Pen.Mode := pmCopy;

        // Draw split lines if there's a split mode active
        if SplitMode <> smNone then
        begin
          Pen.Color := clYellow;
          Pen.Width := 3;

          case SplitMode of
            smHorizontal:
            begin
              MidY := pnl.Height div 2;
              MoveTo(0, MidY);
              LineTo(pnl.Width, MidY);
            end;

            smVertical:
            begin
              MidX := pnl.Width div 2;
              MoveTo(MidX, 0);
              LineTo(MidX, pnl.Height);
            end;

            sm2x2:
            begin
              MidX := pnl.Width div 2;
              MidY := pnl.Height div 2;
              MoveTo(0, MidY);
              LineTo(pnl.Width, MidY);
              MoveTo(MidX, 0);
              LineTo(MidX, pnl.Height);
            end;

            sm3x3:
            begin
              ThirdX := pnl.Width div 3;
              TwoThirdX := (pnl.Width * 2) div 3;
              ThirdY := pnl.Height div 3;
              TwoThirdY := (pnl.Height * 2) div 3;

              MoveTo(ThirdX, 0);
              LineTo(ThirdX, pnl.Height);
              MoveTo(TwoThirdX, 0);
              LineTo(TwoThirdX, pnl.Height);

              MoveTo(0, ThirdY);
              LineTo(pnl.Width, ThirdY);
              MoveTo(0, TwoThirdY);
              LineTo(pnl.Width, TwoThirdY);
            end;
          end;
        end;

        // Draw snap highlights
        Pen.Color := clRed;
        Pen.Width := 5;

        if EdgeHighlightVisibleTop[i] then
        begin
          MoveTo(0, 2);
          LineTo(pnl.Width, 2);
        end;

        if EdgeHighlightVisibleBottom[i] then
        begin
          MoveTo(0, pnl.Height - 3);
          LineTo(pnl.Width, pnl.Height - 3);
        end;

        if EdgeHighlightVisibleLeft[i] then
        begin
          MoveTo(2, 0);
          LineTo(2, pnl.Height);
        end;

        if EdgeHighlightVisibleRight[i] then
        begin
          MoveTo(pnl.Width - 3, 0);
          LineTo(pnl.Width - 3, pnl.Height);
        end;
      end;

      Break;
    end;
  end;
end;

procedure TForm1.CreateMonitorPanel(const i: integer);
begin
  //make the panel that represents a display
  MonitorPanels[i] := TPanel.Create(Form1);
  MonitorPanels[i].OnPaint := @pnlDispArPaint;
  MonitorPanels[i].OnClick := @pnlDispArClick;
  MonitorPanels[i].OnMouseEnter := @pnlDispArMouseEnter;
  MonitorPanels[i].OnMouseLeave := @pnlDispArMouseLeave;
  MonitorPanels[i].OnMouseDown := @pnlDispArMouseDown;
  MonitorPanels[i].OnMouseUp := @pnlDispArMouseUp;
  MonitorPanels[i].OnMouseMove := @pnlDispArMouseMove;
  MonitorPanels[i].BevelColor := clWhite;
  MonitorPanels[i].BorderStyle := bsSingle;
  MonitorPanels[i].DoubleBuffered := False; // Disable double buffering for direct canvas access
  MonitorPanels[i].Parent := pnlMonitorContainer;

  // Create sexy modern badge container for the display number
  MonitorLabelContainers[i] := TPanel.Create(MonitorPanels[i]);
  MonitorLabelContainers[i].Parent := MonitorPanels[i];
  MonitorLabelContainers[i].BevelOuter := bvNone;
  MonitorLabelContainers[i].Color := clBlack; // Background will be painted
  MonitorLabelContainers[i].Width := 70;
  MonitorLabelContainers[i].Height := 70;
  MonitorLabelContainers[i].Cursor := crHandPoint;
  MonitorLabelContainers[i].Tag := i;
  MonitorLabelContainers[i].OnClick := @MonitorLabelClick;
  MonitorLabelContainers[i].OnPaint := @MonitorBadgePaint;
  MonitorLabelContainers[i].ParentBackground := False;

  // Create the label inside the container (now hidden, number is drawn in badge)
  MonitorPanelLabels[i] := TLabel.Create(MonitorLabelContainers[i]);
  MonitorPanelLabels[i].Caption := IntToStr(i);
  MonitorPanelLabels[i].Parent := MonitorLabelContainers[i];
  MonitorPanelLabels[i].Visible := False; // Hide it, number is now part of badge drawing

  // Add primary checkbox at bottom of panel
  MonitorPrimaryCheckboxes[i] := TCheckBox.Create(Form1);
  MonitorPrimaryCheckboxes[i].Parent := MonitorPanels[i];
  MonitorPrimaryCheckboxes[i].Caption := 'Primary';
  MonitorPrimaryCheckboxes[i].Font.Size := 11;
  MonitorPrimaryCheckboxes[i].Font.Style := [fsBold];
  MonitorPrimaryCheckboxes[i].Tag := i;
  MonitorPrimaryCheckboxes[i].Left := 5;
  MonitorPrimaryCheckboxes[i].Top := MonitorPanels[i].Height - 30;
  MonitorPrimaryCheckboxes[i].AutoSize := True;
  MonitorPrimaryCheckboxes[i].ParentColor := False;
  MonitorPrimaryCheckboxes[i].Color := clDefault;
  MonitorPrimaryCheckboxes[i].OnClick := @MonitorPrimaryCheckboxClick;

  // Add rotation button at bottom right
  MonitorRotationButtons[i] := TButton.Create(Form1);
  MonitorRotationButtons[i].Parent := MonitorPanels[i];
  MonitorRotationButtons[i].Caption := '↑▭↑';
  MonitorRotationButtons[i].Font.Size := 12;
  MonitorRotationButtons[i].Tag := i;
  MonitorRotationButtons[i].Width := 60;
  MonitorRotationButtons[i].Height := 30;
  MonitorRotationButtons[i].Left := MonitorPanels[i].Width - MonitorRotationButtons[i].Width - 5;
  MonitorRotationButtons[i].Top := MonitorPanels[i].Height - 35;
  MonitorRotationButtons[i].OnClick := @MonitorRotationButtonClick;
  MonitorRotationButtons[i].Hint := 'Rotation: Normal (Landscape)';
  MonitorRotationButtons[i].ShowHint := True;

  // Add resolution combobox at top right
  MonitorResolutionCombos[i] := TComboBox.Create(Form1);
  MonitorResolutionCombos[i].Parent := MonitorPanels[i];
  MonitorResolutionCombos[i].Font.Size := 8;
  MonitorResolutionCombos[i].Tag := i;
  MonitorResolutionCombos[i].Width := 130;
  MonitorResolutionCombos[i].Height := 25;
  MonitorResolutionCombos[i].Left := MonitorPanels[i].Width - MonitorResolutionCombos[i].Width - 5;
  MonitorResolutionCombos[i].Top := 5;
  MonitorResolutionCombos[i].Style := csDropDownList;
  MonitorResolutionCombos[i].OnChange := @MonitorResolutionComboChange;

  // Add refresh rate combobox under the badge (centered)
  MonitorRefreshRateCombos[i] := TComboBox.Create(Form1);
  MonitorRefreshRateCombos[i].Parent := MonitorPanels[i];
  MonitorRefreshRateCombos[i].Font.Size := 8;
  MonitorRefreshRateCombos[i].Tag := i;
  MonitorRefreshRateCombos[i].Width := 100;
  MonitorRefreshRateCombos[i].Height := 25;
  MonitorRefreshRateCombos[i].Left := (MonitorPanels[i].Width - MonitorRefreshRateCombos[i].Width) div 2;
  MonitorRefreshRateCombos[i].Top := (MonitorPanels[i].Height div 2) + 40;
  MonitorRefreshRateCombos[i].Style := csDropDownList;
  MonitorRefreshRateCombos[i].OnChange := @MonitorRefreshRateComboChange;

  // Create popup menu for this monitor (for split options)
  MonitorPopupMenus[i] := TPopupMenu.Create(Form1);
  MonitorPanels[i].PopupMenu := MonitorPopupMenus[i];
  MonitorLabelContainers[i].PopupMenu := MonitorPopupMenus[i];

  // Initialize snap highlight flags
  EdgeHighlightVisibleTop[i] := False;
  EdgeHighlightVisibleBottom[i] := False;
  EdgeHighlightVisibleLeft[i] := False;
  EdgeHighlightVisibleRight[i] := False;
end;

procedure TForm1.UpdateEdgeHighlights;
var
  i: integer;
begin
  // Just invalidate all panels to trigger repaint
  for i := 0 to Length(MonitorPanels) - 1 do
    MonitorPanels[i].Invalidate;
end;

procedure TForm1.mouseMVpanel(var pnl: TPanel; const Y: integer; const X: integer; var Shift: TShiftState);
var
  mvRect: TRect;
begin
  if (Shift = [ssLeft]) and (IsPanelMoving) then
  begin
    mvRect.Left := pnl.Left + (x - mmDownSx);
    mvRect.Top := pnl.Top + (y - mmDownSy);
    pnl.SetBounds(mvRect.Left, mvRect.Top, pnl.Width, pnl.Height);
  end;

end;

procedure TForm1.InitializeMonitorPanels;
var
  i: integer;
begin
  SetLength(MonitorPanels, Screen.MonitorCount);
  SetLength(MonitorPanelLabels, screen.MonitorCount);
  SetLength(MonitorLabelContainers, screen.MonitorCount);
  SetLength(MonitorPrimaryCheckboxes, screen.MonitorCount);
  SetLength(MonitorSplitModes, screen.MonitorCount);
  SetLength(MonitorRotationButtons, screen.MonitorCount);
  SetLength(MonitorResolutionCombos, screen.MonitorCount);
  SetLength(MonitorRefreshRateCombos, screen.MonitorCount);
  SetLength(MonitorPopupMenus, screen.MonitorCount);
  SetLength(MonitorBadgeRotations, screen.MonitorCount);

  SetLength(EdgeHighlightVisibleTop, screen.MonitorCount);
  SetLength(EdgeHighlightVisibleBottom, screen.MonitorCount);
  SetLength(EdgeHighlightVisibleLeft, screen.MonitorCount);
  SetLength(EdgeHighlightVisibleRight, screen.MonitorCount);



  for i := 0 to Screen.MonitorCount - 1 do
  begin
    if screen.Monitors[i].Primary then
      lstMonitors.Items.Add('Display ' + IntToStr(screen.Monitors[i].MonitorNum) + ' (Primary)')
    else
      lstMonitors.Items.Add('Display ' + IntToStr(screen.Monitors[i].MonitorNum)
        );

    // Initialize split mode to none
    MonitorSplitModes[i] := smNone;
    MonitorBadgeRotations[i] := 0; // Normal rotation

    CreateMonitorPanel(i);
  end;
end;

procedure TForm1.PositionPanelsToMatchMonitors;
var
  highR: integer;
  i, j: integer;
begin
  highR := 0;
  for i := 0 to screen.MonitorCount - 1 do
  begin
    if Screen.Monitors[i].BoundsRect.Right > highR then
      highR := Screen.Monitors[i].WorkareaRect.Right;
  end;

  scaleLObyXY := pnlMonitorContainer.Width / int64(highR);
  scaleTocntrX := pnlMonitorContainer.Width div 4;
  scaleTocntrY := pnlMonitorContainer.Height div 4;

  for i := 0 to Screen.MonitorCount - 1 do
  begin

    MonitorPanels[i].Left := (trunc(Screen.Monitors[i].Left * scaleLObyXY) div 2) + scaleTocntrX;
    MonitorPanels[i].Top := (trunc(Screen.Monitors[i].Top * scaleLObyXY) div 2) + scaleTocntrY;

    MonitorPanels[i].Width := (trunc(Screen.Monitors[i].Width * scaleLObyXY) div 2);
    MonitorPanels[i].Height := (trunc(Screen.Monitors[i].Height * scaleLObyXY) div 2);

    // Center the badge container perfectly
    MonitorLabelContainers[i].Left := (MonitorPanels[i].Width - MonitorLabelContainers[i].Width) div 2;
    MonitorLabelContainers[i].Top := (MonitorPanels[i].Height - MonitorLabelContainers[i].Height) div 2;

    // Position the primary checkbox at the bottom left
    MonitorPrimaryCheckboxes[i].Top := MonitorPanels[i].Height - 30;

    // Set primary checkbox based on monitor primary status using the mapping
    if (MonitorToXRandrMap[i] >= 0) and (MonitorToXRandrMap[i] < XRManager.GetOutputCount) and
       XRManager.GetOutput(MonitorToXRandrMap[i]).Primary then
      MonitorPrimaryCheckboxes[i].Checked := True;

    // Position rotation button at bottom right
    MonitorRotationButtons[i].Left := MonitorPanels[i].Width - MonitorRotationButtons[i].Width - 5;
    MonitorRotationButtons[i].Top := MonitorPanels[i].Height - 35;

    // Position resolution combo at top right
    MonitorResolutionCombos[i].Left := MonitorPanels[i].Width - MonitorResolutionCombos[i].Width - 5;

    // Position refresh rate combo under badge (centered)
    MonitorRefreshRateCombos[i].Left := (MonitorPanels[i].Width - MonitorRefreshRateCombos[i].Width) div 2;
    MonitorRefreshRateCombos[i].Top := (MonitorPanels[i].Height div 2) + 40;

    // Populate resolution and refresh rate combos from XRManager
    if (MonitorToXRandrMap[i] >= 0) and (MonitorToXRandrMap[i] < XRManager.GetOutputCount) then
    begin
      // Populate resolutions
      MonitorResolutionCombos[i].Items.Clear;
      if XRManager.GetOutput(MonitorToXRandrMap[i]).AvailableModes <> nil then
      begin
        MonitorResolutionCombos[i].Items.Assign(XRManager.GetOutput(MonitorToXRandrMap[i]).AvailableModes);
        // Set current mode as selected - ensure it's selected even if ItemIndex was already set
        if (XRManager.GetOutput(MonitorToXRandrMap[i]).CurrentMode <> '') and
           (MonitorResolutionCombos[i].Items.Count > 0) then
        begin
          MonitorResolutionCombos[i].ItemIndex := MonitorResolutionCombos[i].Items.IndexOf(
            XRManager.GetOutput(MonitorToXRandrMap[i]).CurrentMode);
          // If not found, select first item
          if MonitorResolutionCombos[i].ItemIndex < 0 then
            MonitorResolutionCombos[i].ItemIndex := 0;
        end;
      end;

      // Populate refresh rates for current resolution
      MonitorRefreshRateCombos[i].Items.Clear;
      if (XRManager.GetOutput(MonitorToXRandrMap[i]).CurrentMode <> '') and
         (XRManager.GetOutput(MonitorToXRandrMap[i]).AvailableRefreshRates <> nil) then
      begin
        // Get refresh rates for current resolution
        for j := 0 to XRManager.GetOutput(MonitorToXRandrMap[i]).AvailableRefreshRates.Count - 1 do
        begin
          if Pos(XRManager.GetOutput(MonitorToXRandrMap[i]).CurrentMode + ':',
                 XRManager.GetOutput(MonitorToXRandrMap[i]).AvailableRefreshRates[j]) = 1 then
          begin
            MonitorRefreshRateCombos[i].Items.Add(
              Copy(XRManager.GetOutput(MonitorToXRandrMap[i]).AvailableRefreshRates[j],
                   Length(XRManager.GetOutput(MonitorToXRandrMap[i]).CurrentMode) + 2,
                   999));
          end;
        end;

        // Select current refresh rate if available
        if XRManager.GetOutput(MonitorToXRandrMap[i]).CurrentRefreshRate <> '' then
          MonitorRefreshRateCombos[i].ItemIndex :=
            MonitorRefreshRateCombos[i].Items.IndexOf(XRManager.GetOutput(MonitorToXRandrMap[i]).CurrentRefreshRate)
        else if MonitorRefreshRateCombos[i].Items.Count > 0 then
          MonitorRefreshRateCombos[i].ItemIndex := 0;
      end
      else
      begin
        // Fallback if no refresh rates parsed
        MonitorRefreshRateCombos[i].Items.Add('60.0 Hz');
        MonitorRefreshRateCombos[i].ItemIndex := 0;
      end;

      // Set rotation button and badge rotation with orientation symbols and arrows
      case XRManager.GetOutput(MonitorToXRandrMap[i]).Rotation of
        'normal':
        begin
          MonitorRotationButtons[i].Caption := '↑▭↑';  // Normal landscape
          MonitorRotationButtons[i].Hint := 'Rotation: Normal (Landscape)';
          MonitorBadgeRotations[i] := 0;
        end;
        'left':
        begin
          MonitorRotationButtons[i].Caption := '←▯←';  // Portrait left
          MonitorRotationButtons[i].Hint := 'Rotation: Left (Portrait ←)';
          MonitorBadgeRotations[i] := 90;
        end;
        'right':
        begin
          MonitorRotationButtons[i].Caption := '→▯→';  // Portrait right
          MonitorRotationButtons[i].Hint := 'Rotation: Right (Portrait →)';
          MonitorBadgeRotations[i] := 270;
        end;
        'inverted':
        begin
          MonitorRotationButtons[i].Caption := '↓▭↓';  // Upside down landscape
          MonitorRotationButtons[i].Hint := 'Rotation: Inverted (Upside Down)';
          MonitorBadgeRotations[i] := 180;
        end;
      else
        MonitorRotationButtons[i].Caption := '↑▭↑';
        MonitorRotationButtons[i].Hint := 'Rotation: Normal (Landscape)';
        MonitorBadgeRotations[i] := 0;
      end;

      // Build popup menu
      BuildMonitorPopupMenu(i);
    end;

  end;
end;

procedure TForm1.SnapHighLightsAll(enbld: boolean);
var
  i: integer;
begin
  for i := 0 to Length(MonitorPanels) - 1 do
  begin
    EdgeHighlightVisibleTop[i] := enbld;
    EdgeHighlightVisibleBottom[i] := enbld;
    EdgeHighlightVisibleLeft[i] := enbld;
    EdgeHighlightVisibleRight[i] := enbld;
  end;
end;


procedure TForm1.btnApplyClick(Sender: TObject);
begin
  ShowScriptPreview;
end;

procedure TForm1.ShowScriptPreview;
var
  PreviewForm: TfrmScriptPreview;
  ApplyScriptPath, SafetyScriptPath: string;
  HasVirtualSplits: boolean;
  i: integer;
  Configs: array of TMonitorConfig;
  NewX, NewY: integer;
begin
  ApplyScriptPath := GetCurrentDir + '/xrandr_apply.sh';
  SafetyScriptPath := GetCurrentDir + '/SETMYMONITORS.sh';

  // Check if any monitors have virtual splits enabled
  HasVirtualSplits := False;
  for i := 0 to Length(MonitorSplitModes) - 1 do
  begin
    if MonitorSplitModes[i] <> smNone then
    begin
      HasVirtualSplits := True;
      Break;
    end;
  end;

  // Build monitor config array from current panel positions and UI state
  SetLength(Configs, Length(MonitorPanels));
  for i := 0 to Length(MonitorPanels) - 1 do
  begin
    if (MonitorToXRandrMap[i] >= 0) and (MonitorToXRandrMap[i] < XRManager.GetOutputCount) then
    begin
      Configs[i].OutputName := XRManager.GetOutput(MonitorToXRandrMap[i]).Name;
      Configs[i].Width := XRManager.GetOutput(MonitorToXRandrMap[i]).Width;
      Configs[i].Height := XRManager.GetOutput(MonitorToXRandrMap[i]).Height;
      Configs[i].IsPrimary := MonitorPrimaryCheckboxes[i].Checked;  // Use checkbox state
      Configs[i].SplitMode := MonitorSplitModes[i];

      // Convert panel position back to monitor coordinates
      NewX := Round((MonitorPanels[i].Left - scaleTocntrX) * 2 / scaleLObyXY);
      NewY := Round((MonitorPanels[i].Top - scaleTocntrY) * 2 / scaleLObyXY);
      Configs[i].XPos := NewX;
      Configs[i].YPos := NewY;
    end;
  end;

  // Generate both scripts using XRManager
  XRManager.GenerateBothScripts(ApplyScriptPath, SafetyScriptPath, Configs);

  // Create and show preview form
  PreviewForm := TfrmScriptPreview.Create(nil);
  try
    PreviewForm.SetupPreview(ApplyScriptPath, SafetyScriptPath, XRManager.CurrentDE,
                             HasVirtualSplits, XRManager.DESupportsVirtualMonitors);

    if PreviewForm.ShowModal = mrOK then
    begin
      PreviewForm.ExecuteScripts;
      PanelsMoved := False;
      btnApply.Enabled := False;
    end;
  finally
    PreviewForm.Free;
  end;
end;

procedure TForm1.MonitorLabelClick(Sender: TObject);
var
  ctrl: TControl;
  MonitorIndex: integer;
begin
  if Sender is TControl then
  begin
    ctrl := Sender as TControl;
    MonitorIndex := ctrl.Tag;
    FlashDisplayNumber(MonitorIndex);
  end;
end;

procedure TForm1.FlashDisplayNumber(MonitorIndex: integer);
var
  FlashForm: TForm;
  FlashLabel: TLabel;
  MonitorRect: TRect;
  StartTime: TDateTime;
  ElapsedSeconds: integer;
begin
  if (MonitorIndex < 0) or (MonitorIndex >= Screen.MonitorCount) then
    Exit;

  MonitorRect := Screen.Monitors[MonitorIndex].BoundsRect;

  FlashForm := TForm.Create(nil);
  try
    FlashForm.BorderStyle := bsNone;
    FlashForm.FormStyle := fsStayOnTop;
    FlashForm.Color := $00FF8C00; // Sexy orange/amber
    FlashForm.AlphaBlend := True;
    FlashForm.AlphaBlendValue := 220;
    FlashForm.Left := MonitorRect.Left + 20;
    FlashForm.Top := MonitorRect.Top + 20;
    FlashForm.Width := 300;
    FlashForm.Height := 300;

    FlashLabel := TLabel.Create(FlashForm);
    FlashLabel.Parent := FlashForm;
    FlashLabel.Caption := IntToStr(MonitorIndex);
    FlashLabel.Font.Size := 150;
    FlashLabel.Font.Style := [fsBold];
    FlashLabel.Font.Color := clWhite;
    FlashLabel.AutoSize := False;
    FlashLabel.Alignment := taCenter;
    FlashLabel.Layout := tlCenter;
    FlashLabel.Width := 300;
    FlashLabel.Height := 300;
    FlashLabel.Left := 0;
    FlashLabel.Top := 0;

    FlashForm.Show;
    Application.ProcessMessages;

    StartTime := Now;
    while SecondsBetween(Now, StartTime) < 3 do
    begin
      Application.ProcessMessages;
      Sleep(100);
    end;

  finally
    FlashForm.Free;
  end;
end;

procedure TForm1.MonitorBadgePaint(Sender: TObject);
var
  pnl: TPanel;
  MonitorIndex: integer;
begin
  pnl := Sender as TPanel;
  MonitorIndex := pnl.Tag;
  DrawMonitorBadge(pnl.Canvas, pnl.Width, pnl.Height, pnl.Parent.Color, MonitorBadgeRotations[MonitorIndex], MonitorIndex);
end;

procedure TForm1.MonitorPrimaryCheckboxClick(Sender: TObject);
var
  chk: TCheckBox;
  MonitorIndex: integer;
  i: integer;
begin
  chk := Sender as TCheckBox;
  MonitorIndex := chk.Tag;

  // Only one monitor can be primary - uncheck all others
  if chk.Checked then
  begin
    for i := 0 to Length(MonitorPrimaryCheckboxes) - 1 do
    begin
      if i <> MonitorIndex then
        MonitorPrimaryCheckboxes[i].Checked := False;
    end;
    PanelsMoved := True;
    btnApply.Enabled := True;
  end;
end;

procedure TForm1.MonitorRotationButtonClick(Sender: TObject);
var
  btn: TButton;
  MonitorIndex: integer;
  TempDim: integer;
begin
  btn := Sender as TButton;
  MonitorIndex := btn.Tag;

  // Cycle through rotations: normal -> left -> inverted -> right -> normal
  if Pos('Normal', btn.Hint) > 0 then
  begin
    btn.Caption := '←▯←';  // Portrait left
    btn.Hint := 'Rotation: Left (Portrait ←)';
    MonitorBadgeRotations[MonitorIndex] := 90;
    // Rotate panel 90 degrees left - swap width and height
    TempDim := MonitorPanels[MonitorIndex].Width;
    MonitorPanels[MonitorIndex].Width := MonitorPanels[MonitorIndex].Height;
    MonitorPanels[MonitorIndex].Height := TempDim;
  end
  else if Pos('Left', btn.Hint) > 0 then
  begin
    btn.Caption := '↓▭↓';  // Landscape upside down
    btn.Hint := 'Rotation: Inverted (Upside Down)';
    MonitorBadgeRotations[MonitorIndex] := 180;
    // Rotate 180 from left - swap back to landscape
    TempDim := MonitorPanels[MonitorIndex].Width;
    MonitorPanels[MonitorIndex].Width := MonitorPanels[MonitorIndex].Height;
    MonitorPanels[MonitorIndex].Height := TempDim;
  end
  else if Pos('Inverted', btn.Hint) > 0 then
  begin
    btn.Caption := '→▯→';  // Portrait right
    btn.Hint := 'Rotation: Right (Portrait →)';
    MonitorBadgeRotations[MonitorIndex] := 270;
    // Rotate 90 degrees right - swap to portrait
    TempDim := MonitorPanels[MonitorIndex].Width;
    MonitorPanels[MonitorIndex].Width := MonitorPanels[MonitorIndex].Height;
    MonitorPanels[MonitorIndex].Height := TempDim;
  end
  else  // Right
  begin
    btn.Caption := '↑▭↑';  // Normal landscape
    btn.Hint := 'Rotation: Normal (Landscape)';
    MonitorBadgeRotations[MonitorIndex] := 0;
    // Rotate back to normal - swap back to landscape
    TempDim := MonitorPanels[MonitorIndex].Width;
    MonitorPanels[MonitorIndex].Width := MonitorPanels[MonitorIndex].Height;
    MonitorPanels[MonitorIndex].Height := TempDim;
  end;

  // Reposition child controls after rotation
  MonitorLabelContainers[MonitorIndex].Left := (MonitorPanels[MonitorIndex].Width - MonitorLabelContainers[MonitorIndex].Width) div 2;
  MonitorLabelContainers[MonitorIndex].Top := (MonitorPanels[MonitorIndex].Height - MonitorLabelContainers[MonitorIndex].Height) div 2;
  MonitorPrimaryCheckboxes[MonitorIndex].Top := MonitorPanels[MonitorIndex].Height - 30;
  MonitorRotationButtons[MonitorIndex].Left := MonitorPanels[MonitorIndex].Width - MonitorRotationButtons[MonitorIndex].Width - 5;
  MonitorRotationButtons[MonitorIndex].Top := MonitorPanels[MonitorIndex].Height - 35;
  MonitorResolutionCombos[MonitorIndex].Left := MonitorPanels[MonitorIndex].Width - MonitorResolutionCombos[MonitorIndex].Width - 5;
  MonitorRefreshRateCombos[MonitorIndex].Left := (MonitorPanels[MonitorIndex].Width - MonitorRefreshRateCombos[MonitorIndex].Width) div 2;
  MonitorRefreshRateCombos[MonitorIndex].Top := (MonitorPanels[MonitorIndex].Height div 2) + 40;

  // Repaint badge with new rotation
  MonitorLabelContainers[MonitorIndex].Invalidate;

  MonitorPanels[MonitorIndex].Invalidate;
  PanelsMoved := True;
  btnApply.Enabled := True;
end;

procedure TForm1.MonitorResolutionComboChange(Sender: TObject);
var
  combo: TComboBox;
  MonitorIndex, XRandrIndex, i: integer;
  SelectedResolution, RateEntry, Rate: string;
begin
  combo := Sender as TComboBox;
  MonitorIndex := combo.Tag;
  XRandrIndex := MonitorToXRandrMap[MonitorIndex];

  // Update refresh rates based on selected resolution
  if (XRandrIndex >= 0) and (XRandrIndex < XRManager.GetOutputCount) and
     (combo.ItemIndex >= 0) then
  begin
    SelectedResolution := combo.Items[combo.ItemIndex];
    MonitorRefreshRateCombos[MonitorIndex].Items.Clear;

    // Find all refresh rates for this resolution
    if XRManager.GetOutput(XRandrIndex).AvailableRefreshRates <> nil then
    begin
      for i := 0 to XRManager.GetOutput(XRandrIndex).AvailableRefreshRates.Count - 1 do
      begin
        RateEntry := XRManager.GetOutput(XRandrIndex).AvailableRefreshRates[i];
        // Format is "resolution:rate Hz"
        if Pos(SelectedResolution + ':', RateEntry) = 1 then
        begin
          Rate := Copy(RateEntry, Length(SelectedResolution) + 2, Length(RateEntry));
          MonitorRefreshRateCombos[MonitorIndex].Items.Add(Rate);
        end;
      end;

      // Default to first refresh rate if available
      if MonitorRefreshRateCombos[MonitorIndex].Items.Count > 0 then
        MonitorRefreshRateCombos[MonitorIndex].ItemIndex := 0;
    end;
  end;

  PanelsMoved := True;
  btnApply.Enabled := True;
end;

procedure TForm1.MonitorRefreshRateComboChange(Sender: TObject);
var
  combo: TComboBox;
  MonitorIndex: integer;
begin
  combo := Sender as TComboBox;
  MonitorIndex := combo.Tag;

  PanelsMoved := True;
  btnApply.Enabled := True;
end;

procedure TForm1.BuildMonitorPopupMenu(MonitorIndex: integer);
var
  ParentMenuItem, MenuItem: TMenuItem;
begin
  MonitorPopupMenus[MonitorIndex].Items.Clear;

  // Create parent menu item for Virtual Display Split
  ParentMenuItem := TMenuItem.Create(MonitorPopupMenus[MonitorIndex]);
  ParentMenuItem.Caption := 'Virtual Display Split';
  MonitorPopupMenus[MonitorIndex].Items.Add(ParentMenuItem);

  // Split mode submenu items
  MenuItem := TMenuItem.Create(ParentMenuItem);
  MenuItem.Caption := 'No Split';
  MenuItem.Tag := MonitorIndex * 1000 + 0;
  MenuItem.OnClick := @MonitorPopupMenuClick;
  if MonitorSplitModes[MonitorIndex] = smNone then
    MenuItem.Checked := True;
  ParentMenuItem.Add(MenuItem);

  MenuItem := TMenuItem.Create(ParentMenuItem);
  MenuItem.Caption := 'Split Horizontal';
  MenuItem.Tag := MonitorIndex * 1000 + 1;
  MenuItem.OnClick := @MonitorPopupMenuClick;
  if MonitorSplitModes[MonitorIndex] = smHorizontal then
    MenuItem.Checked := True;
  ParentMenuItem.Add(MenuItem);

  MenuItem := TMenuItem.Create(ParentMenuItem);
  MenuItem.Caption := 'Split Vertical';
  MenuItem.Tag := MonitorIndex * 1000 + 2;
  MenuItem.OnClick := @MonitorPopupMenuClick;
  if MonitorSplitModes[MonitorIndex] = smVertical then
    MenuItem.Checked := True;
  ParentMenuItem.Add(MenuItem);

  MenuItem := TMenuItem.Create(ParentMenuItem);
  MenuItem.Caption := 'Split 2x2 Grid';
  MenuItem.Tag := MonitorIndex * 1000 + 3;
  MenuItem.OnClick := @MonitorPopupMenuClick;
  if MonitorSplitModes[MonitorIndex] = sm2x2 then
    MenuItem.Checked := True;
  ParentMenuItem.Add(MenuItem);

  MenuItem := TMenuItem.Create(ParentMenuItem);
  MenuItem.Caption := 'Split 3x3 Grid';
  MenuItem.Tag := MonitorIndex * 1000 + 4;
  MenuItem.OnClick := @MonitorPopupMenuClick;
  if MonitorSplitModes[MonitorIndex] = sm3x3 then
    MenuItem.Checked := True;
  ParentMenuItem.Add(MenuItem);
end;

procedure TForm1.MonitorPopupMenuClick(Sender: TObject);
var
  MenuItem: TMenuItem;
  MonitorIndex, ActionCode: integer;
begin
  MenuItem := Sender as TMenuItem;
  MonitorIndex := MenuItem.Tag div 1000;
  ActionCode := MenuItem.Tag mod 1000;

  // Split modes (0-4)
  case ActionCode of
    0: MonitorSplitModes[MonitorIndex] := smNone;
    1: MonitorSplitModes[MonitorIndex] := smHorizontal;
    2: MonitorSplitModes[MonitorIndex] := smVertical;
    3: MonitorSplitModes[MonitorIndex] := sm2x2;
    4: MonitorSplitModes[MonitorIndex] := sm3x3;
  end;

  // Rebuild menu to update checkmarks
  BuildMonitorPopupMenu(MonitorIndex);

  MonitorPanels[MonitorIndex].Invalidate;
  PanelsMoved := True;
  btnApply.Enabled := True;
end;

end.
