unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  Grids, ExtCtrls, StrUtils, Types;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnReload1:  TButton;
    ListBox1:    TListBox;
    pnlLayout:   TPanel;
    StringGrid1: TStringGrid;
    procedure tnReloadClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ListBox1Click(Sender: TObject);
    procedure pnlDispArClick(Sender: TObject);
    procedure pnlDispArContextPopup(Sender: TObject; MousePos: TPoint;
      var Handled: boolean);
    procedure pnlDispArMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure pnlDispArMouseEnter(Sender: TObject);
    procedure pnlDispArMouseLeave(Sender: TObject);
    procedure pnlDispArMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: integer);
    procedure pnlDispArMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure pnlDispArPaint(Sender: TObject);
  private

  public
    procedure makPnlsFromCurrent;
    procedure mouseMVpanel(var pnl: TPanel; const Y: integer;
      const X: integer; var Shift: TShiftState);
    procedure posPnls2Current;

  end;

var
  Form1:      TForm1;
  schDispPnl: array of TPanel;
  schDispLbl: array of TLabel;

  schDisSnapHLt: array of TPanel;
  schDisSnapHLb: array of TPanel;
  schDisSnapHLl: array of TPanel;
  schDisSnapHLr: array of TPanel;

  snapHLpnlT: array of Boolean;
  snapHLpnlB: array of Boolean;
  snapHLpnlL: array of Boolean;
  snapHLpnlR: array of Boolean;



  scaleLObyXY:    double;
  scaleTocntrX, scaleTocntrY: integer;
  scaleTocntrXYi: integer;


  pnlMoving:  boolean = False;
  pnlSnapped: boolean = False;
  mmDownSx, mmDownSy: integer;



const
  OLTHRHO: integer = 12; // distance from other edge threshhold i guess

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  makPnlsFromCurrent;
  posPnls2Current;
end;

procedure TForm1.tnReloadClick(Sender: TObject);
begin
  posPnls2Current;
end;


procedure TForm1.ListBox1Click(Sender: TObject);
begin
  if AnsiContainsText(ListBox1.Items[ListBox1.ItemIndex], 'fake') then exit;
  StringGrid1.Cells[0, 0] := 'Resolution';
  StringGrid1.Cells[1, 0] :=
    IntToStr(Screen.Monitors[ListBox1.ItemIndex].Width) + 'x' +
    IntToStr(Screen.Monitors[ListBox1.ItemIndex].Height);

  StringGrid1.Cells[0, 1] := 'Top';
  StringGrid1.Cells[1, 1] :=
    IntToStr(Screen.Monitors[ListBox1.ItemIndex].Top);

  StringGrid1.Cells[0, 2] := 'Bottom';
  StringGrid1.Cells[1, 2] :=
    IntToStr(Screen.Monitors[ListBox1.ItemIndex].BoundsRect.Bottom);

  StringGrid1.Cells[0, 3] := 'Left';
  StringGrid1.Cells[1, 3] :=
    IntToStr(Screen.Monitors[ListBox1.ItemIndex].BoundsRect.Left);

  StringGrid1.Cells[0, 4] := 'Right';
  StringGrid1.Cells[1, 4] :=
    IntToStr(Screen.Monitors[ListBox1.ItemIndex].BoundsRect.Right);

end;

procedure TForm1.pnlDispArClick(Sender: TObject);
var
  i:   integer;
  pnl: TPanel;
begin
  pnl := Sender as TPanel;

  for i := 0 to Length(schDispPnl) - 1 do
  begin
    //find the display clicked and set listindex
    if pnl.Handle = schDispPnl[i].Handle then
    begin
      ListBox1.ItemIndex := i;
      ListBox1Click(Sender);
      exit;
    end;
  end;
end;

procedure TForm1.pnlDispArContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: boolean);
begin

end;

procedure TForm1.pnlDispArMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  pnl: TPanel;
begin
  pnl      := Sender as TPanel;
  pnlMoving := True;
  mmDownSx := x;
  mmDownSy := y;

end;

procedure TForm1.pnlDispArMouseEnter(Sender: TObject);
var
  pnl: TPanel;
