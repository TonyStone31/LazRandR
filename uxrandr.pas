unit uXRandR;

{ xrandr interrogation and application.

  Replaces the old XRandrManager. The virtual-monitor / --setmonitor split
  support is gone: Cinnamon's window manager ignores XRandR monitors, so the
  feature could never do anything useful here.

  What replaced it is provider handling, because on this class of machine the
  portable USB-C panel hangs off the CPU's integrated GPU while the desktop is
  rendered by the discrete card, and the two have to be linked every session
  before the panel is usable at all. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Process, Math, uDisplayTypes;

type
  { One entry from xrandr --listproviders. }
  TProviderInfo = record
    Id: string;
    Index: integer;
    Name: string;
    CanSource: boolean;
    CanSink: boolean;
  end;
  TProviderArray = array of TProviderInfo;

  { TXRandR }

  TXRandR = class
  private
    FOutputs: TOutputArray;
    FProviders: TProviderArray;
    FScreenW, FScreenH: integer;
    FLastError: string;
    FGrowthBlocked: boolean;
    procedure ParseOutputHeader(const Line: string; var Outp: TOutputInfo);
    procedure ParseModeLine(const Line: string; var Outp: TOutputInfo);
  public
    constructor Create;

    { Re-read everything from the X server. }
    function Refresh: boolean;
    function RefreshProviders: boolean;

    { Build the xrandr command line that realises the Desired* state.
      Returns '' when nothing would change. }
    function BuildApplyCommand: string;

    { Run an arbitrary command, capturing stdout+stderr. }
    function Run(const Cmd: string; out Output: string): boolean;

    { Apply the desired configuration. }
    function Apply(out Output: string): boolean;

    { Link a render source provider to an output sink provider (reverse PRIME).
      Without this the iGPU-attached panel shows nothing at all. }
    function LinkProvider(const SinkName, SourceName: string; out Output: string): boolean;

    { Helpers. }
    function IndexOfOutput(const AName: string): integer;
    { 1-based position among CONNECTED outputs. The raw array index counts
      every phantom connector the driver exposes (this box reports 16), so it
      is useless as a label the user has to match against a screen. }
    function DisplayOrdinal(Idx: integer): integer;
    function ActiveOutputCount: integer;
    function ConnectedOutputCount: integer;
    { Total bounding box of the desired layout. }
    procedure DesiredScreenSize(out W, H: integer);
    { Normalise the desired layout so the top-left corner sits at 0,0.
      X refuses negative coordinates. }
    procedure NormaliseDesiredOrigin;
    { Reset all Desired* fields back to what the server currently reports. }
    procedure RevertDesired;
    function HasPendingChanges: boolean;

    { Find the non-NVIDIA sink provider, i.e. the one a USB-C/iGPU panel
      would be hanging off. Returns '' when there is none. }
    { A cheap signature of "what hardware is attached right now". Compared on
      a timer so the app notices a panel being plugged in or unplugged
      without the user having to think about it. One subprocess per poll. }
    function TopologyFingerprint: string;

    function FindSinkProvider: string;
    function FindSourceProvider: string;

    property Outputs: TOutputArray read FOutputs;
    property Providers: TProviderArray read FProviders;
    property ScreenW: integer read FScreenW;
    property ScreenH: integer read FScreenH;
    property LastError: string read FLastError;
    { Set once an apply has been refused with BadMatch on RRSetScreenSize.
      Some drivers -- NVIDIA here -- fix the maximum X screen size when X
      starts, so a layout needing a bigger desktop can never be applied in
      this session. Worth saying so before the user arranges one, not only
      after it fails. }
    property GrowthBlocked: boolean read FGrowthBlocked;
  end;

{ Split a string on whitespace runs. }
procedure SplitWords(const S: string; List: TStrings);

implementation

procedure SplitWords(const S: string; List: TStrings);
var
  i, Start: integer;
begin
  List.Clear;
  i := 1;
  while i <= Length(S) do
  begin
    while (i <= Length(S)) and (S[i] in [' ', #9]) do Inc(i);
    if i > Length(S) then Break;
    Start := i;
    while (i <= Length(S)) and not (S[i] in [' ', #9]) do Inc(i);
    List.Add(Copy(S, Start, i - Start));
  end;
end;

{ Parse "1920x1080+3840+0" into its four numbers. }
function ParseGeometry(const S: string; out W, H, X, Y: integer): boolean;
var
  PosX, PosPlus1, PosPlus2: integer;
  SW, SH, SX, SY: string;
begin
  Result := False;
  W := 0; H := 0; X := 0; Y := 0;

  PosX := Pos('x', S);
  if PosX < 2 then Exit;
  PosPlus1 := PosEx('+', S, PosX);
  if PosPlus1 = 0 then Exit;
  PosPlus2 := PosEx('+', S, PosPlus1 + 1);
  if PosPlus2 = 0 then Exit;

  SW := Copy(S, 1, PosX - 1);
  SH := Copy(S, PosX + 1, PosPlus1 - PosX - 1);
  SX := Copy(S, PosPlus1 + 1, PosPlus2 - PosPlus1 - 1);
  SY := Copy(S, PosPlus2 + 1, MaxInt);

  Result := TryStrToInt(SW, W) and TryStrToInt(SH, H) and
            TryStrToInt(SX, X) and TryStrToInt(SY, Y);
end;

{ Parse "1920x1080" }
function ParseResolution(const S: string; out W, H: integer): boolean;
var
  PosX: integer;
begin
  Result := False;
  W := 0; H := 0;
  PosX := Pos('x', S);
  if PosX < 2 then Exit;
  Result := TryStrToInt(Copy(S, 1, PosX - 1), W) and
            TryStrToInt(Copy(S, PosX + 1, MaxInt), H);
  { Some mode lines carry an 'i' suffix for interlaced. }
  if not Result then
  begin
    Result := TryStrToInt(Copy(S, 1, PosX - 1), W) and
              TryStrToInt(TrimRight(StringReplace(Copy(S, PosX + 1, MaxInt),
                'i', '', [rfReplaceAll])), H);
  end;
end;

{ TXRandR }

constructor TXRandR.Create;
begin
  inherited Create;
  SetLength(FOutputs, 0);
  SetLength(FProviders, 0);
  FScreenW := 0;
  FScreenH := 0;
end;

function TXRandR.Run(const Cmd: string; out Output: string): boolean;
var
  P: TProcess;
  Buf: array[0..4095] of byte;
  Read: longint;
  MS: TMemoryStream;
begin
  Result := False;
  Output := '';
  MS := TMemoryStream.Create;
  P := TProcess.Create(nil);
  try
    P.Executable := '/bin/bash';
    P.Parameters.Add('-c');
    P.Parameters.Add(Cmd + ' 2>&1');
    P.Options := [poUsePipes, poNoConsole];
    try
      P.Execute;
      while True do
      begin
        Read := P.Output.Read(Buf, SizeOf(Buf));
        if Read > 0 then
          MS.Write(Buf, Read)
        else if not P.Running then
          Break
        else
          Sleep(5);
      end;
      { Drain anything buffered after the process exited. }
      repeat
        Read := P.Output.Read(Buf, SizeOf(Buf));
        if Read > 0 then MS.Write(Buf, Read);
      until Read <= 0;

      MS.Position := 0;
      SetLength(Output, MS.Size);
      if MS.Size > 0 then
        MS.Read(Output[1], MS.Size);
      Result := P.ExitStatus = 0;
      if not Result then
        FLastError := Output;
    except
      on E: Exception do
      begin
        FLastError := E.Message;
        Result := False;
      end;
    end;
  finally
    P.Free;
    MS.Free;
  end;
end;

procedure TXRandR.ParseOutputHeader(const Line: string; var Outp: TOutputInfo);
var
  W: TStringList;
  i, GW, GH, GX, GY: integer;
  GeomIdx: integer;
  T: string;
begin
  W := TStringList.Create;
  try
    SplitWords(Line, W);
    if W.Count < 2 then Exit;

    Outp.Name := W[0];
    Outp.Connected := (W[1] = 'connected');
    Outp.Primary := False;
    Outp.Active := False;
    Outp.Rotation := rotNormal;
    Outp.MMWidth := 0;
    Outp.MMHeight := 0;
    SetLength(Outp.Modes, 0);

    GeomIdx := -1;
    for i := 2 to W.Count - 1 do
    begin
      T := W[i];
      if T = 'primary' then
        Outp.Primary := True
      else if (GeomIdx < 0) and (Pos('+', T) > 0) and (Pos('x', T) > 0) then
      begin
        if ParseGeometry(T, GW, GH, GX, GY) then
        begin
          GeomIdx := i;
          Outp.Active := True;
          Outp.X := GX;
          Outp.Y := GY;
          Outp.LogicalW := GW;
          Outp.LogicalH := GH;
        end;
      end
      else if (GeomIdx >= 0) and (i = GeomIdx + 1) then
      begin
        { The token straight after the geometry is the active rotation, but
          only when it is not already the start of the supported-rotations
          list in parentheses. }
        if (T = 'left') or (T = 'right') or (T = 'inverted') then
          Outp.Rotation := StrToRotation(T);
      end;

      { Physical size, e.g. "698mm x 393mm". }
      if (Length(T) > 2) and (Copy(T, Length(T) - 1, 2) = 'mm') then
      begin
        if Outp.MMWidth = 0 then
          Outp.MMWidth := StrToIntDef(Copy(T, 1, Length(T) - 2), 0)
        else if Outp.MMHeight = 0 then
          Outp.MMHeight := StrToIntDef(Copy(T, 1, Length(T) - 2), 0);
      end;
    end;

    { The reported geometry is post-rotation. Recover the panel's own
      orientation so the mode list lines up with it. }
    if Outp.Active then
    begin
      if RotationIsPortrait(Outp.Rotation) then
      begin
        Outp.ModeW := Outp.LogicalH;
        Outp.ModeH := Outp.LogicalW;
      end
      else
      begin
        Outp.ModeW := Outp.LogicalW;
        Outp.ModeH := Outp.LogicalH;
      end;
    end;
  finally
    W.Free;
  end;
end;

procedure TXRandR.ParseModeLine(const Line: string; var Outp: TOutputInfo);
var
  W: TStringList;
  i, MW, MH, n: integer;
  RateStr: string;
  Rate: double;
  IsCur, IsPref: boolean;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  W := TStringList.Create;
  try
    SplitWords(Line, W);
    if W.Count < 1 then Exit;
    if not ParseResolution(W[0], MW, MH) then Exit;

    for i := 1 to W.Count - 1 do
    begin
      RateStr := W[i];
      IsCur := Pos('*', RateStr) > 0;
      IsPref := Pos('+', RateStr) > 0;
      RateStr := StringReplace(RateStr, '*', '', [rfReplaceAll]);
      RateStr := StringReplace(RateStr, '+', '', [rfReplaceAll]);
      RateStr := Trim(RateStr);
      if RateStr = '' then Continue;
      if not TryStrToFloat(RateStr, Rate, FS) then Continue;

      n := Length(Outp.Modes);
      SetLength(Outp.Modes, n + 1);
      Outp.Modes[n].Width := MW;
      Outp.Modes[n].Height := MH;
      Outp.Modes[n].Rate := Rate;
      Outp.Modes[n].IsCurrent := IsCur;
      Outp.Modes[n].IsPreferred := IsPref;

      if IsCur then
        Outp.Rate := Rate;
    end;
  finally
    W.Free;
  end;
end;

function TXRandR.Refresh: boolean;
var
  Output: string;
  Lines: TStringList;
  i, n, CW, CH: integer;
  Line: string;
  Cur: TOutputInfo;
  HaveCur: boolean;
  W: TStringList;
begin
  Result := False;
  SetLength(FOutputs, 0);

  if not Run('xrandr --query', Output) then
  begin
    FLastError := 'xrandr --query failed: ' + Output;
    Exit;
  end;

  Lines := TStringList.Create;
  W := TStringList.Create;
  try
    Lines.Text := Output;
    HaveCur := False;
    FillChar(Cur, SizeOf(Cur), 0);

    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      if Trim(Line) = '' then Continue;

      if Copy(Line, 1, 7) = 'Screen ' then
      begin
        { "Screen 0: minimum 8 x 8, current 7680 x 2160, maximum 32767 x 32767" }
        SplitWords(StringReplace(Line, ',', ' ', [rfReplaceAll]), W);
        for n := 0 to W.Count - 1 do
          if (W[n] = 'current') and (n + 3 < W.Count) then
          begin
            if TryStrToInt(W[n + 1], CW) and TryStrToInt(W[n + 3], CH) then
            begin
              FScreenW := CW;
              FScreenH := CH;
            end;
            Break;
          end;
        Continue;
      end;

      if (Line[1] <> ' ') and (Line[1] <> #9) then
      begin
        { New output header -- flush the previous one. }
        if HaveCur then
        begin
          n := Length(FOutputs);
          SetLength(FOutputs, n + 1);
          FOutputs[n] := Cur;
        end;
        FillChar(Cur, SizeOf(Cur), 0);
        Cur.Name := '';
        Cur.Rate := 0;
        ParseOutputHeader(Line, Cur);
        HaveCur := Cur.Name <> '';
      end
      else if HaveCur then
        ParseModeLine(Line, Cur);
    end;

    if HaveCur then
    begin
      n := Length(FOutputs);
      SetLength(FOutputs, n + 1);
      FOutputs[n] := Cur;
    end;

    RevertDesired;
    Result := True;
  finally
    Lines.Free;
    W.Free;
  end;
end;

function TXRandR.RefreshProviders: boolean;
var
  Output: string;
  Lines: TStringList;
  i, n, P, CapVal, ColonPos: integer;
  Line, NameVal, CapStr: string;
begin
  Result := False;
  SetLength(FProviders, 0);

  if not Run('xrandr --listproviders', Output) then Exit;

  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      if Pos('Provider ', Line) = 0 then Continue;

      { "Provider 0: id: 0x1b7 cap: 0x1, Source Output crtcs: 4 ... name:NVIDIA-0" }
      P := Pos('name:', Line);
      if P = 0 then Continue;
      NameVal := Trim(Copy(Line, P + 5, MaxInt));

      n := Length(FProviders);
      SetLength(FProviders, n + 1);
      FProviders[n].Name := NameVal;
      FProviders[n].Index := n;
      FProviders[n].CanSource := Pos('Source Output', Line) > 0;
      FProviders[n].CanSink := Pos('Sink Output', Line) > 0;

      P := Pos('cap: ', Line);
      if P > 0 then
      begin
        CapStr := Copy(Line, P + 5, 32);
        ColonPos := Pos(',', CapStr);
        if ColonPos > 0 then CapStr := Copy(CapStr, 1, ColonPos - 1);
        CapStr := Trim(CapStr);
        if TryStrToInt(CapStr, CapVal) then
          FProviders[n].Id := CapStr;
      end;
    end;
    Result := True;
  finally
    Lines.Free;
  end;
end;

function TXRandR.TopologyFingerprint: string;
var
  Output: string;
begin
  Result := '';
  { Name + connected alone is not enough: switching an output off leaves it
    "connected" (the cable is still in), so the signature would never move.
    Keep the screen size, primary flag, geometry and rotation too, which also
    catches a layout changed by some other tool while we are open. }
  if Run('xrandr --query | sed -n ''/^Screen /p; / connected/p'' ' +
         '| sed ''s/(.*//''; echo ---; xinput list --id-only 2>/dev/null',
         Output) then
    Result := Output;
end;

function TXRandR.FindSinkProvider: string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(FProviders) do
    if FProviders[i].CanSink and (Pos('nvidia', LowerCase(FProviders[i].Name)) = 0) then
    begin
      Result := FProviders[i].Name;
      Exit;
    end;
end;

function TXRandR.FindSourceProvider: string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(FProviders) do
    if FProviders[i].CanSource then
    begin
      Result := FProviders[i].Name;
      Exit;
    end;
end;

function TXRandR.IndexOfOutput(const AName: string): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FOutputs) do
    if FOutputs[i].Name = AName then
      Exit(i);
end;

function TXRandR.DisplayOrdinal(Idx: integer): integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FOutputs) do
  begin
    if FOutputs[i].Connected then Inc(Result);
    if i = Idx then Exit;
  end;
  Result := Idx + 1;
end;

function TXRandR.ActiveOutputCount: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FOutputs) do
    if FOutputs[i].DesiredEnabled then Inc(Result);
end;

function TXRandR.ConnectedOutputCount: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FOutputs) do
    if FOutputs[i].Connected then Inc(Result);
end;

procedure TXRandR.RevertDesired;
var
  i, j, BestIdx: integer;
  BestRate: double;
begin
  for i := 0 to High(FOutputs) do
  begin
    FOutputs[i].DesiredEnabled := FOutputs[i].Active;
    FOutputs[i].DesiredX := FOutputs[i].X;
    FOutputs[i].DesiredY := FOutputs[i].Y;
    FOutputs[i].DesiredRotation := FOutputs[i].Rotation;
    FOutputs[i].DesiredPrimary := FOutputs[i].Primary;

    if FOutputs[i].Active then
    begin
      FOutputs[i].DesiredModeW := FOutputs[i].ModeW;
      FOutputs[i].DesiredModeH := FOutputs[i].ModeH;
      FOutputs[i].DesiredRate := FOutputs[i].Rate;
    end
    else
    begin
      { Not active: seed with the preferred mode so enabling it just works. }
      BestIdx := -1;
      BestRate := -1;
      for j := 0 to High(FOutputs[i].Modes) do
        if FOutputs[i].Modes[j].IsPreferred then
        begin
          if FOutputs[i].Modes[j].Rate > BestRate then
          begin
            BestRate := FOutputs[i].Modes[j].Rate;
            BestIdx := j;
          end;
        end;
      if (BestIdx < 0) and (Length(FOutputs[i].Modes) > 0) then
        BestIdx := 0;

      if BestIdx >= 0 then
      begin
        FOutputs[i].DesiredModeW := FOutputs[i].Modes[BestIdx].Width;
        FOutputs[i].DesiredModeH := FOutputs[i].Modes[BestIdx].Height;
        FOutputs[i].DesiredRate := FOutputs[i].Modes[BestIdx].Rate;
      end;
    end;
  end;
end;

procedure TXRandR.DesiredScreenSize(out W, H: integer);
var
  i, R, B, LW, LH: integer;
begin
  W := 0;
  H := 0;
  for i := 0 to High(FOutputs) do
  begin
    if not FOutputs[i].DesiredEnabled then Continue;
    if RotationIsPortrait(FOutputs[i].DesiredRotation) then
    begin
      LW := FOutputs[i].DesiredModeH;
      LH := FOutputs[i].DesiredModeW;
    end
    else
    begin
      LW := FOutputs[i].DesiredModeW;
      LH := FOutputs[i].DesiredModeH;
    end;
    R := FOutputs[i].DesiredX + LW;
    B := FOutputs[i].DesiredY + LH;
    if R > W then W := R;
    if B > H then H := B;
  end;
end;

procedure TXRandR.NormaliseDesiredOrigin;
var
  i, MinX, MinY: integer;
begin
  MinX := MaxInt;
  MinY := MaxInt;
  for i := 0 to High(FOutputs) do
    if FOutputs[i].DesiredEnabled then
    begin
      if FOutputs[i].DesiredX < MinX then MinX := FOutputs[i].DesiredX;
      if FOutputs[i].DesiredY < MinY then MinY := FOutputs[i].DesiredY;
    end;
  if (MinX = MaxInt) or ((MinX = 0) and (MinY = 0)) then Exit;

  for i := 0 to High(FOutputs) do
    if FOutputs[i].DesiredEnabled then
    begin
      Dec(FOutputs[i].DesiredX, MinX);
      Dec(FOutputs[i].DesiredY, MinY);
    end;
end;

function TXRandR.HasPendingChanges: boolean;
var
  i: integer;
begin
  Result := True;
  for i := 0 to High(FOutputs) do
  begin
    if FOutputs[i].DesiredEnabled <> FOutputs[i].Active then Exit;
    if not FOutputs[i].DesiredEnabled then Continue;
    if FOutputs[i].DesiredX <> FOutputs[i].X then Exit;
    if FOutputs[i].DesiredY <> FOutputs[i].Y then Exit;
    if FOutputs[i].DesiredModeW <> FOutputs[i].ModeW then Exit;
    if FOutputs[i].DesiredModeH <> FOutputs[i].ModeH then Exit;
    if FOutputs[i].DesiredRotation <> FOutputs[i].Rotation then Exit;
    if FOutputs[i].DesiredPrimary <> FOutputs[i].Primary then Exit;
    if not SameRate(FOutputs[i].DesiredRate, FOutputs[i].Rate) then Exit;
  end;
  Result := False;
end;

function TXRandR.BuildApplyCommand: string;
var
  i: integer;
  S: string;
begin
  NormaliseDesiredOrigin;
  S := 'xrandr';
  for i := 0 to High(FOutputs) do
  begin
    if not FOutputs[i].Connected and not FOutputs[i].Active then Continue;

    S := S + ' \' + LineEnding + '  --output ' + FOutputs[i].Name;
    if not FOutputs[i].DesiredEnabled then
    begin
      S := S + ' --off';
      Continue;
    end;

    S := S + ' --mode ' + IntToStr(FOutputs[i].DesiredModeW) + 'x' +
         IntToStr(FOutputs[i].DesiredModeH);
    if FOutputs[i].DesiredRate > 0 then
      S := S + ' --rate ' + RateToStr(FOutputs[i].DesiredRate);
    S := S + ' --rotate ' + RotationNames[FOutputs[i].DesiredRotation];
    S := S + ' --pos ' + IntToStr(FOutputs[i].DesiredX) + 'x' +
         IntToStr(FOutputs[i].DesiredY);
    if FOutputs[i].DesiredPrimary then
      S := S + ' --primary';
  end;
  Result := S;
end;

function TXRandR.Apply(out Output: string): boolean;
var
  Cmd: string;
begin
  Cmd := BuildApplyCommand;
  Result := Run(Cmd, Output);
  if (not Result) and
     ((Pos('RRSetScreenSize', Output) > 0) or (Pos('BadMatch', Output) > 0)) then
    FGrowthBlocked := True;
end;

function TXRandR.LinkProvider(const SinkName, SourceName: string;
  out Output: string): boolean;
begin
  Result := Run(Format('xrandr --setprovideroutputsource "%s" "%s"',
    [SinkName, SourceName]), Output);
end;

end.
