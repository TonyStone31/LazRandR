unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  Grids, ExtCtrls, StrUtils, Types;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnReload: TButton;
    btnAddFake: TButton;
    ListBox1: TListBox;
    pnlLayout: TPanel;
    StringGrid1: TStringGrid;
    procedure btnReloadClick(Sender: TObject);
    procedure btnAddFakeClick(Sender: TObject);
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


  pnlMoving: boolean = False;
  mmDownSx, mmDownSy: integer;

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
  makPnlsFromCurrent;
  posPnls2Current;
end;

procedure TForm1.btnAddFakeClick(Sender: TObject);
var
  i: integer;
begin
  SetLength(schDisplays, length(schdisplays)+1);
  SetLength(schDisplaysRects, length(schdisplays)+1);
  setlength(schDisplaysLbl, length(schdisplays)+1);
  i:=length(schDisplays)-1;
  ListBox1.Items.Add('Fake Display ' + IntToStr(i));



    schDisplays[i] := TPanel.Create(Form1);
    schDisplays[i].OnPaint := @pnlDispArPaint;
    schDisplays[i].OnClick := @pnlDispArClick;
    schDisplays[i].OnMouseEnter := @pnlDispArMouseEnter;
    schDisplays[i].OnMouseLeave := @pnlDispArMouseLeave;
    schDisplays[i].OnMouseDown := @pnlDispArMouseDown;
    schDisplays[i].OnMouseUp := @pnlDispArMouseUp;
    schDisplays[i].OnMouseMove := @pnlDispArMouseMove;
    schDisplays[i].OnMouseDown := @pnlDispArMouseDown;


    schDisplaysLbl[i] := TLabel.Create(schDisplays[i]);
    schDisplaysLbl[i].Caption := IntToStr(i);
    schDisplaysLbl[i].Parent := schDisplays[i];
    schDisplays[i].BevelColor := clWhite;
    schDisplays[i].BorderStyle := bsSingle;
    schDisplays[i].Parent := pnlLayout;
    schDisplays[i].top := schDisplays[i-1].Top;
    schDisplays[i].left := schDisplays[i-1].left;
end;



procedure TForm1.ListBox1Click(Sender: TObject);
begin
  if AnsiContainsText(ListBox1.Items[ListBox1.ItemIndex],'fake') then exit;
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
  i: integer;
  pnl: TPanel;
begin
  pnl := Sender as TPanel;
  for i := 0 to Length(schDisplays) - 1 do
  begin
    //find the display clicked and set listindex
    if pnl.Handle = schDisplays[i].Handle then
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
  pnl := Sender as TPanel;
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
  i: integer;
  snapCloseTop, SnapCloseLeft, SnapCloseRight, SnapCloseBottom: integer;
  goTop, goBottom, goLeft, goRight: boolean;
  overLappersX, overLappersY: array of boolean;

  snapToT, SnapToB, SnapToL, SnapToR: array of boolean;
  ovLapsT, ovLapsB, ovLapsL, ovLapsR: array of boolean;
  enSnapT, enSnapB, enSnapL, enSnapR: integer; // final calculated positions to snap to

  olThrHo: integer = 25; // distance from other edge threshhold i guess
begin
  pnl := Sender as TPanel;
  if (Shift = [ssLeft]) and (pnlMoving) then
  begin
    pnl.Left := pnl.Left + (x - mmDownSx);
    pnl.Top := pnl.Top + (y - mmDownSy);
  end;

    SetLength(overLappersX, Length(schDisplays));
    SetLength(overLappersY, Length(schDisplays));
    SetLength(snapToT, Length(schDisplays));
    SetLength(SnapToB, Length(schDisplays));
    SetLength(SnapToL, Length(schDisplays));
    SetLength(SnapToR, Length(schDisplays));
    SetLength(ovLapsT, Length(schDisplays));
    SetLength(ovLapsB, Length(schDisplays));
    SetLength(ovLapsL, Length(schDisplays));
    SetLength(ovLapsR, Length(schDisplays));


  if (Shift = [ssLeft]) and (pnlMoving) then begin
    for i:=0 to Length(schDisplays)-1 do begin
      if pnl.Handle = schDisplays[i].Handle then continue;

      if (abs(pnl.Top)+olThrHo > abs(schDisplays[i].Top)) and
         (abs(pnl.Top)-olThrHo > abs(schDisplays[i].Top)) then begin
         snapToT[i]:=True;
      end else snapToB[i]:=false;

      if (abs(pnl.BoundsRect.Bottom)+olThrHo > abs(schDisplays[i].BoundsRect.Bottom)) and
         (abs(pnl.BoundsRect.Bottom)-olThrHo > abs(schDisplays[i].BoundsRect.Bottom)) then begin
         snapToB[i]:=True;
      end else snapToT[i]:=false;

    end;

  end;

  for i:=0 to Length(schDisplays)-1 do begin
    if snapToT[i] = true then pnl.Top:=schDisplays[i].Top ;
  end;

  for i:=0 to Length(schDisplays)-1 do begin
    if snapToB[i] = true then pnl.Top:=schDisplays[i].Top-schDisplays[i].Height ;
  end;


