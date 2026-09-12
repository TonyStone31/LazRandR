unit uProfiles;

{ Saving, restoring and persisting display + touch layouts.

  Cinnamon writes nothing for a layout applied outside its own settings panel,
  and it has no concept of touch mapping at all, so a working arrangement is
  lost on every logout. A profile here is a plain INI file plus a generated
  shell script; the script is what an autostart entry replays at login, and it
  re-applies BOTH the geometry and the input matrices. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, FileUtil, uDisplayTypes, uXRandR, uTouch;

type

  { TProfileStore }

  TProfileStore = class
  private
    FXR: TXRandR;
    FTouch: TTouchManager;
    FConfigDir: string;
    FProfileDir: string;
    function AutostartFile: string;
    function ScriptFile: string;
  public
    constructor Create(AXR: TXRandR; ATouch: TTouchManager);

    procedure EnsureDirs;
    procedure ListProfiles(List: TStrings);
    function ProfilePath(const AName: string): string;

    function SaveProfile(const AName: string; out Err: string): boolean;
    function LoadProfile(const AName: string; out Err: string): boolean;
    function DeleteProfile(const AName: string): boolean;

    { Build the replay script covering the current desired state. }
    procedure BuildScript(Lines: TStrings; LinkProvider: boolean;
      const SinkName, SourceName: string);

    function WriteScript(out Err: string; LinkProvider: boolean;
      const SinkName, SourceName: string): boolean;

    function AutostartInstalled: boolean;
    function InstallAutostart(out Err: string): boolean;
    function RemoveAutostart(out Err: string): boolean;

    property ConfigDir: string read FConfigDir;
    property ScriptPath: string read ScriptFile;
    property AutostartPath: string read AutostartFile;
  end;

implementation

constructor TProfileStore.Create(AXR: TXRandR; ATouch: TTouchManager);
begin
  inherited Create;
  FXR := AXR;
  FTouch := ATouch;
  FConfigDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) +
    '.config/lazrandr';
  FProfileDir := FConfigDir + '/profiles';
end;

procedure TProfileStore.EnsureDirs;
begin
  if not DirectoryExists(FConfigDir) then
    ForceDirectories(FConfigDir);
  if not DirectoryExists(FProfileDir) then
    ForceDirectories(FProfileDir);
end;

function TProfileStore.ScriptFile: string;
begin
  Result := FConfigDir + '/apply-layout.sh';
end;

function TProfileStore.AutostartFile: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) +
    '.config/autostart/lazrandr-apply.desktop';
end;

function TProfileStore.ProfilePath(const AName: string): string;
var
  Safe: string;
  i: integer;
