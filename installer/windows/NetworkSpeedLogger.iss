#ifndef AppVersion
  #define AppVersion "0.3.0"
#endif

#define AppName "Network Speed Logger"
#define AppExeName "NetworkSpeedLogger.exe"
#define RepositoryUrl "https://github.com/hoshinoshion/network-speed-logger"

[Setup]
AppId={{D34531B5-1AC6-4F7A-AB38-7C8685A44BE0}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=hoshinoshion
AppPublisherURL={#RepositoryUrl}
AppSupportURL={#RepositoryUrl}/issues
AppUpdatesURL={#RepositoryUrl}/releases
AppCopyright=Copyright (C) 2026 hoshinoshion
DefaultDirName={localappdata}\Programs\NetworkSpeedLogger
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
MinVersion=10.0.10240
OutputDir=..\..\dist
OutputBaseFilename=NetworkSpeedLogger-Setup
SetupIconFile=..\..\src\windows\NetworkSpeedLogger\Icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
UsePreviousLanguage=yes
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=hoshinoshion
VersionInfoDescription={#AppName} installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoCopyright=Copyright (C) 2026 hoshinoshion

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl,languages\ChineseSimplified.isl"

[CustomMessages]
english.DesktopShortcut=Create a desktop shortcut
chinesesimp.DesktopShortcut=创建桌面快捷方式
english.DotNetMissing=Network Speed Logger requires .NET Framework 4.8 or later.%n%nInstall all available Windows updates or install .NET Framework 4.8, then run Setup again.
chinesesimp.DotNetMissing=Network Speed Logger 需要 .NET Framework 4.8 或更高版本。%n%n请安装所有可用的 Windows 更新或安装 .NET Framework 4.8，然后重新运行安装程序。

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\src\windows\NetworkSpeedLogger\bin\Release\net48\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\src\windows\NetworkSpeedLogger\bin\Release\net48\{#AppExeName}.config"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{localappdata}\NetworkSpeedLogger\settings.json"
Type: files; Name: "{localappdata}\NetworkSpeedLogger\settings.json.tmp"
Type: files; Name: "{localappdata}\NetworkSpeedLogger\settings.json.bak"
Type: files; Name: "{localappdata}\NetworkSpeedLogger\language.txt"
Type: dirifempty; Name: "{localappdata}\NetworkSpeedLogger"

[Code]
function HasDotNetFramework48OrLater: Boolean;
var
  Release: Cardinal;
begin
  Result := RegQueryDWordValue(
    HKLM32,
    'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full',
    'Release',
    Release) and (Release >= 528040);

  if (not Result) and IsWin64 then
    Result := RegQueryDWordValue(
      HKLM64,
      'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full',
      'Release',
      Release) and (Release >= 528040);
end;

function InitializeSetup: Boolean;
begin
  Result := HasDotNetFramework48OrLater;
  if not Result then
    MsgBox(ExpandConstant('{cm:DotNetMissing}'), mbError, MB_OK);
end;
