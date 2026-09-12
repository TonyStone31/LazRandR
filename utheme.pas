unit uTheme;

{ Dark theme palette and skinning helpers for LazRandR.

  The LFM files carry plain, designer-friendly components. Everything that
  makes them look like something other than stock GTK is applied here at
  runtime, so the forms stay openable in the Lazarus designer. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, StdCtrls, ExtCtrls, Forms,
  BGRABitmap, BGRABitmapTypes, BGRAGradientScanner,
  BCButton, BCPanel, BCLabel, BCTypes;

type
  TButtonKind = (bkPrimary, bkNeutral, bkDanger, bkGhost);
  TPanelKind = (pkWindow, pkSurface, pkRaised, pkHeader);

var
  { Core surfaces, darkest to lightest. }
  clWindowBg: TColor;
  clSurface: TColor;
  clSurfaceAlt: TColor;
  clRaised: TColor;
  clHairline: TColor;
  clHairlineSoft: TColor;

  { Text. }
  clTextBright: TColor;
  clText: TColor;
  clTextDim: TColor;
  clTextFaint: TColor;

  { Accents. }
  clAccent: TColor;
  clAccentHi: TColor;
  clAccentLo: TColor;
  clTouch: TColor;
  clTouchHi: TColor;
  clWarn: TColor;
  clDanger: TColor;
  clDangerHi: TColor;
  clOkay: TColor;

  { Canvas-specific. }
  clTileFrom: TColor;
  clTileTo: TColor;
  clTileDisabledFrom: TColor;
  clTileDisabledTo: TColor;
  clGuide: TColor;
  clGridDot: TColor;

const
  UIFont = 'Ubuntu';
  UIFontFallback = 'Sans';

function ToBGRA(C: TColor; Alpha: byte = 255): TBGRAPixel;
function MixColor(A, B: TColor; Ratio: single): TColor;

procedure SkinButton(Btn: TBCButton; Kind: TButtonKind; FontHeight: integer = 0);
procedure SkinPanel(Pnl: TBCPanel; Kind: TPanelKind; Rounding: integer = 0);
{ BgColor must match the panel the label sits on. A "clear" BCLabel still
  gets a real window from GTK3 and shows the FORM's colour through it, which
  reads as a dark box floating on a lighter panel -- so paint it explicitly. }
procedure SkinLabel(Lbl: TBCLabel; AColor: TColor; FontHeight: integer;
  Bold: boolean = False; Align: TBCAlignment = bcaLeftCenter;
  BgColor: TColor = clNone);

{ Plain LCL controls that have to stay stock for the designer still get as
  much dark treatment as GTK3 will honour. }
procedure SkinCombo(Cbo: TComboBox);
procedure SkinCheck(Chk: TCheckBox);
procedure SkinPlainPanel(Pnl: TPanel; Kind: TPanelKind);

{ Shared BGRA drawing helpers used by the layout canvas. }
procedure FillRounded(Bmp: TBGRABitmap; R: TRect; Radius: integer;
  ColFrom, ColTo: TBGRAPixel);
procedure StrokeRounded(Bmp: TBGRABitmap; R: TRect; Radius: integer;
  Col: TBGRAPixel; W: single = 1);
procedure DropShadow(Bmp: TBGRABitmap; R: TRect; Radius, Spread: integer;
  Alpha: byte = 90);
procedure GlossHighlight(Bmp: TBGRABitmap; R: TRect; Radius: integer);

implementation

function ToBGRA(C: TColor; Alpha: byte): TBGRAPixel;
var
  RGB: longint;
begin
  RGB := ColorToRGB(C);
  Result := BGRA(Red(RGB), Green(RGB), Blue(RGB), Alpha);
end;

function MixColor(A, B: TColor; Ratio: single): TColor;
var
  RA, RB: longint;
begin
  if Ratio < 0 then Ratio := 0;
  if Ratio > 1 then Ratio := 1;
  RA := ColorToRGB(A);
  RB := ColorToRGB(B);
  Result := RGBToColor(
    Round(Red(RA) + (Red(RB) - Red(RA)) * Ratio),
    Round(Green(RA) + (Green(RB) - Green(RA)) * Ratio),
    Round(Blue(RA) + (Blue(RB) - Blue(RA)) * Ratio));
end;

procedure StyleState(St: TBCButtonState; FromCol, ToCol, BorderCol, TextCol: TColor;
  FontHeight: integer);
begin
  St.Background.Style := bbsGradient;
  St.Background.Gradient1.StartColor := FromCol;
  St.Background.Gradient1.EndColor := ToCol;
  St.Background.Gradient1.GradientType := gtLinear;
  St.Background.Gradient1.Point1YPercent := 0;
  St.Background.Gradient1.Point2YPercent := 100;
  St.Background.Gradient2.StartColor := FromCol;
  St.Background.Gradient2.EndColor := ToCol;
  St.Background.Gradient2.GradientType := gtLinear;
  St.Background.Gradient1EndPercent := 100;

  St.Border.Style := bboSolid;
  St.Border.Color := BorderCol;
  St.Border.Width := 1;
  St.Border.LightWidth := 0;

  St.FontEx.Color := TextCol;
  St.FontEx.Name := UIFont;
  St.FontEx.Height := FontHeight;
  St.FontEx.Style := [fsBold];
  St.FontEx.TextAlignment := bcaCenter;
  St.FontEx.FontQuality := fqFineAntialiasing;
end;

procedure SkinButton(Btn: TBCButton; Kind: TButtonKind; FontHeight: integer);
begin
  if Btn = nil then Exit;
  if FontHeight = 0 then FontHeight := 15;

  Btn.Rounding.RoundX := 7;
  Btn.Rounding.RoundY := 7;
  Btn.RoundingDropDown.RoundX := 7;
  Btn.RoundingDropDown.RoundY := 7;

  case Kind of
    bkPrimary:
      begin
        StyleState(Btn.StateNormal, clAccentHi, clAccent, clAccentLo, clWhite, FontHeight);
        StyleState(Btn.StateHover, MixColor(clAccentHi, clWhite, 0.18),
          MixColor(clAccent, clWhite, 0.12), clAccentHi, clWhite, FontHeight);
        StyleState(Btn.StateClicked, clAccentLo, clAccentLo, clAccentLo, clWhite, FontHeight);
      end;
    bkNeutral:
      begin
        StyleState(Btn.StateNormal, clRaised, clSurfaceAlt, clHairline, clText, FontHeight);
        StyleState(Btn.StateHover, MixColor(clRaised, clAccent, 0.22),
          MixColor(clSurfaceAlt, clAccent, 0.16), clAccent, clTextBright, FontHeight);
        StyleState(Btn.StateClicked, clSurface, clSurface, clAccentLo, clTextBright, FontHeight);
      end;
    bkDanger:
      begin
        StyleState(Btn.StateNormal, clDangerHi, clDanger, clDanger, clWhite, FontHeight);
        StyleState(Btn.StateHover, MixColor(clDangerHi, clWhite, 0.18),
          MixColor(clDanger, clWhite, 0.1), clDangerHi, clWhite, FontHeight);
        StyleState(Btn.StateClicked, clDanger, clDanger, clDanger, clWhite, FontHeight);
      end;
    bkGhost:
      begin
        StyleState(Btn.StateNormal, clSurface, clSurface, clHairlineSoft, clTextDim, FontHeight);
        StyleState(Btn.StateHover, clSurfaceAlt, clSurfaceAlt, clHairline, clText, FontHeight);
        StyleState(Btn.StateClicked, clWindowBg, clWindowBg, clAccentLo, clText, FontHeight);
      end;
  end;
end;

procedure SkinPanel(Pnl: TBCPanel; Kind: TPanelKind; Rounding: integer);
var
  Base: TColor;
begin
  if Pnl = nil then Exit;

  case Kind of
    pkWindow: Base := clWindowBg;
    pkSurface: Base := clSurface;
    pkRaised: Base := clRaised;
    pkHeader: Base := clSurfaceAlt;
  end;

  Pnl.Background.Style := bbsColor;
  Pnl.Background.Color := Base;
  Pnl.Rounding.RoundX := Rounding;
  Pnl.Rounding.RoundY := Rounding;

  if Kind = pkWindow then
  begin
    Pnl.Border.Style := bboNone;
  end
  else
  begin
    Pnl.Border.Style := bboSolid;
    Pnl.Border.Color := clHairline;
    Pnl.Border.Width := 1;
    Pnl.Border.LightWidth := 0;
  end;

  Pnl.FontEx.Color := clText;
  Pnl.FontEx.Name := UIFont;
  Pnl.FontEx.FontQuality := fqFineAntialiasing;
end;

procedure SkinLabel(Lbl: TBCLabel; AColor: TColor; FontHeight: integer;
  Bold: boolean; Align: TBCAlignment; BgColor: TColor);
begin
  if Lbl = nil then Exit;
  if BgColor = clNone then
    Lbl.Background.Style := bbsClear
  else
  begin
    Lbl.Background.Style := bbsColor;
    Lbl.Background.Color := BgColor;
  end;
  Lbl.Border.Style := bboNone;
  Lbl.FontEx.Color := AColor;
  Lbl.FontEx.Name := UIFont;
  Lbl.FontEx.Height := FontHeight;
  Lbl.FontEx.FontQuality := fqFineAntialiasing;
  Lbl.FontEx.TextAlignment := Align;
  if Bold then
    Lbl.FontEx.Style := [fsBold]
  else
    Lbl.FontEx.Style := [];
end;

procedure SkinCombo(Cbo: TComboBox);
begin
  if Cbo = nil then Exit;
  { Leave Style alone -- owner-draw would need a full paint handler and GTK3
    renders the popup list itself regardless. }
  Cbo.ItemHeight := 22;
  Cbo.Color := clRaised;
  Cbo.Font.Color := clTextBright;
  Cbo.Font.Name := UIFont;
  Cbo.Font.Height := 14;
end;

procedure SkinCheck(Chk: TCheckBox);
begin
  if Chk = nil then Exit;
  Chk.Font.Color := clText;
  Chk.Font.Name := UIFont;
  Chk.Font.Height := 14;
  Chk.ParentColor := False;
  Chk.Color := clSurface;
end;

procedure SkinPlainPanel(Pnl: TPanel; Kind: TPanelKind);
var
  Base: TColor;
begin
  if Pnl = nil then Exit;
  case Kind of
    pkWindow: Base := clWindowBg;
    pkSurface: Base := clSurface;
    pkRaised: Base := clRaised;
    pkHeader: Base := clSurfaceAlt;
  end;
  Pnl.BevelOuter := bvNone;
  Pnl.BevelInner := bvNone;
  Pnl.ParentBackground := False;
  Pnl.ParentColor := False;
  Pnl.Color := Base;
  Pnl.Font.Color := clText;
  Pnl.Font.Name := UIFont;
end;

procedure FillRounded(Bmp: TBGRABitmap; R: TRect; Radius: integer;
  ColFrom, ColTo: TBGRAPixel);
var
  Grad: TBGRACustomScanner;
begin
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;
  Grad := TBGRAGradientScanner.Create(ColFrom, ColTo, gtLinear,
    PointF(R.Left, R.Top), PointF(R.Left, R.Bottom));
  try
    Bmp.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom,
      Radius, Radius, Grad);
  finally
    Grad.Free;
  end;
