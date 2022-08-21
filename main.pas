// https://github.com/vmmcall/remap-plugin

unit main;

interface

uses Winapi.Windows, System.SysUtils, cepluginsdk;

function GetVersion(var PluginVersion: TpluginVersion; sizeofpluginversion: Integer): BOOL; stdcall;
function InitializePlugin(ExportedFunctions: PExportedFunctions; pluginid: DWORD): BOOL; stdcall;
function DisablePlugin: BOOL; stdcall;

implementation

function NtResumeProcess(ProcessHandle: THandle): ULONG; stdcall; external 'ntdll.dll';
function NtSuspendProcess(ProcessHandle: THandle): ULONG; stdcall; external 'ntdll.dll';
function NtClose(Handle: THandle): ULONG; stdcall; external 'ntdll.dll';
function NtCreateSection(
    var SectionHandle: THandle;
    DesiredAccess: ACCESS_MASK;
    ObjectAttributes: Pointer;
    SectionSize: PLargeInteger;
    Protect: ULONG;
    Attributes: ULONG;
    FileHandle: THandle
  ): ULONG; stdcall; external 'ntdll.dll';

function NtMapViewOfSection(
    SectionHandle: THandle;
    ProcessHandle: THandle;
    var BaseAddress: PVOID;
    ZeroBits: ULONG;
    CommitSize: ULONG;
    SectionOffset: LARGE_INTEGER;
    var ViewSize: ULONG;
    InheritDisposition: ULONG;
    AllocationType: ULONG;
    Protect: ULONG
  ): ULONG; stdcall; external 'ntdll.dll';

function NtUnmapViewOfSection(ProcessHandle: THandle; BaseAddress: Pointer): ULONG; stdcall; external 'ntdll.dll';

var Exported: TExportedFunctions;
VersionName: PAnsiChar;

function MemoryViewPlugin(disassembleraddress: pptruint; selected_disassembler_address: pptruint; hexviewaddress: pptruint): BOOL; stdcall;
var hProcess: THandle;
mbi: TMemoryBasicInformation;
Buffer: Pointer;
hSection: THandle;
SectionSize: LARGE_INTEGER;
ViewSize: ULONG;
begin
  Result := True;
  hProcess := Exported.OpenedProcessHandle^;
  if not Exported.IsValidHandle(hProcess) then
    Exit;

  VirtualQueryEx(hProcess, Pointer(disassembleraddress^), mbi, SizeOf(mbi));
  Buffer := VirtualAlloc(nil, mbi.RegionSize, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);
  if Buffer = nil then
  begin
    Exported.showmessage(PAnsiChar(AnsiString(Format('buffer allocation failed (0x%.x)', [mbi.RegionSize]))));
    Exit;
  end;
  NtSuspendProcess(hProcess);
  ReadProcessMemory(hProcess, mbi.AllocationBase, Buffer, mbi.RegionSize, PSIZE_T(nil)^);
  SectionSize.QuadPart := mbi.RegionSize;
  NtCreateSection(hSection, SECTION_ALL_ACCESS, nil, @SectionSize, PAGE_EXECUTE_READWRITE, SEC_COMMIT, 0);
  NtUnmapViewOfSection(hProcess, mbi.AllocationBase);
  SectionSize.QuadPart := 0;
  ViewSize := 0;
  NtMapViewOfSection(hSection, hProcess, mbi.AllocationBase, 0, mbi.RegionSize, SectionSize, ViewSize, 2, 0, PAGE_EXECUTE_READWRITE);
  WriteProcessMemory(hProcess, mbi.AllocationBase, Buffer, mbi.RegionSize, PSIZE_T(nil)^);
  NtClose(hSection);
  NtResumeProcess(hProcess);
  VirtualFree(Buffer, 0, MEM_RELEASE);
end;

function GetVersion(var PluginVersion: TpluginVersion; sizeofpluginversion: Integer): BOOL; stdcall;
var s: AnsiString;
begin
  Result := False;
  if sizeofpluginversion <> SizeOf(TPluginVersion) then Exit;
  s := 'page remapper';
  GetMem(VersionName, Length(s)+1);
  CopyMemory(VersionName, @s[1], Length(s));
  VersionName[Length(s)] := #0;
  PluginVersion.version := 1;
  PluginVersion.pluginname := VersionName;
  Result := True;
end;

function InitializePlugin(ExportedFunctions: PExportedFunctions; pluginid: DWORD): BOOL; stdcall;
var func: TFunction1;
begin
  Exported := ExportedFunctions^;
  func.name := 'Remap Page';
  func.callbackroutine := MemoryViewPlugin;
  func.shortcut := nil;
  Exported.registerfunction(pluginid, ptMemoryView, @func);
  Result := True;
end;

function DisablePlugin: BOOL; stdcall;
begin
  Result := True;
end;

end.
