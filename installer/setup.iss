; NanoSync Installer Script
; Inno Setup 6.0+ Required
; Documentation: https://jrsoftware.org/ishelp/

#define MyAppName "NanoSync"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "NanoSync Team"
#define MyAppURL "https://github.com/nanosync/nanosync"
#define MyAppExeName "nano_sync.exe"

[Setup]
AppId={{8A7D9F3E-2B1C-4D6E-A5F8-9C3E7B1D4E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={commonpf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=Output
OutputBaseFilename=NanoSync-Setup-{#MyAppVersion}
SetupIconFile=resources\icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=no
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "autostart"; Description: "开机自动启动"; GroupDescription: "启动选项"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "resources\license.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKLM; Subkey: "Software\{#MyAppName}"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\{#MyAppName}"; ValueType: string; ValueName: "Version"; ValueData: "{#MyAppVersion}"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Check: IsAutoStart

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: postinstall nowait skipifsilent
Filename: "https://github.com/nanosync/nanosync/wiki"; Description: "查看使用指南"; Flags: postinstall shellexec skipifsilent unchecked

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
var
  KeepDataPage: TOutputMsgWizardPage;

function IsAutoStart: Boolean;
begin
  Result := WizardIsTaskSelected('autostart');
end;

function InitializeSetup: Boolean;
var
  OldVersion: String;
begin
  if RegQueryStringValue(HKLM, 'Software\{#MyAppName}', 'Version', OldVersion) then
  begin
    if MsgBox(
      '检测到 NanoSync ' + OldVersion + ' 已安装。' + #13#10#13#10 +
      '建议先卸载旧版本后再继续安装，以避免潜在的冲突问题。' + #13#10#13#10 +
      '是否继续安装？', 
      mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
      Exit;
    end;
  end;
  Result := True;
end;

procedure InitializeWizard;
begin
  KeepDataPage := CreateOutputMsgPage(
    wpWelcome,
    '保留用户数据',
    '是否保留同步任务配置和历史记录？',
    '如果您计划重新安装 NanoSync，可以选择保留用户数据。' + #13#10#13#10 +
    '用户数据包括：' + #13#10 +
    '• 同步任务配置' + #13#10 +
    '• 同步历史记录' + #13#10 +
    '• 应用设置' + #13#10#13#10 +
    '数据存储位置：%APPDATA%\NanoSync\'
  );
end;

function InitializeUninstall: Boolean;
var
  DataPath: string;
begin
  Result := True;
  DataPath := ExpandConstant('{userappdata}\{#MyAppName}');
  
  if DirExists(DataPath) then
  begin
    if MsgBox(
      '是否保留同步任务配置和历史记录？' + #13#10#13#10 +
      '选择"是"将保留用户数据，方便下次安装时继续使用。' + #13#10 +
      '选择"否"将完全删除所有数据。' + #13#10#13#10 +
      '数据位置: ' + DataPath,
      mbConfirmation, MB_YESNO) = IDYES then
    begin
    end
    else
    begin
      DelTree(DataPath, True, True, True);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RegDeleteKeyIncludingSubkeys(HKLM, 'Software\{#MyAppName}');
  end;
end;