end;

procedure StrokeRounded(Bmp: TBGRABitmap; R: TRect; Radius: integer;
  Col: TBGRAPixel; W: single);
begin
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;
  Bmp.RoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom,
    Radius, Radius, Col, W);
end;

procedure DropShadow(Bmp: TBGRABitmap; R: TRect; Radius, Spread: integer;
  Alpha: byte);
var
  i: integer;
  A: byte;
  RR: TRect;
begin
  { Cheap layered shadow: a few progressively fainter, progressively larger
    rounded outlines under the tile. Much faster than a real gaussian blur
    and indistinguishable at these sizes. }
  for i := Spread downto 1 do
  begin
    A := Round(Alpha * (1 - (i / (Spread + 1))) * 0.55);
    if A = 0 then Continue;
    RR := Rect(R.Left - i, R.Top - i + 2, R.Right + i, R.Bottom + i + 2);
    Bmp.RoundRectAntialias(RR.Left, RR.Top, RR.Right, RR.Bottom,
      Radius + i, Radius + i, BGRA(0, 0, 0, A), 1.4);
  end;
end;

procedure GlossHighlight(Bmp: TBGRABitmap; R: TRect; Radius: integer);
var
  H: integer;
  Grad: TBGRACustomScanner;
  Clip: TBGRABitmap;
