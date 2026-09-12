program lazrandr;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms,
  ufrmMain,
  ufrmScriptPreview,
  ufrmIdentify,
  ufrmConfirm,
  ufrmGreeter,
  uDisplayTypes,
  uXRandR,
  uTouch,
  uTheme,
  uLayoutCanvas,
  uProfiles,
  uGreeter;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := 'LazRandR';
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