begin
  pnl := Sender as TPanel;
  pnl.BevelInner := bvRaised;
  pnl.BringToFront;
end;

procedure TForm1.pnlDispArMouseLeave(Sender: TObject);
var
  pnl: TPanel;
begin
  pnl := Sender as TPanel;
  pnl.BevelInner := bvNone;

end;

procedure TForm1.pnlDispArMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  pnl: TPanel;
  i:   integer;
  SnapsTH, SnapsTL, SnapsBH, SnapsBL, SnapsLH, SnapsLL, SnapsRH, SnapsRL: array of
  integer;

  snapRect: TRect;

begin
  pnl := Sender as TPanel;

  for i:=0 to Length(schDispPnl)-1 do begin
    snapHLpnlT[i]:=False;
    snapHLpnlB[i]:=False;
    snapHLpnlL[i]:=False;
    snapHLpnlR[i]:=False;
  end;

  mouseMVpanel(pnl, Y, X, Shift);
  snapRect := pnl.BoundsRect;


  SetLength(SnapsTH, Length(schDispPnl));
  SetLength(SnapsTL, Length(schDispPnl));
  SetLength(SnapsBH, Length(schDispPnl));
  SetLength(SnapsBL, Length(schDispPnl));
  SetLength(SnapsLH, Length(schDispPnl));
  SetLength(SnapsLL, Length(schDispPnl));
  SetLength(SnapsRH, Length(schDispPnl));
  SetLength(SnapsRL, Length(schDispPnl));

  if (Shift = [ssLeft]) and (pnlMoving) then
  begin
    // establish all ranges where snapping needs to happen
    for i := 0 to Length(schDispPnl) - 1 do
    begin
      SnapsTH[i] := schDispPnl[i].BoundsRect.Top + OLTHRHO;
      SnapsTL[i] := schDispPnl[i].BoundsRect.Top - OLTHRHO;
      SnapsBH[i] := schDispPnl[i].BoundsRect.Bottom + OLTHRHO;
      SnapsBL[i] := schDispPnl[i].BoundsRect.Bottom - OLTHRHO;
      SnapsLH[i] := schDispPnl[i].BoundsRect.Left + OLTHRHO;
      SnapsLL[i] := schDispPnl[i].BoundsRect.Left - OLTHRHO;
      SnapsRH[i] := schDispPnl[i].BoundsRect.Right + OLTHRHO;
      SnapsRL[i] := schDispPnl[i].BoundsRect.Right - OLTHRHO;
    end;

    for i := 0 to Length(schDispPnl) - 1 do
    begin
      // dont want it to try to snap to itself
      if pnl = schDispPnl[i] then
      begin
        Continue;
      end;

      // try to snap a TOP to a TOP
      if (pnl.BoundsRect.Top < SnapsTH[i]) and (pnl.BoundsRect.Top > SnapsTL[i]) then
      begin
        snapRect.Top := schDispPnl[i].Top;
        snapHLpnlT[i]:=True;
      end;

      // try to snap a TOP to a BOTTOM
      if (pnl.BoundsRect.Top < SnapsBH[i]) and (pnl.BoundsRect.Top > SnapsBL[i]) then
      begin
        snapRect.Top := schDispPnl[i].BoundsRect.Bottom;
        snapHLpnlB[i]:=True;
      end;

      // try to snap to a BOTTOM to a TOP
      if (pnl.BoundsRect.Bottom < SnapsTH[i]) and
        (pnl.BoundsRect.Bottom > SnapsTL[i]) then
      begin
        snapRect.Top := schDispPnl[i].Top - pnl.Height;
        snapHLpnlT[i]:=True;
      end;

      // try to snap a BOTTOM to a BOTTOM
      if (pnl.BoundsRect.Bottom < SnapsBH[i]) and
        (pnl.BoundsRect.Bottom > SnapsBL[i]) then
      begin
        snapRect.Top := schDispPnl[i].BoundsRect.Bottom - pnl.Height;
        snapHLpnlB[i]:=True;
      end;

      // try to snap a LEFT to a LEFT
      if (pnl.BoundsRect.Left < SnapsLH[i]) and (pnl.BoundsRect.Left > SnapsLL[i]) then
      begin
        snapRect.Left := schDispPnl[i].BoundsRect.Left;
        snapHLpnlL[i]:=True;
      end;

      // try to snap a LEFT to a Right
      if (pnl.BoundsRect.Left < SnapsRH[i]) and (pnl.BoundsRect.Left > SnapsRL[i]) then
      begin
        snapRect.Left := schDispPnl[i].BoundsRect.Right;
        snapHLpnlR[i]:=True;
      end;

      // try to snap a RIGHT to a LEFT
      if (pnl.BoundsRect.Right < SnapsLH[i]) and (pnl.BoundsRect.Right > SnapsLL[i]) then
      begin
        snapRect.Left := schDispPnl[i].BoundsRect.left - pnl.Width;
        snapHLpnlL[i]:=True;
      end;

      // try to snap a RIGHT to a RIGHT
      if (pnl.BoundsRect.Right < SnapsRH[i]) and (pnl.BoundsRect.Right > SnapsRL[i]) then
      begin
        snapRect.Left := schDispPnl[i].BoundsRect.Right - pnl.Width;
        snapHLpnlR[i]:=True;
      end;

    end;

  end;


  pnl.SetBounds(snapRect.Left, snapRect.Top, pnl.Width, pnl.Height);
  for i:=0 to Length(schDispPnl)-1 do begin
    schDisSnapHLt[i].Visible:=snapHLpnlT[i];
    schDisSnapHLb[i].Visible:=snapHLpnlB[i];
    schDisSnapHLl[i].Visible:=snapHLpnlL[i];
    schDisSnapHLr[i].Visible:=snapHLpnlR[i];
  end;


