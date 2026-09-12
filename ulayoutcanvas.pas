unit uLayoutCanvas;

{ The monitor layout canvas.

  A single custom-drawn control replaces the old one-TPanel-per-monitor
  arrangement. Everything is rendered into a BGRABitmap and blitted in one
  go, which is what makes the gradients, shadows and antialiased corners
  affordable, and it keeps drag behaviour free of child-control flicker. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, Types, Math, Forms,
  BGRABitmap, BGRABitmapTypes,
  uDisplayTypes, uXRandR, uTouch, uTheme;

type
  TTileEvent = procedure(Sender: TObject; OutputIndex: integer) of object;

  { TLayoutCanvas }

  TLayoutCanvas = class(TCustomControl)
  private
    FBmp: TBGRABitmap;
    FBack: TBGRABitmap;     // cached backdrop, redrawn only on resize
    FXR: TXRandR;
    FTouch: TTouchManager;
    FSelected: integer;
    FHot: integer;
    FDragging: boolean;
    FDragIndex: integer;
    FDragGrabX, FDragGrabY: integer;   // grab offset, in desktop px
    FScale: double;
    FOffX, FOffY: integer;             // canvas px offset of desktop origin
    FOriginX, FOriginY: integer;       // desktop coords at canvas origin
    FGuideV, FGuideH: integer;         // active snap guides, canvas px, -1 = none
    { Sticky snap state, per axis. }
    FSnapXOn, FSnapYOn: boolean;
    FSnapXVal, FSnapYVal: integer;     // desktop coord the tile is stuck to
    FSnapXGuide, FSnapYGuide: integer; // desktop coord to draw the guide at
    FOnChanged: TNotifyEvent;
    FOnCommit: TNotifyEvent;
    FOnSelect: TTileEvent;
    FDragFromTray: boolean;
    FTrayHot: boolean;      // cursor over the tray while dragging
    FShowTouchBadges: boolean;

    procedure ComputeScale(Force: boolean = False);
    function DesktopToCanvas(DX, DY: integer): TPoint;
    function CanvasToDesktop(CX, CY: integer): TPoint;
    procedure LogicalSize(Idx: integer; out W, H: integer);
    function TileRect(Idx: integer): TRect;
    function TileAt(CX, CY: integer): integer;
    procedure ApplySnapping(Idx: integer; var NX, NY: integer);
    procedure ClampToNeighbours(Idx: integer; var NX, NY: integer);
    function DisabledCount: integer;
    function EnabledCount: integer;
    function TrayVisible: boolean;
    function TrayBounds: TRect;
    function TraySlotRect(Slot: integer): TRect;
    function TrayIndexAt(CX, CY: integer): integer;
    procedure DrawTray;
    procedure DrawTrayTile(Idx, Slot: integer);
    function TileHasButtons(Idx: integer): boolean;
    function TileButtonRect(Idx, N: integer): TRect;
    function TileButtonAt(Idx, CX, CY: integer): integer;
    procedure DrawTileButtons(Idx: integer);
    function OutputHasTouch(Idx: integer): boolean;

    procedure DrawBackdrop;
    procedure DrawTile(Idx: integer);
    procedure DrawGuides;
    procedure DrawEmptyState;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Attach(AXR: TXRandR; ATouch: TTouchManager);
    procedure Rebuild;
    procedure FitToContent;
    procedure SelectOutput(Idx: integer);

    property SelectedIndex: integer read FSelected;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    { Fired once when a drag finishes, rather than on every mouse move, so
      the side panel can refresh without being rebuilt mid-drag. }
    property OnCommit: TNotifyEvent read FOnCommit write FOnCommit;
    property OnSelect: TTileEvent read FOnSelect write FOnSelect;
    property ShowTouchBadges: boolean read FShowTouchBadges write FShowTouchBadges;
  end;

implementation

const
  TilePad = 28;          // canvas px breathing room around the layout
  TileRadius = 11;

  { Snap thresholds are expressed in CANVAS pixels and converted to desktop
    pixels through the current zoom. A fixed desktop-pixel threshold felt
    strong on a small layout and useless once the canvas rescaled to fit a
    third screen, which is exactly when it mattered most.

    Acquire < Break gives hysteresis: once an edge is stuck it takes a
    deliberate pull to let go, so tiles stop jittering in and out of
    alignment while you are still dragging.

    Acquire is deliberately small. It is the distance the tile TELEPORTS when
    it grabs, so a large value reads as the thing jumping out from under the
    cursor. The holding power comes from Break instead, which costs nothing
    visually. }
  SnapAcquireCanvasPx = 9;
  SnapBreakCanvasPx = 32;

  { Leave slack around the arrangement instead of filling the canvas edge to
    edge. Tiles sized to the last pixel made dragging toward an outer edge
    fiddly, because there was nowhere to overshoot into. }
  LayoutFillFactor = 0.86;

  { How far a screen may be dragged beyond the others before it is stopped.
    Without this the layout's bounding box grows without limit, the canvas
    scales down to fit it, and every tile shrinks to nothing with no way
    back. A display arrangement has no meaning with a mile-wide gap anyway. }
  MaxGapDesktopPx = 600;

  { Never let a tile get too small to grab, whatever the layout does. }
  MinTileCanvasPx = 26;

  { The inactive tray.

    A disabled output still carries whatever position it last had, so drawn
    in desktop space it ends up underneath an active screen and invisible --
    you only discover it by dragging the others off it. A disabled output has
    no geometry on the X screen at all, so placing it in desktop space was
    wrong to begin with. It gets parked here instead. }
  TrayHeight = 96;
  TrayPad = 12;
  TrayTileW = 132;
  TrayTileH = 56;
  TrayGap = 10;
  TrayLabelH = 18;

  { Quick controls drawn on the selected tile. Rotating or marking a primary
    is most of what anyone does here, and reaching for the side panel for it
    breaks the flow of arranging screens. }
  TileBtnSize = 28;
  TileBtnGap = 6;
  TileBtnMinW = 150;      // tile must be at least this big to carry them
  TileBtnMinH = 92;

constructor TLayoutCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  FBmp := TBGRABitmap.Create(1, 1);
  FBack := TBGRABitmap.Create(1, 1);
  FSelected := -1;
  FHot := -1;
  FDragIndex := -1;
  FGuideV := -1;
  FGuideH := -1;
  FScale := 1;
  FShowTouchBadges := True;
end;

destructor TLayoutCanvas.Destroy;
begin
  FBmp.Free;
  FBack.Free;
  inherited Destroy;
end;

procedure TLayoutCanvas.Attach(AXR: TXRandR; ATouch: TTouchManager);
begin
  FXR := AXR;
  FTouch := ATouch;
  FSelected := -1;
  Rebuild;
end;

procedure TLayoutCanvas.Rebuild;
begin
  ComputeScale(True);
  Invalidate;
end;

procedure TLayoutCanvas.FitToContent;
begin
  ComputeScale(True);
  Invalidate;
end;

procedure TLayoutCanvas.SelectOutput(Idx: integer);
begin
  if FSelected = Idx then Exit;
  FSelected := Idx;
  Invalidate;
  if Assigned(FOnSelect) then FOnSelect(Self, Idx);
end;

procedure TLayoutCanvas.LogicalSize(Idx: integer; out W, H: integer);
begin
  if RotationIsPortrait(FXR.Outputs[Idx].DesiredRotation) then
  begin
    W := FXR.Outputs[Idx].DesiredModeH;
    H := FXR.Outputs[Idx].DesiredModeW;
  end
  else
  begin
    W := FXR.Outputs[Idx].DesiredModeW;
    H := FXR.Outputs[Idx].DesiredModeH;
  end;
  if W <= 0 then W := 1920;
  if H <= 0 then H := 1080;
end;

procedure TLayoutCanvas.ComputeScale(Force: boolean);
var
  i, LW, LH: integer;
  MinX, MinY, MaxX, MaxY: integer;
  Any: boolean;
  SX, SY: double;
  Ideal: double;
  BoxW, BoxH, AvailW, AvailH, TrayTop: integer;
  Overflows: boolean;
begin
  TrayTop := 0;
  if TrayVisible then TrayTop := TrayHeight;
  FOffX := 0;
  FOffY := 0;
  FOriginX := 0;
  FOriginY := 0;
  if FXR = nil then
  begin
    FScale := 1;
    Exit;
  end;

  MinX := MaxInt; MinY := MaxInt;
  MaxX := -MaxInt; MaxY := -MaxInt;
  Any := False;

  for i := 0 to High(FXR.Outputs) do
  begin
    if not FXR.Outputs[i].Connected then Continue;
    { Disabled screens live in the tray, not the layout, so they must not
      drag the bounding box around. }
    if not FXR.Outputs[i].DesiredEnabled then Continue;
    LogicalSize(i, LW, LH);
    Any := True;
    MinX := Min(MinX, FXR.Outputs[i].DesiredX);
    MinY := Min(MinY, FXR.Outputs[i].DesiredY);
    MaxX := Max(MaxX, FXR.Outputs[i].DesiredX + LW);
    MaxY := Max(MaxY, FXR.Outputs[i].DesiredY + LH);
  end;

  if not Any then
  begin
    if FScale <= 0 then FScale := 1;
    Exit;
  end;

  BoxW := MaxX - MinX;
  BoxH := MaxY - MinY;
  if (BoxW <= 0) or (BoxH <= 0) then Exit;

  AvailW := Max(40, Width - TilePad * 2);
  AvailH := Max(40, Height - TilePad * 2 - TrayTop);

  SX := AvailW / BoxW;
  SY := AvailH / BoxH;
  Ideal := Min(SX, SY) * LayoutFillFactor;

  { Refitting on every drop made the untouched screens visibly grow and
    shrink as you moved another one around -- the layout was fine, the zoom
    was not. So only rescale when it is actually needed: when the content no
    longer fits, or when it has been left with a lot of slack. }
  Overflows := (BoxW * FScale > AvailW) or (BoxH * FScale > AvailH);

  if Force or (FScale <= 0) then
    FScale := Ideal
  else if Overflows then
    FScale := Ideal
  else if Ideal > FScale * 1.6 then
    FScale := Ideal;

  { Hard floor: whatever the layout is doing, keep the smallest screen big
    enough to see and grab. Overflowing the viewport is far better than
    tiles that have shrunk out of existence. }
  for i := 0 to High(FXR.Outputs) do
  begin
    if not FXR.Outputs[i].Connected then Continue;
    if not FXR.Outputs[i].DesiredEnabled then Continue;
    LogicalSize(i, LW, LH);
    if Min(LW, LH) > 0 then
      FScale := Max(FScale, MinTileCanvasPx / Min(LW, LH));
  end;

  FOriginX := MinX;
  FOriginY := MinY;
  FOffX := (Width - Round(BoxW * FScale)) div 2;
  FOffY := TrayTop + (Height - TrayTop - Round(BoxH * FScale)) div 2;
end;

function TLayoutCanvas.DesktopToCanvas(DX, DY: integer): TPoint;
begin
  Result.X := FOffX + Round((DX - FOriginX) * FScale);
  Result.Y := FOffY + Round((DY - FOriginY) * FScale);
end;

function TLayoutCanvas.CanvasToDesktop(CX, CY: integer): TPoint;
begin
  if FScale = 0 then
  begin
    Result := Point(0, 0);
    Exit;
  end;
  Result.X := FOriginX + Round((CX - FOffX) / FScale);
  Result.Y := FOriginY + Round((CY - FOffY) / FScale);
end;

function TLayoutCanvas.TileRect(Idx: integer): TRect;
var
  LW, LH: integer;
  TL, BR: TPoint;
begin
  LogicalSize(Idx, LW, LH);
  TL := DesktopToCanvas(FXR.Outputs[Idx].DesiredX, FXR.Outputs[Idx].DesiredY);
  BR := DesktopToCanvas(FXR.Outputs[Idx].DesiredX + LW, FXR.Outputs[Idx].DesiredY + LH);
  Result := Rect(TL.X, TL.Y, BR.X, BR.Y);
end;

function TLayoutCanvas.TileAt(CX, CY: integer): integer;
var
  i: integer;
  R: TRect;
begin
  Result := -1;
  if FXR = nil then Exit;
  { Walk backwards so the topmost drawn tile wins. }
  for i := High(FXR.Outputs) downto 0 do
  begin
    if not FXR.Outputs[i].Connected then Continue;
    if not FXR.Outputs[i].DesiredEnabled then Continue;
    R := TileRect(i);
    if PtInRect(R, Point(CX, CY)) then
      Exit(i);
  end;
end;

function TLayoutCanvas.OutputHasTouch(Idx: integer): boolean;
var
  i: integer;
begin
  Result := False;
  if FTouch = nil then Exit;
  for i := 0 to High(FTouch.Devices) do
    if FTouch.Devices[i].DesiredOutput = FXR.Outputs[Idx].Name then
      Exit(True);
end;

function TLayoutCanvas.DisabledCount: integer;
var
  i: integer;
begin
  Result := 0;
  if FXR = nil then Exit;
  for i := 0 to High(FXR.Outputs) do
    if FXR.Outputs[i].Connected and not FXR.Outputs[i].DesiredEnabled then
      Inc(Result);
end;

function TLayoutCanvas.EnabledCount: integer;
var
  i: integer;
begin
  Result := 0;
  if FXR = nil then Exit;
  for i := 0 to High(FXR.Outputs) do
    if FXR.Outputs[i].Connected and FXR.Outputs[i].DesiredEnabled then
      Inc(Result);
end;

function TLayoutCanvas.TrayVisible: boolean;
begin
  { Always reserved, never conditional. Showing it only when occupied or
    mid-drag meant the strip appeared the instant a drag began, the layout
    area below it shrank, and every tile jumped -- while you were holding
    one. A permanent strip costs a little height and makes the drop target
    always available and always in the same place. }
  Result := (FXR <> nil) and (FXR.ConnectedOutputCount > 0);
end;

function TLayoutCanvas.TrayBounds: TRect;
begin
  Result := Rect(0, 0, Width, TrayHeight);
end;

function TLayoutCanvas.TraySlotRect(Slot: integer): TRect;
var
  X, Y: integer;
begin
  X := TrayPad + Slot * (TrayTileW + TrayGap);
  Y := TrayLabelH + TrayPad;
  Result := Rect(X, Y, X + TrayTileW, Y + TrayTileH);
end;

function TLayoutCanvas.TrayIndexAt(CX, CY: integer): integer;
var
  i, Slot: integer;
begin
  Result := -1;
  if (FXR = nil) or not TrayVisible then Exit;
  if not PtInRect(TrayBounds, Point(CX, CY)) then Exit;

  Slot := 0;
  for i := 0 to High(FXR.Outputs) do
  begin
    if not FXR.Outputs[i].Connected then Continue;
    if FXR.Outputs[i].DesiredEnabled then Continue;
    if PtInRect(TraySlotRect(Slot), Point(CX, CY)) then
      Exit(i);
    Inc(Slot);
  end;
end;

procedure TLayoutCanvas.ClampToNeighbours(Idx: integer; var NX, NY: integer);
var
  i, LW, LH, OW, OH: integer;
  MinX, MinY, MaxX, MaxY: integer;
  Any: boolean;
begin
  MinX := MaxInt; MinY := MaxInt;
  MaxX := -MaxInt; MaxY := -MaxInt;
  Any := False;

  for i := 0 to High(FXR.Outputs) do
  begin
    if i = Idx then Continue;
    if not FXR.Outputs[i].Connected then Continue;
    if not FXR.Outputs[i].DesiredEnabled then Continue;
    LogicalSize(i, OW, OH);
    Any := True;
    MinX := Min(MinX, FXR.Outputs[i].DesiredX);
    MinY := Min(MinY, FXR.Outputs[i].DesiredY);
    MaxX := Max(MaxX, FXR.Outputs[i].DesiredX + OW);
    MaxY := Max(MaxY, FXR.Outputs[i].DesiredY + OH);
  end;

  if not Any then Exit;   // nothing to be relative to
  LogicalSize(Idx, LW, LH);

  { Far enough out to sit on any side with a visible gap, no further. }
  NX := Max(MinX - LW - MaxGapDesktopPx, Min(NX, MaxX + MaxGapDesktopPx));
  NY := Max(MinY - LH - MaxGapDesktopPx, Min(NY, MaxY + MaxGapDesktopPx));
end;

procedure TLayoutCanvas.ApplySnapping(Idx: integer; var NX, NY: integer);
var
  i, LW, LH, OW, OH: integer;
  AcquireD, BreakD: integer;
  BestD, D: integer;
  CandV, CandG: integer;
  FoundX, FoundY: boolean;
  BestVX, BestGX, BestVY, BestGY: integer;

  { Offer one candidate position for an axis. Value is where the tile's
    leading edge would land; Guide is where to draw the alignment line. }
  procedure OfferX(Value, Guide: integer);
  begin
    D := Abs(Value - NX);
    if (D <= AcquireD) and (D < BestD) then
    begin
      BestD := D;
      BestVX := Value;
      BestGX := Guide;
      FoundX := True;
    end;
  end;

  procedure OfferY(Value, Guide: integer);
  begin
    D := Abs(Value - NY);
    if (D <= AcquireD) and (D < BestD) then
    begin
      BestD := D;
      BestVY := Value;
      BestGY := Guide;
      FoundY := True;
    end;
  end;

begin
  FGuideV := -1;
  FGuideH := -1;
  if FScale <= 0 then Exit;

  LogicalSize(Idx, LW, LH);
  AcquireD := Round(SnapAcquireCanvasPx / FScale);
  BreakD := Round(SnapBreakCanvasPx / FScale);

  { ---------- X axis ---------- }
  if FSnapXOn and (Abs(NX - FSnapXVal) <= BreakD) then
  begin
    { Still within the break distance: stay stuck. }
    NX := FSnapXVal;
    FGuideV := DesktopToCanvas(FSnapXGuide, 0).X;
  end
  else
  begin
    FSnapXOn := False;
    FoundX := False;
    BestD := MaxInt;
    BestVX := NX;
    BestGX := 0;

    for i := 0 to High(FXR.Outputs) do
    begin
      if i = Idx then Continue;
      if not FXR.Outputs[i].Connected then Continue;
      if not FXR.Outputs[i].DesiredEnabled then Continue;
      LogicalSize(i, OW, OH);

      CandV := FXR.Outputs[i].DesiredX + OW;              // my left  -> their right
      CandG := CandV;                       OfferX(CandV, CandG);
      CandV := FXR.Outputs[i].DesiredX - LW;              // my right -> their left
      CandG := FXR.Outputs[i].DesiredX;     OfferX(CandV, CandG);
      CandV := FXR.Outputs[i].DesiredX;                   // left edges flush
      CandG := CandV;                       OfferX(CandV, CandG);
      CandV := FXR.Outputs[i].DesiredX + OW - LW;         // right edges flush
      CandG := CandV + LW;                  OfferX(CandV, CandG);
      CandV := FXR.Outputs[i].DesiredX + (OW - LW) div 2; // centres aligned
      CandG := CandV + LW div 2;            OfferX(CandV, CandG);
    end;

    if FoundX then
    begin
      NX := BestVX;
      FSnapXOn := True;
      FSnapXVal := BestVX;
      FSnapXGuide := BestGX;
      FGuideV := DesktopToCanvas(BestGX, 0).X;
    end;
  end;

  { ---------- Y axis ---------- }
  if FSnapYOn and (Abs(NY - FSnapYVal) <= BreakD) then
  begin
    NY := FSnapYVal;
    FGuideH := DesktopToCanvas(0, FSnapYGuide).Y;
  end
  else
  begin
    FSnapYOn := False;
    FoundY := False;
    BestD := MaxInt;
    BestVY := NY;
    BestGY := 0;

    for i := 0 to High(FXR.Outputs) do
    begin
      if i = Idx then Continue;
      if not FXR.Outputs[i].Connected then Continue;
      if not FXR.Outputs[i].DesiredEnabled then Continue;
      LogicalSize(i, OW, OH);

      CandV := FXR.Outputs[i].DesiredY + OH;              // my top    -> their bottom
      CandG := CandV;                       OfferY(CandV, CandG);
      CandV := FXR.Outputs[i].DesiredY - LH;              // my bottom -> their top
      CandG := FXR.Outputs[i].DesiredY;     OfferY(CandV, CandG);
      CandV := FXR.Outputs[i].DesiredY;                   // top edges flush
      CandG := CandV;                       OfferY(CandV, CandG);
      CandV := FXR.Outputs[i].DesiredY + OH - LH;         // bottom edges flush
      CandG := CandV + LH;                  OfferY(CandV, CandG);
      CandV := FXR.Outputs[i].DesiredY + (OH - LH) div 2; // centres aligned
      CandG := CandV + LH div 2;            OfferY(CandV, CandG);
    end;

    if FoundY then
    begin
      NY := BestVY;
      FSnapYOn := True;
      FSnapYVal := BestVY;
      FSnapYGuide := BestGY;
      FGuideH := DesktopToCanvas(0, BestGY).Y;
    end;
  end;
end;

procedure TLayoutCanvas.DrawBackdrop;
var
  x, y: integer;
  Dot: TBGRAPixel;
begin
  { The dot grid never changes unless the control does, so build it once and
    blit it. Regenerating it pixel by pixel on every repaint was most of the
    cost of a window resize. }
  if (FBack.Width <> FBmp.Width) or (FBack.Height <> FBmp.Height) then
  begin
    FBack.SetSize(FBmp.Width, FBmp.Height);
    FBack.Fill(ToBGRA(clWindowBg));
    Dot := ToBGRA(clGridDot);
    y := 0;
    while y < FBack.Height do
    begin
      x := 0;
      while x < FBack.Width do
      begin
        FBack.SetPixel(x, y, Dot);
        Inc(x, 22);
      end;
      Inc(y, 22);
    end;
  end;
  FBmp.PutImage(0, 0, FBack, dmSet);
end;

procedure TLayoutCanvas.DrawTile(Idx: integer);
var
  R, Inner: TRect;
  Sel, Ena: boolean;
  NumStr, NameStr, ResStr: string;
  LW, LH: integer;
  FromC, ToC: TColor;
  TW, TH: integer;
  BadgeX, BadgeY: integer;

  procedure Pill(var PX: integer; PY: integer; const Text: string;
    Col: TColor; TextCol: TColor);
  var
    PW, PH: integer;
    PR: TRect;
  begin
    FBmp.FontName := UIFont;
    FBmp.FontStyle := [fsBold];
    FBmp.FontHeight := 11;
    PW := FBmp.TextSize(Text).cx + 14;
    PH := 17;
    if PX + PW > R.Right - 8 then Exit;
    PR := Rect(PX, PY, PX + PW, PY + PH);
    FBmp.FillRoundRectAntialias(PR.Left, PR.Top, PR.Right, PR.Bottom,
      8, 8, ToBGRA(Col, 235));
    FBmp.TextOut(PR.Left + 7, PR.Top + 2, Text, ToBGRA(TextCol));
    Inc(PX, PW + 6);
  end;

begin
  R := TileRect(Idx);
  if (R.Right - R.Left < 6) or (R.Bottom - R.Top < 6) then Exit;

  Sel := (Idx = FSelected);
  Ena := FXR.Outputs[Idx].DesiredEnabled;
  LogicalSize(Idx, LW, LH);

  DropShadow(FBmp, R, TileRadius, 7, IfThen(Sel, 130, 85));

  if Ena then
  begin
    FromC := clTileFrom;
    ToC := clTileTo;
    if Sel then
    begin
      FromC := MixColor(clTileFrom, clAccent, 0.30);
      ToC := MixColor(clTileTo, clAccent, 0.18);
    end
    else if Idx = FHot then
    begin
      FromC := MixColor(clTileFrom, clAccent, 0.12);
      ToC := MixColor(clTileTo, clAccent, 0.06);
    end;
  end
  else
  begin
    FromC := clTileDisabledFrom;
    ToC := clTileDisabledTo;
  end;

  FillRounded(FBmp, R, TileRadius, ToBGRA(FromC), ToBGRA(ToC));
  GlossHighlight(FBmp, R, TileRadius);

  { Selection ring, with a soft outer glow so it reads at a glance. }
  if Sel then
  begin
    StrokeRounded(FBmp, Rect(R.Left - 2, R.Top - 2, R.Right + 2, R.Bottom + 2),
      TileRadius + 2, ToBGRA(clAccent, 70), 2);
    StrokeRounded(FBmp, R, TileRadius, ToBGRA(clAccentHi), 1.8);
  end
  else if Ena then
    StrokeRounded(FBmp, R, TileRadius, ToBGRA(clHairline), 1)
  else
    StrokeRounded(FBmp, R, TileRadius, ToBGRA(clHairlineSoft), 1);

  { Big ghosted index number, the thing you actually navigate by. }
  NumStr := IntToStr(FXR.DisplayOrdinal(Idx));
  FBmp.FontName := UIFont;
  FBmp.FontStyle := [fsBold];
  FBmp.FontQuality := fqFineAntialiasing;
  FBmp.FontHeight := Max(18, Min((R.Bottom - R.Top) * 2 div 3, (R.Right - R.Left) * 2 div 3));
  TW := FBmp.TextSize(NumStr).cx;
  TH := FBmp.TextSize(NumStr).cy;
  FBmp.TextOut((R.Left + R.Right - TW) div 2,
    (R.Top + R.Bottom - TH) div 2,
    NumStr, ToBGRA(IfThen(Ena, clTextBright, clTextFaint), IfThen(Ena, 36, 26)));

  Inner := Rect(R.Left + 10, R.Top + 8, R.Right - 10, R.Bottom - 8);
  if Inner.Right <= Inner.Left then Exit;

  { Output name. }
  NameStr := FXR.Outputs[Idx].Name;
  FBmp.FontHeight := 14;
  FBmp.FontStyle := [fsBold];
  if FBmp.TextSize(NameStr).cx < Inner.Right - Inner.Left then
    FBmp.TextOut(Inner.Left, Inner.Top, NameStr,
      ToBGRA(IfThen(Ena, clTextBright, clTextFaint)));

  { Resolution + rate, or an off marker. }
  FBmp.FontHeight := 12;
  FBmp.FontStyle := [];
  if Ena then
    ResStr := Format('%d x %d  ·  %s Hz', [LW, LH, RateToStr(FXR.Outputs[Idx].DesiredRate)])
  else
    ResStr := 'disabled';
  if (FBmp.TextSize(ResStr).cx < Inner.Right - Inner.Left) and
     (Inner.Bottom - Inner.Top > 34) then
    FBmp.TextOut(Inner.Left, Inner.Top + 17, ResStr, ToBGRA(clTextDim));

  { Badges along the bottom. }
  if Inner.Bottom - Inner.Top > 52 then
  begin
    BadgeX := Inner.Left;
    BadgeY := Inner.Bottom - 17;
    if FXR.Outputs[Idx].DesiredPrimary and Ena then
      Pill(BadgeX, BadgeY, 'PRIMARY', clAccent, clWhite);
    if FShowTouchBadges and OutputHasTouch(Idx) then
      Pill(BadgeX, BadgeY, 'TOUCH', clTouch, clWindowBg);
    if FXR.Outputs[Idx].DesiredRotation <> rotNormal then
      Pill(BadgeX, BadgeY, RotationShort[FXR.Outputs[Idx].DesiredRotation] + '°',
        clWarn, clWindowBg);
  end;
end;

function TLayoutCanvas.TileHasButtons(Idx: integer): boolean;
var
  R: TRect;
begin
  Result := False;
  if (Idx < 0) or (Idx > High(FXR.Outputs)) then Exit;
  if not FXR.Outputs[Idx].DesiredEnabled then Exit;
  if Idx <> FSelected then Exit;
  R := TileRect(Idx);
  Result := (R.Right - R.Left >= TileBtnMinW) and
            (R.Bottom - R.Top >= TileBtnMinH);
end;

function TLayoutCanvas.TileButtonRect(Idx, N: integer): TRect;
var
  R: TRect;
  X, Y: integer;
begin
  R := TileRect(Idx);
  { Laid out right to left from the tile's top-right corner. }
  X := R.Right - 9 - (N + 1) * TileBtnSize - N * TileBtnGap;
  Y := R.Top + 9;
  Result := Rect(X, Y, X + TileBtnSize, Y + TileBtnSize);
end;

function TLayoutCanvas.TileButtonAt(Idx, CX, CY: integer): integer;
var
  N: integer;
begin
  Result := -1;
  if not TileHasButtons(Idx) then Exit;
  for N := 0 to 2 do
    if PtInRect(TileButtonRect(Idx, N), Point(CX, CY)) then
      Exit(N);
end;

procedure TLayoutCanvas.DrawTileButtons(Idx: integer);
var
  N, k: integer;
  R: TRect;
  Fg, Bg: TColor;
  TW: integer;
  CX, CY, Rad: single;
  Pts: array[0..9] of TPointF;
  Ang: single;
  S: string;
begin
  if not TileHasButtons(Idx) then Exit;

  for N := 0 to 2 do
  begin
    R := TileButtonRect(Idx, N);
    if R.Left < TileRect(Idx).Left then Continue;

    Bg := clRaised;
    Fg := clText;
    if (N = 1) and FXR.Outputs[Idx].DesiredPrimary then
    begin
      Bg := clAccent;
      Fg := clWhite;
    end;
    if N = 2 then Fg := clDangerHi;

    FBmp.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, 7, 7,
      ToBGRA(Bg, 232));
    FBmp.RoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, 7, 7,
      ToBGRA(clHairline, 210), 1);

    CX := (R.Left + R.Right) / 2;
    CY := (R.Top + R.Bottom) / 2;

    { Glyphs are drawn rather than typed: a font that happens to lack the
      character renders a tofu box, and these are small enough that the
      shapes are crisper drawn anyway. }
    case N of
      0:
        begin
          S := '90°';
          FBmp.FontName := UIFont;
          FBmp.FontStyle := [fsBold];
          FBmp.FontHeight := 12;
          TW := FBmp.TextSize(S).cx;
          FBmp.TextOut(Round(CX) - TW div 2,
            Round(CY) - FBmp.TextSize(S).cy div 2, S, ToBGRA(Fg));
        end;
      1:
        begin
          { Five-pointed star: alternate outer and inner radius. }
          Rad := TileBtnSize * 0.30;
          for k := 0 to 9 do
          begin
            Ang := -Pi / 2 + k * Pi / 5;
            if k mod 2 = 0 then
              Pts[k] := PointF(CX + Rad * Cos(Ang), CY + Rad * Sin(Ang))
            else
              Pts[k] := PointF(CX + Rad * 0.44 * Cos(Ang),
                               CY + Rad * 0.44 * Sin(Ang));
          end;
          FBmp.FillPolyAntialias(Pts, ToBGRA(Fg));
        end;
      2:
        begin
          Rad := TileBtnSize * 0.20;
          FBmp.DrawLineAntialias(Round(CX - Rad), Round(CY - Rad),
            Round(CX + Rad), Round(CY + Rad), ToBGRA(Fg), 2);
          FBmp.DrawLineAntialias(Round(CX + Rad), Round(CY - Rad),
            Round(CX - Rad), Round(CY + Rad), ToBGRA(Fg), 2);
        end;
    end;
  end;
