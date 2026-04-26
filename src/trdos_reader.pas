unit trdos_reader;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math;

const
  SECTOR_SIZE = 256;
  SECTORS_PER_TRACK = 16;
  MAX_FILES_IN_CATALOG = 128;  // Фактически 142, но оставим 128 для совместимости
  MAX_FILES_REAL = 142;         // Реальное количество записей каталога

  // File status
  FILE_ACTIVE = $00;
  FILE_DELETED = $01;
  FILE_TERMINATOR = $00;

  // File types
  FILE_TYPE_BASIC = 'B';
  FILE_TYPE_CODE = 'C';
  FILE_TYPE_DATA = 'D';
  FILE_TYPE_STREAM = '#';

  // Disk types (стандартные коды TR-DOS)
  DISK_TYPE_80DS = $16;  // 80 дорожек, двусторонний
  DISK_TYPE_40DS = $17;  // 40 дорожек, двусторонний
  DISK_TYPE_80SS = $18;  // 80 дорожек, односторонний
  DISK_TYPE_40SS = $19;  // 40 дорожек, односторонний

  // Константы из C++ кода
  NO_TRKS = 80;           // число треков (цилиндров) на одной стороне
  NO_SECS = 16;           // число секторов на треке
  SEC_SIZE = 256;         // размер сектора

  // TR-DOS сигнатуры
  DS_SIGNATURE: array[0..8] of char = ('D', 'i', 'r', 'S', 'y', 's', '1', '0', '0');