begin
  Safe := '';
  for i := 1 to Length(AName) do
    if AName[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', ' '] then
      Safe := Safe + AName[i];
  Safe := Trim(Safe);
  if Safe = '' then Safe := 'profile';
  Result := FProfileDir + '/' + Safe + '.conf';
end;

procedure TProfileStore.ListProfiles(List: TStrings);
var
  Found: TStringList;
  i: integer;
begin
  List.Clear;
  EnsureDirs;
  Found := TStringList.Create;
  try
    FindAllFiles(Found, FProfileDir, '*.conf', False);
    Found.Sort;
    for i := 0 to Found.Count - 1 do
      List.Add(ChangeFileExt(ExtractFileName(Found[i]), ''));
  finally
    Found.Free;
  end;
end;

function TProfileStore.SaveProfile(const AName: string; out Err: string): boolean;
var
  Ini: TIniFile;
  i: integer;
  Sec: string;
begin
  Result := False;
  Err := '';
  EnsureDirs;
  try
    Ini := TIniFile.Create(ProfilePath(AName));
    try
      Ini.WriteString('meta', 'name', AName);
      Ini.WriteString('meta', 'saved', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
      Ini.WriteInteger('meta', 'outputs', Length(FXR.Outputs));

      for i := 0 to High(FXR.Outputs) do
      begin
        if not FXR.Outputs[i].Connected then Continue;
        Sec := 'output:' + FXR.Outputs[i].Name;
        Ini.WriteBool(Sec, 'enabled', FXR.Outputs[i].DesiredEnabled);
        Ini.WriteInteger(Sec, 'x', FXR.Outputs[i].DesiredX);
        Ini.WriteInteger(Sec, 'y', FXR.Outputs[i].DesiredY);
        Ini.WriteInteger(Sec, 'mode_w', FXR.Outputs[i].DesiredModeW);
        Ini.WriteInteger(Sec, 'mode_h', FXR.Outputs[i].DesiredModeH);
        Ini.WriteString(Sec, 'rate', RateToStr(FXR.Outputs[i].DesiredRate));
        Ini.WriteString(Sec, 'rotation', RotationNames[FXR.Outputs[i].DesiredRotation]);
        Ini.WriteBool(Sec, 'primary', FXR.Outputs[i].DesiredPrimary);
      end;

      if FTouch <> nil then
        for i := 0 to High(FTouch.Devices) do
        begin
          Sec := 'touch:' + FTouch.Devices[i].Name;
          Ini.WriteString(Sec, 'output', FTouch.Devices[i].DesiredOutput);
          Ini.WriteString(Sec, 'kind', DeviceKindNames[FTouch.Devices[i].Kind]);
        end;

      Ini.UpdateFile;
      Result := True;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      Err := E.Message;
  end;
end;

function TProfileStore.LoadProfile(const AName: string; out Err: string): boolean;
var
  Ini: TIniFile;
  i: integer;
  Sec: string;
  FS: TFormatSettings;
  R: double;
begin
  Result := False;
  Err := '';
  if not FileExists(ProfilePath(AName)) then
  begin
    Err := 'Profile not found: ' + AName;
    Exit;
  end;

  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  try
    Ini := TIniFile.Create(ProfilePath(AName));
    try
      for i := 0 to High(FXR.Outputs) do
      begin
        Sec := 'output:' + FXR.Outputs[i].Name;
        if not Ini.SectionExists(Sec) then Continue;

        FXR.Outputs[i].DesiredEnabled := Ini.ReadBool(Sec, 'enabled', FXR.Outputs[i].DesiredEnabled);
        FXR.Outputs[i].DesiredX := Ini.ReadInteger(Sec, 'x', FXR.Outputs[i].DesiredX);
        FXR.Outputs[i].DesiredY := Ini.ReadInteger(Sec, 'y', FXR.Outputs[i].DesiredY);
        FXR.Outputs[i].DesiredModeW := Ini.ReadInteger(Sec, 'mode_w', FXR.Outputs[i].DesiredModeW);
        FXR.Outputs[i].DesiredModeH := Ini.ReadInteger(Sec, 'mode_h', FXR.Outputs[i].DesiredModeH);
        if TryStrToFloat(Ini.ReadString(Sec, 'rate', ''), R, FS) then
          FXR.Outputs[i].DesiredRate := R;
        FXR.Outputs[i].DesiredRotation := StrToRotation(Ini.ReadString(Sec, 'rotation', 'normal'));
        FXR.Outputs[i].DesiredPrimary := Ini.ReadBool(Sec, 'primary', FXR.Outputs[i].DesiredPrimary);
      end;

      if FTouch <> nil then
        for i := 0 to High(FTouch.Devices) do
        begin
          Sec := 'touch:' + FTouch.Devices[i].Name;
          if Ini.SectionExists(Sec) then
            FTouch.Devices[i].DesiredOutput := Ini.ReadString(Sec, 'output', '');
        end;

      Result := True;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      Err := E.Message;
  end;
end;

function TProfileStore.DeleteProfile(const AName: string): boolean;
begin
  Result := DeleteFile(ProfilePath(AName));
end;

procedure TProfileStore.BuildScript(Lines: TStrings; LinkProvider: boolean;
  const SinkName, SourceName: string);
var
  i: integer;
  Cmd: string;
  TouchCmds: TStringList;
  Expected: string;
begin
  Lines.Clear;
  Lines.Add('#!/bin/bash');
  Lines.Add('# Generated by LazRandR on ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  Lines.Add('#');
  Lines.Add('# Re-applies the saved display layout AND the touch input mapping.');
  Lines.Add('# The mapping half is the part no desktop-environment display panel');
  Lines.Add('# does for you: without it an absolute input device reports across');
  Lines.Add('# the whole desktop instead of its own screen.');
  Lines.Add('');
  Lines.Add('export DISPLAY="${DISPLAY:-:0}"');
  Lines.Add('');
  Lines.Add('# Wait for the X server to answer before touching anything.');
  Lines.Add('for i in $(seq 1 40); do');
  Lines.Add('    xrandr --query >/dev/null 2>&1 && break');
  Lines.Add('    sleep 0.25');
  Lines.Add('done');
  Lines.Add('');

  if LinkProvider and (SinkName <> '') and (SourceName <> '') then
  begin
    Lines.Add('# Reverse PRIME: let the render GPU drive the other GPU''s output.');
    Lines.Add('# Needed when the panel hangs off a different GPU than the desktop');
    Lines.Add('# is rendered on -- without it the port has no video source at all.');
    Lines.Add(Format('xrandr --setprovideroutputsource "%s" "%s" 2>/dev/null || true',
      [SinkName, SourceName]));
    Lines.Add('');
  end;

  { Wait for the outputs the layout actually names, so the script also works
    as a hotplug handler rather than only at login. }
  Expected := '';
  for i := 0 to High(FXR.Outputs) do
    if FXR.Outputs[i].DesiredEnabled then
    begin
      if Expected <> '' then Expected := Expected + ' ';
      Expected := Expected + FXR.Outputs[i].Name;
    end;

  if Expected <> '' then
  begin
    Lines.Add('# Wait for every output this layout needs to actually show up.');
    Lines.Add('# Makes the script safe to run from a hotplug hook too.');
    Lines.Add(Format('NEEDED="%s"', [Expected]));
    Lines.Add('for i in $(seq 1 40); do');
    Lines.Add('    missing=0');
    Lines.Add('    for o in $NEEDED; do');
    Lines.Add('        xrandr --query | grep -q "^$o connected" || missing=1');
    Lines.Add('    done');
    Lines.Add('    [ "$missing" = "0" ] && break');
    Lines.Add('    sleep 0.25');
    Lines.Add('done');
    Lines.Add('if [ "$missing" != "0" ]; then');
    Lines.Add('    echo "lazrandr: not all outputs present, applying anyway" >&2');
    Lines.Add('fi');
    Lines.Add('');
  end;

  Lines.Add('# ---- display geometry ----');
  Cmd := FXR.BuildApplyCommand;
  Lines.Add(Cmd);
  Lines.Add('');

  TouchCmds := TStringList.Create;
  try
    if FTouch <> nil then
      FTouch.BuildAllCommands(TouchCmds, True);

    if TouchCmds.Count > 0 then
    begin
      Lines.Add('# ---- touch / stylus mapping ----');
      Lines.Add('# Devices are addressed by NAME, not by id: xinput ids are');
      Lines.Add('# reassigned on every replug and reboot, names are stable.');
      Lines.Add('sleep 0.4');
      for i := 0 to TouchCmds.Count - 1 do
        Lines.Add(TouchCmds[i] + ' 2>/dev/null || true');
      Lines.Add('');
    end
    else
    begin
      Lines.Add('# (no touch or stylus devices were present when this was generated)');
      Lines.Add('');
    end;
  finally
    TouchCmds.Free;
  end;

  Lines.Add('exit 0');
end;

function TProfileStore.WriteScript(out Err: string; LinkProvider: boolean;
  const SinkName, SourceName: string): boolean;
var
  L: TStringList;
  Output: string;
begin
  Result := False;
  Err := '';
  EnsureDirs;
  L := TStringList.Create;
  try
    try
      BuildScript(L, LinkProvider, SinkName, SourceName);
      L.SaveToFile(ScriptFile);
      FXR.Run(Format('chmod 755 "%s"', [ScriptFile]), Output);
      Result := True;
    except
      on E: Exception do
        Err := E.Message;
    end;
  finally
    L.Free;
  end;
end;

function TProfileStore.AutostartInstalled: boolean;
begin
  Result := FileExists(AutostartFile);
end;

function TProfileStore.InstallAutostart(out Err: string): boolean;
var
  L: TStringList;
  Dir: string;
begin
  Result := False;
  Err := '';
  Dir := ExtractFileDir(AutostartFile);
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  L := TStringList.Create;
  try
    try
      L.Add('[Desktop Entry]');
      L.Add('Type=Application');
      L.Add('Name=LazRandR display + touch layout');
      L.Add('Comment=Re-apply the saved monitor arrangement and touchscreen mapping at login');
      L.Add('Exec=' + ScriptFile);
      L.Add('Terminal=false');
      L.Add('NoDisplay=true');
      L.Add('X-GNOME-Autostart-enabled=true');
      L.Add('X-GNOME-Autostart-Phase=Applications');
      L.SaveToFile(AutostartFile);
      Result := True;
    except
      on E: Exception do
        Err := E.Message;
    end;
  finally
    L.Free;
  end;
end;

function TProfileStore.RemoveAutostart(out Err: string): boolean;
begin
  Err := '';
  Result := True;
  if FileExists(AutostartFile) then
  begin
    Result := DeleteFile(AutostartFile);
    if not Result then Err := 'Could not remove ' + AutostartFile;
  end;
end;

end.