end;

procedure TForm1.pnlDispArMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  pnl: TPanel;
  i:   integer;
begin
  for i := 0 to Length(schDispPnl) - 1 do
  begin
    schDisSnapHLt[i].Visible := False;
    schDisSnapHLb[i].Visible := False;
    schDisSnapHLl[i].Visible := False;
    schDisSnapHLr[i].Visible := False;
  end;

end;

procedure TForm1.pnlDispArPaint(Sender: TObject);
begin

end;

procedure TForm1.mouseMVpanel(var pnl: TPanel; const Y: integer;
  const X: integer; var Shift: TShiftState);
begin
  if (Shift = [ssLeft]) and (pnlMoving) then
  begin
    pnl.Left := pnl.Left + (x - mmDownSx);
    pnl.Top  := pnl.Top + (y - mmDownSy);

  end;
end;

procedure TForm1.makPnlsFromCurrent;
var
  i: integer;
begin
  SetLength(schDispPnl, Screen.MonitorCount);
  SetLength(schDispLbl, screen.MonitorCount);
  SetLength(schDisSnapHLt, screen.MonitorCount);
  SetLength(schDisSnapHLb, screen.MonitorCount);
  SetLength(schDisSnapHLl, screen.MonitorCount);
  SetLength(schDisSnapHLr, screen.MonitorCount);

  SetLength(snapHLpnlT, screen.MonitorCount);
  SetLength(snapHLpnlB, screen.MonitorCount);
  SetLength(snapHLpnlL, screen.MonitorCount);
  SetLength(snapHLpnlR, screen.MonitorCount);



  for i := 0 to Screen.MonitorCount - 1 do
  begin
    if screen.Monitors[i].Primary then
      ListBox1.Items.Add('Display ' + IntToStr(screen.Monitors[i].MonitorNum) +
        ' (Primary)')
    else
      ListBox1.Items.Add('Display ' + IntToStr(screen.Monitors[i].MonitorNum)
        );


    //make the panel that represents a display
    schDispPnl[i] := TPanel.Create(Form1);
    schDispPnl[i].OnPaint := @pnlDispArPaint;
    schDispPnl[i].OnClick := @pnlDispArClick;
    schDispPnl[i].OnMouseEnter := @pnlDispArMouseEnter;
    schDispPnl[i].OnMouseLeave := @pnlDispArMouseLeave;
    schDispPnl[i].OnMouseDown := @pnlDispArMouseDown;
    schDispPnl[i].OnMouseUp := @pnlDispArMouseUp;
    schDispPnl[i].OnMouseMove := @pnlDispArMouseMove;
    schDispPnl[i].OnMouseDown := @pnlDispArMouseDown;
    schDispPnl[i].BevelColor := clWhite;
    schDispPnl[i].BorderStyle := bsSingle;
    schDispPnl[i].Parent := pnlLayout;

    // make a label that goes with each display/panel
    schDispLbl[i] := TLabel.Create(schDispPnl[i]);
    schDispLbl[i].Caption := IntToStr(i);
    schDispLbl[i].Parent := schDispPnl[i];

    // make the highlight panels that show where its snapping to
    schDisSnapHLt[i] := TPanel.Create(schDispPnl[i]);
    schDisSnapHLt[i].Parent := schDispPnl[i];
    schDisSnapHLb[i] := TPanel.Create(schDispPnl[i]);
    schDisSnapHLb[i].Parent := schDispPnl[i];
    schDisSnapHLl[i] := TPanel.Create(schDispPnl[i]);
    schDisSnapHLl[i].Parent := schDispPnl[i];
    schDisSnapHLr[i] := TPanel.Create(schDispPnl[i]);
    schDisSnapHLr[i].Parent := schDispPnl[i];

    snapHLpnlT[i]:=False;
    snapHLpnlB[i]:=False;
    snapHLpnlL[i]:=False;
    snapHLpnlR[i]:=False;
  end;