type
  // Disk type enumeration
  TTRDSDiskType = (
    dtUnknown,
    dt40SS,   // 40 tracks, single side
    dt40DS,   // 40 tracks, double side
    dt80SS,   // 80 tracks, single side
    dt80DS    // 80 tracks, double side
  );

  // File header in catalog (как в C++: FileHdr)
  TFileHdr = packed record
    Name: array[0..7] of char;
    FileType: Char;
    StartAddress: Word;      // load address (for CODE) or total length (for BASIC)
    Length: Word;            // file length (code length for BASIC)
    SectorsCount: Byte;      // number of sectors
    StartSector: Byte;       // starting sector
    StartTrack: Byte;        // starting track
  end;

  // Track0 structure - вся дорожка 0 (16 секторов)
  TTrack0 = packed record
    Files: array[0..MAX_FILES_REAL - 1] of TFileHdr;
    Reserved1: Byte;                          // 142 * 16 + 1 = 2273 ?
    FirstFreeSector: Byte;                    // first free sector
    FirstFreeTrack: Byte;                     // first free track
    DiskType: Byte;                           // disk type ($16, $17, $18, $19)
    FilesCount: Byte;                         // number of active files
    FreeSectorsCount: Word;                   // number of free sectors
    Flag: Byte;                               // TR-DOS flag ($10)
    Reserved2: array[0..11] of Byte;          // reserved
    DeletedFilesCount: Byte;                  // number of deleted files
    VolumeLabel: array[0..10] of char;        // disk label (11 bytes)
    DScrc: Word;                              // Double side CRC
    DSSignature: array[0..8] of char;         // 'DirSys100' for double side
    DSFileMap: array[0..$7F] of Byte;         // file map for double side
    DSFolderMap: array[0..$7F] of Byte;       // folder map for double side
    DSFolders: array[0..$7E] of array[0..10] of char; // folder names
    DSEnd: Byte;                              // end marker
    Empty: array[0..$7E] of Byte;             // padding (0x7F bytes)
  end;

  // Extended file info для разных типов
  TBasicFileInfo = packed record
    ProgramAndDataLength: Word;  // Total length (program + variables)
    ProgramLength: Word;         // Length of program code only
  end;

  TCodeFileInfo = packed record
    StartAddress: Word;          // Load address
    Length: Word;                // Code length
  end;

  TDataFileInfo = packed record
    Reserved: Word;              // Not used in TR-DOS
    Length: Word;                // Data length
  end;

  TStreamFileInfo = packed record
    ExtentNo: Byte;              // Extent number (0-3)
    Reserved: Byte;              // Always 0
    Length: Word;                // Stream length
  end;

  // Extended file info для удобства
  TFullFileHdr = packed record
    Name: array[0..7] of char;
    FileType: Char;
    TypeData: array[0..3] of Byte;  // 4 байта для type-specific info
    SectorsCount: Byte;
    StartSector: Byte;
    StartTrack: Byte;
  end;

  // File information for user
  TFileInfo = record
    Name: string;
    FileType: Char;
    FileTypeDesc: string;
    StartTrack: Byte;
    StartSector: Byte;
    SectorsCount: Byte;
    RawSize: Integer;            // Size in sectors * 256
    RealSize: Integer;           // Actual data size
    LoadAddress: Word;           // Load address (CODE files)
    CodeLength: Word;            // Code length (CODE files)
    BasicProgramLength: Word;    // Program length (BASIC files)
    BasicDataLength: Word;       // Variables length (BASIC files)
    BasicStartLine: Word;        // First line number (BASIC)
    ExtentNo: Byte;              // Extent number (STREAM files)
    IsDeleted: Boolean;
  end;

  // Free sector info
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
    FAutoMove: Boolean;  // Автоматическое перемещение файлов при удалении

    // Track0 cache - вся дорожка 0
    FTrack0: TTrack0;

    // Disk geometry
    FLogicalTracks: Integer;     // Количество логических треков в образе
    FPhysicalCylinders: Integer; // Количество физических цилиндров
    FIsDoubleSided: Boolean;     // Двусторонний ли диск
    FTotalSectors: Integer;
    FFreeSectorsList: TFreeSectorInfoList;

    // Для DS дисков
    FFileMap: array[0..MAX_FILES_REAL - 1] of Byte;
    FFileMapValid: Boolean;

    // Helper methods
    function GetSectorOffset(Track, Sector: Byte): Int64;
    function ReadSector(Track, Sector: Byte; var Data: array of Byte): Boolean;
    function WriteSector(Track, Sector: Byte; const Data: array of Byte): Boolean;
    procedure LoadTrack0;
    procedure SaveTrack0;

    // String conversion
    function ZXStringToPascal(const ZXStr: array of char): string;
    procedure PascalToZXString(const PascalStr: string; var ZXStr: array of char);
    function NormalizeFileName(const Name: string): string;

    // File type handling
    function GetFileTypeDescription(FileType: Char): string;

    // Catalog operations
    procedure ParseCatalog;
    procedure CompactCatalog;     // Сжатие каталога (удаление помеченных записей)
    procedure CompactDisk;        // Физическое перемещение файлов для заполнения "дырок"
    function FindFreeCatalogSlot: Integer;

    // Space management
    procedure BuildFreeSectorsList;
    function AllocateSectors(Count: Integer): TFreeSectorInfoList;
    procedure FreeSectors(const Sectors: TFreeSectorInfoList);
    function CalculateSectorsNeeded(Size: Integer): Integer;

    // Disk geometry
    procedure UpdateDiskGeometry;
    function GetTotalSectorsCount: Integer;

    // Basic file parsing
    function ExtractBasicStartLine(const Data: TStream): Word;
    function ParseBasicFile(var Info: TFileInfo; const Data: TStream): Boolean;

    // Low-level operations
    function LoadFromFileInternal(const AFileName: string): Boolean;
    function SaveToFileInternal(const AFileName: string): Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    // Basic operations
    function LoadFromFile(const AFileName: string): Boolean;
    function SaveToFile(const AFileName: string): Boolean;
    function SaveToCurrentFile: Boolean;
    procedure Clear;
    function CreateNewDisk(const Params: TNewDiskParams): Boolean;
    function CreateNewDiskEx(DiskType: TTRDSDiskType; const LabelName: string;
                             const Password: string = ''): Boolean;
    function FormatTrd(DiskType: TTRDSDiskType; const LabelName: string;
                    const Password: string = ''): Boolean;

    // File operations
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

    // Disk information
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

    // Geometry information
    function GetLogicalTracksCount: Integer;
    function GetPhysicalCylindersCount: Integer;
    function IsDoubleSided: Boolean;

    // Options
    property AutoMove: Boolean read FAutoMove write FAutoMove;

    // Properties
    property IsLoaded: Boolean read FIsLoaded;
    property IsModified: Boolean read FModified;
    property ErrorMessage: string read FErrorMessage;
    property FileCount: Integer read FFileCount;
    property Files[Index: Integer]: TFileInfo read GetFileInfo;
    property FileName: string read FFileName;
  end;

