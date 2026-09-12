unit uDisplayTypes;

{ Shared data types for LazRandR.

  Everything the app knows about a display output or an input device is
  described here so the xrandr layer, the touch layer and the UI can pass
  state around without depending on each other. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  { Screen rotation. The ordinal order matches a 90 degree clockwise step,
    which makes "rotate by one notch" a simple Succ() with wraparound. }
  TRotation = (rotNormal, rotRight, rotInverted, rotLeft);

  { A single resolution+refresh pairing reported by xrandr. }
  TModeInfo = record
    Width: integer;
    Height: integer;
    Rate: double;
    IsPreferred: boolean;
    IsCurrent: boolean;
  end;
  TModeArray = array of TModeInfo;

  { One xrandr output (a physical connector). Holds both the state read back
    from the server and the state the user is editing -- the UI mutates the
    Desired* fields and Apply turns those into an xrandr command line. }
  TOutputInfo = record
    Name: string;
    Connected: boolean;
    Active: boolean;          // currently has geometry on the X screen
    Primary: boolean;
    // Live geometry as reported (logical, i.e. already rotated)
    X, Y: integer;
    LogicalW, LogicalH: integer;
    // Live mode (panel native orientation, i.e. pre-rotation)
    ModeW, ModeH: integer;
    Rate: double;
    Rotation: TRotation;
    // Physical size in mm from EDID, 0 when unknown
    MMWidth, MMHeight: integer;
    Modes: TModeArray;
    // ---- user-edited state ----
    DesiredEnabled: boolean;
    DesiredX, DesiredY: integer;
    DesiredModeW, DesiredModeH: integer;
    DesiredRate: double;
    DesiredRotation: TRotation;
    DesiredPrimary: boolean;
  end;
  TOutputArray = array of TOutputInfo;

  { Classification of an X input device. Only the pointer-ish absolute devices
    matter to us; the rest are filtered out before they reach the UI. }
  TDeviceKind = (dkOther, dkTouchscreen, dkStylus, dkEraser, dkTouchpad);

  { A 3x3 coordinate transformation matrix in row-major order, matching the
    layout xinput expects for "Coordinate Transformation Matrix". }
  TCTM = array[0..8] of double;

  { An X input device that can be bound to an output. }
  TInputDevice = record
    Id: integer;
    Name: string;
    Kind: TDeviceKind;
    IsSlave: boolean;
    Matrix: TCTM;
    HasMatrix: boolean;
    MappedOutput: string;     // output name inferred from Matrix, '' if none/whole desktop
    DesiredOutput: string;    // what the user picked; '' = whole desktop
  end;
  TInputDeviceArray = array of TInputDevice;

const
  IdentityCTM: TCTM = (1, 0, 0, 0, 1, 0, 0, 0, 1);

  RotationNames: array[TRotation] of string =
    ('normal', 'right', 'inverted', 'left');

  { What the user sees. xrandr's own labels read backwards to most people
    (--rotate right gives you a clockwise-rotated image), so spell it out. }
  RotationCaptions: array[TRotation] of string =
    ('Landscape', 'Portrait (clockwise)', 'Landscape (flipped)', 'Portrait (counter-clockwise)');

  RotationShort: array[TRotation] of string =
    ('0', '90', '180', '270');

  DeviceKindNames: array[TDeviceKind] of string =
    ('Other', 'Touchscreen', 'Stylus', 'Eraser', 'Touchpad');

function StrToRotation(const S: string): TRotation;
function RotationIsPortrait(R: TRotation): boolean;
function NextRotation(R: TRotation): TRotation;

{ Compose the matrix that confines an absolute input device to a sub-rectangle
  of the whole X screen, honouring the output's rotation.

  This is the piece Cinnamon's display panel never does, and the reason a
  touchscreen reports coordinates across the entire desktop instead of just
  its own panel. }
function BuildCTM(OutX, OutY, OutW, OutH, ScreenW, ScreenH: integer;
  Rotation: TRotation): TCTM;

function CTMToString(const M: TCTM): string;
function CTMEquals(const A, B: TCTM): boolean;

{ Format a rate the way xrandr wants it (dot decimal separator, 2 places). }
function RateToStr(R: double): string;
function SameRate(A, B: double): boolean;

implementation

function StrToRotation(const S: string): TRotation;
var
  T: string;
begin
  T := LowerCase(Trim(S));
  if T = 'left' then Result := rotLeft
  else if T = 'right' then Result := rotRight
  else if (T = 'inverted') or (T = 'upsidedown') then Result := rotInverted
  else Result := rotNormal;
end;

function RotationIsPortrait(R: TRotation): boolean;
begin
  Result := R in [rotLeft, rotRight];
end;

function NextRotation(R: TRotation): TRotation;
begin
  if R = High(TRotation) then
    Result := Low(TRotation)
  else
    Result := Succ(R);
end;

function BuildCTM(OutX, OutY, OutW, OutH, ScreenW, ScreenH: integer;
  Rotation: TRotation): TCTM;
var
  Scale, Rot, Res: TCTM;
  i, j, k: integer;
  Sum: double;
begin
  Result := IdentityCTM;
  if (ScreenW <= 0) or (ScreenH <= 0) or (OutW <= 0) or (OutH <= 0) then
    Exit;

  { Scale+translate: map the full [0..1] input range onto the output's
    rectangle expressed as a fraction of the whole screen. }
  Scale := IdentityCTM;
  Scale[0] := OutW / ScreenW;
  Scale[2] := OutX / ScreenW;
  Scale[4] := OutH / ScreenH;
  Scale[5] := OutY / ScreenH;

  { Rotation about the unit square. These are the standard xinput rotation
    matrices; note they rotate the *input coordinates*, which is why right
    and left look swapped relative to a naive rotation matrix. }
  case Rotation of
    rotNormal:
      Rot := IdentityCTM;
    rotRight:
      begin
        Rot := IdentityCTM;
        Rot[0] := 0;  Rot[1] := 1;  Rot[2] := 0;
        Rot[3] := -1; Rot[4] := 0;  Rot[5] := 1;
        Rot[6] := 0;  Rot[7] := 0;  Rot[8] := 1;
      end;
    rotInverted:
      begin
        Rot := IdentityCTM;
        Rot[0] := -1; Rot[1] := 0;  Rot[2] := 1;
        Rot[3] := 0;  Rot[4] := -1; Rot[5] := 1;
        Rot[6] := 0;  Rot[7] := 0;  Rot[8] := 1;
      end;
    rotLeft:
      begin
        Rot := IdentityCTM;
        Rot[0] := 0;  Rot[1] := -1; Rot[2] := 1;
        Rot[3] := 1;  Rot[4] := 0;  Rot[5] := 0;
        Rot[6] := 0;  Rot[7] := 0;  Rot[8] := 1;
      end;
  end;

  { Res := Scale * Rot }
  Res := IdentityCTM;
  for i := 0 to 2 do
    for j := 0 to 2 do
    begin
      Sum := 0;
      for k := 0 to 2 do
        Sum := Sum + Scale[i * 3 + k] * Rot[k * 3 + j];
      Res[i * 3 + j] := Sum;
    end;

  Result := Res;
end;

function CTMToString(const M: TCTM): string;
var
  i: integer;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := '';
  for i := 0 to 8 do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + FormatFloat('0.######', M[i], FS);
  end;
end;

function CTMEquals(const A, B: TCTM): boolean;
var
  i: integer;
begin
  Result := True;
  for i := 0 to 8 do
    if Abs(A[i] - B[i]) > 0.0005 then
    begin
      Result := False;
      Exit;
    end;
end;

function RateToStr(R: double): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FormatFloat('0.00', R, FS);
end;

function SameRate(A, B: double): boolean;
begin
  Result := Abs(A - B) < 0.02;
end;

end.