end;

procedure TForm1.posPnls2Current;
var
  highR: integer;
  i:     integer;
begin
  highR := 0;
  for i := 0 to screen.MonitorCount - 1 do
  begin
    if Screen.Monitors[i].BoundsRect.Right > highR then
      highR := Screen.Monitors[i].WorkareaRect.Right;
    Writeln('Highest Right: ' + IntToStr(highR));

  end;

  scaleLObyXY  := pnlLayout.Width / int64(highR);
  scaleTocntrX := pnlLayout.Width div 4;
  scaleTocntrY := pnlLayout.Height div 4;

  for i := 0 to Screen.MonitorCount - 1 do
  begin

    schDispPnl[i].Left := (trunc(Screen.Monitors[i].Left * scaleLObyXY) div 2) +
      scaleTocntrX;
    schDispPnl[i].Top  := (trunc(Screen.Monitors[i].Top * scaleLObyXY) div 2) +
      scaleTocntrY;

    schDispPnl[i].Width  := (trunc(Screen.Monitors[i].Width * scaleLObyXY) div 2);
    schDispPnl[i].Height := (trunc(Screen.Monitors[i].Height * scaleLObyXY) div 2);

    // place your labels in each
    schDispLbl[i].Left := (schDispPnl[i].Width div 2); //Center horizontally
    schDispLbl[i].Top  := (schDispPnl[i].Height div 2); //center vertically

    // lay out the "highlighter panels"
    schDisSnapHLt[i].Left    := 0;
    schDisSnapHLt[i].Top     := 0;
    schDisSnapHLt[i].Width   := schDispPnl[i].Width;
    schDisSnapHLt[i].Height  := 5;
    schDisSnapHLt[i].Color   := clRed;
    schDisSnapHLt[i].Visible := False;

    schDisSnapHLb[i].Left    := 0;
    schDisSnapHLb[i].Top     := schDispPnl[i].Height - 5;
    schDisSnapHLb[i].Width   := schDispPnl[i].Width;
    schDisSnapHLb[i].Height  := 5;
    schDisSnapHLb[i].Color   := clRed;
    schDisSnapHLb[i].Visible := False;

    schDisSnapHLl[i].Left    := 0;
    schDisSnapHLl[i].Top     := 0;
    schDisSnapHLl[i].Width   := 5;
    schDisSnapHLl[i].Height  := schDispPnl[i].Height;
    schDisSnapHLl[i].Color   := clRed;
    schDisSnapHLl[i].Visible := False;

    schDisSnapHLr[i].Left    := schDispPnl[i].Width - 5;
    schDisSnapHLr[i].Top     := 0;
    schDisSnapHLr[i].Width   := 5;
    schDisSnapHLr[i].Height  := schDispPnl[i].Height;
    schDisSnapHLr[i].Color   := clRed;
    schDisSnapHLr[i].Visible := False;

  end;
end;

end.
