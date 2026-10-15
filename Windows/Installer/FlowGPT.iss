[Setup]
AppId={{C0DD7357-60AA-4124-B232-912E1B8F94B4}
AppName=FlowGPT
AppVersion=1.3.2
AppPublisher=Rachit Kothadia
AppPublisherURL=https://github.com/rachitkothadia/FlowGPT
DefaultDirName={localappdata}\Programs\FlowGPT
DefaultGroupName=FlowGPT
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
OutputDir=..\..\release\windows
OutputBaseFilename=FlowGPT-1.3.2-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\Assets\FlowGPT.ico
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\FlowGPT.exe
LicenseFile=..\..\LICENSE
#ifdef FLOW_SIGNED
SignTool=flowSign
SignedUninstaller=yes
#endif

[Files]
Source: "..\out\x64\Release\*"; DestDir: "{app}"; Excludes: "*.pdb,native-tests.json,ui-*.json,ui-*.txt,ui-*.png"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "WebView2Bootstrapper.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "..\..\LICENSE"; DestDir: "{app}"
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"

Source: "..\..\Shared\Data\UNICODE-LICENSE.txt"; DestDir: "{app}\Licenses"

[Icons]
Name: "{group}\FlowGPT"; Filename: "{app}\FlowGPT.exe"
Name: "{autodesktop}\FlowGPT"; Filename: "{app}\FlowGPT.exe"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
Name: startup; Description: "Start FlowGPT in the tray when I sign in"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "FlowGPT"; ValueData: """{app}\FlowGPT.exe"" --background"; Check: StartAtLoginSelected; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "FlowGPT"; Check: StartAtLoginNotSelected; Flags: deletevalue
Root: HKCU; Subkey: "Software\FlowGPT\Startup"; ValueType: dword; ValueName: "StartAtLogin"; ValueData: "1"; Check: StartAtLoginSelected
Root: HKCU; Subkey: "Software\FlowGPT\Startup"; ValueType: dword; ValueName: "StartAtLogin"; ValueData: "0"; Check: StartAtLoginNotSelected

[Run]
Filename: "{tmp}\WebView2Bootstrapper.exe"; Parameters: "/silent /install"; StatusMsg: "Checking Microsoft Edge WebView2 Runtime…"; Flags: waituntilterminated
Filename: "{app}\FlowGPT.exe"; Description: "Open FlowGPT"; Flags: nowait postinstall skipifsilent

[Code]
function StartAtLoginSelected: Boolean;
var
  PreviousChoice: Cardinal;
begin
  if WizardSilent and RegQueryDWordValue(HKCU, 'Software\FlowGPT\Startup', 'StartAtLogin', PreviousChoice) then
    Result := PreviousChoice <> 0
  else
    Result := WizardIsTaskSelected('startup');
end;

function StartAtLoginNotSelected: Boolean;
begin
  Result := not StartAtLoginSelected;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    if SuppressibleMsgBox('Also delete local FlowGPT transcripts, settings, and ChatGPT sign-in data? Choose No to keep them for reinstalling.', mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
      DelTree(ExpandConstant('{localappdata}\FlowGPT'), True, True, True);
end;
