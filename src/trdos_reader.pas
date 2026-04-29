unit trdos_reader;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math;

const
  SECTOR_SIZE = 256;
  SECTORS_PER_TRACK = 16;
  MAX_FILES_IN_CATALOG = 128;
  MAX_FILES_REAL = 142;

  // File status
  FILE_ACTIVE = $00;
  FILE_DELETED = $01;
  FILE_TERMINATOR = $00;

  // File types
  FILE_TYPE_BASIC = 'B';
  FILE_TYPE_CODE = 'C';
  FILE_TYPE_DATA = 'D';
  FILE_TYPE_STREAM = '#';

  // Disk types
  DISK_TYPE_80DS = $16;
  DISK_TYPE_40DS = $17;
  DISK_TYPE_80SS = $18;
  DISK_TYPE_40SS = $19;

  NO_TRKS = 80;
  NO_SECS = 16;
  SEC_SIZE = 256;

  DS_SIGNATURE: array[0..8] of char = ('D', 'i', 'r', 'S', 'y', 's', '1', '0', '0');

  SCL_SIGNATURE: array[0..7] of char = ('S', 'I', 'N', 'C', 'L', 'A', 'I', 'R');
  SCL_HEADER_SIZE = 8;
  SCL_CHECKSUM_SIZE = 4;

type
  TSCLFileHdr = packed record
    Name: array[0..7] of char;
    FileType: Char;
    StartAddress: Word;
    Length: Word;
    SectorsCount: Byte;
  end;

  TSCLDiskHeader = packed record
    Signature: array[0..7] of char;
    FilesCount: Byte;
  end;

  TTRDSDiskType = (
    dtUnknown,
    dt40SS,
    dt40DS,
    dt80SS,
    dt80DS
  );

  TFileHdr = packed record
    Name: array[0..7] of char;
    FileType: Char;
    StartAddress: Word;
    Length: Word;
    SectorsCount: Byte;
    StartSector: Byte;
    StartTrack: Byte;
  end;

  TTrack0 = packed record
    Files: array[0..MAX_FILES_REAL - 1] of TFileHdr;
    Reserved1: Byte;
    FirstFreeSector: Byte;
    FirstFreeTrack: Byte;
    DiskType: Byte;
    FilesCount: Byte;
    FreeSectorsCount: Word;
    Flag: Byte;
    Reserved2: array[0..11] of Byte;
    DeletedFilesCount: Byte;
    VolumeLabel: array[0..10] of char;
    DScrc: Word;
    DSSignature: array[0..8] of char;
    DSFileMap: array[0..$7F] of Byte;
    DSFolderMap: array[0..$7F] of Byte;
    DSFolders: array[0..$7E] of array[0..10] of char;
    DSEnd: Byte;
    Empty: array[0..$7E] of Byte;
  end;

  TBasicFileInfo = packed record
    ProgramAndDataLength: Word;
    ProgramLength: Word;
  end;

  TCodeFileInfo = packed record
    StartAddress: Word;
    Length: Word;
  end;

  TDataFileInfo = packed record
    Reserved: Word;
    Length: Word;
  end;

  TStreamFileInfo = packed record
    ExtentNo: Byte;
    Reserved: Byte;
    Length: Word;
  end;

  TFullFileHdr = packed record
    Name: array[0..7] of char;
    FileType: Char;
    TypeData: array[0..3] of Byte;
    SectorsCount: Byte;
    StartSector: Byte;
    StartTrack: Byte;
  end;

  TFileInfo = record
    Name: string;
    FileType: Char;
    FileTypeDesc: string;
    StartTrack: Byte;
    StartSector: Byte;
    SectorsCount: Byte;
    RawSize: Integer;
    RealSize: Integer;
    LoadAddress: Word;
    CodeLength: Word;
    BasicProgramLength: Word;
    BasicDataLength: Word;
    BasicStartLine: Word;
    ExtentNo: Byte;
    IsDeleted: Boolean;
  end;

  TFreeSectorInfo = record
    Track: Byte;
    Sector: Byte;
  end;

  TFileInfoList = array of TFileInfo;
  TFreeSectorInfoList = array of TFreeSectorInfo;

  TNewDiskParams = record
    DiskType: TTRDSDiskType;
    LabelName: string;
    Password: string;
  end;

  // SCL file data structure
  TSCLFileData = packed record
    Header: TSCLFileHdr;
    FileInfo: TFileInfo;
    SectorOffset: Integer;  // Смещение в секторах от начала данных
  end;

  { TTRDOSReader }
  TTRDOSReader = class
  private
    FFileName: string;
    FImageData: TMemoryStream;
    FFiles: TFileInfoList;
    FFileCount: Integer;
    FIsLoaded: Boolean;
    FErrorMessage: string;
    FModified: Boolean;
    FAutoMove: Boolean;

    FTrack0: TTrack0;
    FLogicalTracks: Integer;
    FPhysicalCylinders: Integer;
    FIsDoubleSided: Boolean;
    FTotalSectors: Integer;
    FFreeSectorsList: TFreeSectorInfoList;
    FFileMap: array[0..MAX_FILES_REAL - 1] of Byte;
    FFileMapValid: Boolean;

    function GetSectorOffset(Track, Sector: Byte): Int64;
    function ReadSector(Track, Sector: Byte; var Data: array of Byte): Boolean;
    function WriteSector(Track, Sector: Byte; const Data: array of Byte): Boolean;
    procedure LoadTrack0;
    procedure SaveTrack0;
    procedure ParseCatalog;
    procedure CompactCatalog;
    procedure CompactDisk;
    function FindFreeCatalogSlot: Integer;
    procedure BuildFreeSectorsList;
    function AllocateSectors(Count: Integer): TFreeSectorInfoList;
    procedure FreeSectors(const Sectors: TFreeSectorInfoList);
    function CalculateSectorsNeeded(Size: Integer): Integer;
    procedure UpdateDiskGeometry;
    function GetTotalSectorsCount: Integer;
    function ExtractBasicStartLine(const Data: TStream): Word;
    function ParseBasicFile(var Info: TFileInfo; const Data: TStream): Boolean;
    function LoadFromFileInternal(const AFileName: string): Boolean;
    function SaveToFileInternal(const AFileName: string): Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    function LoadFromFile(const AFileName: string): Boolean;
    function SaveToFile(const AFileName: string): Boolean;
    function SaveToCurrentFile: Boolean;
    procedure Clear;
    function CreateNewDisk(const Params: TNewDiskParams): Boolean;
    function CreateNewDiskEx(DiskType: TTRDSDiskType; const LabelName: string;
                             const Password: string = ''): Boolean;
    function FormatTrd(DiskType: TTRDSDiskType; const LabelName: string;
                    const Password: string = ''): Boolean;

    function GetFileInfo(Index: Integer): TFileInfo;
    function GetFileInfoByName(const FileName: string): TFileInfo;
    function ExtractFile(Index: Integer; DestStream: TStream): Boolean;
    function ExtractFileToFile(Index: Integer; const DestFileName: string): Boolean;
    function ExtractFileToMemory(Index: Integer): TMemoryStream;

    function AddFile(const FileName: string; FileType: Char;
                     LoadAddress: Word; FileLength: Word;
                     DataStream: TStream; BasicStartLine: Word = 0): Boolean;
    function AddFileFromFile(const FileName: string; FileType: Char;
                             LoadAddress: Word; FileLength: Word;
                             const SourceFileName: string;
                             BasicStartLine: Word = 0): Boolean;

    function DeleteFile(Index: Integer): Boolean;
    function DeleteFileByName(const FileName: string): Boolean;
    function RenameFile(Index: Integer; const NewName: string): Boolean;
    function UndeleteFile(Index: Integer): Boolean;

    function GetDiskTypeString: string;
    function GetDiskLabel: string;
    function SetDiskLabel(const LabelName: string): Boolean;
    function GetFreeSectorsCount: Integer;
    function GetFreeSpace: Integer;
    function GetUsedSpace: Integer;
    function GetTotalSpace: Integer;
    function GetUsagePercent: Single;
    function GetFilesCount: Integer;
    function GetDeletedFilesCount: Integer;
    function GetLogicalTracksCount: Integer;
    function GetPhysicalCylindersCount: Integer;
    function IsDoubleSided: Boolean;

    property AutoMove: Boolean read FAutoMove write FAutoMove;
    property IsLoaded: Boolean read FIsLoaded;
    property IsModified: Boolean read FModified;
    property ErrorMessage: string read FErrorMessage;
    property FileCount: Integer read FFileCount;
    property Files[Index: Integer]: TFileInfo read GetFileInfo;
    property FileName: string read FFileName;
  end;

  { TSCLReader }
  TSCLReader = class
  private
    FFileName: string;
    FImageData: TMemoryStream;
    FFiles: TFileInfoList;
    FSCLFiles: array of TSCLFileData;  // Массив с данными о файлах
    FFileCount: Integer;
    FIsLoaded: Boolean;
    FErrorMessage: string;
    FModified: Boolean;

    procedure ParseSCL;
    function ReadSCLHeader(var Header: TSCLDiskHeader): Boolean;
    function CalculateSCLCheckSum: DWord;
    procedure UpdateSCLCheckSum;
    function WriteSCLHeader: Boolean;
    function GetDataStartOffset: Int64;
    function GetSectorOffsetInFile(Index: Integer): Int64;

  public
    constructor Create;
    destructor Destroy; override;

    function LoadFromFile(const AFileName: string): Boolean;
    function SaveToFile(const AFileName: string): Boolean;
    function SaveToCurrentFile: Boolean;
    procedure Clear;
    function CreateNewSCL: Boolean;
    function TryRecoverSCL: Boolean;

    function GetFileInfo(Index: Integer): TFileInfo;
    function GetFileInfoByName(const FileName: string): TFileInfo;
    function ExtractFile(Index: Integer; DestStream: TStream): Boolean;
    function ExtractFileToFile(Index: Integer; const DestFileName: string): Boolean;
    function ExtractFileToMemory(Index: Integer): TMemoryStream;

    function AddFile(const FileName: string; FileType: Char;
                     LoadAddress: Word; FileLength: Word;
                     DataStream: TStream): Boolean;
    function AddFileFromFile(const FileName: string; FileType: Char;
                             LoadAddress: Word; FileLength: Word;
                             const SourceFileName: string): Boolean;

    function DeleteFile(Index: Integer): Boolean;
    function DeleteFileByName(const FileName: string): Boolean;
    function RenameFile(Index: Integer; const NewName: string): Boolean;

    function GetFilesCount: Integer;
    function GetTotalSize: Int64;

    property IsLoaded: Boolean read FIsLoaded;
    property IsModified: Boolean read FModified;
    property ErrorMessage: string read FErrorMessage;
    property FileCount: Integer read FFileCount;
    property Files[Index: Integer]: TFileInfo read GetFileInfo;
    property FileName: string read FFileName;
  end;

  TImageFormat = (ifUnknown, ifTRD, ifSCL);

  { TZXImageReader }
  TZXImageReader = class
  private
    FTRDReader: TTRDOSReader;
    FSCLReader: TSCLReader;
    FCurrentFormat: TImageFormat;
    FFileName: string;
    FIsLoaded: Boolean;
    FErrorMessage: string;

    function DetectFormat(const AFileName: string): TImageFormat;

  public
    constructor Create;
    destructor Destroy; override;

    function LoadFromFile(const AFileName: string): Boolean;
    function SaveToFile(const AFileName: string): Boolean;
    function SaveToCurrentFile: Boolean;
    procedure Clear;
    function CreateNewDiskEx(DiskType: TTRDSDiskType; const LabelName: string;
                             const Password: string = ''): Boolean;
    function FormatTrd(DiskType: TTRDSDiskType; const LabelName: string;
                       const Password: string = ''): Boolean;

    function GetFileInfo(Index: Integer): TFileInfo;
    function GetFileCount: Integer;
    function ExtractFile(Index: Integer; DestStream: TStream): Boolean;
    function ExtractFileToFile(Index: Integer; const DestFileName: string): Boolean;
    function ExtractFileToMemory(Index: Integer): TMemoryStream;

    function AddFile(const FileName: string; FileType: Char;
                     LoadAddress: Word; FileLength: Word;
                     DataStream: TStream; BasicStartLine: Word = 0): Boolean;
    function AddFileFromFile(const FileName: string; FileType: Char;
                             LoadAddress: Word; FileLength: Word;
                             const SourceFileName: string;
                             BasicStartLine: Word = 0): Boolean;
    function DeleteFile(Index: Integer): Boolean;
    function DeleteFileByName(const FileName: string): Boolean;
    function RenameFile(Index: Integer; const NewName: string): Boolean;

    function GetDiskLabel: string;
    function GetDiskTypeString: string;
    function GetFreeSpace: Integer;
    function GetUsedSpace: Integer;
    function GetTotalSpace: Integer;
    function GetFreeSectorsCount: Integer;
    function GetUsagePercent: Single;
    function GetFilesCount: Integer;
    function GetDeletedFilesCount: Integer;
    function IsDoubleSided: Boolean;
    function GetLogicalTracksCount: Integer;
    function GetPhysicalCylindersCount: Integer;

    property IsLoaded: Boolean read FIsLoaded;
    property IsModified: Boolean read FIsLoaded;
    property CurrentFormat: TImageFormat read FCurrentFormat;
    property ErrorMessage: string read FErrorMessage;
    property FileCount: Integer read GetFileCount;
    property Files[Index: Integer]: TFileInfo read GetFileInfo;
    property FileName: string read FFileName;
  end;