implementation

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
  FAutoMove := True;  // По умолчанию включено, как в C++ коде
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
        FLogicalTracks := 160;      // 80 цилиндров * 2 стороны
        FIsDoubleSided := True;
        FPhysicalCylinders := 80;
      end;
    DISK_TYPE_40DS:
      begin
        FLogicalTracks := 80;       // 40 цилиндров * 2 стороны
        FIsDoubleSided := True;
        FPhysicalCylinders := 40;
      end;
    DISK_TYPE_80SS:
      begin
        FLogicalTracks := 80;       // 80 цилиндров * 1 сторона
        FIsDoubleSided := False;
        FPhysicalCylinders := 80;
      end;
    DISK_TYPE_40SS:
      begin
        FLogicalTracks := 40;       // 40 цилиндров * 1 сторона
        FIsDoubleSided := False;
        FPhysicalCylinders := 40;
      end;
  else
    begin
      // Определяем по размеру файла
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

{ String conversion }

function TTRDOSReader.ZXStringToPascal(const ZXStr: array of char): string;
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

procedure TTRDOSReader.PascalToZXString(const PascalStr: string; var ZXStr: array of char);
var
  i: Integer;
  s: string;
begin
  for i := 0 to High(ZXStr) do
    ZXStr[i] := ' ';

  s := {UpperCase}(PascalStr);
  for i := 1 to Length(s) do
    if i - 1 <= High(ZXStr) then
      ZXStr[i-1] := s[i];
end;

