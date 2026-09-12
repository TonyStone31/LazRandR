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
    FOnChanged: TNotifyEvent;
    FOnSelect: TTileEvent;
    FShowTouchBadges: boolean;

    procedure ComputeScale;
    function DesktopToCanvas(DX, DY: integer): TPoint;
    function CanvasToDesktop(CX, CY: integer): TPoint;
    procedure LogicalSize(Idx: integer; out W, H: integer);
    function TileRect(Idx: integer): TRect;
    function TileAt(CX, CY: integer): integer;
    procedure ApplySnapping(Idx: integer; var NX, NY: integer);
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
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Attach(AXR: TXRandR; ATouch: TTouchManager);
    procedure Rebuild;
    procedure SelectOutput(Idx: integer);

    property SelectedIndex: integer read FSelected;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnSelect: TTileEvent read FOnSelect write FOnSelect;
    property ShowTouchBadges: boolean read FShowTouchBadges write FShowTouchBadges;
  end;

implementation

const
  TilePad = 28;          // canvas px breathing room around the layout
  TileRadius = 11;
  SnapPixels = 90;       // snap threshold, in DESKTOP px

constructor TLayoutCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  FBmp := TBGRABitmap.Create(1, 1);
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
  ComputeScale;
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

procedure TLayoutCanvas.ComputeScale;
var
  i, LW, LH: integer;
  MinX, MinY, MaxX, MaxY: integer;
  Any: boolean;
  SX, SY: double;
  BoxW, BoxH, AvailW, AvailH: integer;
begin
  FScale := 1;
  FOffX := 0;
  FOffY := 0;
  FOriginX := 0;
  FOriginY := 0;
  if FXR = nil then Exit;

  MinX := MaxInt; MinY := MaxInt;
  MaxX := -MaxInt; MaxY := -MaxInt;
  Any := False;

  for i := 0 to High(FXR.Outputs) do
  begin
    if not FXR.Outputs[i].Connected then Continue;
    LogicalSize(i, LW, LH);
    Any := True;
    MinX := Min(MinX, FXR.Outputs[i].DesiredX);
    MinY := Min(MinY, FXR.Outputs[i].DesiredY);
    MaxX := Max(MaxX, FXR.Outputs[i].DesiredX + LW);
    MaxY := Max(MaxY, FXR.Outputs[i].DesiredY + LH);
  end;

  if not Any then Exit;

  BoxW := MaxX - MinX;
  BoxH := MaxY - MinY;
  if (BoxW <= 0) or (BoxH <= 0) then Exit;

  AvailW := Max(40, Width - TilePad * 2);
  AvailH := Max(40, Height - TilePad * 2);

  SX := AvailW / BoxW;
  SY := AvailH / BoxH;
  FScale := Min(SX, SY);

  FOriginX := MinX;
  FOriginY := MinY;
  FOffX := (Width - Round(BoxW * FScale)) div 2;
  FOffY := (Height - Round(BoxH * FScale)) div 2;
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

procedure TLayoutCanvas.ApplySnapping(Idx: integer; var NX, NY: integer);
var
  i, LW, LH, OW, OH: integer;
  BestDX, BestDY, D: integer;
  GX, GY: integer;

  procedure TryX(Candidate, GuideAt: integer);
  begin
    D := Abs(Candidate - NX);
    if D < BestDX then
    begin
      BestDX := D;
      GX := GuideAt;
      NX := Candidate;
    end;
  end;

  procedure TryY(Candidate, GuideAt: integer);
  begin
    D := Abs(Candidate - NY);
    if D < BestDY then
    begin
      BestDY := D;
      GY := GuideAt;
      NY := Candidate;
    end;
  end;

var
  CandX, CandY: integer;
