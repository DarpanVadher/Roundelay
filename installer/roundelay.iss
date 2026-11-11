; Inno Setup script for the Roundelay Windows installer.
; Built by the release workflow: iscc /DAppVersion=X.Y.Z /DSourceDir=<Release folder> installer\roundelay.iss
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\app\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change AppId: it is how Windows recognises an upgrade of the same app.
AppId={{6F3B1C9E-4D2A-4E7B-9A51-2C8D0E5F7A13}
AppName=Roundelay
AppVersion={#AppVersion}
AppPublisher=The Roundelay Authors
AppPublisherURL=https://darpanvadher.github.io/Roundelay/
AppSupportURL=https://github.com/DarpanVadher/Roundelay/issues
DefaultDirName={autopf}\Roundelay
DefaultGroupName=Roundelay
UninstallDisplayIcon={app}\multiphone_player.exe
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=Roundelay-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installs for the current user without an administrator prompt; the user can choose "all users" in the dialog.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
DisableProgramGroupPage=yes

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\NOTICE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Roundelay"; Filename: "{app}\multiphone_player.exe"
Name: "{autodesktop}\Roundelay"; Filename: "{app}\multiphone_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\multiphone_player.exe"; Description: "Launch Roundelay"; Flags: nowait postinstall skipifsilent