end;

procedure TForm1.pnlDispArMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  pnl: TPanel;
  i: integer;
  snapCloseTop, SnapCloseLeft, SnapCloseRight, SnapCloseBottom: integer;
  goTop, goBottom, goLeft, goRight: boolean;
  overLappersX, overLappersY: array of boolean;

  snapToT, SnapToB, SnapToL, SnapToR: array of boolean;
  ovLapsT, ovLapsB, ovLapsL, ovLapsR: array of boolean;
  enSnapT, enSnapB, enSnapL, enSnapR: integer; // final calculated positions to snap to

  olThrHo: integer = 20; // distance from other edge threshhold i guess
begin
  if Button = mbLeft then
  begin

    pnl := Sender as TPanel;
    pnlMoving := False;


  //  SetLength(overLappersX, Length(schDisplays));
  //  SetLength(overLappersY, Length(schDisplays));
  //  SetLength(snapToT, Length(schDisplays));
  //  SetLength(SnapToB, Length(schDisplays));
  //  SetLength(SnapToL, Length(schDisplays));
  //  SetLength(SnapToR, Length(schDisplays));
  //  SetLength(ovLapsT, Length(schDisplays));
  //  SetLength(ovLapsB, Length(schDisplays));
  //  SetLength(ovLapsL, Length(schDisplays));
  //  SetLength(ovLapsR, Length(schDisplays));
  //
  //  //find Tops to snap to first i think
  //  for i := 0 to Length(schDisplays) - 1 do
  //  begin
  //    //find if it needs to snap to a bottom or top of another panel
  //    if pnl.Handle = schDisplays[i].Handle then
  //    begin
  //      overLappersY[i] := False; // well it certainly doesn't overlap itself, does it?
  //      continue; // restart loop and increase i
  //    end;
  //
  //
  //    if (pnl.Top < schDisplays[i].Top + olThrHo) and (pnl.top <
  //      schDisplays[i].top - olThrHo) then
  //    begin
  //      ovLapsT[i] := True; //over
  //      pnl.Top := schDisplays[i].BoundsRect.Bottom;
  //      exit;
  //    end
  //    else
  //    begin
  //      overLappersY[i] := False;
  //
  //    end;
  //
  //  end;
  //
  //  //for i:=0 to Length(schDisplays) do begin
  //
  //  //  WriteLn('X Overlap with Display'+IntToStr(i)+BoolToStr(overLappersX[i],true);
  //  //end;
  //
  //end;
  end;

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
      ListBox1.Items.Add('Display ' + IntToStr(screen.Monitors[i].MonitorNum) +
        ' (Primary)')
    else
      ListBox1.Items.Add('Display ' + IntToStr(screen.Monitors[i].MonitorNum)
        );



    schDisplays[i] := TPanel.Create(Form1);
    schDisplays[i].OnPaint := @pnlDispArPaint;
    schDisplays[i].OnClick := @pnlDispArClick;
    schDisplays[i].OnMouseEnter := @pnlDispArMouseEnter;
    schDisplays[i].OnMouseLeave := @pnlDispArMouseLeave;
    schDisplays[i].OnMouseDown := @pnlDispArMouseDown;
    schDisplays[i].OnMouseUp := @pnlDispArMouseUp;
    schDisplays[i].OnMouseMove := @pnlDispArMouseMove;
    schDisplays[i].OnMouseDown := @pnlDispArMouseDown;


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
  scaleTocntrY := pnlLayout.Height div 4;

  for i := 0 to Screen.MonitorCount - 1 do
  begin

    schDisplays[i].Left := (trunc(Screen.Monitors[i].Left * scaleLObyXY) div 2) +
      scaleTocntrX;
    schDisplays[i].Top := (trunc(Screen.Monitors[i].Top * scaleLObyXY) div 2) +
      scaleTocntrY;

    schDisplays[i].Width := (trunc(Screen.Monitors[i].Width * scaleLObyXY) div 2);
    schDisplays[i].Height := (trunc(Screen.Monitors[i].Height * scaleLObyXY) div 2);
  end;
end;

end.