begin
  H := (R.Bottom - R.Top) div 2;
  if H < 4 then Exit;

  { Draw the sheen into a scratch layer masked by the same rounded shape so
    it never bleeds outside the tile's corners. }
  Clip := TBGRABitmap.Create(R.Right - R.Left, R.Bottom - R.Top, BGRAPixelTransparent);
  try
    Grad := TBGRAGradientScanner.Create(
      BGRA(255, 255, 255, 26), BGRA(255, 255, 255, 0), gtLinear,
      PointF(0, 0), PointF(0, H));
    try
      Clip.FillRoundRectAntialias(0, 0, Clip.Width, Clip.Height,
        Radius, Radius, Grad);
    finally
      Grad.Free;
    end;
    Bmp.PutImage(R.Left, R.Top, Clip, dmDrawWithTransparency);
  finally
    Clip.Free;
  end;
end;

procedure InitPalette;
begin
  clWindowBg     := RGBToColor($10, $12, $17);
  clSurface      := RGBToColor($17, $1A, $21);
  clSurfaceAlt   := RGBToColor($1D, $21, $2A);
  clRaised       := RGBToColor($25, $2A, $35);
  clHairline     := RGBToColor($34, $3A, $48);
  clHairlineSoft := RGBToColor($26, $2B, $36);

  clTextBright   := RGBToColor($F2, $F5, $FA);
  clText         := RGBToColor($D2, $D8, $E4);
  clTextDim      := RGBToColor($8D, $96, $A8);
  clTextFaint    := RGBToColor($5C, $65, $76);

  clAccent       := RGBToColor($2F, $6F, $F5);
  clAccentHi     := RGBToColor($5A, $92, $FF);
  clAccentLo     := RGBToColor($1E, $4E, $B8);
  clTouch        := RGBToColor($15, $C2, $8E);
  clTouchHi      := RGBToColor($3B, $E8, $B0);
  clWarn         := RGBToColor($F0, $A5, $2A);
  clDanger       := RGBToColor($E0, $4B, $4B);
  clDangerHi     := RGBToColor($FF, $6E, $6E);
  clOkay         := RGBToColor($3D, $D6, $8C);

  clTileFrom         := RGBToColor($32, $3A, $4B);
  clTileTo           := RGBToColor($21, $26, $33);
  clTileDisabledFrom := RGBToColor($1E, $21, $28);
  clTileDisabledTo   := RGBToColor($17, $19, $1F);
  clGuide            := RGBToColor($5A, $92, $FF);
  clGridDot          := RGBToColor($23, $28, $33);
end;

initialization
  InitPalette;

end.
