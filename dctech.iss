[Setup]
AppName=DC TECH - Quan ly thue loa
AppVersion=1.0.2
DefaultDirName={autopf}\DC TECH
DefaultGroupName=DC TECH
OutputBaseFilename=DCTech_Setup_1.0.2
Compression=lzma
SolidCompression=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\DC TECH"; Filename: "{app}\dc_tech_rental.exe"
Name: "{autodesktop}\DC TECH"; Filename: "{app}\dc_tech_rental.exe"