end;

procedure TLayoutCanvas.DrawTray;
var
  R: TRect;
  i, Slot: integer;
  Cap: string;
begin
  R := TrayBounds;

  FBmp.FillRect(R.Left, R.Top, R.Right, R.Bottom, ToBGRA(clSurface), dmSet);
  FBmp.SetHorizLine(R.Left, R.Bottom - 1, R.Right - 1, ToBGRA(clHairline));

  FBmp.FontName := UIFont;
  FBmp.FontQuality := fqFineAntialiasing;
  FBmp.FontStyle := [fsBold];
  FBmp.FontHeight := 11;

  if FDragging and FTrayHot then
    Cap := 'RELEASE TO SWITCH THIS SCREEN OFF'
  else if DisabledCount = 0 then
    Cap := 'INACTIVE  —  drop a screen here to switch it off'
  else
    Cap := 'INACTIVE  —  drag onto the canvas to switch on, or drop one here to switch off';
  if FDragging and FTrayHot then
    FBmp.TextOut(TrayPad, 5, Cap, ToBGRA(clDangerHi))
  else
  FBmp.TextOut(TrayPad, 5, Cap, ToBGRA(clTextFaint));

  Slot := 0;
  for i := 0 to High(FXR.Outputs) do
  begin
    if not FXR.Outputs[i].Connected then Continue;
    if FXR.Outputs[i].DesiredEnabled then Continue;
    DrawTrayTile(i, Slot);
    Inc(Slot);
  end;

  { Make the drop target obvious while a screen is in flight. }
  if FDragging then
  begin
    { Light the whole strip while a screen is being held over it, so there is
      no doubt that letting go will switch it off. }
    if FTrayHot then
    begin
      FBmp.FillRect(R.Left, R.Top, R.Right, R.Bottom - 1,
        ToBGRA(clDanger, 42), dmDrawWithTransparency);
      FBmp.SetHorizLine(R.Left, R.Bottom - 1, R.Right - 1, ToBGRA(clDanger));
    end;
    if DisabledCount = 0 then
      FBmp.RoundRectAntialias(TrayPad, TrayLabelH + TrayPad,
        TrayPad + TrayTileW, TrayLabelH + TrayPad + TrayTileH,
        8, 8, ToBGRA(IfThen(FTrayHot, clDanger, clHairline), 190), 1.5);
  end;
