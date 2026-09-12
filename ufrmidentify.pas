unit ufrmIdentify;

{ The big "which screen am I" card.

  One borderless window is shown centred on each active output. Drawn with
  BGRABitmap so it matches the rest of the app rather than looking like a
  stock dialog. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, Math,
  BGRABitmap, BGRABitmapTypes, uTheme;

type

  { TfrmIdentify }

  TfrmIdentify = class(TForm)
    pbIdent: TPaintBox;
    procedure pbIdentPaint(Sender: TObject);
  private
    FNumber: string;
    FName: string;
    FDetail: string;
  public
    procedure Configure(const ANumber, AName, ADetail: string;
      OutX, OutY, OutW, OutH: integer);
  end;

implementation

{$R *.lfm}

const
  CardW = 430;
  CardH = 260;

procedure TfrmIdentify.Configure(const ANumber, AName, ADetail: string;
  OutX, OutY, OutW, OutH: integer);
var
  W, H: integer;
begin
  FNumber := ANumber;
  FName := AName;
  FDetail := ADetail;

  { Shrink the card on small or portrait panels so it never overflows. }
  W := Min(CardW, Max(180, OutW - 40));
  H := Min(CardH, Max(120, OutH - 40));

  SetBounds(OutX + (OutW - W) div 2, OutY + (OutH - H) div 2, W, H);
end;

procedure TfrmIdentify.pbIdentPaint(Sender: TObject);
var
  Bmp: TBGRABitmap;
  R: TRect;
  TW, NumH: integer;
begin
  Bmp := TBGRABitmap.Create(pbIdent.Width, pbIdent.Height);
  try
    Bmp.Fill(BGRAPixelTransparent);
    R := Rect(0, 0, Bmp.Width, Bmp.Height);

    FillRounded(Bmp, R, 20, ToBGRA(clRaised, 246), ToBGRA(clWindowBg, 246));
    StrokeRounded(Bmp, Rect(R.Left, R.Top, R.Right - 1, R.Bottom - 1), 20,
      ToBGRA(clAccentHi, 210), 2.4);
    GlossHighlight(Bmp, R, 20);

    Bmp.FontName := UIFont;
    Bmp.FontQuality := fqFineAntialiasing;

    { Screen number, sized to the card so it works on a narrow portrait panel. }
    Bmp.FontStyle := [fsBold];
    NumH := Max(48, Min(Bmp.Height * 2 div 3, 150));
    Bmp.FontHeight := NumH;
    TW := Bmp.TextSize(FNumber).cx;
    Bmp.TextOut((Bmp.Width - TW) div 2,
      Bmp.Height div 2 - Bmp.TextSize(FNumber).cy div 2 - 18,
      FNumber, ToBGRA(clTextBright));

    Bmp.FontStyle := [fsBold];
    Bmp.FontHeight := Max(14, Min(22, Bmp.Height div 11));
    TW := Bmp.TextSize(FName).cx;
    Bmp.TextOut((Bmp.Width - TW) div 2, Bmp.Height - 62, FName,
      ToBGRA(clAccentHi));

    Bmp.FontStyle := [];
    Bmp.FontHeight := Max(12, Min(16, Bmp.Height div 15));
    TW := Bmp.TextSize(FDetail).cx;
    Bmp.TextOut((Bmp.Width - TW) div 2, Bmp.Height - 36, FDetail,
      ToBGRA(clTextDim));

    Bmp.Draw(pbIdent.Canvas, 0, 0, True);
  finally
    Bmp.Free;
  end;
end;

end.
