unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ValEdit,
  Grids, ExtCtrls, AnchorDockPanel, Types;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnReload: TButton;
    ListBox1: TListBox;
    pnlLayout: TPanel;
    StringGrid1: TStringGrid;
    procedure btnReloadClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure ListBox1Click(Sender: TObject);
    procedure pnlDispArClick(Sender: TObject);
    procedure pnlDispArContextPopup(Sender: TObject; MousePos: TPoint;
      var Handled: Boolean);
    procedure pnlDispArMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pnlDispArMouseEnter(Sender: TObject);
    procedure pnlDispArMouseLeave(Sender: TObject);
    procedure pnlDispArMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer
      );
    procedure pnlDispArMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pnlDispArPaint(Sender: TObject);
  private

  public
    procedure makPnlsFromCurrent;
    procedure posPnls2Current;

  end;

var
  Form1: TForm1;
  schDisplays: array of TPanel;
  schDisplaysRects: array of TRect;
  schDisplaysLbl: array of TLabel;
  scaleLObyXY: double;
  scaleTocntrX, scaleTocntrY: integer;
  scaleTocntrXYi: integer;


  pnlMoving: Boolean = false;
  mmDownSx, mmDownSy: Integer;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  makPnlsFromCurrent;
  posPnls2Current;
end;

procedure TForm1.btnReloadClick(Sender: TObject);
begin
  posPnls2Current;
end;

procedure TForm1.FormResize(Sender: TObject);
begin

end;




procedure TForm1.ListBox1Click(Sender: TObject);
begin

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
begin

end;

procedure TForm1.pnlDispArContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin

end;

procedure TForm1.pnlDispArMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  pnl: TPanel;
begin
  pnl:=sender as TPanel;
  pnlMoving:=true;
  mmDownSx:=x;
  mmDownSy:=y;

end;

procedure TForm1.pnlDispArMouseEnter(Sender: TObject);
var
  pnl: TPanel;
begin
  pnl:=sender as TPanel;
  pnl.BevelInner:=bvRaised;
end;

procedure TForm1.pnlDispArMouseLeave(Sender: TObject);
var
  pnl: TPanel;
begin
  pnl:=sender as TPanel;
  pnl.BevelInner:=bvNone;

end;

procedure TForm1.pnlDispArMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
var
  pnl: TPanel;
begin
  pnl:=sender as TPanel;
  if (Shift = [ssLeft]) and (pnlMoving) then begin
    pnl.Left:=pnl.Left + (x - mmDownSx);
    pnl.Top:=pnl.Top + (y - mmDownSy);
  end;

end;

procedure TForm1.pnlDispArMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  pnl: TPanel;
  snapCloseTop, SnapCloseLeft, SnapCloseRight, SnapCloseBottom, i: Integer;
  goTop, goBottom, goLeft, goRight: Boolean;
  overLappersX,overLappersY: Array of Boolean;
begin
  pnl:=sender as TPanel;
  pnlMoving:=False;
  SetLength(overLappersX,Length(schDisplays));
  SetLength(overLappersY,Length(schDisplays));

  //find overlapperY first i think
  for i:=0 to Length(schDisplays)-1 do begin
    //find if it needs to snap to a bottom or top of another panel
    if pnl.Handle=schDisplays[i].Handle then begin
      overLappersY[i]:=false; // well it certainly doesnt overlap itself, does it?
      WriteLn('Skip loop Y Overlap with Display'+IntToStr(i)+BoolToStr(overLappersY[i],true));
      continue;
    end;
      if (pnl.Top > schDisplays[i].Top) and
         (pnl.top+pnl.Height < schDisplays[i].top+schDisplays[i].Height) then
           overLappersY[i]:=true else overLappersY[i]:=false;
   WriteLn('Y Overlap with Display'+IntToStr(i)+BoolToStr(overLappersY[i],true));
  end;

  //for i:=0 to Length(schDisplays) do begin
  //
  //  WriteLn('X Overlap with Display'+IntToStr(i)+BoolToStr(overLappersX[i],true);
  //end;



end;

procedure TForm1.pnlDispArPaint(Sender: TObject);
begin

end;

procedure TForm1.makPnlsFromCurrent;
var
  i: integer;
begin
  SetLength(schDisplays, Screen.MonitorCount);
    SetLength(schDisplaysRects, Screen.MonitorCount);
    setlength(schDisplaysLbl, screen.MonitorCount);

    for i := 0 to Screen.MonitorCount - 1 do
    begin
      if screen.Monitors[i].Primary then
        ListBox1.Items.Add('Display ' + IntToStr(screen.Monitors[i].MonitorNum)
          +
          ' (Primary)')
      else
        ListBox1.Items.Add('Display ' + IntToStr(screen.Monitors[i].MonitorNum)
          );



      schDisplays[i] := TPanel.Create(Form1);
      schDisplays[i].OnPaint:=@pnlDispArPaint;
      schDisplays[i].OnClick:=@pnlDispArClick;
      schDisplays[i].OnMouseEnter:=@pnlDispArMouseEnter;
      schDisplays[i].OnMouseLeave:=@pnlDispArMouseLeave;
      schDisplays[i].OnMouseDown:=@pnlDispArMouseDown;
      schDisplays[i].OnMouseUp:=@pnlDispArMouseUp;
      schDisplays[i].OnMouseMove:=@pnlDispArMouseMove;
      schDisplays[i].OnMouseDown:=@pnlDispArMouseDown;


      schDisplaysLbl[i] := TLabel.Create(schDisplays[i]);
      schDisplaysLbl[i].Caption := IntToStr(i);
      schDisplaysLbl[i].Parent := schDisplays[i];
      schDisplays[i].BevelColor := clWhite;
      schDisplays[i].BorderStyle := bsSingle;
      schDisplays[i].Parent := pnlLayout;
    end;
end;

procedure TForm1.posPnls2Current;
var
  highR: integer;
  i: integer;
begin
  highR := 0;
  for i := 0 to screen.MonitorCount - 1 do
  begin
    if Screen.Monitors[i].BoundsRect.Right > highR then
      highR := Screen.Monitors[i].WorkareaRect.Right;
    Writeln('Highest Right: ' + IntToStr(highR));

  end;

  scaleLObyXY := pnlLayout.Width / int64(highR);
  scaleTocntrX := pnlLayout.Width div 4;
  scaleTocntrY:=pnlLayout.Height div 4;

  for i := 0 to Screen.MonitorCount - 1 do
  begin

    schDisplays[i].Left := (trunc(Screen.Monitors[i].Left * scaleLObyXY) div
      2) + scaleTocntrX;
    schDisplays[i].Top := (trunc(Screen.Monitors[i].Top * scaleLObyXY) div 2) +
      scaleTocntrY;

    schDisplays[i].Width := (trunc(Screen.Monitors[i].Width * scaleLObyXY) div 2
      );
    schDisplays[i].Height := (trunc(Screen.Monitors[i].Height * scaleLObyXY)
      div 2);
  end;
end;

end.