end;

procedure TLayoutCanvas.DrawTrayTile(Idx, Slot: integer);
var
  R: TRect;
  Sel: boolean;
  NameStr, SubStr: string;
  LW, LH: integer;
begin
  R := TraySlotRect(Slot);
  if R.Right > Width - TrayPad then Exit;   // ran out of room

  Sel := (Idx = FSelected);
  LogicalSize(Idx, LW, LH);

  FillRounded(FBmp, R, 8, ToBGRA(clTileDisabledFrom), ToBGRA(clTileDisabledTo));
  if Sel then
    StrokeRounded(FBmp, R, 8, ToBGRA(clAccentHi), 1.8)
  else
    StrokeRounded(FBmp, R, 8, ToBGRA(clHairlineSoft), 1);

  FBmp.FontName := UIFont;
  FBmp.FontStyle := [fsBold];
  FBmp.FontHeight := 13;
  NameStr := FXR.Outputs[Idx].Name;
  FBmp.TextOut(R.Left + 9, R.Top + 7, NameStr, ToBGRA(clTextDim));

  FBmp.FontStyle := [];
  FBmp.FontHeight := 11;
  SubStr := Format('%d × %d  ·  off', [LW, LH]);
  FBmp.TextOut(R.Left + 9, R.Top + 25, SubStr, ToBGRA(clTextFaint));
