unit uGreeter;

{ Persisting the layout one layer below the session: the login manager.

  The session-level script (uProfiles) fixes the desktop, but it runs far too
  late to help the greeter. The X server sizes its screen from whichever
  outputs have finished their handshake at the moment the video driver
  validates modes; a panel that wakes a second later cannot be placed at its
  saved position any more, because the screen was never made big enough to
  hold it. X puts it at +0+0 instead and the login screen comes up mirrored.

  The fix is a hook the display manager runs on the greeter's X display before
  the greeter is drawn. Every manager spells it differently, so the shape of
  the work is: write one script, then point the manager at it.

  Both files live outside $HOME, so installing is a privileged operation and
  goes through pkexec. Nothing here writes to /etc directly. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Process, uDisplayTypes, uXRandR, uTouch;

type
  { Which login manager is driving this seat. }
  TGreeterKind = (gkUnknown, gkLightDM, gkSDDM, gkGDM);

  { TGreeterConfig }

  TGreeterConfig = class
  private
    FXR: TXRandR;
    FTouch: TTouchManager;
    FKind: TGreeterKind;
    FConfigDir: string;
    function StagedScriptPath: string;
    function StagedInstallerPath: string;
    function RunPkexec(const ScriptPath: string; out Err: string): boolean;
    procedure EmitResolver(L: TStrings);
    procedure EmitWanted(L: TStrings);
  public
    constructor Create(AXR: TXRandR; ATouch: TTouchManager);

    { Work out which manager is in charge. Cheap; call before using the rest. }
    procedure Detect;

    { True when we know how to hook this manager without editing a file the
      distribution owns. }
    function Supported: boolean;
    function ManagerName: string;
    function WhyUnsupported: string;

    { Where the hook lands once installed. }
    function TargetScriptPath: string;
    function TargetConfPath: string;
    function Installed: boolean;

    { The script the manager will run. }
    procedure BuildScript(Lines: TStrings; LinkProvider: boolean;
      const SinkName, SourceName: string);

    function Install(out Err: string; LinkProvider: boolean;
      const SinkName, SourceName: string): boolean;
    function Remove(out Err: string): boolean;

    property Kind: TGreeterKind read FKind;
  end;

implementation

const
  { One fixed pair of paths, so an install always replaces the previous one
    rather than accumulating hooks. }
  GreeterScript = '/usr/local/bin/lazrandr-greeter.sh';
  LightDMConf   = '/etc/lightdm/lightdm.conf.d/60-lazrandr.conf';
  SDDMConf      = '/etc/sddm.conf.d/60-lazrandr.conf';

{ The EDID physical size, formatted exactly as xrandr prints it so the
  generated script can match on it with a plain grep -F. Empty when the
  driver reported no size, which is the signal to skip the fallback. }
function MMSpec(W, H: integer): string;
begin
  if (W > 0) and (H > 0) then
    Result := Format('%dmm x %dmm', [W, H])
  else
    Result := '';
end;

constructor TGreeterConfig.Create(AXR: TXRandR; ATouch: TTouchManager);
begin
  inherited Create;
  FXR := AXR;
  FTouch := ATouch;
  FKind := gkUnknown;
  FConfigDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) +
    '.config/lazrandr';
end;

function TGreeterConfig.StagedScriptPath: string;
begin
  Result := FConfigDir + '/greeter-layout.sh';
end;

function TGreeterConfig.StagedInstallerPath: string;
begin
  Result := FConfigDir + '/.greeter-install.sh';
end;

procedure TGreeterConfig.Detect;
var
  L: TStringList;
  S: string;
begin
  FKind := gkUnknown;

  { Debian/Ubuntu record the chosen manager here, and it is the only answer
    that reflects what will actually run at the next boot. }
  if FileExists('/etc/X11/default-display-manager') then
  begin
    L := TStringList.Create;
    try
      try
        L.LoadFromFile('/etc/X11/default-display-manager');
        if L.Count > 0 then
        begin
          S := LowerCase(Trim(ExtractFileName(Trim(L[0]))));
          if S = 'lightdm' then FKind := gkLightDM
          else if S = 'sddm' then FKind := gkSDDM
          else if (S = 'gdm') or (S = 'gdm3') then FKind := gkGDM;
        end;
      except
        { An unreadable file just means we fall through to the guess below. }
      end;
    finally
      L.Free;
    end;
  end;

  if FKind <> gkUnknown then Exit;

  { No record of a choice: guess from what is installed. }
  if DirectoryExists('/etc/lightdm') then FKind := gkLightDM
  else if DirectoryExists('/etc/sddm.conf.d') or FileExists('/etc/sddm.conf') then FKind := gkSDDM
  else if DirectoryExists('/etc/gdm3') or DirectoryExists('/etc/gdm') then FKind := gkGDM;
