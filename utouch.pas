unit uTouch;

{ Touch / stylus input mapping.

  This is the part Cinnamon's display panel has no answer for. An absolute
  input device reports coordinates spanning the WHOLE X screen, so on a
  multi-monitor desktop a touch on the portable panel lands on whichever
  monitor happens to occupy that fraction of the desktop -- usually not the
  panel you touched.

  The fix is a per-device Coordinate Transformation Matrix confining the
  device to its output's rectangle. We compute that matrix ourselves (see
  uDisplayTypes.BuildCTM) rather than leaning on "xinput --map-to-output",
  because we also need to emit it into a persistence script where the output
  may not be active at the moment the script runs. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, uDisplayTypes, uXRandR;

type

  { TTouchManager }

  TTouchManager = class
  private
    FDevices: TInputDeviceArray;
    FXR: TXRandR;
    function ClassifyDevice(const AName: string; const Props: string): TDeviceKind;
    function ReadMatrix(Id: integer; out M: TCTM): boolean;
  public
    constructor Create(AXR: TXRandR);

    { Enumerate absolute pointer devices worth mapping. }
    function Refresh: boolean;

    { Work out which output each device's current matrix corresponds to, by
      comparing against the matrix each output would produce. }
    procedure ResolveCurrentMapping;

    { The xinput command that pins one device to one output. Addressed by
      device NAME so the command survives the id reshuffling that happens on
      every replug and reboot. }
    function BuildMapCommand(const Dev: TInputDevice; const OutputName: string;
      UseDesiredLayout: boolean): string;

    { Apply the desired mapping for every device. }
    function ApplyAll(out Output: string): boolean;

    { Every map command, for the persistence script. }
    procedure BuildAllCommands(List: TStrings; UseDesiredLayout: boolean);

    { Restore every device to the matrix it has right now. Paired with
      TXRandR.BuildRestoreCommand so an undo puts input back too -- geometry
      alone would leave touch mapped to a layout that no longer exists. }
    procedure BuildRestoreCommands(List: TStrings);

    { Enable or disable a device outright. A touchscreen attached to an
      output that is off still reports across the whole desktop and will
      fight the mouse for the pointer, so being able to switch it off from
      here is not a luxury. }
    function SetDeviceEnabled(Index: integer; AEnabled: boolean;
      out Output: string): boolean;

    function IndexOfDevice(Id: integer): integer;
    function HasPendingChanges: boolean;
    function TouchDeviceCount: integer;

    property Devices: TInputDeviceArray read FDevices;
  end;

implementation

const
  CTMProp = 'Coordinate Transformation Matrix';

constructor TTouchManager.Create(AXR: TXRandR);
begin
  inherited Create;
  FXR := AXR;
  SetLength(FDevices, 0);
end;

function TTouchManager.ClassifyDevice(const AName: string;
  const Props: string): TDeviceKind;
var
  N: string;
begin
  N := LowerCase(AName);

  if Pos('eraser', N) > 0 then
    Result := dkEraser
  else if (Pos('stylus', N) > 0) or (Pos(' pen', N) > 0) then
    Result := dkStylus
  else if Pos('touchpad', N) > 0 then
    Result := dkTouchpad
  else if (Pos('touchscreen', N) > 0) or (Pos('touch screen', N) > 0) or
          (Pos('finger', N) > 0) or (Pos('touch', N) > 0) then
    Result := dkTouchscreen
  { Fall back on capabilities: an absolute-axis device with a transform
    matrix is mappable even when its name says nothing useful. }
  else if (Pos('Abs MT Position', Props) > 0) or
          (Pos('Abs Position', Props) > 0) then
    Result := dkTouchscreen
  else
    Result := dkOther;
end;

function TTouchManager.ReadMatrix(Id: integer; out M: TCTM): boolean;
var
  Output, Line, Nums: string;
  Lines, Parts: TStringList;
  i, P: integer;
  FS: TFormatSettings;
  V: double;
begin
  Result := False;
  M := IdentityCTM;

  if not FXR.Run(Format('xinput list-props %d', [Id]), Output) then Exit;

  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  Lines := TStringList.Create;
  Parts := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      if Pos(CTMProp, Line) = 0 then Continue;
      P := Pos(':', Line);
      if P = 0 then Continue;
      Nums := Copy(Line, P + 1, MaxInt);
      Parts.Delimiter := ',';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := Nums;
      if Parts.Count < 9 then Continue;
      for P := 0 to 8 do
      begin
        if not TryStrToFloat(Trim(Parts[P]), V, FS) then Exit;
        M[P] := V;
      end;
      Result := True;
      Exit;
    end;
  finally
    Lines.Free;
    Parts.Free;
  end;