end;

procedure TLayoutCanvas.DrawGuides;
var
  y, x: integer;
begin
  if FGuideV >= 0 then
  begin
    y := 0;
    while y < FBmp.Height do
    begin
      FBmp.SetVertLine(FGuideV, y, Min(y + 5, FBmp.Height - 1), ToBGRA(clGuide, 165));
      Inc(y, 10);
    end;
  end;
  if FGuideH >= 0 then
  begin
    x := 0;
    while x < FBmp.Width do
    begin
      FBmp.SetHorizLine(x, FGuideH, Min(x + 5, FBmp.Width - 1), ToBGRA(clGuide, 165));
      Inc(x, 10);
    end;
  end;
end;

procedure TLayoutCanvas.DrawEmptyState;
var
  S: string;
  TW: integer;
begin
  S := 'No connected displays detected';
  FBmp.FontName := UIFont;
  FBmp.FontStyle := [fsBold];
  FBmp.FontHeight := 17;
  TW := FBmp.TextSize(S).cx;
  FBmp.TextOut((FBmp.Width - TW) div 2, FBmp.Height div 2 - 12, S, ToBGRA(clTextDim));
end;

procedure TLayoutCanvas.Paint;
var
  i: integer;
begin
  if (Width <= 0) or (Height <= 0) then Exit;

  if (FBmp.Width <> Width) or (FBmp.Height <> Height) then
    FBmp.SetSize(Width, Height);

  DrawBackdrop;

  if (FXR = nil) or (FXR.ConnectedOutputCount = 0) then
    DrawEmptyState
  else
  begin
    { Active screens only -- the disabled ones live in the tray. Selected
      one last so it sits on top. }
    for i := 0 to High(FXR.Outputs) do
      if FXR.Outputs[i].Connected and FXR.Outputs[i].DesiredEnabled and
         (i <> FSelected) then
        DrawTile(i);
    if (FSelected >= 0) and (FSelected <= High(FXR.Outputs)) and
       FXR.Outputs[FSelected].Connected and
       FXR.Outputs[FSelected].DesiredEnabled then
    begin
      DrawTile(FSelected);
      if not FDragging then
        DrawTileButtons(FSelected);
    end;

    DrawGuides;

    if TrayVisible then
      DrawTray;
  end;

  FBmp.Draw(Canvas, 0, 0, True);