begin
  FGuideV := -1;
  FGuideH := -1;
  LogicalSize(Idx, LW, LH);

  BestDX := SnapPixels + 1;
  BestDY := SnapPixels + 1;
  GX := -1;
  GY := -1;

  for i := 0 to High(FXR.Outputs) do
  begin
    if i = Idx then Continue;
    if not FXR.Outputs[i].Connected then Continue;
    if not FXR.Outputs[i].DesiredEnabled then Continue;
    LogicalSize(i, OW, OH);

    { --- horizontal: butt up against either side, or align edges --- }
    CandX := FXR.Outputs[i].DesiredX + OW;          // my left to their right
    if Abs(CandX - NX) <= SnapPixels then TryX(CandX, CandX);
    CandX := FXR.Outputs[i].DesiredX - LW;          // my right to their left
    if Abs(CandX - NX) <= SnapPixels then TryX(CandX, FXR.Outputs[i].DesiredX);
    CandX := FXR.Outputs[i].DesiredX;               // left edges flush
    if Abs(CandX - NX) <= SnapPixels then TryX(CandX, CandX);
    CandX := FXR.Outputs[i].DesiredX + OW - LW;     // right edges flush
    if Abs(CandX - NX) <= SnapPixels then TryX(CandX, CandX + LW);

    { --- vertical: same four relationships --- }
    CandY := FXR.Outputs[i].DesiredY + OH;
    if Abs(CandY - NY) <= SnapPixels then TryY(CandY, CandY);
    CandY := FXR.Outputs[i].DesiredY - LH;
    if Abs(CandY - NY) <= SnapPixels then TryY(CandY, FXR.Outputs[i].DesiredY);
    CandY := FXR.Outputs[i].DesiredY;
    if Abs(CandY - NY) <= SnapPixels then TryY(CandY, CandY);
    CandY := FXR.Outputs[i].DesiredY + OH - LH;
    if Abs(CandY - NY) <= SnapPixels then TryY(CandY, CandY + LH);

    { Centre alignment reads as "lined up" to the eye, so offer it too. }
    CandY := FXR.Outputs[i].DesiredY + (OH - LH) div 2;
    if Abs(CandY - NY) <= SnapPixels then TryY(CandY, CandY + LH div 2);
    CandX := FXR.Outputs[i].DesiredX + (OW - LW) div 2;
    if Abs(CandX - NX) <= SnapPixels then TryX(CandX, CandX + LW div 2);
  end;

  if GX >= 0 then FGuideV := DesktopToCanvas(GX, 0).X;
  if GY >= 0 then FGuideH := DesktopToCanvas(0, GY).Y;
end;

procedure TLayoutCanvas.DrawBackdrop;
var
  x, y: integer;
  Dot: TBGRAPixel;
begin
  FBmp.Fill(ToBGRA(clWindowBg));

  { A faint dot grid gives the drag something to read against without the
    busy look of full gridlines. }
  Dot := ToBGRA(clGridDot);
  y := 0;
  while y < FBmp.Height do
  begin
    x := 0;
    while x < FBmp.Width do
    begin
      FBmp.SetPixel(x, y, Dot);
      Inc(x, 22);
    end;
    Inc(y, 22);
  end;
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
    { Disabled first, then enabled, then the selected one on top. }
    for i := 0 to High(FXR.Outputs) do
      if FXR.Outputs[i].Connected and not FXR.Outputs[i].DesiredEnabled and (i <> FSelected) then
        DrawTile(i);
    for i := 0 to High(FXR.Outputs) do
      if FXR.Outputs[i].Connected and FXR.Outputs[i].DesiredEnabled and (i <> FSelected) then
        DrawTile(i);
    if (FSelected >= 0) and (FSelected <= High(FXR.Outputs)) and
       FXR.Outputs[FSelected].Connected then
      DrawTile(FSelected);

    DrawGuides;
  end;

  FBmp.Draw(Canvas, 0, 0, True);
end;

procedure TLayoutCanvas.Resize;
begin
  inherited Resize;
  ComputeScale;
  Invalidate;
end;

procedure TLayoutCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Idx: integer;
  D: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FXR = nil then Exit;

  Idx := TileAt(X, Y);
  SelectOutput(Idx);

  if (Idx >= 0) and (Button = mbLeft) and FXR.Outputs[Idx].DesiredEnabled then
  begin
    FDragging := True;
    FDragIndex := Idx;
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

    { Alt bypasses snapping for the rare case you want a deliberate gap. }
    if not (ssAlt in Shift) then
      ApplySnapping(FDragIndex, NX, NY)
    else
    begin
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
      Invalidate;
  end
  else
  begin
    OldHot := FHot;
    FHot := TileAt(X, Y);
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
    FDragging := False;
    FDragIndex := -1;
    FGuideV := -1;
    FGuideH := -1;
    Screen.Cursor := crDefault;
    if FXR <> nil then
    begin
      FXR.NormaliseDesiredOrigin;
      ComputeScale;
    end;
    Invalidate;
    if Assigned(FOnChanged) then FOnChanged(Self);
  end;
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
