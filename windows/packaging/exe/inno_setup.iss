; 本文件部分逻辑改编自 FlClash (https://github.com/chen08209/FlClash) 的
; windows/packaging/exe/inno_setup.iss (GPL-3.0)。

[Setup]
AppId={{@APP_ID@}
AppVersion=@APP_VERSION@
AppVerName=FlSpeak @APP_VERSION@
AppName=FlSpeak
AppPublisher=com.dr1mh4x
AppPublisherURL=https://github.com/Dr1mH4X/FlSpeak
AppSupportURL=https://github.com/Dr1mH4X/FlSpeak/issues
AppUpdatesURL=https://github.com/Dr1mH4X/FlSpeak/releases
DefaultDirName={autopf}\FlSpeak
DisableProgramGroupPage=yes
OutputDir=@OUTPUT_DIR@
OutputBaseFilename=@OUTPUT_BASE_FILENAME@
Compression=lzma
SolidCompression=yes
SetupIconFile=@SETUP_ICON_FILE@
UninstallDisplayIcon={app}\flspeak.exe
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=@ARCH@
ArchitecturesInstallIn64BitMode=@ARCH@
CloseApplications=yes
CloseApplicationsFilter=flspeak.exe

[Code]
procedure KillProcesses;
var
  ResultCode: Integer;
begin
  Exec('taskkill', '/f /im flspeak.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillProcesses;
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  KillProcesses;
  Result := True;
end;

// path_provider 按 windows/runner/Runner.rc 的 CompanyName 与 ProductName 拼接目录。
procedure RemoveUserData;
begin
  DelTree(ExpandConstant('{userappdata}\com.dr1mh4x\FlSpeak'), True, True, True);
  DelTree(ExpandConstant('{localappdata}\com.dr1mh4x\FlSpeak'), True, True, True);
  RemoveDir(ExpandConstant('{userappdata}\com.dr1mh4x'));
  RemoveDir(ExpandConstant('{localappdata}\com.dr1mh4x'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if not UninstallSilent and (MsgBox(CustomMessage('RemoveUserData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES) then
    begin
      RemoveUserData;
    end;
  end;
end;

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chineseSimplified"; MessagesFile: "@CHINESE_ISL_FILE@"

[CustomMessages]
english.RemoveUserData=Also delete your profiles and settings?
chineseSimplified.RemoveUserData=是否同时删除您的配置与身份数据？

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "@SOURCE_DIR@\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FlSpeak"; Filename: "{app}\flspeak.exe"
Name: "{autodesktop}\FlSpeak"; Filename: "{app}\flspeak.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\flspeak.exe"; Description: "{cm:LaunchProgram,FlSpeak}"; Flags: nowait postinstall skipifsilent runasoriginaluser