end;

procedure TLayoutCanvas.Resize;
begin
  inherited Resize;
  ComputeScale(True);
  Invalidate;
end;

procedure TLayoutCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Idx, TrayIdx, LW, LH, NX, NY, BtnN: integer;
  D: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FXR = nil then Exit;

  { Picking a screen out of the inactive tray switches it on straight away
    and hands it to the normal drag, so it follows the cursor onto the
    layout. Dropping it back in the tray undoes that. }
  TrayIdx := TrayIndexAt(X, Y);
  if (TrayIdx >= 0) and (Button = mbLeft) then
  begin
    SelectOutput(TrayIdx);
    FXR.Outputs[TrayIdx].DesiredEnabled := True;
    LogicalSize(TrayIdx, LW, LH);
    D := CanvasToDesktop(X, Y);
    NX := D.X - LW div 2;
    NY := D.Y - LH div 2;
    ClampToNeighbours(TrayIdx, NX, NY);
    FXR.Outputs[TrayIdx].DesiredX := NX;
    FXR.Outputs[TrayIdx].DesiredY := NY;

    FDragging := True;
    FDragFromTray := True;
    FDragIndex := TrayIdx;
    FDragGrabX := LW div 2;
    FDragGrabY := LH div 2;
    FSnapXOn := False;
    FSnapYOn := False;
    Screen.Cursor := crSizeAll;
    Invalidate;
    if Assigned(FOnChanged) then FOnChanged(Self);
    Exit;
  end;

  if PtInRect(TrayBounds, Point(X, Y)) and TrayVisible then Exit;

  { A click on one of the selected tile's quick controls acts, and must not
    also begin a drag. }
  if (FSelected >= 0) and (Button = mbLeft) then
  begin
    BtnN := TileButtonAt(FSelected, X, Y);
    if BtnN >= 0 then
    begin
      case BtnN of
        0: FXR.Outputs[FSelected].DesiredRotation :=
             NextRotation(FXR.Outputs[FSelected].DesiredRotation);
        1: for LW := 0 to High(FXR.Outputs) do
             FXR.Outputs[LW].DesiredPrimary := (LW = FSelected);
        2: if EnabledCount > 1 then
             FXR.Outputs[FSelected].DesiredEnabled := False;
      end;
      ComputeScale(False);
      Invalidate;
      if Assigned(FOnChanged) then FOnChanged(Self);
      if Assigned(FOnCommit) then FOnCommit(Self);
      Exit;
    end;
  end;

  Idx := TileAt(X, Y);
  SelectOutput(Idx);

  if (Idx >= 0) and (Button = mbLeft) and FXR.Outputs[Idx].DesiredEnabled then
  begin
    FDragging := True;
    FDragFromTray := False;
    FDragIndex := Idx;
    FSnapXOn := False;
    FSnapYOn := False;
    D := CanvasToDesktop(X, Y);
    FDragGrabX := D.X - FXR.Outputs[Idx].DesiredX;
    FDragGrabY := D.Y - FXR.Outputs[Idx].DesiredY;
    Screen.Cursor := crSizeAll;
  end;