end;

function TGreeterConfig.Supported: boolean;
begin
  Result := FKind in [gkLightDM, gkSDDM];
end;

function TGreeterConfig.ManagerName: string;
begin
  case FKind of
    gkLightDM: Result := 'LightDM';
    gkSDDM:    Result := 'SDDM';
    gkGDM:     Result := 'GDM';
  else
    Result := 'unknown';
  end;
end;

function TGreeterConfig.WhyUnsupported: string;
begin
  case FKind of
    gkGDM:
      Result := 'GDM has no drop-in directory for a display setup hook -- the ' +
        'only place to call one is /etc/gdm3/Init/Default, a file the ' +
        'distribution owns and replaces on upgrade. GDM also defaults to ' +
        'Wayland, where xrandr does nothing at all. Install the script by ' +
        'hand if your greeter is running on X.';
    gkUnknown:
      Result := 'No login manager could be identified. /etc/X11/default-display-manager ' +
        'is missing or names something unfamiliar, and none of the usual ' +
        'configuration directories exist.';
  else
    Result := '';
  end;
end;

function TGreeterConfig.TargetScriptPath: string;
begin
  Result := GreeterScript;
end;

function TGreeterConfig.TargetConfPath: string;
begin
  case FKind of
    gkLightDM: Result := LightDMConf;
    gkSDDM:    Result := SDDMConf;
  else
    Result := '';
  end;
end;

function TGreeterConfig.Installed: boolean;
begin
  Result := (TargetConfPath <> '') and FileExists(TargetConfPath)
    and FileExists(GreeterScript);
end;

{ ---------------------------------------------------------------------------
  Script generation
  --------------------------------------------------------------------------- }

procedure TGreeterConfig.EmitWanted(L: TStrings);
var
  i: integer;
  O: TOutputInfo;
  MM: string;
begin
  L.Add('# Each wanted output is recorded as  connector|physical-size  so it can');
  L.Add('# still be found when the connector name has moved (see resolve below).');
  L.Add('WANT=(');
  for i := 0 to High(FXR.Outputs) do
  begin
    O := FXR.Outputs[i];
    if not O.Connected then Continue;
    if not O.DesiredEnabled then Continue;
    MM := MMSpec(O.MMWidth, O.MMHeight);
    L.Add(Format('    "%s|%s"', [O.Name, MM]));
  end;
  L.Add(')');
  L.Add('');
end;

procedure TGreeterConfig.EmitResolver(L: TStrings);
begin
  L.Add('# Connector names are not stable across boots. An output behind a');
  L.Add('# DisplayPort hub or on a second GPU comes back as DP-1-1 one boot and');
  L.Add('# DP-2-1 the next, so matching on the name alone quietly drops it.');
  L.Add('#');
  L.Add('# Match on the recorded name first. If that connector is gone, fall back');
  L.Add('# to the EDID physical size -- but only when exactly one unclaimed');
  L.Add('# output carries it, because two identical monitors are not');
  L.Add('# distinguishable that way and guessing would swap them.');
  L.Add('claimed=""');
  L.Add('');
  L.Add('resolve() {');
  L.Add('    local want_name="$1" want_mm="$2" c cand hits');
  L.Add('    if printf ''%s\n'' "$SNAP" | grep -q "^${want_name} connected"; then');
  L.Add('        echo "$want_name"');
  L.Add('        return 0');
  L.Add('    fi');
  L.Add('    [ -n "$want_mm" ] || return 1');
  L.Add('    hits=$(printf ''%s\n'' "$SNAP" | grep " connected" | grep -F "$want_mm" | awk ''{print $1}'')');
  L.Add('    cand=""');
  L.Add('    for c in $hits; do');
  L.Add('        case " $claimed " in *" $c "*) continue ;; esac');
  L.Add('        [ -n "$cand" ] && return 1   # ambiguous: refuse to guess');
  L.Add('        cand="$c"');
  L.Add('    done');
  L.Add('    [ -n "$cand" ] || return 1');
  L.Add('    echo "$cand"');
  L.Add('}');
  L.Add('');
end;

procedure TGreeterConfig.BuildScript(Lines: TStrings; LinkProvider: boolean;
  const SinkName, SourceName: string);