function TTRDOSReader.NormalizeFileName(const Name: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(Name) do
    if Name[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_'] then
      Result := Result + {UpCase}(Name[i]);

  if Length(Result) > 8 then
    Result := Copy(Result, 1, 8);

  if Result = '' then
    Result := 'UNNAMED';

  Result := Result;
end;

function TTRDOSReader.GetFileTypeDescription(FileType: Char): string;
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

{ Basic file parsing }

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

{ Catalog operations }

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

    // Конец каталога (терминатор)
    if Hdr.Name[0] = #0 then
      Break;

    // Пропускаем удаленные файлы - они не отображаются в списке
    if Hdr.Name[0] = Char(FILE_DELETED) then
      Continue;

    // Заполняем информацию о файле
    FillChar(FileInfo, SizeOf(TFileInfo), 0);

    // Имя файла (8 символов)
    FileInfo.Name := ZXStringToPascal(Hdr.Name);

    // Тип файла
    FileInfo.FileType := Hdr.FileType;
    FileInfo.FileTypeDesc := GetFileTypeDescription(Hdr.FileType);

    // Позиция на диске
    FileInfo.StartTrack := Hdr.StartTrack;
    FileInfo.StartSector := Hdr.StartSector;
    FileInfo.SectorsCount := Hdr.SectorsCount;
    FileInfo.RawSize := Hdr.SectorsCount * SEC_SIZE;
    FileInfo.IsDeleted := False;

    if not (Hdr.FileType in [FILE_TYPE_BASIC, FILE_TYPE_DATA, FILE_TYPE_STREAM]) then
      Hdr.FileType := FILE_TYPE_CODE;  // все что не известно то code

    // Заполняем в зависимости от типа файла
    case Hdr.FileType of
      FILE_TYPE_CODE:
        begin
          FileInfo.LoadAddress := Hdr.StartAddress;
          FileInfo.CodeLength := Hdr.Length;
          FileInfo.RealSize := Hdr.Length;
        end;

      FILE_TYPE_BASIC:
        begin
          // Для BASIC: StartAddress = общий размер (программа + переменные)
          // Length = длина кода программы
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

    // Добавляем файл в список
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

  // Собираем все НЕудаленные файлы в начало
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

  // Очищаем остаток каталога
  for i := NewIndex to MAX_FILES_REAL - 1 do
    FillChar(FTrack0.Files[i], SizeOf(TFileHdr), 0);

  // Обновляем счетчики только если они не были обновлены ранее
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

  // Как в C++: for(int i = 0; i < noFiles; ++i)
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
      // Удаленный файл не копируем - он исчезает
    end
    else
    begin
      if DelFound then
      begin
        // Перемещаем живой файл на место удаленного
        FromTrack := FTrack0.Files[i].StartTrack;
        FromSector := FTrack0.Files[i].StartSector;

        // Обновляем заголовок
        FTrack0.Files[i].StartTrack := ToTrack;
        FTrack0.Files[i].StartSector := ToSector;

        // Копируем сектора
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

      // Сдвигаем файл в начало массива
      if NewFileIndex <> i then
        FTrack0.Files[NewFileIndex] := FTrack0.Files[i];
      Inc(NewFileIndex);
    end;
  end;

  // Очищаем остаток каталога
  for i := NewFileIndex to MAX_FILES_REAL - 1 do
    FillChar(FTrack0.Files[i], SizeOf(TFileHdr), 0);

  // Обновляем первый свободный сектор (как в C++)
  if DelFound then
  begin
    FTrack0.FirstFreeTrack := ToTrack;
    FTrack0.FirstFreeSector := ToSector;
  end;

  // Обновляем счетчики (как в C++)
  FTrack0.FilesCount := NewFileIndex;
  FTrack0.DeletedFilesCount := 0;
  // FTrack0.FreeSectorsCount := FTrack0.FreeSectorsCount + TotalDelSectors;
  BuildFreeSectorsList; // ✅ ЗАМЕНИТЬ: точный пересчёт на основе актуального состояния диска
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

{ Space management }

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

  // 1. Инициализация: все сектора свободны
  for Track := 0 to FLogicalTracks - 1 do
    for Sector := 0 to SECTORS_PER_TRACK - 1 do
      UsedSectors[Track, Sector] := False;

  // 2. Каталог (дорожка 0) всегда занята
  for Sector := 0 to SECTORS_PER_TRACK - 1 do
    UsedSectors[0, Sector] := True;

  // 3. Отмечаем сектора файлов (включая удалённые)
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

    // ✅ ДОБАВЛЕНО: Учитываем DSFileMap для второй стороны
    if FFileMapValid then
    begin
      for Track := 80 to FLogicalTracks - 1 do // Только сторона 1
      begin
        for Sector := 0 to SECTORS_PER_TRACK - 1 do
        begin
          BitIndex := ((Track - 80) * SECTORS_PER_TRACK) + Sector;
          if BitIndex < 1024 then // 128 байт * 8 бит
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

  // 4. Формируем список свободных секторов
  SetLength(FFreeSectorsList, 0);
  for Track := 0 to FLogicalTracks - 1 do
    for Sector := 0 to SECTORS_PER_TRACK - 1 do
      if not UsedSectors[Track, Sector] then
      begin
        SetLength(FFreeSectorsList, Length(FFreeSectorsList) + 1);
        FFreeSectorsList[High(FFreeSectorsList)].Track := Track;
        FFreeSectorsList[High(FFreeSectorsList)].Sector := Sector;
      end;

  // 5. Обновляем заголовок диска
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

  // Сортировка по Track, Sector
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

{ File I/O }

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

    // Загружаем Track0
    LoadTrack0;
    UpdateDiskGeometry;

    // Загружаем DS информацию если есть
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
    // Сохраняем DS информацию если есть
    if FFileMapValid then
    begin
      Move(FFileMap, FTrack0.DSFileMap, SizeOf(FFileMap));
    end;

    SaveTrack0;
    writeln(AFileName);
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

{ Public methods }

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
    // Устанавливаем тип диска
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

    // Создаем пустой образ диска
    FillChar(Buffer, SEC_SIZE, 0);
    FImageData.Size := 0;

    for Track := 0 to FLogicalTracks - 1 do
      for Sector := 0 to SECTORS_PER_TRACK - 1 do
        FImageData.Write(Buffer, SEC_SIZE);

    // Инициализируем Track0
    FillChar(FTrack0, SizeOf(TTrack0), 0);

    // Заполняем каталог пустыми записями
    for i := 0 to MAX_FILES_REAL - 1 do
    begin
      FillChar(FTrack0.Files[i], SizeOf(TFileHdr), 0);
    end;

    // Настраиваем заголовок диска
    FTrack0.Flag := $10;
    FTrack0.FirstFreeTrack := 1;
    FTrack0.FirstFreeSector := 0;
    FTrack0.FilesCount := 0;
    FTrack0.DeletedFilesCount := 0;
    FTrack0.FreeSectorsCount := FTotalSectors - SECTORS_PER_TRACK;

    // Заполняем метку
    if Params.LabelName <> '' then
      PascalToZXString(ShortString(Copy(Params.LabelName, 1, 11)), FTrack0.VolumeLabel)
    else
      PascalToZXString('DISK       ', FTrack0.VolumeLabel);

    // Для двусторонних дисков устанавливаем сигнатуру
    if FIsDoubleSided then
    begin
      FTrack0.DScrc := $D019;
      for i := 0 to 8 do
        FTrack0.DSSignature[i] := DS_SIGNATURE[i];
      Move(FFileMap, FTrack0.DSFileMap, SizeOf(FFileMap));
    end;

    // Сохраняем Track0
    SaveTrack0;

    // Строим список свободных секторов
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

  // Заполняем заголовок файла
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
        Hdr.StartAddress := FileLength;  // ProgramAndDataLength
        Hdr.Length := FileLength;        // ProgramLength
      end;

    FILE_TYPE_DATA:
      begin
        Hdr.StartAddress := LoadAddress;
        Hdr.Length := FileLength;
      end;

    FILE_TYPE_STREAM:
      begin
        Hdr.StartAddress := 0;  // ExtentNo
        Hdr.Length := FileLength;
      end;
  end;

  FTrack0.Files[SlotIndex] := Hdr;
  Inc(FTrack0.FilesCount);

  // Записываем данные
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

  // Обновляем информацию о файле
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
  BuildFreeSectorsList; //синхронизируем кэш после записи

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

  // Находим реальную позицию в каталоге (как в C++ коде)
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

  // Помечаем файл как удаленный (как в C++: files[j].name[0] = 0x01)
  FTrack0.Files[ActualIndex].Name[0] := Char(FILE_DELETED);
  Inc(FTrack0.DeletedFilesCount);

  // В C++ коде FilesCount НЕ уменьшается при пометке!
  // FTrack0.FilesCount остается прежним

  if FAutoMove then
  begin
    // Выполняем сжатие диска (как move() в C++)
    CompactDisk;
  end;

  // Сохраняем изменения на диск (как writeInfo() в C++)
  SaveTrack0;

  // Перестраиваем список файлов в памяти
  SetLength(FFiles, 0);
  FFileCount := 0;
  ParseCatalog;
  BuildFreeSectorsList; // ✅ ДОБАВИТЬ: пересчитываем список свободных секторов
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

  // Находим реальную позицию в каталоге
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
  //Result := Length(FFreeSectorsList);
   // Эмуляторы читают именно это поле
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

end.