end;

procedure TLayoutCanvas.MouseMove(Shift: TShiftState; X, Y: integer);
var
  D: TPoint;
  NX, NY, OldHot: integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FXR = nil then Exit;

  if FDragging and (FDragIndex >= 0) then
  begin
    D := CanvasToDesktop(X, Y);
    NX := D.X - FDragGrabX;
    NY := D.Y - FDragGrabY;

    ClampToNeighbours(FDragIndex, NX, NY);

    FTrayHot := PtInRect(TrayBounds, Point(X, Y));

    { Alt bypasses snapping for the rare case you want a deliberate gap. }
    if not (ssAlt in Shift) then
      ApplySnapping(FDragIndex, NX, NY)
    else
    begin
      { Alt held: free placement, and forget any stuck edge. }
      FSnapXOn := False;
      FSnapYOn := False;
      FGuideV := -1;
      FGuideH := -1;
    end;

    if (NX <> FXR.Outputs[FDragIndex].DesiredX) or
       (NY <> FXR.Outputs[FDragIndex].DesiredY) then
    begin
      FXR.Outputs[FDragIndex].DesiredX := NX;
      FXR.Outputs[FDragIndex].DesiredY := NY;
      Invalidate;
      if Assigned(FOnChanged) then FOnChanged(Self);
    end
    else
      Invalidate;   // tray feedback still needs to track the cursor
  end
  else
  begin
    OldHot := FHot;
    FHot := TileAt(X, Y);
    if FHot < 0 then FHot := TrayIndexAt(X, Y);
    if FHot <> OldHot then
    begin
      Cursor := IfThen(FHot >= 0, crHandPoint, crDefault);
      Invalidate;
    end;
  end;