var
  i: integer;
  O: TOutputInfo;
  TouchCmds: TStringList;
  PrimaryName, PrimaryMode: string;
begin
  Lines.Clear;
  Lines.Add('#!/bin/bash');
  Lines.Add('# LazRandR greeter layout -- generated ' +
    FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  Lines.Add('#');
  Lines.Add('# Runs as root on the greeter''s X display, before the login window is');
  Lines.Add('# drawn. It exists because the X server sizes its screen from whichever');
  Lines.Add('# outputs have finished their handshake when the video driver validates');
  Lines.Add('# modes. A panel that wakes a second later has nowhere to go -- the');
  Lines.Add('# screen was never made big enough -- so X drops it at +0+0 and the');
  Lines.Add('# login screen comes up mirrored.');
  Lines.Add('#');
  Lines.Add('# This script must never fail the seat. Every path ends in exit 0, the');
  Lines.Add('# wait for outputs is bounded, and outputs are applied individually so');
  Lines.Add('# one absent panel cannot take the whole layout down with it.');
  Lines.Add('');
  Lines.Add('export DISPLAY="${DISPLAY:-:0}"');
  Lines.Add('');
  Lines.Add('LOG=/var/log/lazrandr-greeter.log');
  Lines.Add('exec >>"$LOG" 2>&1');
  Lines.Add('echo "--- $(date ''+%F %T'') greeter setup on $DISPLAY ---"');
  Lines.Add('');
  Lines.Add('command -v xrandr >/dev/null 2>&1 || { echo "xrandr not found"; exit 0; }');
  Lines.Add('');
  Lines.Add('# Wait for the X server to answer at all.');
  Lines.Add('for i in $(seq 1 40); do');
  Lines.Add('    xrandr --query >/dev/null 2>&1 && break');
  Lines.Add('    sleep 0.25');
  Lines.Add('done');
  Lines.Add('');

  if LinkProvider and (SinkName <> '') and (SourceName <> '') then
  begin
    Lines.Add('# Reverse PRIME. The panel hangs off a different GPU than the desktop');
    Lines.Add('# renders on; without this link its connector has no video source and');
    Lines.Add('# nothing below will make it light up.');
    Lines.Add(Format('xrandr --setprovideroutputsource "%s" "%s" || echo "provider link failed"',
      [SinkName, SourceName]));
    Lines.Add('');
  end;

  EmitWanted(Lines);
  EmitResolver(Lines);

  Lines.Add('# Wait until every wanted output has turned up, but do not wait forever.');
  Lines.Add('# This is the whole point of the hook: the late panel is the one that');
  Lines.Add('# gets mirrored, and it is late by a second or two, not by a minute.');
  Lines.Add('DEADLINE=$(( SECONDS + 15 ))');
  Lines.Add('while :; do');
  Lines.Add('    SNAP=$(xrandr --query)');
  Lines.Add('    claimed=""');
  Lines.Add('    missing=0');
  Lines.Add('    for spec in "${WANT[@]}"; do');
  Lines.Add('        r=$(resolve "${spec%%|*}" "${spec#*|}") || { missing=1; continue; }');
  Lines.Add('        claimed="$claimed $r"');
  Lines.Add('    done');
  Lines.Add('    [ "$missing" = 0 ] && break');
  Lines.Add('    if [ "$SECONDS" -ge "$DEADLINE" ]; then');
  Lines.Add('        echo "timed out waiting for outputs; applying what is present"');
  Lines.Add('        break');
  Lines.Add('    fi');
  Lines.Add('    sleep 0.25');
  Lines.Add('done');
  Lines.Add('');

  Lines.Add('# ---- display geometry ----');
  Lines.Add('# Built one output at a time. A single --output naming a connector that');
  Lines.Add('# is not there makes xrandr reject the entire command line, which would');
  Lines.Add('# leave the greeter on whatever X guessed -- the exact failure this is');
  Lines.Add('# meant to prevent.');
  Lines.Add('SNAP=$(xrandr --query)');
  Lines.Add('claimed=""');
  Lines.Add('ARGS=()');
  Lines.Add('');

  PrimaryName := '';
  PrimaryMode := '';
  for i := 0 to High(FXR.Outputs) do
  begin
    O := FXR.Outputs[i];
    if not O.Connected then Continue;
    if not O.DesiredEnabled then Continue;

    Lines.Add(Format('real=$(resolve "%s" "%s") && {', [O.Name,
      MMSpec(O.MMWidth, O.MMHeight)]));
    Lines.Add('    claimed="$claimed $real"');
    Lines.Add(Format('    ARGS+=(--output "$real" --mode %dx%d --rate %s --rotate %s --pos %dx%d%s)',
      [O.DesiredModeW, O.DesiredModeH, RateToStr(O.DesiredRate),
       RotationNames[O.DesiredRotation], O.DesiredX, O.DesiredY,
       IfThen(O.DesiredPrimary, ' --primary', ' --noprimary')]));
    Lines.Add('}');
    Lines.Add(Format('[ -n "$real" ] || echo "output %s not present, skipped"', [O.Name]));
    Lines.Add('real=""');
    Lines.Add('');

    if O.DesiredPrimary then
    begin
      PrimaryName := O.Name;
      PrimaryMode := Format('%dx%d', [O.DesiredModeW, O.DesiredModeH]);
    end;
  end;

  { Outputs the user switched off still have to be told so, or they keep
    whatever geometry X handed them at startup and sit on top of the layout. }
  for i := 0 to High(FXR.Outputs) do
  begin
    O := FXR.Outputs[i];
    if not O.Connected then Continue;
    if O.DesiredEnabled then Continue;
    Lines.Add(Format('printf ''%%s\n'' "$SNAP" | grep -q "^%s connected" && ARGS+=(--output "%s" --off)',
      [O.Name, O.Name]));
  end;
  Lines.Add('');

  Lines.Add('if [ ${#ARGS[@]} -gt 0 ]; then');
  Lines.Add('    echo "xrandr ${ARGS[*]}"');
  Lines.Add('    if ! xrandr "${ARGS[@]}"; then');
  Lines.Add('        echo "layout failed; falling back to the primary output alone"');
  if PrimaryName <> '' then
  begin
    Lines.Add(Format('        p=$(resolve "%s" "") || p="%s"', [PrimaryName, PrimaryName]));
    Lines.Add(Format('        xrandr --output "$p" --mode %s --pos 0x0 --primary || true',
      [PrimaryMode]));
  end
  else
    Lines.Add('        xrandr --auto || true');
  Lines.Add('    fi');
  Lines.Add('else');
  Lines.Add('    echo "no outputs resolved; leaving the server''s own guess alone"');
  Lines.Add('fi');
  Lines.Add('');

  TouchCmds := TStringList.Create;
  try
    if FTouch <> nil then
      FTouch.BuildAllCommands(TouchCmds, True);

    if TouchCmds.Count > 0 then
    begin
      Lines.Add('# ---- touch / stylus mapping ----');
      Lines.Add('# Without this the greeter''s touch input reports across the whole');
      Lines.Add('# desktop, so tapping the password box on one panel puts the cursor');
      Lines.Add('# somewhere else entirely.');
      Lines.Add('if command -v xinput >/dev/null 2>&1; then');
      Lines.Add('    sleep 0.4');
      for i := 0 to TouchCmds.Count - 1 do
        Lines.Add('    ' + TouchCmds[i] + ' || true');
      Lines.Add('fi');
      Lines.Add('');
    end;
  finally
    TouchCmds.Free;
  end;

  Lines.Add('echo "done"');
  Lines.Add('exit 0');
end;

{ ---------------------------------------------------------------------------
  Installation
  --------------------------------------------------------------------------- }

function TGreeterConfig.RunPkexec(const ScriptPath: string; out Err: string): boolean;
var
  P: TProcess;
  Buf: TStringList;
begin
  Result := False;
  Err := '';
  P := TProcess.Create(nil);
  Buf := TStringList.Create;
  try
    P.Executable := '/usr/bin/pkexec';
    P.Parameters.Add('/bin/bash');
    P.Parameters.Add(ScriptPath);
    P.Options := [poWaitOnExit, poUsePipes, poStderrToOutPut];
    try
      P.Execute;
      Buf.LoadFromStream(P.Output);
      if P.ExitStatus = 0 then
        Result := True
      else if P.ExitStatus = 126 then
        Err := 'Authorisation was declined.'
      else if P.ExitStatus = 127 then
        Err := 'pkexec could not run the installer (exit 127).'
      else
        Err := Format('Installer exited with status %d.%s%s',
          [P.ExitStatus, LineEnding, Trim(Buf.Text)]);
    except
      on E: Exception do
        Err := E.Message;
    end;
  finally
    Buf.Free;
    P.Free;
  end;
end;

function TGreeterConfig.Install(out Err: string; LinkProvider: boolean;
  const SinkName, SourceName: string): boolean;
var
  Script, Inst: TStringList;
  Output: string;
begin
  Result := False;
  Err := '';

  if not Supported then
  begin
    Err := WhyUnsupported;
    Exit;
  end;

  if not DirectoryExists(FConfigDir) then
    ForceDirectories(FConfigDir);

  Script := TStringList.Create;
  Inst := TStringList.Create;
  try
    try
      BuildScript(Script, LinkProvider, SinkName, SourceName);
      Script.SaveToFile(StagedScriptPath);

      { The installer is the only thing that runs as root, and it does exactly
        two things: copy the script into place and point the manager at it. }
      Inst.Add('#!/bin/bash');
      Inst.Add('set -e');
      Inst.Add(Format('install -D -m 0755 -o root -g root "%s" "%s"',
        [StagedScriptPath, GreeterScript]));

      case FKind of
        gkLightDM:
          begin
            Inst.Add(Format('mkdir -p "%s"', [ExtractFileDir(LightDMConf)]));
            Inst.Add(Format('cat > "%s" <<''LAZEOF''', [LightDMConf]));
            Inst.Add('# Written by LazRandR. Re-applies the saved monitor layout and');
            Inst.Add('# touch mapping on the greeter''s X display before it is drawn.');
            Inst.Add('[Seat:*]');
            Inst.Add('display-setup-script=' + GreeterScript);
            Inst.Add('LAZEOF');
            Inst.Add(Format('chmod 0644 "%s"', [LightDMConf]));
          end;
        gkSDDM:
          begin
            Inst.Add(Format('mkdir -p "%s"', [ExtractFileDir(SDDMConf)]));
            { SDDM has one DisplayCommand, not a drop-in list, so chain the
              distribution's Xsetup rather than replacing it. }
            Inst.Add('cat > /usr/local/bin/lazrandr-greeter-chain.sh <<''LAZEOF''');
            Inst.Add('#!/bin/bash');
            Inst.Add('# Runs the distribution Xsetup first, then the LazRandR layout,');
            Inst.Add('# because SDDM allows only a single DisplayCommand.');
            Inst.Add('[ -x /usr/share/sddm/scripts/Xsetup ] && /usr/share/sddm/scripts/Xsetup "$@"');
            Inst.Add(GreeterScript + ' || true');
            Inst.Add('exit 0');
            Inst.Add('LAZEOF');
            Inst.Add('chmod 0755 /usr/local/bin/lazrandr-greeter-chain.sh');
            Inst.Add(Format('cat > "%s" <<''LAZEOF''', [SDDMConf]));
            Inst.Add('# Written by LazRandR.');
            Inst.Add('[X11]');
            Inst.Add('DisplayCommand=/usr/local/bin/lazrandr-greeter-chain.sh');
            Inst.Add('LAZEOF');
            Inst.Add(Format('chmod 0644 "%s"', [SDDMConf]));
          end;
      else
        { Supported() already rejected everything else; this is here so the
          compiler can see the case is total. }
        Err := WhyUnsupported;
        Exit;
      end;

      Inst.Add('exit 0');
      Inst.SaveToFile(StagedInstallerPath);
      FXR.Run(Format('chmod 700 "%s"', [StagedInstallerPath]), Output);

      Result := RunPkexec(StagedInstallerPath, Err);
    except
      on E: Exception do
        Err := E.Message;
    end;
  finally
    Inst.Free;
    Script.Free;
  end;
end;

function TGreeterConfig.Remove(out Err: string): boolean;
var
  Inst: TStringList;
  Output: string;
begin
  Result := False;
  Err := '';

  if not DirectoryExists(FConfigDir) then
    ForceDirectories(FConfigDir);

  Inst := TStringList.Create;
  try
    try
      Inst.Add('#!/bin/bash');
      Inst.Add('# Written by LazRandR: undo the greeter hook.');
      if TargetConfPath <> '' then
        Inst.Add(Format('rm -f "%s"', [TargetConfPath]));
      Inst.Add(Format('rm -f "%s"', [GreeterScript]));
      Inst.Add('rm -f /usr/local/bin/lazrandr-greeter-chain.sh');
      Inst.Add('exit 0');
      Inst.SaveToFile(StagedInstallerPath);
      FXR.Run(Format('chmod 700 "%s"', [StagedInstallerPath]), Output);

      Result := RunPkexec(StagedInstallerPath, Err);
    except
      on E: Exception do
        Err := E.Message;
    end;
  finally
    Inst.Free;
  end;
end;

end.