function ZXStringToPascal(const ZXStr: array of char): string;
procedure PascalToZXString(const PascalStr: string; var ZXStr: array of char);
function GetFileTypeDescription(FileType: Char): string;
function NormalizeFileName(const Name: string): string;
function CalcCheckSum(const Data; Size: Integer): DWord;

implementation

function CalcCheckSum(const Data; Size: Integer): DWord;
var
  i: Integer;
  P: PByte;
begin
  Result := 0;
  P := @Data;
  for i := 0 to Size - 1 do
  begin
    Result := Result + P^;
    Inc(P);
  end;
end;

function ZXStringToPascal(const ZXStr: array of char): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 0 to Length(ZXStr) - 1 do
  begin
    c := ZXStr[i];
    if c = #0 then Break;
    if c = ' ' then Continue;
    Result := Result + c;
  end;
  Result := Trim(Result);
end;

procedure PascalToZXString(const PascalStr: string; var ZXStr: array of char);
var
  i: Integer;
  s: string;
begin
  for i := 0 to High(ZXStr) do
    ZXStr[i] := ' ';

  s := PascalStr;
  for i := 1 to Length(s) do
    if i - 1 <= High(ZXStr) then
      ZXStr[i-1] := s[i];
end;

function GetFileTypeDescription(FileType: Char): string;
begin
  case FileType of
    FILE_TYPE_BASIC: Result := 'BASIC program';
    FILE_TYPE_CODE:  Result := 'Machine code';
    FILE_TYPE_DATA:  Result := 'DATA array';
    FILE_TYPE_STREAM: Result := 'STREAM file';
  else
    Result := 'Unknown';
  end;
end;