end;

procedure TLayoutCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragging then
  begin
    { Dropped back into the tray: switch the screen off. Refuse if it is the
      last one left -- a desktop with no active output is not recoverable
      from inside this window. }
    if (FXR <> nil) and (FDragIndex >= 0) and
       PtInRect(TrayBounds, Point(X, Y)) then
    begin
      if EnabledCount > 1 then
        FXR.Outputs[FDragIndex].DesiredEnabled := False
      else if FDragFromTray then
        FXR.Outputs[FDragIndex].DesiredEnabled := False;
    end;

    FDragging := False;
    FDragFromTray := False;
    FTrayHot := False;
    FDragIndex := -1;
    FGuideV := -1;
    FGuideH := -1;
    Screen.Cursor := crDefault;
    if FXR <> nil then
    begin
      FXR.NormaliseDesiredOrigin;
      ComputeScale(False);
    end;
    Invalidate;
    if Assigned(FOnChanged) then FOnChanged(Self);
    if Assigned(FOnCommit) then FOnCommit(Self);
  end;
end;

procedure TLayoutCanvas.DblClick;
begin
  inherited DblClick;
  { Double-clicking the background refits the view -- the escape hatch when
    a layout has been dragged somewhere awkward. }
  if FSelected < 0 then
    FitToContent;
end;

procedure TLayoutCanvas.MouseLeave;
begin
  inherited MouseLeave;
  if FHot <> -1 then
  begin
    FHot := -1;
    Cursor := crDefault;
    Invalidate;
  end;
end;

end.