end;

function TTouchManager.Refresh: boolean;
var
  Output, Line, NameVal, Props, IdStr: string;
  Lines: TStringList;
  i, P, Q, Id, n: integer;
  Kind: TDeviceKind;
  M: TCTM;
begin
  Result := False;
  SetLength(FDevices, 0);

  { --short keeps the tree-drawing characters but one device per line. }
  if not FXR.Run('xinput list --short', Output) then Exit;

  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];

      { Slave pointers carry a transformation matrix. A DISABLED device is
        reported as "floating slave" instead -- match it too, otherwise a
        device vanishes from the UI the moment you switch it off and there is
        no way to switch it back on. }
      if (Pos('slave  pointer', Line) = 0) and
         (Pos('floating slave', Line) = 0) then Continue;

      P := Pos('id=', Line);
      if P = 0 then Continue;

      { Name is everything between the tree glyph and the id column. }
      Q := P - 1;
      while (Q > 1) and (Line[Q] in [' ', #9]) do Dec(Q);
      NameVal := Copy(Line, 1, Q);
      { Strip the leading box-drawing/arrow decoration. }
      Q := 1;
      while Q <= Length(NameVal) do
      begin
        if NameVal[Q] in ['A'..'Z', 'a'..'z', '0'..'9'] then Break;
        Inc(Q);
      end;
      NameVal := Trim(Copy(NameVal, Q, MaxInt));
      if NameVal = '' then Continue;

      IdStr := '';
      Q := P + 3;
      while (Q <= Length(Line)) and (Line[Q] in ['0'..'9']) do
      begin
        IdStr := IdStr + Line[Q];
        Inc(Q);
      end;
      if not TryStrToInt(IdStr, Id) then Continue;

      if not FXR.Run(Format('xinput list-props %d', [Id]), Props) then
        Props := '';

      { No transformation matrix means nothing for us to set. }
      if Pos(CTMProp, Props) = 0 then Continue;

      Kind := ClassifyDevice(NameVal, Props);
      { Touchpads are relative pointers in practice; mapping them to an
        output is almost never what anyone wants, so leave them out. }
      if Kind in [dkOther, dkTouchpad] then Continue;

      if not ReadMatrix(Id, M) then
        M := IdentityCTM;

      n := Length(FDevices);
      SetLength(FDevices, n + 1);
      FDevices[n].Id := Id;
      FDevices[n].Name := NameVal;
      FDevices[n].Kind := Kind;
      FDevices[n].IsSlave := True;
      FDevices[n].Matrix := M;
      FDevices[n].HasMatrix := True;
      FDevices[n].Enabled := Pos('Device Enabled', Props) = 0;
      P := Pos('Device Enabled', Props);
      if P > 0 then
      begin
        Q := PosEx(':', Props, P);
        FDevices[n].Enabled := (Q > 0) and
          (Pos('1', Copy(Props, Q, 8)) > 0);
      end;
      FDevices[n].MappedOutput := '';
      FDevices[n].DesiredOutput := '';
    end;

    ResolveCurrentMapping;
    Result := True;
  finally
    Lines.Free;
  end;
end;

procedure TTouchManager.ResolveCurrentMapping;
var
  i, j, LW, LH: integer;
  Candidate: TCTM;
  Outs: TOutputArray;
begin
  Outs := FXR.Outputs;
  for i := 0 to High(FDevices) do
  begin
    FDevices[i].MappedOutput := '';

    if CTMEquals(FDevices[i].Matrix, IdentityCTM) then
    begin
      { Identity = spanning the whole desktop. That is exactly the broken
        state we exist to fix, so leave MappedOutput empty. }
      FDevices[i].DesiredOutput := '';
      Continue;
    end;

    for j := 0 to High(Outs) do
    begin
      if not Outs[j].Active then Continue;
      LW := Outs[j].LogicalW;
      LH := Outs[j].LogicalH;
      Candidate := BuildCTM(Outs[j].X, Outs[j].Y, LW, LH,
        FXR.ScreenW, FXR.ScreenH, Outs[j].Rotation);
      if CTMEquals(Candidate, FDevices[i].Matrix) then
      begin
        FDevices[i].MappedOutput := Outs[j].Name;
        Break;
      end;
    end;

    FDevices[i].DesiredOutput := FDevices[i].MappedOutput;
  end;
end;

function TTouchManager.BuildMapCommand(const Dev: TInputDevice;
  const OutputName: string; UseDesiredLayout: boolean): string;
var
  idx, LW, LH, SW, SH, OX, OY: integer;
  Rot: TRotation;
  M: TCTM;
begin
  Result := '';

  if OutputName = '' then
  begin
    { Whole desktop: identity resets any previous confinement. }
    Result := Format('xinput set-prop "%s" "%s" %s',
      [Dev.Name, CTMProp, CTMToString(IdentityCTM)]);
    Exit;
  end;

  idx := FXR.IndexOfOutput(OutputName);
  if idx < 0 then Exit;

  if UseDesiredLayout then
  begin
    if not FXR.Outputs[idx].DesiredEnabled then Exit;
    OX := FXR.Outputs[idx].DesiredX;
    OY := FXR.Outputs[idx].DesiredY;
    Rot := FXR.Outputs[idx].DesiredRotation;
    if RotationIsPortrait(Rot) then
    begin
      LW := FXR.Outputs[idx].DesiredModeH;
      LH := FXR.Outputs[idx].DesiredModeW;
    end
    else
    begin
      LW := FXR.Outputs[idx].DesiredModeW;
      LH := FXR.Outputs[idx].DesiredModeH;
    end;
    FXR.DesiredScreenSize(SW, SH);
  end
  else
  begin
    if not FXR.Outputs[idx].Active then Exit;
    OX := FXR.Outputs[idx].X;
    OY := FXR.Outputs[idx].Y;
    Rot := FXR.Outputs[idx].Rotation;
    LW := FXR.Outputs[idx].LogicalW;
    LH := FXR.Outputs[idx].LogicalH;
    SW := FXR.ScreenW;
    SH := FXR.ScreenH;
  end;

  M := BuildCTM(OX, OY, LW, LH, SW, SH, Rot);
  Result := Format('xinput set-prop "%s" "%s" %s',
    [Dev.Name, CTMProp, CTMToString(M)]);
end;

procedure TTouchManager.BuildAllCommands(List: TStrings; UseDesiredLayout: boolean);
var
  i: integer;
  Cmd: string;
begin
  for i := 0 to High(FDevices) do
  begin
    Cmd := BuildMapCommand(FDevices[i], FDevices[i].DesiredOutput, UseDesiredLayout);
    if Cmd <> '' then
      List.Add(Cmd);
  end;
end;

procedure TTouchManager.BuildRestoreCommands(List: TStrings);
var
  i: integer;
begin
  for i := 0 to High(FDevices) do
    List.Add(Format('xinput set-prop "%s" "%s" %s',
      [FDevices[i].Name, CTMProp, CTMToString(FDevices[i].Matrix)]));
end;

function TTouchManager.ApplyAll(out Output: string): boolean;
var
  Cmds: TStringList;
  i: integer;
  Res, One: string;
begin
  Result := True;
  Output := '';
  Res := '';
  Cmds := TStringList.Create;
  try
    BuildAllCommands(Cmds, False);
    for i := 0 to Cmds.Count - 1 do
    begin
      if not FXR.Run(Cmds[i], One) then
      begin
        Result := False;
        Res := Res + Cmds[i] + LineEnding + One + LineEnding;
      end;
    end;
    Output := Res;
  finally
    Cmds.Free;
  end;
end;

function TTouchManager.SetDeviceEnabled(Index: integer; AEnabled: boolean;
  out Output: string): boolean;
const
  Verb: array[boolean] of string = ('disable', 'enable');
begin
  Result := False;
  Output := '';
  if (Index < 0) or (Index > High(FDevices)) then Exit;
  Result := FXR.Run(Format('xinput %s %d', [Verb[AEnabled], FDevices[Index].Id]),
    Output);
  if Result then
    FDevices[Index].Enabled := AEnabled;
end;

function TTouchManager.IndexOfDevice(Id: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FDevices) do
    if FDevices[i].Id = Id then
      Exit(i);
end;

function TTouchManager.HasPendingChanges: boolean;
var
  i: integer;
begin
  Result := True;
  for i := 0 to High(FDevices) do
    if FDevices[i].DesiredOutput <> FDevices[i].MappedOutput then
      Exit;
  Result := False;
end;

function TTouchManager.TouchDeviceCount: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FDevices) do
    if FDevices[i].Kind in [dkTouchscreen, dkStylus, dkEraser] then
      Inc(Result);
end;

end.