function NormalizeFileName(const Name: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(Name) do
    if Name[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_'] then
      Result := Result + UpCase(Name[i]);

  if Length(Result) > 8 then
    Result := Copy(Result, 1, 8);

  if Result = '' then
    Result := 'UNNAMED';
end;

{ TTRDOSReader }

constructor TTRDOSReader.Create;
begin
  inherited Create;
  FImageData := TMemoryStream.Create;
  FFiles := nil;
  FFreeSectorsList := nil;
  FLogicalTracks := 0;
  FPhysicalCylinders := 0;
  FIsDoubleSided := False;
  FAutoMove := True;
  FFileMapValid := False;
  Clear;
end;

destructor TTRDOSReader.Destroy;
begin
  FImageData.Free;
  SetLength(FFiles, 0);
  SetLength(FFreeSectorsList, 0);
  inherited Destroy;
end;

procedure TTRDOSReader.Clear;
begin
  FFileName := '';
  FFileCount := 0;
  FIsLoaded := False;
  FErrorMessage := '';
  FModified := False;
  FLogicalTracks := NO_TRKS;
  FPhysicalCylinders := NO_TRKS;
  FIsDoubleSided := False;
  FTotalSectors := 0;
  FFileMapValid := False;

  SetLength(FFiles, 0);
  SetLength(FFreeSectorsList, 0);
  FillChar(FTrack0, SizeOf(TTrack0), 0);
  FillChar(FFileMap, SizeOf(FFileMap), 0);
  FImageData.Clear;
end;

function TTRDOSReader.GetSectorOffset(Track, Sector: Byte): Int64;
begin
  Result := SEC_SIZE * (SECTORS_PER_TRACK * Track + Sector);
end;

function TTRDOSReader.ReadSector(Track, Sector: Byte; var Data: array of Byte): Boolean;
var
  Offset: Int64;
begin
  Result := False;

  if Track >= FLogicalTracks then
  begin
    FErrorMessage := Format('Track %d out of range (max %d)', [Track, FLogicalTracks - 1]);
    Exit;
  end;

  if Sector >= SECTORS_PER_TRACK then
  begin
    FErrorMessage := Format('Sector %d out of range (max %d)', [Sector, SECTORS_PER_TRACK - 1]);
    Exit;
  end;

  if Length(Data) < SEC_SIZE then
  begin
    FErrorMessage := 'Data buffer too small';
    Exit;
  end;

  Offset := GetSectorOffset(Track, Sector);

  if (Offset >= 0) and (Offset + SEC_SIZE <= FImageData.Size) then
  begin
    FImageData.Position := Offset;
    FImageData.Read(Data[0], SEC_SIZE);
    Result := True;
  end
  else
  begin
    FErrorMessage := Format('Sector out of range: T%d S%d, Offset=%d, Size=%d',
      [Track, Sector, Offset, FImageData.Size]);
    Result := False;
  end;
end;

function TTRDOSReader.WriteSector(Track, Sector: Byte; const Data: array of Byte): Boolean;
var
  Offset: Int64;
begin
  Result := False;

  if Track >= FLogicalTracks then
  begin
    FErrorMessage := Format('Track %d out of range', [Track]);
    Exit;
  end;

  if Sector >= SECTORS_PER_TRACK then
  begin
    FErrorMessage := Format('Sector %d out of range', [Sector]);
    Exit;
  end;

  if Length(Data) < SEC_SIZE then
  begin
    FErrorMessage := 'Data buffer too small';
    Exit;
  end;

  Offset := GetSectorOffset(Track, Sector);

  if (Offset >= 0) and (Offset + SEC_SIZE <= FImageData.Size) then
  begin
    FImageData.Position := Offset;
    FImageData.Write(Data[0], SEC_SIZE);
    FModified := True;
    Result := True;
  end
  else
  begin
    FErrorMessage := Format('Sector out of range: T%d S%d', [Track, Sector]);
    Result := False;
  end;
end;

procedure TTRDOSReader.LoadTrack0;
var
  Sector: Integer;
  SectorData: array[0..SEC_SIZE-1] of Byte;
  Offset: Integer;
begin
  FillChar(FTrack0, SizeOf(TTrack0), 0);

  for Sector := 0 to SECTORS_PER_TRACK - 1 do
  begin
    if ReadSector(0, Sector, SectorData) then
    begin
      Offset := Sector * SEC_SIZE;
      Move(SectorData[0], PByte(@FTrack0)[Offset], SEC_SIZE);
    end;
  end;
end;

procedure TTRDOSReader.SaveTrack0;
var
  Sector: Integer;
  SectorData: array[0..SEC_SIZE-1] of Byte;
  Offset: Integer;
begin
  for Sector := 0 to SECTORS_PER_TRACK - 1 do
  begin
    Offset := Sector * SEC_SIZE;
    Move(PByte(@FTrack0)[Offset], SectorData[0], SEC_SIZE);
    WriteSector(0, Sector, SectorData);
  end;
end;

procedure TTRDOSReader.UpdateDiskGeometry;
begin
  case FTrack0.DiskType of
    DISK_TYPE_80DS:
      begin
        FLogicalTracks := 160;
        FIsDoubleSided := True;
        FPhysicalCylinders := 80;
      end;
    DISK_TYPE_40DS:
      begin
        FLogicalTracks := 80;
        FIsDoubleSided := True;
        FPhysicalCylinders := 40;
      end;
    DISK_TYPE_80SS:
      begin
        FLogicalTracks := 80;
        FIsDoubleSided := False;
        FPhysicalCylinders := 80;
      end;
    DISK_TYPE_40SS:
      begin
        FLogicalTracks := 40;
        FIsDoubleSided := False;
        FPhysicalCylinders := 40;
      end;
  else
    begin
      FIsDoubleSided := (FImageData.Size > NO_TRKS * SECTORS_PER_TRACK * SEC_SIZE);
      if FIsDoubleSided then
      begin
        FPhysicalCylinders := FImageData.Size div (2 * SECTORS_PER_TRACK * SEC_SIZE);
        FLogicalTracks := FPhysicalCylinders * 2;
      end
      else
      begin
        FPhysicalCylinders := FImageData.Size div (SECTORS_PER_TRACK * SEC_SIZE);
        FLogicalTracks := FPhysicalCylinders;
      end;
    end;
  end;

  FTotalSectors := GetTotalSectorsCount;
end;

function TTRDOSReader.GetTotalSectorsCount: Integer;
begin
  Result := FLogicalTracks * SECTORS_PER_TRACK;
end;

function TTRDOSReader.ExtractBasicStartLine(const Data: TStream): Word;
var
  Buffer: array[0..255] of Byte;
  SavedPos: Int64;
  i: Integer;
  LineNum: Word;
begin
  Result := 0;
  SavedPos := Data.Position;
  Data.Position := 0;

  try
    if Data.Size >= 5 then
    begin
      FillChar(Buffer, SizeOf(Buffer), 0);
      Data.Read(Buffer, Min(Data.Size, 256));

      i := 0;
      while i < Data.Size - 4 do
      begin
        LineNum := Buffer[i+2] + (Buffer[i+3] shl 8);
        if (LineNum > 0) and (LineNum < 10000) then
        begin
          Result := LineNum;
          Break;
        end;
        Inc(i);
      end;
    end;
  finally
    Data.Position := SavedPos;
  end;
end;

function TTRDOSReader.ParseBasicFile(var Info: TFileInfo; const Data: TStream): Boolean;
var
  SavedPos: Int64;
begin
  Result := False;
  SavedPos := Data.Position;

  try
    Info.BasicProgramLength := Info.CodeLength;
    Info.BasicDataLength := Info.RawSize - Info.CodeLength;
    Info.BasicStartLine := ExtractBasicStartLine(Data);
    Result := True;
  finally
    Data.Position := SavedPos;
  end;
end;

procedure TTRDOSReader.ParseCatalog;
var
  i: Integer;
  FileInfo: TFileInfo;
  Hdr: TFileHdr;
begin
  SetLength(FFiles, 0);
  FFileCount := 0;

  for i := 0 to MAX_FILES_REAL - 1 do
  begin
    Hdr := FTrack0.Files[i];

    if Hdr.Name[0] = #0 then
      Break;

    if Hdr.Name[0] = Char(FILE_DELETED) then
      Continue;

    FillChar(FileInfo, SizeOf(TFileInfo), 0);

    FileInfo.Name := ZXStringToPascal(Hdr.Name);
    FileInfo.FileType := Hdr.FileType;
    FileInfo.FileTypeDesc := GetFileTypeDescription(Hdr.FileType);
    FileInfo.StartTrack := Hdr.StartTrack;
    FileInfo.StartSector := Hdr.StartSector;
    FileInfo.SectorsCount := Hdr.SectorsCount;
    FileInfo.RawSize := Hdr.SectorsCount * SEC_SIZE;
    FileInfo.IsDeleted := False;

    if not (Hdr.FileType in [FILE_TYPE_BASIC, FILE_TYPE_DATA, FILE_TYPE_STREAM]) then
      Hdr.FileType := FILE_TYPE_CODE;

    case Hdr.FileType of
      FILE_TYPE_CODE:
        begin
          FileInfo.LoadAddress := Hdr.StartAddress;
          FileInfo.CodeLength := Hdr.Length;
          FileInfo.RealSize := Hdr.Length;
        end;

      FILE_TYPE_BASIC:
        begin
          FileInfo.LoadAddress := Hdr.StartAddress;
          FileInfo.CodeLength := Hdr.Length;
          FileInfo.BasicProgramLength := Hdr.Length;
          FileInfo.BasicDataLength := Hdr.StartAddress - Hdr.Length;
          FileInfo.RealSize := Hdr.StartAddress;
        end;

      FILE_TYPE_DATA:
        begin
          FileInfo.LoadAddress := Hdr.StartAddress;
          FileInfo.CodeLength := Hdr.Length;
          FileInfo.RealSize := Hdr.Length;
        end;

      FILE_TYPE_STREAM:
        begin
          FileInfo.ExtentNo := Hdr.StartAddress and $FF;
          FileInfo.RealSize := Hdr.Length;
        end;
    end;

    Inc(FFileCount);
    SetLength(FFiles, Length(FFiles) + 1);
    FFiles[High(FFiles)] := FileInfo;
  end;
end;

procedure TTRDOSReader.CompactCatalog;
var
  i: Integer;
  NewIndex: Integer;
begin
  NewIndex := 0;

  for i := 0 to MAX_FILES_REAL - 1 do
  begin
    if (FTrack0.Files[i].Name[0] <> #0) and
       (FTrack0.Files[i].Name[0] <> Char(FILE_DELETED)) then
    begin
      if i <> NewIndex then
        FTrack0.Files[NewIndex] := FTrack0.Files[i];
      Inc(NewIndex);
    end
    else if FTrack0.Files[i].Name[0] = #0 then
      Break;
  end;

  for i := NewIndex to MAX_FILES_REAL - 1 do
    FillChar(FTrack0.Files[i], SizeOf(TFileHdr), 0);

  if FTrack0.FilesCount <> NewIndex then
  begin
    FTrack0.FilesCount := NewIndex;
    FTrack0.DeletedFilesCount := 0;
  end;
end;

procedure TTRDOSReader.CompactDisk;
var
  i, j: Integer;
  FromTrack, FromSector: Byte;
  ToTrack, ToSector: Byte;
  SectorData: array[0..SEC_SIZE-1] of Byte;
  DelFound: Boolean;
  TotalDelSectors: Integer;
  NewFileIndex: Integer;
begin
  TotalDelSectors := 0;
  DelFound := False;
  ToTrack := 1;
  ToSector := 0;
  NewFileIndex := 0;

  for i := 0 to MAX_FILES_REAL - 1 do
  begin
    if FTrack0.Files[i].Name[0] = #0 then
      Break;

    if FTrack0.Files[i].Name[0] = Char(FILE_DELETED) then
    begin
      if not DelFound then
      begin
        ToTrack := FTrack0.Files[i].StartTrack;
        ToSector := FTrack0.Files[i].StartSector;
        DelFound := True;
      end;
      Inc(TotalDelSectors, FTrack0.Files[i].SectorsCount);
    end
    else
    begin
      if DelFound then
      begin
        FromTrack := FTrack0.Files[i].StartTrack;
        FromSector := FTrack0.Files[i].StartSector;

        FTrack0.Files[i].StartTrack := ToTrack;
        FTrack0.Files[i].StartSector := ToSector;

        for j := 1 to FTrack0.Files[i].SectorsCount do
        begin
          if ReadSector(FromTrack, FromSector, SectorData) then
            WriteSector(ToTrack, ToSector, SectorData);

          Inc(FromSector);
          if FromSector >= SECTORS_PER_TRACK then
          begin
            FromSector := 0;
            Inc(FromTrack);
          end;

          Inc(ToSector);
          if ToSector >= SECTORS_PER_TRACK then
          begin
            ToSector := 0;
            Inc(ToTrack);
          end;
        end;
      end;

      if NewFileIndex <> i then
        FTrack0.Files[NewFileIndex] := FTrack0.Files[i];
      Inc(NewFileIndex);
    end;
  end;

  for i := NewFileIndex to MAX_FILES_REAL - 1 do
    FillChar(FTrack0.Files[i], SizeOf(TFileHdr), 0);

  if DelFound then
  begin
    FTrack0.FirstFreeTrack := ToTrack;
    FTrack0.FirstFreeSector := ToSector;
  end;

  FTrack0.FilesCount := NewFileIndex;
  FTrack0.DeletedFilesCount := 0;
  BuildFreeSectorsList;
end;

function TTRDOSReader.FindFreeCatalogSlot: Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to MAX_FILES_REAL - 1 do
  begin
    if (FTrack0.Files[i].Name[0] = #0) then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

procedure TTRDOSReader.BuildFreeSectorsList;
var
  Track, Sector: Integer;
  UsedSectors: array of array of Boolean;
  i, j: Integer;
  TrackIdx, SectorIdx: Integer;
  BitIndex, ByteIndex, BitMask: Integer;
begin
  UpdateDiskGeometry;
  if FLogicalTracks <= 0 then
  begin
    SetLength(FFreeSectorsList, 0);
    Exit;
  end;

  SetLength(UsedSectors, FLogicalTracks, SECTORS_PER_TRACK);

  for Track := 0 to FLogicalTracks - 1 do
    for Sector := 0 to SECTORS_PER_TRACK - 1 do
      UsedSectors[Track, Sector] := False;

  for Sector := 0 to SECTORS_PER_TRACK - 1 do
    UsedSectors[0, Sector] := True;

  if FIsLoaded then
  begin
    for i := 0 to MAX_FILES_REAL - 1 do
    begin
      if (FTrack0.Files[i].Name[0] = #0) then Break;
      if FTrack0.Files[i].SectorsCount > 0 then
      begin
        TrackIdx := FTrack0.Files[i].StartTrack;
        SectorIdx := FTrack0.Files[i].StartSector;
        for j := 1 to FTrack0.Files[i].SectorsCount do
        begin
          if (TrackIdx >= 0) and (TrackIdx < FLogicalTracks) and
             (SectorIdx >= 0) and (SectorIdx < SECTORS_PER_TRACK) then
            UsedSectors[TrackIdx, SectorIdx] := True;
          Inc(SectorIdx);
          if SectorIdx >= SECTORS_PER_TRACK then
          begin
            SectorIdx := 0;
            Inc(TrackIdx);
          end;
          if TrackIdx >= FLogicalTracks then Break;
        end;
      end;
    end;

    if FFileMapValid then
    begin
      for Track := 80 to FLogicalTracks - 1 do
      begin
        for Sector := 0 to SECTORS_PER_TRACK - 1 do
        begin
          BitIndex := ((Track - 80) * SECTORS_PER_TRACK) + Sector;
          if BitIndex < 1024 then
          begin
            ByteIndex := BitIndex shr 3;
            BitMask := 1 shl (BitIndex and 7);
            if (FFileMap[ByteIndex] and BitMask) <> 0 then
              UsedSectors[Track, Sector] := True;
          end;
        end;
      end;
    end;
  end;

  SetLength(FFreeSectorsList, 0);
  for Track := 0 to FLogicalTracks - 1 do
    for Sector := 0 to SECTORS_PER_TRACK - 1 do
      if not UsedSectors[Track, Sector] then
      begin
        SetLength(FFreeSectorsList, Length(FFreeSectorsList) + 1);
        FFreeSectorsList[High(FFreeSectorsList)].Track := Track;
        FFreeSectorsList[High(FFreeSectorsList)].Sector := Sector;
      end;

  if Length(FFreeSectorsList) > 0 then
  begin
    FTrack0.FirstFreeTrack := FFreeSectorsList[0].Track;
    FTrack0.FirstFreeSector := FFreeSectorsList[0].Sector;
  end
  else
  begin
    FTrack0.FirstFreeTrack := 0;
    FTrack0.FirstFreeSector := 0;
  end;
  FTrack0.FreeSectorsCount := Length(FFreeSectorsList);
end;

function TTRDOSReader.AllocateSectors(Count: Integer): TFreeSectorInfoList;
var
  i: Integer;
begin
  SetLength(Result, 0);

  if Count <= 0 then
    Exit;

  if Length(FFreeSectorsList) < Count then
  begin
    FErrorMessage := Format('Not enough free sectors. Need %d, have %d',
      [Count, Length(FFreeSectorsList)]);
    Exit;
  end;

  SetLength(Result, Count);
  for i := 0 to Count - 1 do
    Result[i] := FFreeSectorsList[i];

  for i := 0 to Length(FFreeSectorsList) - Count - 1 do
    FFreeSectorsList[i] := FFreeSectorsList[i + Count];
  SetLength(FFreeSectorsList, Length(FFreeSectorsList) - Count);

  if Length(FFreeSectorsList) > 0 then
  begin
    FTrack0.FirstFreeTrack := FFreeSectorsList[0].Track;
    FTrack0.FirstFreeSector := FFreeSectorsList[0].Sector;
  end
  else
  begin
    FTrack0.FirstFreeTrack := 0;
    FTrack0.FirstFreeSector := 0;
  end;
  FTrack0.FreeSectorsCount := Length(FFreeSectorsList);
end;

procedure TTRDOSReader.FreeSectors(const Sectors: TFreeSectorInfoList);
var
  i, j, NewLen: Integer;
  OldLen: Integer;
  Temp: TFreeSectorInfo;
begin
  OldLen := Length(FFreeSectorsList);
  NewLen := OldLen + Length(Sectors);
  SetLength(FFreeSectorsList, NewLen);

  for i := 0 to Length(Sectors) - 1 do
    FFreeSectorsList[OldLen + i] := Sectors[i];

  for i := 0 to NewLen - 2 do
    for j := i + 1 to NewLen - 1 do
      if (FFreeSectorsList[i].Track > FFreeSectorsList[j].Track) or
         ((FFreeSectorsList[i].Track = FFreeSectorsList[j].Track) and
          (FFreeSectorsList[i].Sector > FFreeSectorsList[j].Sector)) then
      begin
        Temp := FFreeSectorsList[i];
        FFreeSectorsList[i] := FFreeSectorsList[j];
        FFreeSectorsList[j] := Temp;
      end;
end;

function TTRDOSReader.CalculateSectorsNeeded(Size: Integer): Integer;
begin
  Result := (Size + SEC_SIZE - 1) div SEC_SIZE;
  if Result = 0 then
    Result := 1;
end;

function TTRDOSReader.LoadFromFileInternal(const AFileName: string): Boolean;
var
  FileStream: TFileStream;
begin
  Result := False;

  try
    FileStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      FImageData.Size := 0;
      FImageData.CopyFrom(FileStream, FileStream.Size);
    finally
      FileStream.Free;
    end;

    if FImageData.Size < SECTORS_PER_TRACK * SEC_SIZE then
    begin
      FErrorMessage := 'Image too small (less than one track)';
      Exit;
    end;

    if FImageData.Size mod SEC_SIZE <> 0 then
    begin
      FErrorMessage := 'Image size not multiple of sector size';
      Exit;
    end;

    LoadTrack0;
    UpdateDiskGeometry;

    FFileMapValid := False;
    if FIsDoubleSided and (FTrack0.DSSignature[0] = 'D') then
    begin
      Move(FTrack0.DSFileMap, FFileMap, SizeOf(FFileMap));
      FFileMapValid := True;
    end;

    FIsLoaded := True;
    ParseCatalog;
    BuildFreeSectorsList;

    FFileName := AFileName;
    FModified := False;
    Result := True;

  except
    on E: Exception do
    begin
      FErrorMessage := 'Error reading file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TTRDOSReader.SaveToFileInternal(const AFileName: string): Boolean;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No disk image loaded';
    Exit;
  end;

  try
    if FFileMapValid then
    begin
      Move(FFileMap, FTrack0.DSFileMap, SizeOf(FFileMap));
    end;

    SaveTrack0;
    FImageData.SaveToFile(AFileName);
    FFileName := AFileName;
    FModified := False;
    Result := True;
  except
    on E: Exception do
    begin
      FErrorMessage := 'Error saving file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TTRDOSReader.LoadFromFile(const AFileName: string): Boolean;
begin
  Clear;
  Result := LoadFromFileInternal(AFileName);
end;

function TTRDOSReader.SaveToFile(const AFileName: string): Boolean;
begin
  Result := SaveToFileInternal(AFileName);
end;

function TTRDOSReader.SaveToCurrentFile: Boolean;
begin
  if FFileName = '' then
    Result := False
  else
    Result := SaveToFile(FFileName);
end;

function TTRDOSReader.CreateNewDisk(const Params: TNewDiskParams): Boolean;
var
  Track, Sector: Integer;
  Buffer: array[0..SEC_SIZE-1] of Byte;
  i: Integer;
  LogicalTracksCount: Integer;
begin
  Clear;
  Result := False;

  try
    case Params.DiskType of
      dt40SS:
        begin
          FTrack0.DiskType := DISK_TYPE_40SS;
          LogicalTracksCount := 40;
          FIsDoubleSided := False;
          FPhysicalCylinders := 40;
          FFileMapValid := False;
        end;
      dt40DS:
        begin
          FTrack0.DiskType := DISK_TYPE_40DS;
          LogicalTracksCount := 80;
          FIsDoubleSided := True;
          FPhysicalCylinders := 40;
          FFileMapValid := True;
          FillChar(FFileMap, SizeOf(FFileMap), 0);
        end;
      dt80SS:
        begin
          FTrack0.DiskType := DISK_TYPE_80SS;
          LogicalTracksCount := 80;
          FIsDoubleSided := False;
          FPhysicalCylinders := 80;
          FFileMapValid := False;
        end;
      dt80DS:
        begin
          FTrack0.DiskType := DISK_TYPE_80DS;
          LogicalTracksCount := 160;
          FIsDoubleSided := True;
          FPhysicalCylinders := 80;
          FFileMapValid := True;
          FillChar(FFileMap, SizeOf(FFileMap), 0);
        end;
      else
        begin
          FTrack0.DiskType := DISK_TYPE_80DS;
          LogicalTracksCount := 160;
          FIsDoubleSided := True;
          FPhysicalCylinders := 80;
          FFileMapValid := True;
          FillChar(FFileMap, SizeOf(FFileMap), 0);
        end;
    end;

    FLogicalTracks := LogicalTracksCount;
    FTotalSectors := FLogicalTracks * SECTORS_PER_TRACK;

    FillChar(Buffer, SEC_SIZE, 0);
    FImageData.Size := 0;

    for Track := 0 to FLogicalTracks - 1 do
      for Sector := 0 to SECTORS_PER_TRACK - 1 do
        FImageData.Write(Buffer, SEC_SIZE);

    FillChar(FTrack0, SizeOf(TTrack0), 0);

    for i := 0 to MAX_FILES_REAL - 1 do
    begin
      FillChar(FTrack0.Files[i], SizeOf(TFileHdr), 0);
    end;

    FTrack0.Flag := $10;
    FTrack0.FirstFreeTrack := 1;
    FTrack0.FirstFreeSector := 0;
    FTrack0.FilesCount := 0;
    FTrack0.DeletedFilesCount := 0;
    FTrack0.FreeSectorsCount := FTotalSectors - SECTORS_PER_TRACK;

    if Params.LabelName <> '' then
      PascalToZXString(Copy(Params.LabelName, 1, 11), FTrack0.VolumeLabel)
    else
      PascalToZXString('DISK       ', FTrack0.VolumeLabel);

    if FIsDoubleSided then
    begin
      FTrack0.DScrc := $D019;
      for i := 0 to 8 do
        FTrack0.DSSignature[i] := DS_SIGNATURE[i];
      Move(FFileMap, FTrack0.DSFileMap, SizeOf(FFileMap));
    end;

    SaveTrack0;
    BuildFreeSectorsList;

    FIsLoaded := True;
    FModified := True;
    Result := True;

  except
    on E: Exception do
    begin
      FErrorMessage := 'Error creating disk: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TTRDOSReader.CreateNewDiskEx(DiskType: TTRDSDiskType; const LabelName: string;
                                       const Password: string = ''): Boolean;
var
  Params: TNewDiskParams;
begin
  Params.DiskType := DiskType;
  Params.LabelName := LabelName;
  Params.Password := Password;
  Result := CreateNewDisk(Params);
end;

function TTRDOSReader.FormatTrd(DiskType: TTRDSDiskType; const LabelName: string;
                              const Password: string = ''): Boolean;
begin
  Result := CreateNewDiskEx(DiskType, LabelName, Password);
end;

function TTRDOSReader.AddFile(const FileName: string; FileType: Char;
                               LoadAddress: Word; FileLength: Word;
                               DataStream: TStream; BasicStartLine: Word = 0): Boolean;
var
  SlotIndex: Integer;
  RequiredSectors: Integer;
  AllocatedSectors: TFreeSectorInfoList;
  Hdr: TFileHdr;
  FileInfo: TFileInfo;
  TempStream: TMemoryStream;
  Track: Byte;
  Sector: Byte;
  i: Integer;
  Buffer: array[0..SEC_SIZE-1] of Byte;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No disk image loaded';
    Exit;
  end;

  if DataStream = nil then
  begin
    FErrorMessage := 'Data stream is nil';
    Exit;
  end;

  if (Length(FileName) = 0) or (Length(FileName) > 8) then
  begin
    FErrorMessage := 'File name must be 1-8 characters';
    Exit;
  end;

  if not (FileType in [FILE_TYPE_BASIC, FILE_TYPE_CODE, FILE_TYPE_DATA, FILE_TYPE_STREAM]) then
  begin
    FErrorMessage := 'Invalid file type';
    Exit;
  end;

  if FileLength = 0 then
    FileLength := DataStream.Size;

  RequiredSectors := CalculateSectorsNeeded(FileLength);

  AllocatedSectors := AllocateSectors(RequiredSectors);
  if Length(AllocatedSectors) <> RequiredSectors then
    Exit;

  SlotIndex := FindFreeCatalogSlot;
  if SlotIndex = -1 then
  begin
    FErrorMessage := 'Catalog is full';
    Exit;
  end;

  FillChar(Hdr, SizeOf(TFileHdr), 0);
  PascalToZXString(NormalizeFileName(FileName), Hdr.Name);
  Hdr.FileType := FileType;
  Hdr.SectorsCount := RequiredSectors;
  Hdr.StartSector := AllocatedSectors[0].Sector;
  Hdr.StartTrack := AllocatedSectors[0].Track;

  case FileType of
    FILE_TYPE_CODE:
      begin
        Hdr.StartAddress := LoadAddress;
        Hdr.Length := FileLength;
      end;

    FILE_TYPE_BASIC:
      begin
        Hdr.StartAddress := FileLength;
        Hdr.Length := FileLength;
      end;

    FILE_TYPE_DATA:
      begin
        Hdr.StartAddress := LoadAddress;
        Hdr.Length := FileLength;
      end;

    FILE_TYPE_STREAM:
      begin
        Hdr.StartAddress := 0;
        Hdr.Length := FileLength;
      end;
  end;

  FTrack0.Files[SlotIndex] := Hdr;
  Inc(FTrack0.FilesCount);

  TempStream := TMemoryStream.Create;
  try
    DataStream.Position := 0;
    TempStream.CopyFrom(DataStream, FileLength);
    TempStream.Size := RequiredSectors * SEC_SIZE;

    Track := AllocatedSectors[0].Track;
    Sector := AllocatedSectors[0].Sector;

    TempStream.Position := 0;
    for i := 0 to RequiredSectors - 1 do
    begin
      FillChar(Buffer, SEC_SIZE, 0);
      TempStream.Read(Buffer, SEC_SIZE);
      if not WriteSector(Track, Sector, Buffer) then
        Exit;

      Inc(Sector);
      if Sector >= SECTORS_PER_TRACK then
      begin
        Sector := 0;
        Inc(Track);
      end;
    end;
  finally
    TempStream.Free;
  end;

  FillChar(FileInfo, SizeOf(TFileInfo), 0);
  FileInfo.Name := NormalizeFileName(FileName);
  FileInfo.FileType := FileType;
  FileInfo.FileTypeDesc := GetFileTypeDescription(FileType);
  FileInfo.StartTrack := Hdr.StartTrack;
  FileInfo.StartSector := Hdr.StartSector;
  FileInfo.SectorsCount := RequiredSectors;
  FileInfo.RawSize := RequiredSectors * SEC_SIZE;
  FileInfo.RealSize := FileLength;
  FileInfo.LoadAddress := LoadAddress;
  FileInfo.CodeLength := FileLength;
  FileInfo.IsDeleted := False;

  if FileType = FILE_TYPE_BASIC then
    FileInfo.BasicStartLine := BasicStartLine;

  SetLength(FFiles, FFileCount + 1);
  FFiles[FFileCount] := FileInfo;
  Inc(FFileCount);

  SaveTrack0;
  BuildFreeSectorsList;

  FModified := True;
  Result := True;
end;

function TTRDOSReader.AddFileFromFile(const FileName: string; FileType: Char;
                                       LoadAddress: Word; FileLength: Word;
                                       const SourceFileName: string;
                                       BasicStartLine: Word = 0): Boolean;
var
  FileStream: TFileStream;
begin
  Result := False;

  if not FileExists(SourceFileName) then
  begin
    FErrorMessage := 'Source file not found: ' + SourceFileName;
    Exit;
  end;

  try
    FileStream := TFileStream.Create(SourceFileName, fmOpenRead or fmShareDenyWrite);
    try
      Result := AddFile(FileName, FileType, LoadAddress, FileLength, FileStream, BasicStartLine);
    finally
      FileStream.Free;
    end;
  except
    on E: Exception do
    begin
      FErrorMessage := 'Error reading source file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TTRDOSReader.DeleteFile(Index: Integer): Boolean;
var
  i: Integer;
  ActualIndex: Integer;
  FoundCount: Integer;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No disk image loaded';
    Exit;
  end;

  if (Index < 0) or (Index >= FFileCount) then
  begin
    FErrorMessage := 'Invalid file index';
    Exit;
  end;

  ActualIndex := -1;
  FoundCount := 0;
  for i := 0 to MAX_FILES_REAL - 1 do
  begin
    if FTrack0.Files[i].Name[0] = #0 then
      Break;

    if FTrack0.Files[i].Name[0] <> Char(FILE_DELETED) then
    begin
      if FoundCount = Index then
      begin
        ActualIndex := i;
        Break;
      end;
      Inc(FoundCount);
    end;
  end;

  if ActualIndex = -1 then
  begin
    FErrorMessage := 'File not found in catalog';
    Exit;
  end;

  FTrack0.Files[ActualIndex].Name[0] := Char(FILE_DELETED);
  Inc(FTrack0.DeletedFilesCount);

  if FAutoMove then
  begin
    CompactDisk;
  end;

  SaveTrack0;

  SetLength(FFiles, 0);
  FFileCount := 0;
  ParseCatalog;
  BuildFreeSectorsList;
  FModified := True;
  Result := True;
end;

function TTRDOSReader.DeleteFileByName(const FileName: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to FFileCount - 1 do
  begin
    if UpperCase(FFiles[i].Name) = UpperCase(FileName) then
    begin
      Result := DeleteFile(i);
      Exit;
    end;
  end;
  FErrorMessage := 'File not found: ' + FileName;
end;

function TTRDOSReader.UndeleteFile(Index: Integer): Boolean;
begin
  Result := False;
  FErrorMessage := 'Undelete not implemented yet';
end;

function TTRDOSReader.RenameFile(Index: Integer; const NewName: string): Boolean;
var
  i: Integer;
  ActualIndex: Integer;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No disk image loaded';
    Exit;
  end;

  if (Index < 0) or (Index >= FFileCount) then
  begin
    FErrorMessage := 'Invalid file index';
    Exit;
  end;

  if (Length(NewName) = 0) or (Length(NewName) > 8) then
  begin
    FErrorMessage := 'File name must be 1-8 characters';
    Exit;
  end;

  ActualIndex := -1;
  for i := 0 to MAX_FILES_REAL - 1 do
  begin
    if (FTrack0.Files[i].Name[0] <> #0) and
       (FTrack0.Files[i].Name[0] <> Char(FILE_DELETED)) then
    begin
      if ActualIndex = Index - 1 then
      begin
        ActualIndex := i;
        Break;
      end;
      Inc(ActualIndex);
    end;
  end;

  if ActualIndex = -1 then
  begin
    FErrorMessage := 'File not found in catalog';
    Exit;
  end;

  PascalToZXString(NormalizeFileName(NewName), FTrack0.Files[ActualIndex].Name);
  SaveTrack0;
  FFiles[Index].Name := NormalizeFileName(NewName);

  FModified := True;
  Result := True;
end;

function TTRDOSReader.ExtractFile(Index: Integer; DestStream: TStream): Boolean;
var
  Track, Sector: Byte;
  SectorsRemaining: Byte;
  SectorData: array[0..SEC_SIZE-1] of Byte;
  FileInfo: TFileInfo;
  BytesToWrite, TotalWritten: Integer;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No disk image loaded';
    Exit;
  end;

  if (Index < 0) or (Index >= FFileCount) then
  begin
    FErrorMessage := 'Invalid file index';
    Exit;
  end;

  FileInfo := FFiles[Index];

  if FileInfo.SectorsCount = 0 then
  begin
    FErrorMessage := 'File has no data sectors';
    Exit;
  end;

  Track := FileInfo.StartTrack;
  Sector := FileInfo.StartSector;
  SectorsRemaining := FileInfo.SectorsCount;
  TotalWritten := 0;

  while SectorsRemaining > 0 do
  begin
    if not ReadSector(Track, Sector, SectorData) then
    begin
      FErrorMessage := Format('Failed to read sector T%d S%d', [Track, Sector]);
      Exit;
    end;

    if TotalWritten + SEC_SIZE > FileInfo.RealSize then
      BytesToWrite := FileInfo.RealSize - TotalWritten
    else
      BytesToWrite := SEC_SIZE;

    if BytesToWrite > 0 then
    begin
      DestStream.Write(SectorData, BytesToWrite);
      Inc(TotalWritten, BytesToWrite);
    end;

    Inc(Sector);
    if Sector >= SECTORS_PER_TRACK then
    begin
      Sector := 0;
      Inc(Track);
    end;

    Dec(SectorsRemaining);
  end;

  Result := True;
end;

function TTRDOSReader.ExtractFileToFile(Index: Integer; const DestFileName: string): Boolean;
var
  FileStream: TFileStream;
begin
  Result := False;
  try
    FileStream := TFileStream.Create(DestFileName, fmCreate);
    try
      Result := ExtractFile(Index, FileStream);
    finally
      FileStream.Free;
    end;
  except
    on E: Exception do
    begin
      FErrorMessage := 'Failed to create output file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TTRDOSReader.ExtractFileToMemory(Index: Integer): TMemoryStream;
var
  Stream: TMemoryStream;
begin
  Result := nil;
  Stream := TMemoryStream.Create;
  try
    if ExtractFile(Index, Stream) then
      Result := Stream
    else
      Stream.Free;
  except
    Stream.Free;
    raise;
  end;
end;

function TTRDOSReader.GetFileInfo(Index: Integer): TFileInfo;
begin
  FillChar(Result, SizeOf(TFileInfo), 0);
  if (Index >= 0) and (Index < FFileCount) then
    Result := FFiles[Index];
end;

function TTRDOSReader.GetFileInfoByName(const FileName: string): TFileInfo;
var
  i: Integer;
begin
  FillChar(Result, SizeOf(TFileInfo), 0);
  for i := 0 to FFileCount - 1 do
  begin
    if UpperCase(FFiles[i].Name) = UpperCase(FileName) then
    begin
      Result := FFiles[i];
      Exit;
    end;
  end;
end;

function TTRDOSReader.GetDiskTypeString: string;
begin
  case FTrack0.DiskType of
    DISK_TYPE_80DS: Result := '80 tracks, double side (160 logical tracks)';
    DISK_TYPE_40DS: Result := '40 tracks, double side (80 logical tracks)';
    DISK_TYPE_80SS: Result := '80 tracks, single side (80 logical tracks)';
    DISK_TYPE_40SS: Result := '40 tracks, single side (40 logical tracks)';
  else
    if FIsDoubleSided then
      Result := Format('%d logical tracks (%d cylinders, double sided)',
        [FLogicalTracks, FPhysicalCylinders])
    else
      Result := Format('%d logical tracks (%d cylinders, single sided)',
        [FLogicalTracks, FPhysicalCylinders]);
  end;
end;

function TTRDOSReader.GetDiskLabel: string;
begin
  Result := ZXStringToPascal(FTrack0.VolumeLabel);
end;

function TTRDOSReader.SetDiskLabel(const LabelName: string): Boolean;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No disk image loaded';
    Exit;
  end;

  PascalToZXString(LabelName, FTrack0.VolumeLabel);
  SaveTrack0;
  FModified := True;
  Result := True;
end;

function TTRDOSReader.GetFreeSectorsCount: Integer;
begin
  Result := FTrack0.FreeSectorsCount;
end;

function TTRDOSReader.GetFreeSpace: Integer;
begin
  Result := GetFreeSectorsCount * SEC_SIZE;
end;

function TTRDOSReader.GetUsedSpace: Integer;
begin
  Result := GetTotalSpace - GetFreeSpace;
end;

function TTRDOSReader.GetTotalSpace: Integer;
begin
  Result := FTotalSectors * SEC_SIZE;
end;

function TTRDOSReader.GetUsagePercent: Single;
begin
  if GetTotalSpace > 0 then
    Result := (GetUsedSpace / GetTotalSpace) * 100
  else
    Result := 0;
end;

function TTRDOSReader.GetFilesCount: Integer;
begin
  Result := FTrack0.FilesCount;
end;

function TTRDOSReader.GetDeletedFilesCount: Integer;
begin
  Result := FTrack0.DeletedFilesCount;
end;

function TTRDOSReader.GetLogicalTracksCount: Integer;
begin
  Result := FLogicalTracks;
end;

function TTRDOSReader.GetPhysicalCylindersCount: Integer;
begin
  Result := FPhysicalCylinders;
end;

function TTRDOSReader.IsDoubleSided: Boolean;
begin
  Result := FIsDoubleSided;
end;

{ TSCLReader }

constructor TSCLReader.Create;
begin
  inherited Create;
  FImageData := TMemoryStream.Create;
  FFiles := nil;
  FSCLFiles := nil;
  Clear;
end;

destructor TSCLReader.Destroy;
begin
  FImageData.Free;
  SetLength(FFiles, 0);
  SetLength(FSCLFiles, 0);
  inherited Destroy;
end;

procedure TSCLReader.Clear;
begin
  FFileName := '';
  FFileCount := 0;
  FIsLoaded := False;
  FErrorMessage := '';
  FModified := False;

  SetLength(FFiles, 0);
  SetLength(FSCLFiles, 0);
  FImageData.Clear;
end;

function TSCLReader.GetDataStartOffset: Int64;
begin
  Result := SizeOf(TSCLDiskHeader) + FFileCount * SizeOf(TSCLFileHdr);
end;

function TSCLReader.GetSectorOffsetInFile(Index: Integer): Int64;
begin
  if (Index < 0) or (Index >= FFileCount) then
    Result := -1
  else
    Result := GetDataStartOffset + Int64(FSCLFiles[Index].SectorOffset) * SECTOR_SIZE;
end;

function TSCLReader.ReadSCLHeader(var Header: TSCLDiskHeader): Boolean;
begin
  Result := False;
  if FImageData.Size < SizeOf(TSCLDiskHeader) then
    Exit;

  FImageData.Position := 0;
  FImageData.Read(Header, SizeOf(TSCLDiskHeader));

  if not CompareMem(@Header.Signature, @SCL_SIGNATURE, SizeOf(SCL_SIGNATURE)) then
  begin
    FErrorMessage := 'Invalid SCL signature';
    Exit;
  end;

  Result := True;
end;

function TSCLReader.CalculateSCLCheckSum: DWord;
var
  OldPos: Int64;
  Header: TSCLDiskHeader;
  i: Integer;
  Buffer: array[0..SECTOR_SIZE-1] of Byte;
  BytesRead: Integer;
begin
  Result := $255;

  OldPos := FImageData.Position;
  try
    FImageData.Position := 0;

    FillChar(Buffer, SECTOR_SIZE, 0);
    FImageData.Read(Buffer, 8);
    Result := Result + CalcCheckSum(Buffer, 8);

    FillChar(Buffer, SECTOR_SIZE, 0);
    FImageData.Read(Buffer, 1);
    Result := Result + Buffer[0];

    for i := 0 to FFileCount - 1 do
    begin
      FillChar(Buffer, SECTOR_SIZE, 0);
      FImageData.Read(Buffer, SizeOf(TSCLFileHdr));
      Result := Result + CalcCheckSum(Buffer, SizeOf(TSCLFileHdr));
    end;

    while FImageData.Position < FImageData.Size - SCL_CHECKSUM_SIZE do
    begin
      FillChar(Buffer, SECTOR_SIZE, 0);
      BytesRead := FImageData.Read(Buffer, SECTOR_SIZE);
      if BytesRead > 0 then
        Result := Result + CalcCheckSum(Buffer, BytesRead);
    end;

  finally
    FImageData.Position := OldPos;
  end;
end;

procedure TSCLReader.UpdateSCLCheckSum;
var
  CheckSum: DWord;
  OldPos: Int64;
begin
  OldPos := FImageData.Position;
  try
    CheckSum := CalculateSCLCheckSum;
    FImageData.Position := FImageData.Size - SCL_CHECKSUM_SIZE;
    FImageData.Write(CheckSum, SCL_CHECKSUM_SIZE);
  finally
    FImageData.Position := OldPos;
  end;
end;

function TSCLReader.WriteSCLHeader: Boolean;
var
  Header: TSCLDiskHeader;
  i: Integer;
  OldPos: Int64;
begin
  Result := False;
  OldPos := FImageData.Position;

  try
    FImageData.Position := 0;

    Header.Signature := SCL_SIGNATURE;
    Header.FilesCount := FFileCount;
    FImageData.Write(Header, SizeOf(TSCLDiskHeader));

    for i := 0 to FFileCount - 1 do
    begin
      FImageData.Write(FSCLFiles[i].Header, SizeOf(TSCLFileHdr));
    end;

    Result := True;
  except
    Result := False;
  end;

  FImageData.Position := OldPos;
end;

procedure TSCLReader.ParseSCL;
var
  i: Integer;
  Header: TSCLDiskHeader;
  FileData: TSCLFileData;
  CurrentSectorOffset: Integer;
begin
  SetLength(FFiles, 0);
  SetLength(FSCLFiles, 0);

  if not ReadSCLHeader(Header) then
    Exit;

  FFileCount := Header.FilesCount;
  if FFileCount > MAX_FILES_IN_CATALOG then
    FFileCount := MAX_FILES_IN_CATALOG;

  SetLength(FSCLFiles, FFileCount);
  SetLength(FFiles, FFileCount);

  CurrentSectorOffset := 0;

  for i := 0 to FFileCount - 1 do
  begin
    FImageData.Position := SizeOf(TSCLDiskHeader) + i * SizeOf(TSCLFileHdr);
    FImageData.Read(FileData.Header, SizeOf(TSCLFileHdr));

    FileData.SectorOffset := CurrentSectorOffset;
    Inc(CurrentSectorOffset, FileData.Header.SectorsCount);

    FillChar(FileData.FileInfo, SizeOf(TFileInfo), 0);
    FileData.FileInfo.Name := ZXStringToPascal(FileData.Header.Name);
    FileData.FileInfo.FileType := FileData.Header.FileType;
    FileData.FileInfo.FileTypeDesc := GetFileTypeDescription(FileData.Header.FileType);
    FileData.FileInfo.SectorsCount := FileData.Header.SectorsCount;
    FileData.FileInfo.RawSize := FileData.Header.SectorsCount * SECTOR_SIZE;
    FileData.FileInfo.RealSize := FileData.Header.Length;
    FileData.FileInfo.LoadAddress := FileData.Header.StartAddress;
    FileData.FileInfo.CodeLength := FileData.Header.Length;
    FileData.FileInfo.IsDeleted := False;

    FSCLFiles[i] := FileData;
    FFiles[i] := FileData.FileInfo;
  end;
end;

function TSCLReader.LoadFromFile(const AFileName: string): Boolean;
begin
  Clear;
  Result := False;

  try
    FImageData.LoadFromFile(AFileName);

    if FImageData.Size < SizeOf(TSCLDiskHeader) + SCL_CHECKSUM_SIZE then
    begin
      FErrorMessage := 'File too small for SCL format';
      Exit;
    end;

    ParseSCL;

    FFileName := AFileName;
    FIsLoaded := True;
    FModified := False;
    Result := True;

  except
    on E: Exception do
    begin
      FErrorMessage := 'Error loading SCL file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TSCLReader.SaveToFile(const AFileName: string): Boolean;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No SCL image loaded';
    Exit;
  end;

  try
    WriteSCLHeader;
    UpdateSCLCheckSum;

    FImageData.SaveToFile(AFileName);
    FFileName := AFileName;
    FModified := False;
    Result := True;

  except
    on E: Exception do
    begin
      FErrorMessage := 'Error saving SCL file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TSCLReader.SaveToCurrentFile: Boolean;
begin
  if FFileName = '' then
    Result := False
  else
    Result := SaveToFile(FFileName);
end;

function TSCLReader.CreateNewSCL: Boolean;
var
  Header: TSCLDiskHeader;
  CheckSum: DWord;
begin
  // НЕ вызываем Clear, чтобы сохранить FIsLoaded состояние
  // Clear;  // УБРАТЬ!

  Result := False;

  try
    FImageData.Clear;

    // Пишем сигнатуру
    Header.Signature := SCL_SIGNATURE;
    Header.FilesCount := 0;
    FImageData.Write(Header, SizeOf(TSCLDiskHeader));

    // Пишем контрольную сумму
    CheckSum := $255;
    FImageData.Write(CheckSum, SCL_CHECKSUM_SIZE);

    // Очищаем внутренние структуры
    FFileCount := 0;
    SetLength(FSCLFiles, 0);
    SetLength(FFiles, 0);

    // Убеждаемся, что диск загружен (пустой, но загружен)
    FIsLoaded := True;
    FModified := True;
    Result := True;

  except
    on E: Exception do
    begin
      FErrorMessage := 'Error creating SCL: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TSCLReader.AddFile(const FileName: string; FileType: Char;
                            LoadAddress: Word; FileLength: Word;
                            DataStream: TStream): Boolean;
var
  NewFileData: TSCLFileData;
  NewImageData: TMemoryStream;
  i, j: Integer;
  Buffer: array[0..SECTOR_SIZE-1] of Byte;
  CheckSum: DWord;
  BytesRead: Integer;
  NewFileCount: Byte;
  CurrentSectorOffset: Integer;
  FileDataPos: Integer;
  BytesToWrite: Integer;
  OldFileCount: Integer;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No SCL image loaded';
    Exit;
  end;

  if DataStream = nil then
  begin
    FErrorMessage := 'Data stream is nil';
    Exit;
  end;

  if (Length(FileName) = 0) or (Length(FileName) > 8) then
  begin
    FErrorMessage := 'File name must be 1-8 characters';
    Exit;
  end;

  if not (FileType in [FILE_TYPE_BASIC, FILE_TYPE_CODE, FILE_TYPE_DATA, FILE_TYPE_STREAM]) then
  begin
    FErrorMessage := 'Invalid file type';
    Exit;
  end;

  if FileLength = 0 then
    FileLength := DataStream.Size;

  if FileLength = 0 then
  begin
    FErrorMessage := 'File is empty';
    Exit;
  end;

  OldFileCount := FFileCount;
  NewFileCount := FFileCount + 1;

  // Заполняем заголовок нового файла
  FillChar(NewFileData.Header, SizeOf(TSCLFileHdr), 0);
  PascalToZXString(NormalizeFileName(FileName), NewFileData.Header.Name);
  NewFileData.Header.FileType := FileType;
  NewFileData.Header.StartAddress := LoadAddress;
  NewFileData.Header.Length := FileLength;
  NewFileData.Header.SectorsCount := (FileLength + SECTOR_SIZE - 1) div SECTOR_SIZE;
  if NewFileData.Header.SectorsCount = 0 then
    NewFileData.Header.SectorsCount := 1;

  // Заполняем FileInfo
  FillChar(NewFileData.FileInfo, SizeOf(TFileInfo), 0);
  NewFileData.FileInfo.Name := NormalizeFileName(FileName);
  NewFileData.FileInfo.FileType := FileType;
  NewFileData.FileInfo.FileTypeDesc := GetFileTypeDescription(FileType);
  NewFileData.FileInfo.SectorsCount := NewFileData.Header.SectorsCount;
  NewFileData.FileInfo.RawSize := NewFileData.Header.SectorsCount * SECTOR_SIZE;
  NewFileData.FileInfo.RealSize := FileLength;
  NewFileData.FileInfo.LoadAddress := LoadAddress;
  NewFileData.FileInfo.CodeLength := FileLength;
  NewFileData.FileInfo.IsDeleted := False;

  // Сохраняем старые файлы во временный массив
  SetLength(FSCLFiles, NewFileCount);
  SetLength(FFiles, NewFileCount);

  // Создаем новый образ
  NewImageData := TMemoryStream.Create;
  try
    // 1. Сигнатура
    NewImageData.Write(SCL_SIGNATURE, SizeOf(SCL_SIGNATURE));

    // 2. Количество файлов
    NewImageData.WriteByte(NewFileCount);

    // 3. Заголовки всех файлов (старые + новый)
    for i := 0 to OldFileCount - 1 do
    begin
      NewImageData.Write(FSCLFiles[i].Header, SizeOf(TSCLFileHdr));
    end;
    NewImageData.Write(NewFileData.Header, SizeOf(TSCLFileHdr));

    // 4. Данные всех файлов
    CurrentSectorOffset := 0;

    // Копируем данные старых файлов
    for i := 0 to OldFileCount - 1 do
    begin
      FImageData.Position := GetSectorOffsetInFile(i);

      for j := 1 to FSCLFiles[i].Header.SectorsCount do
      begin
        FillChar(Buffer, SECTOR_SIZE, 0);
        BytesRead := FImageData.Read(Buffer, SECTOR_SIZE);
        if BytesRead > 0 then
          NewImageData.Write(Buffer, SECTOR_SIZE);
      end;

      // Сохраняем обновленное смещение
      FSCLFiles[i].SectorOffset := CurrentSectorOffset;
      Inc(CurrentSectorOffset, FSCLFiles[i].Header.SectorsCount);
    end;

    // Записываем данные нового файла
    NewFileData.SectorOffset := CurrentSectorOffset;
    DataStream.Position := 0;
    FileDataPos := 0;

    for j := 1 to NewFileData.Header.SectorsCount do
    begin
      FillChar(Buffer, SECTOR_SIZE, 0);
      if FileDataPos < FileLength then
      begin
        BytesToWrite := Min(SECTOR_SIZE, FileLength - FileDataPos);
        BytesRead := DataStream.Read(Buffer, BytesToWrite);
        if BytesRead <> BytesToWrite then
        begin
          FErrorMessage := 'Failed to read data from stream';
          Exit;
        end;
        Inc(FileDataPos, BytesRead);
      end;
      NewImageData.Write(Buffer, SECTOR_SIZE);
    end;

    // 5. Вычисляем контрольную сумму
    NewImageData.Position := 0;
    CheckSum := $255;

    // Сигнатура
    FillChar(Buffer, SECTOR_SIZE, 0);
    NewImageData.Read(Buffer, 8);
    CheckSum := CheckSum + CalcCheckSum(Buffer, 8);

    // Количество файлов
    FillChar(Buffer, SECTOR_SIZE, 0);
    NewImageData.Read(Buffer, 1);
    CheckSum := CheckSum + Buffer[0];

    // Заголовки
    for i := 0 to NewFileCount - 1 do
    begin
      FillChar(Buffer, SECTOR_SIZE, 0);
      NewImageData.Read(Buffer, SizeOf(TSCLFileHdr));
      CheckSum := CheckSum + CalcCheckSum(Buffer, SizeOf(TSCLFileHdr));
    end;

    // Данные
    while NewImageData.Position < NewImageData.Size do
    begin
      FillChar(Buffer, SECTOR_SIZE, 0);
      BytesRead := NewImageData.Read(Buffer, SECTOR_SIZE);
      if BytesRead > 0 then
        CheckSum := CheckSum + CalcCheckSum(Buffer, BytesRead);
    end;

    // 6. Контрольная сумма
    NewImageData.Write(CheckSum, SCL_CHECKSUM_SIZE);

    // 7. Заменяем старый образ
    FImageData.Clear;
    NewImageData.Position := 0;
    FImageData.CopyFrom(NewImageData, NewImageData.Size);

    // 8. Обновляем внутренние структуры
    // Сначала сохраняем старые файлы с обновленными смещениями
    for i := 0 to OldFileCount - 1 do
    begin
      // FSCLFiles[i] уже содержит обновленный SectorOffset
    end;

    // Добавляем новый файл
    FSCLFiles[OldFileCount] := NewFileData;
    FFiles[OldFileCount] := NewFileData.FileInfo;

    FFileCount := NewFileCount;
    FModified := True;
    Result := True;

  finally
    NewImageData.Free;
  end;
end;

function TSCLReader.AddFileFromFile(const FileName: string; FileType: Char;
                                    LoadAddress: Word; FileLength: Word;
                                    const SourceFileName: string): Boolean;
var
  FileStream: TFileStream;
begin
  Result := False;

  if not FileExists(SourceFileName) then
  begin
    FErrorMessage := 'Source file not found: ' + SourceFileName;
    Exit;
  end;

  try
    FileStream := TFileStream.Create(SourceFileName, fmOpenRead or fmShareDenyWrite);
    try
      Result := AddFile(FileName, FileType, LoadAddress, FileLength, FileStream);
    finally
      FileStream.Free;
    end;
  except
    on E: Exception do
    begin
      FErrorMessage := 'Error reading source file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TSCLReader.DeleteFile(Index: Integer): Boolean;
var
  i, j: Integer;
  NewImageData: TMemoryStream;
  CheckSum: DWord;
  Buffer: array[0..SECTOR_SIZE-1] of Byte;
  BytesRead: Integer;
  NewFileCount: Byte;
  CurrentSectorOffset: Integer;
  OldFileCount: Integer;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No SCL image loaded';
    Exit;
  end;

  if (Index < 0) or (Index >= FFileCount) then
  begin
    FErrorMessage := 'Invalid file index';
    Exit;
  end;

  OldFileCount := FFileCount;

  // Если удаляем последний файл
  if OldFileCount = 1 then
  begin
    // Создаем пустой SCL
    Result := CreateNewSCL;
    // ВАЖНО: после CreateNewSCL FFileCount = 0
    Exit;
  end;

  NewFileCount := OldFileCount - 1;

  // Создаем новый образ
  NewImageData := TMemoryStream.Create;
  try
    // 1. Сигнатура
    NewImageData.Write(SCL_SIGNATURE, SizeOf(SCL_SIGNATURE));

    // 2. Количество файлов
    NewImageData.WriteByte(NewFileCount);

    // 3. Заголовки всех файлов КРОМЕ удаленного
    for i := 0 to OldFileCount - 1 do
    begin
      if i <> Index then
      begin
        NewImageData.Write(FSCLFiles[i].Header, SizeOf(TSCLFileHdr));
      end;
    end;

    // 4. Данные всех файлов КРОМЕ удаленного
    CurrentSectorOffset := 0;

    for i := 0 to OldFileCount - 1 do
    begin
      if i <> Index then
      begin
        // Читаем данные из СТАРОГО образа
        FImageData.Position := GetSectorOffsetInFile(i);

        for j := 1 to FSCLFiles[i].Header.SectorsCount do
        begin
          FillChar(Buffer, SECTOR_SIZE, 0);
          BytesRead := FImageData.Read(Buffer, SECTOR_SIZE);
          if BytesRead > 0 then
            NewImageData.Write(Buffer, SECTOR_SIZE);
        end;

        // Обновляем смещение
        FSCLFiles[i].SectorOffset := CurrentSectorOffset;
        Inc(CurrentSectorOffset, FSCLFiles[i].Header.SectorsCount);
      end;
    end;

    // 5. Вычисляем контрольную сумму
    NewImageData.Position := 0;
    CheckSum := $255;

    // Сигнатура
    FillChar(Buffer, SECTOR_SIZE, 0);
    NewImageData.Read(Buffer, 8);
    CheckSum := CheckSum + CalcCheckSum(Buffer, 8);

    // Количество файлов
    FillChar(Buffer, SECTOR_SIZE, 0);
    NewImageData.Read(Buffer, 1);
    CheckSum := CheckSum + Buffer[0];

    // Заголовки
    for i := 0 to NewFileCount - 1 do
    begin
      FillChar(Buffer, SECTOR_SIZE, 0);
      NewImageData.Read(Buffer, SizeOf(TSCLFileHdr));
      CheckSum := CheckSum + CalcCheckSum(Buffer, SizeOf(TSCLFileHdr));
    end;

    // Данные
    while NewImageData.Position < NewImageData.Size do
    begin
      FillChar(Buffer, SECTOR_SIZE, 0);
      BytesRead := NewImageData.Read(Buffer, SECTOR_SIZE);
      if BytesRead > 0 then
        CheckSum := CheckSum + CalcCheckSum(Buffer, BytesRead);
    end;

    // 6. Контрольная сумма
    NewImageData.Write(CheckSum, SCL_CHECKSUM_SIZE);

    // 7. Заменяем старый образ
    FImageData.Clear;
    NewImageData.Position := 0;
    FImageData.CopyFrom(NewImageData, NewImageData.Size);

    // 8. Обновляем внутренние структуры
    // Создаем новые массивы
    SetLength(FSCLFiles, NewFileCount);
    SetLength(FFiles, NewFileCount);

    // Копируем все файлы кроме удаленного
    j := 0;
    for i := 0 to OldFileCount - 1 do
    begin
      if i <> Index then
      begin
        FSCLFiles[j] := FSCLFiles[i];
        FFiles[j] := FFiles[i];
        Inc(j);
      end;
    end;

    FFileCount := NewFileCount;
    FModified := True;
    Result := True;

  finally
    NewImageData.Free;
  end;
end;

function TSCLReader.DeleteFileByName(const FileName: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to FFileCount - 1 do
  begin
    if UpperCase(FFiles[i].Name) = UpperCase(FileName) then
    begin
      Result := DeleteFile(i);
      Exit;
    end;
  end;
  FErrorMessage := 'File not found: ' + FileName;
end;

function TSCLReader.RenameFile(Index: Integer; const NewName: string): Boolean;
begin
  Result := False;

  if (Index < 0) or (Index >= FFileCount) then
  begin
    FErrorMessage := 'Invalid file index';
    Exit;
  end;

  PascalToZXString(NormalizeFileName(NewName), FSCLFiles[Index].Header.Name);
  FFiles[Index].Name := NormalizeFileName(NewName);
  FModified := True;
  Result := True;
end;

function TSCLReader.ExtractFile(Index: Integer; DestStream: TStream): Boolean;
var
  DataOffset: Int64;
  Buffer: array[0..SECTOR_SIZE-1] of Byte;
  BytesToRead: Integer;
  Remaining: Integer;
begin
  Result := False;

  if (Index < 0) or (Index >= FFileCount) then
  begin
    FErrorMessage := 'Invalid file index';
    Exit;
  end;

  DataOffset := GetSectorOffsetInFile(Index);

  if DataOffset + FSCLFiles[Index].Header.Length > FImageData.Size then
  begin
    FErrorMessage := 'File data out of range';
    Exit;
  end;

  FImageData.Position := DataOffset;
  Remaining := FSCLFiles[Index].Header.Length;

  while Remaining > 0 do
  begin
    BytesToRead := Min(SECTOR_SIZE, Remaining);
    FillChar(Buffer, SECTOR_SIZE, 0);
    FImageData.Read(Buffer, BytesToRead);
    DestStream.Write(Buffer, BytesToRead);
    Dec(Remaining, BytesToRead);
  end;

  Result := True;
end;

function TSCLReader.ExtractFileToFile(Index: Integer; const DestFileName: string): Boolean;
var
  FileStream: TFileStream;
begin
  Result := False;
  try
    FileStream := TFileStream.Create(DestFileName, fmCreate);
    try
      Result := ExtractFile(Index, FileStream);
    finally
      FileStream.Free;
    end;
  except
    on E: Exception do
    begin
      FErrorMessage := 'Failed to create output file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TSCLReader.ExtractFileToMemory(Index: Integer): TMemoryStream;
var
  Stream: TMemoryStream;
begin
  Result := nil;
  Stream := TMemoryStream.Create;
  try
    if ExtractFile(Index, Stream) then
      Result := Stream
    else
      Stream.Free;
  except
    Stream.Free;
    raise;
  end;
end;

function TSCLReader.GetFileInfo(Index: Integer): TFileInfo;
begin
  FillChar(Result, SizeOf(TFileInfo), 0);
  if (Index >= 0) and (Index < FFileCount) then
    Result := FFiles[Index];
end;

function TSCLReader.GetFileInfoByName(const FileName: string): TFileInfo;
var
  i: Integer;
begin
  FillChar(Result, SizeOf(TFileInfo), 0);
  for i := 0 to FFileCount - 1 do
  begin
    if UpperCase(FFiles[i].Name) = UpperCase(FileName) then
    begin
      Result := FFiles[i];
      Exit;
    end;
  end;
end;

function TSCLReader.GetFilesCount: Integer;
begin
  Result := FFileCount;
end;

function TSCLReader.GetTotalSize: Int64;
begin
  Result := FImageData.Size;
end;

function TSCLReader.TryRecoverSCL: Boolean;
begin
  Result := False;
  FErrorMessage := 'Recovery not implemented';
end;

{ TZXImageReader }

constructor TZXImageReader.Create;
begin
  inherited Create;
  FTRDReader := TTRDOSReader.Create;
  FSCLReader := TSCLReader.Create;
  FCurrentFormat := ifUnknown;
  FIsLoaded := False;
end;

destructor TZXImageReader.Destroy;
begin
  FTRDReader.Free;
  FSCLReader.Free;
  inherited Destroy;
end;

function TZXImageReader.DetectFormat(const AFileName: string): TImageFormat;
var
  FileStream: TFileStream;
  Signature: array[0..7] of char;
  BytesRead: Integer;
begin
  Result := ifUnknown;

  try
    FileStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      BytesRead := FileStream.Read(Signature, SizeOf(Signature));

      if BytesRead = SizeOf(Signature) then
      begin
        if CompareMem(@Signature, @SCL_SIGNATURE, SizeOf(SCL_SIGNATURE)) then
        begin
          Result := ifSCL;
          Exit;
        end;
      end;

      FileStream.Position := 0;
      if FileStream.Size mod SECTOR_SIZE = 0 then
        Result := ifTRD;

    finally
      FileStream.Free;
    end;
  except
    Result := ifUnknown;
  end;
end;

function TZXImageReader.LoadFromFile(const AFileName: string): Boolean;
begin
  Clear;
  Result := False;

  FCurrentFormat := DetectFormat(AFileName);

  case FCurrentFormat of
    ifTRD:
      begin
        Result := FTRDReader.LoadFromFile(AFileName);
        if not Result then
          FErrorMessage := FTRDReader.ErrorMessage;
      end;
    ifSCL:
      begin
        Result := FSCLReader.LoadFromFile(AFileName);
        if not Result then
          FErrorMessage := FSCLReader.ErrorMessage;
      end;
    else
      FErrorMessage := 'Unknown or unsupported format';
  end;

  FIsLoaded := Result;
  if Result then
    FFileName := AFileName;
end;

function TZXImageReader.SaveToFile(const AFileName: string): Boolean;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.SaveToFile(AFileName);
    ifSCL: Result := FSCLReader.SaveToFile(AFileName);
    else Result := False;
  end;
end;

function TZXImageReader.SaveToCurrentFile: Boolean;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.SaveToCurrentFile;
    ifSCL: Result := FSCLReader.SaveToCurrentFile;
    else Result := False;
  end;
end;

procedure TZXImageReader.Clear;
begin
  FTRDReader.Clear;
  FSCLReader.Clear;
  FCurrentFormat := ifUnknown;
  FIsLoaded := False;
  FFileName := '';
  FErrorMessage := '';
end;

function TZXImageReader.CreateNewDiskEx(DiskType: TTRDSDiskType; const LabelName: string;
                                        const Password: string = ''): Boolean;
begin
  Result := FTRDReader.CreateNewDiskEx(DiskType, LabelName, Password);
  if Result then
    FCurrentFormat := ifTRD;
end;

function TZXImageReader.FormatTrd(DiskType: TTRDSDiskType; const LabelName: string;
                                  const Password: string = ''): Boolean;
begin
  Result := FTRDReader.FormatTrd(DiskType, LabelName, Password);
  if Result then
    FCurrentFormat := ifTRD;
end;

function TZXImageReader.GetFileInfo(Index: Integer): TFileInfo;
begin
  FillChar(Result, SizeOf(TFileInfo), 0);

  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetFileInfo(Index);
    ifSCL: Result := FSCLReader.GetFileInfo(Index);
  end;
end;

function TZXImageReader.GetFileCount: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetFilesCount;
    ifSCL: Result := FSCLReader.GetFilesCount;
    else Result := 0;
  end;
end;

function TZXImageReader.ExtractFile(Index: Integer; DestStream: TStream): Boolean;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.ExtractFile(Index, DestStream);
    ifSCL: Result := FSCLReader.ExtractFile(Index, DestStream);
    else Result := False;
  end;
end;

function TZXImageReader.ExtractFileToFile(Index: Integer; const DestFileName: string): Boolean;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.ExtractFileToFile(Index, DestFileName);
    ifSCL: Result := FSCLReader.ExtractFileToFile(Index, DestFileName);
    else Result := False;
  end;
end;

function TZXImageReader.ExtractFileToMemory(Index: Integer): TMemoryStream;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.ExtractFileToMemory(Index);
    ifSCL: Result := FSCLReader.ExtractFileToMemory(Index);
    else Result := nil;
  end;
end;

function TZXImageReader.AddFile(const FileName: string; FileType: Char;
                                LoadAddress: Word; FileLength: Word;
                                DataStream: TStream; BasicStartLine: Word = 0): Boolean;
begin
  case FCurrentFormat of
    ifTRD:
      Result := FTRDReader.AddFile(FileName, FileType, LoadAddress, FileLength, DataStream, BasicStartLine);
    ifSCL:
      Result := FSCLReader.AddFile(FileName, FileType, LoadAddress, FileLength, DataStream);
    else
      Result := False;
  end;
end;

function TZXImageReader.AddFileFromFile(const FileName: string; FileType: Char;
                                        LoadAddress: Word; FileLength: Word;
                                        const SourceFileName: string;
                                        BasicStartLine: Word = 0): Boolean;
var
  FileStream: TFileStream;
begin
  Result := False;

  if not FIsLoaded then
  begin
    FErrorMessage := 'No image loaded';
    Exit;
  end;

  if not FileExists(SourceFileName) then
  begin
    FErrorMessage := 'Source file not found: ' + SourceFileName;
    Exit;
  end;

  try
    FileStream := TFileStream.Create(SourceFileName, fmOpenRead or fmShareDenyWrite);
    try
      case FCurrentFormat of
        ifTRD:
          Result := FTRDReader.AddFile(FileName, FileType, LoadAddress, FileLength,
                                        FileStream, BasicStartLine);
        ifSCL:
          Result := FSCLReader.AddFile(FileName, FileType, LoadAddress, FileLength,
                                        FileStream);
        else
          FErrorMessage := 'Unknown format';
      end;
    finally
      FileStream.Free;
    end;
  except
    on E: Exception do
    begin
      FErrorMessage := 'Error adding file: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TZXImageReader.DeleteFile(Index: Integer): Boolean;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.DeleteFile(Index);
    ifSCL: Result := FSCLReader.DeleteFile(Index);
    else Result := False;
  end;
end;

function TZXImageReader.DeleteFileByName(const FileName: string): Boolean;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.DeleteFileByName(FileName);
    ifSCL: Result := FSCLReader.DeleteFileByName(FileName);
    else Result := False;
  end;
end;

function TZXImageReader.RenameFile(Index: Integer; const NewName: string): Boolean;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.RenameFile(Index, NewName);
    ifSCL: Result := FSCLReader.RenameFile(Index, NewName);
    else Result := False;
  end;
end;

function TZXImageReader.GetDiskLabel: string;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetDiskLabel;
    else Result := '';
  end;
end;

function TZXImageReader.GetDiskTypeString: string;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetDiskTypeString;
    ifSCL: Result := 'SCL archive (no disk geometry)';
    else Result := 'Unknown';
  end;
end;

function TZXImageReader.GetFreeSpace: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetFreeSpace;
    else Result := 0;
  end;
end;

function TZXImageReader.GetUsedSpace: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetUsedSpace;
    ifSCL: Result := GetTotalSpace;
    else Result := 0;
  end;
end;

function TZXImageReader.GetTotalSpace: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetTotalSpace;
    ifSCL: Result := FSCLReader.GetTotalSize;
    else Result := 0;
  end;
end;

function TZXImageReader.GetFreeSectorsCount: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetFreeSectorsCount;
    ifSCL: Result := 0;
    else Result := 0;
  end;
end;

function TZXImageReader.GetUsagePercent: Single;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetUsagePercent;
    ifSCL:
      begin
        if GetTotalSpace > 0 then
          Result := (GetUsedSpace / GetTotalSpace) * 100
        else
          Result := 0;
      end;
    else Result := 0;
  end;
end;

function TZXImageReader.GetFilesCount: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetFilesCount;
    ifSCL: Result := FSCLReader.GetFilesCount;
    else Result := 0;
  end;
end;

function TZXImageReader.GetDeletedFilesCount: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetDeletedFilesCount;
    ifSCL: Result := 0;
    else Result := 0;
  end;
end;

function TZXImageReader.IsDoubleSided: Boolean;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.IsDoubleSided;
    ifSCL: Result := False;
    else Result := False;
  end;
end;

function TZXImageReader.GetLogicalTracksCount: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetLogicalTracksCount;
    ifSCL: Result := 0;
    else Result := 0;
  end;
end;

function TZXImageReader.GetPhysicalCylindersCount: Integer;
begin
  case FCurrentFormat of
    ifTRD: Result := FTRDReader.GetPhysicalCylindersCount;
    ifSCL: Result := 0;
    else Result := 0;
  end;
end;

end.
