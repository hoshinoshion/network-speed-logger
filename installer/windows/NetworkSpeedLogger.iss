#ifndef AppVersion
  #define AppVersion "0.5.0"
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
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
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

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\src\windows\NetworkSpeedLogger.WinUI\bin\x64\Release\net10.0-windows10.0.17763.0\win-x64\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\{#AppExeName}.config"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\NetworkSpeedLogger.ico"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\NetworkSpeedLogger.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{localappdata}\NetworkSpeedLogger\settings.json"
Type: files; Name: "{localappdata}\NetworkSpeedLogger\settings.json.tmp"
Type: files; Name: "{localappdata}\NetworkSpeedLogger\settings.json.bak"
Type: files; Name: "{localappdata}\NetworkSpeedLogger\language.txt"
Type: dirifempty; Name: "{localappdata}\NetworkSpeedLogger"
