unit rayfiledialog;

{$mode objfpc}{$H+}
{$WARN 5044 off : Symbol "$1" is not portable}
interface

uses
  Classes, SysUtils, raylib, raygui;

type

  // Базовый класс для всех диалогов
  TCustomFileDialog = class
  private
    // Window management
    FActive: Boolean;
    FWindowBounds: TRectangle;
    FPanOffset: TVector2;
    FDragMode: Boolean;

    // UI variables
    FDirPathEditMode: Boolean;
    FDirPathText: string;
    FFilesListScrollIndex: Integer;
    FFilesListActive: Integer;
    FPrevFilesListActive: Integer;
    FFileNameEditMode: Boolean;
    FFileNameText: array[0..1023] of Char;
    FItemFocused: Integer;

    // Data
    FDirFiles: TFilePathList;
    FDirectories: TStringList;
    FFiles: TStringList;
    FDirFilesIcon: array of PChar;

    // Properties
    FFilter: string;
    FInitialDir: string;
    FFileName: string;

    procedure ReloadDirectoryContents;
    procedure FreeIcons;
    function GetPrevDirectoryPath(const DirPath: string): string;
    procedure LoadDirectoryContents;
    procedure UpdateWindowTitle;

  protected
    function GetDialogTitle: string; virtual; abstract;
    function GetActionButtonText: string; virtual; abstract;
    function ValidateBeforeClose: Boolean; virtual;
    procedure OnFileSelected(const FilePath: string); virtual;
    procedure CancelDialog; virtual;

  public
    constructor Create;
    destructor Destroy; override;

    function Execute: Boolean;
    procedure Update; virtual;
    procedure Close;
    procedure Cancel;
    function IsActive: Boolean;

    property FileName: string read FFileName write FFileName;
    property InitialDir: string read FInitialDir write FInitialDir;
    property Filter: string read FFilter write FFilter;
  end;

  // Диалог открытия файла
  TOpenDialog = class(TCustomFileDialog)
  protected
    function GetDialogTitle: string; override;
    function GetActionButtonText: string; override;
    function ValidateBeforeClose: Boolean; override;
    procedure OnFileSelected(const FilePath: string); override;
    procedure CancelDialog; override;
  end;

  // Диалог сохранения файла
  TSaveDialog = class(TCustomFileDialog)
  private
    FOverwriteWarningShown: Boolean;
    FShowWarningModal: Boolean;
    FSaveAfterWarning: Boolean;
    procedure DrawOverwriteWarning;
    function CheckFileExists(const FileName_: string): Boolean;

  protected
    function GetDialogTitle: string; override;
    function GetActionButtonText: string; override;
    function ValidateBeforeClose: Boolean; override;
    procedure OnFileSelected(const FilePath: string); override;
    procedure CancelDialog; override;

  public
    constructor Create;
    destructor Destroy; override;
    procedure Update; override;
    function IsActive: Boolean;
  end;

implementation

const
  PATH_SEPARATOR = {$IFDEF WINDOWS} '\' {$ELSE} '/' {$ENDIF};
  MAX_ICON_PATH_LENGTH = 512;

// Вспомогательные функции для работы с путями
function IncludeTrailingPathDelimiter(const Path: string): string;
begin
  Result := Path;
  if (Result <> '') and (Result[Length(Result)] <> PATH_SEPARATOR) then
    Result := Result + PATH_SEPARATOR;
end;

function ExcludeTrailingPathDelimiter(const Path: string): string;
begin
  Result := Path;
  while (Result <> '') and (Result[Length(Result)] = PATH_SEPARATOR) do
    SetLength(Result, Length(Result) - 1);
end;

{ TCustomFileDialog }

constructor TCustomFileDialog.Create;
begin
  inherited Create;

  FWindowBounds := RectangleCreate(
    GetScreenWidth div 2 - 440 div 2,
    GetScreenHeight div 2 - 310 div 2,
    440, 310
  );

  FActive := False;
  FDragMode := False;
  FPanOffset := Vector2Create(0, 0);
  FDirPathEditMode := False;
  FFileNameEditMode := False;
  FFilesListActive := -1;
  FPrevFilesListActive := -1;
  FFilesListScrollIndex := 0;
  FItemFocused := 0;
  FillChar(FFileNameText, SizeOf(FFileNameText), 0);

  FDirPathText := GetWorkingDirectory();
  FFileName := '';
  FFilter := '';
  FInitialDir := '';

  FDirectories := TStringList.Create;
  FFiles := TStringList.Create;

  FDirFiles.count := 0;
  FDirFiles.paths := nil;
  SetLength(FDirFilesIcon, 0);
end;

destructor TCustomFileDialog.Destroy;
var i: integer;
begin
  FreeIcons;
  FDirectories.Free;
  FFiles.Free;

  if FDirFiles.paths <> nil then
  begin
    for i := 0 to FDirFiles.count - 1 do
      if FDirFiles.paths[i] <> nil then
        StrDispose(FDirFiles.paths[i]);
    FreeMem(FDirFiles.paths);
  end;

  inherited Destroy;
end;

function TCustomFileDialog.Execute: Boolean;
begin
  if FInitialDir <> '' then
    FDirPathText := ExpandFileName(FInitialDir)
  else
    FDirPathText := GetWorkingDirectory();

  FDirPathText := ExcludeTrailingPathDelimiter(FDirPathText);

  FActive := True;
  FFilesListActive := -1;
  FPrevFilesListActive := -1;
  FFileNameEditMode := False;
  FDirPathEditMode := False;
  FItemFocused := 0;

  FWindowBounds.x := GetScreenWidth div 2 - 440 div 2;
  FWindowBounds.y := GetScreenHeight div 2 - 310 div 2;

  ReloadDirectoryContents;
  Result := True;
end;

procedure TCustomFileDialog.Cancel;
begin
  CancelDialog;
  Close;
end;

procedure TCustomFileDialog.CancelDialog;
begin
  FFileName := '';
  FillChar(FFileNameText, SizeOf(FFileNameText), 0);
end;

procedure TCustomFileDialog.Update;
var
  mousePosition: TVector2;
  guiResult: Integer;
  pathBuffer: array[0..1023] of Char;
  selectedPath, tempStr, savedFileName: string;
  dirFilesIconArray: PPChar;
  i: Integer;
  prevAlignment, prevHeight: Integer;
  btnResult: Integer;
begin
  if not FActive then
    Exit;

  // Window dragging
  mousePosition := GetMousePosition;

  if IsMouseButtonPressed(MOUSE_LEFT_BUTTON) then
  begin
    if CheckCollisionPointRec(mousePosition,
       RectangleCreate(FWindowBounds.x, FWindowBounds.y,
                      FWindowBounds.width, RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT)) then
    begin
      FDragMode := True;
      FPanOffset.x := mousePosition.x - FWindowBounds.x;
      FPanOffset.y := mousePosition.y - FWindowBounds.y;
    end;
  end;

  if FDragMode then
  begin
    FWindowBounds.x := mousePosition.x - FPanOffset.x;
    FWindowBounds.y := mousePosition.y - FPanOffset.y;

    if FWindowBounds.x < 0 then
      FWindowBounds.x := 0
    else if FWindowBounds.x > (GetScreenWidth - FWindowBounds.width) then
      FWindowBounds.x := GetScreenWidth - FWindowBounds.width;

    if FWindowBounds.y < 0 then
      FWindowBounds.y := 0
    else if FWindowBounds.y > (GetScreenHeight - FWindowBounds.height) then
      FWindowBounds.y := GetScreenHeight - FWindowBounds.height;

    if IsMouseButtonReleased(MOUSE_LEFT_BUTTON) then
      FDragMode := False;
  end;

  // Load files if needed
  if FDirFiles.paths = nil then
    ReloadDirectoryContents;

  // Draw window
  guiResult := GuiWindowBox(FWindowBounds, PChar(GetDialogTitle));
  if guiResult <> 0 then
    Cancel;

  GuiSetStyle(BUTTON, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);

  // Up button
  if GuiButton(RectangleCreate(
    FWindowBounds.x + FWindowBounds.width - 48,
    FWindowBounds.y + 24 + 12,
    40, 24), '< ..') <> 0 then
  begin
    savedFileName := FFileName;
    tempStr := GetPrevDirectoryPath(FDirPathText);
    if tempStr <> '' then
      FDirPathText := ExpandFileName(tempStr)
    else
      FDirPathText := GetWorkingDirectory();
    FDirPathText := ExcludeTrailingPathDelimiter(FDirPathText);
    ReloadDirectoryContents;
    FFilesListActive := -1;
    if savedFileName <> '' then
    begin
      FFileName := savedFileName;
      StrLCopy(FFileNameText, PChar(ExtractFileName(savedFileName)), SizeOf(FFileNameText) - 1);
    end;
  end;

  // Path text box
  StrLCopy(pathBuffer, PChar(ExpandFileName(FDirPathText)), SizeOf(pathBuffer) - 1);

  if GuiTextBox(RectangleCreate(
    FWindowBounds.x + 8,
    FWindowBounds.y + 24 + 12,
    FWindowBounds.width - 48 - 16,
    24), pathBuffer, 1024, FDirPathEditMode) <> 0 then
  begin
    FDirPathEditMode := not FDirPathEditMode;
    if not FDirPathEditMode then
    begin
      savedFileName := FFileName;
      FDirPathText := ExpandFileName(string(pathBuffer));
      FDirPathText := ExcludeTrailingPathDelimiter(FDirPathText);
      if DirectoryExists(PChar(FDirPathText)) then
        ReloadDirectoryContents
      else
        FDirPathText := GetWorkingDirectory();
      if savedFileName <> '' then
      begin
        FFileName := savedFileName;
        StrLCopy(FFileNameText, PChar(ExtractFileName(savedFileName)), SizeOf(FFileNameText) - 1);
      end;
    end;
  end;

  // List view
  prevAlignment := GuiGetStyle(LISTVIEW, TEXT_ALIGNMENT);
  prevHeight := GuiGetStyle(LISTVIEW, LIST_ITEMS_HEIGHT);

  GuiSetStyle(LISTVIEW, TEXT_ALIGNMENT, TEXT_ALIGN_LEFT);
  GuiSetStyle(LISTVIEW, LIST_ITEMS_HEIGHT, 24);

  if (Length(FDirFilesIcon) > 0) and (FDirFiles.count > 0) then
  begin
    GetMem(dirFilesIconArray, SizeOf(PChar) * FDirFiles.count);
    try
      for i := 0 to FDirFiles.count - 1 do
        dirFilesIconArray[i] := FDirFilesIcon[i];

      GuiListViewEx(RectangleCreate(
        FWindowBounds.x + 8,
        FWindowBounds.y + 48 + 20,
        FWindowBounds.width - 16,
        FWindowBounds.height - 60 - 16 - 68),
        dirFilesIconArray,
        FDirFiles.count,
        @FFilesListScrollIndex,
        @FFilesListActive,
        @FItemFocused);
    finally
      FreeMem(dirFilesIconArray);
    end;
  end;

  GuiSetStyle(LISTVIEW, TEXT_ALIGNMENT, prevAlignment);
  GuiSetStyle(LISTVIEW, LIST_ITEMS_HEIGHT, prevHeight);

  // Handle selection - ИСПРАВЛЕНО
  if (FFilesListActive >= 0) and (FFilesListActive <> FPrevFilesListActive) then
  begin
    if (FFilesListActive < FDirFiles.count) then
    begin
      selectedPath := string(FDirFiles.paths[FFilesListActive]);

      // Если это файл (не директория) - подставляем его имя
      if not DirectoryExists(PChar(selectedPath)) then
      begin
        StrLCopy(FFileNameText, PChar(ExtractFileName(selectedPath)), SizeOf(FFileNameText) - 1);
        FFileName := string(FFileNameText);
      end;

      // Если это директория - переходим в нее
      if DirectoryExists(PChar(selectedPath)) then
      begin
        savedFileName := FFileName;

        // ИСПРАВЛЕНО: используем полный путь из selectedPath
        if ExtractFileName(selectedPath) = '..' then
          FDirPathText := GetPrevDirectoryPath(FDirPathText)
        else
          FDirPathText := ExcludeTrailingPathDelimiter(ExpandFileName(selectedPath));

        ReloadDirectoryContents;
        FFilesListActive := -1;
        if savedFileName <> '' then
        begin
          FFileName := savedFileName;
          StrLCopy(FFileNameText, PChar(ExtractFileName(savedFileName)), SizeOf(FFileNameText) - 1);
        end;
      end;
    end;
    FPrevFilesListActive := FFilesListActive;
  end;

  // File name input
  GuiLabel(RectangleCreate(
    FWindowBounds.x + 8,
    FWindowBounds.y + FWindowBounds.height - 68,
    60, 24), 'File name:');

  if GuiTextBox(RectangleCreate(
    FWindowBounds.x + 72,
    FWindowBounds.y + FWindowBounds.height - 68,
    FWindowBounds.width - 184,
    24), FFileNameText, SizeOf(FFileNameText) - 1, FFileNameEditMode) <> 0 then
  begin
    FFileNameEditMode := not FFileNameEditMode;
    if not FFileNameEditMode then
      FFileName := string(FFileNameText);
  end;

  // Action button
  btnResult := GuiButton(RectangleCreate(
    FWindowBounds.x + FWindowBounds.width - 96 - 8,
    FWindowBounds.y + FWindowBounds.height - 68,
    96, 24), PChar(GetActionButtonText));

  if btnResult <> 0 then
  begin
    if FFileNameEditMode then
      FFileName := string(FFileNameText);

    if ValidateBeforeClose then
    begin
      OnFileSelected(IncludeTrailingPathDelimiter(FDirPathText) + FFileName);
      Close;
    end;
  end;

  // Cancel button
  if GuiButton(RectangleCreate(
    FWindowBounds.x + FWindowBounds.width - 96 - 8,
    FWindowBounds.y + FWindowBounds.height - 24 - 12,
    96, 24), 'Cancel') <> 0 then
    Cancel;
end;

procedure TCustomFileDialog.Close;
var i: integer;
begin
  FActive := False;
  FFileNameEditMode := False;

  if FDirFiles.paths <> nil then
  begin
    for i := 0 to FDirFiles.count - 1 do
      if FDirFiles.paths[i] <> nil then
        StrDispose(FDirFiles.paths[i]);
    FreeMem(FDirFiles.paths);
    FDirFiles.paths := nil;
  end;
  FDirFiles.count := 0;
end;

function TCustomFileDialog.IsActive: Boolean;
begin
  Result := FActive;
end;

procedure TCustomFileDialog.ReloadDirectoryContents;
var
  i: Integer;
  totalItems: Integer;
  iconText: string;
  dirName: string;
  fileNameItem: string;
  savedFileName: string;
  fullPath: string;
begin
  savedFileName := FFileName;

  // Unload old
  if FDirFiles.paths <> nil then
  begin
    for i := 0 to FDirFiles.count - 1 do
      if FDirFiles.paths[i] <> nil then
        StrDispose(FDirFiles.paths[i]);
    FreeMem(FDirFiles.paths);
    FDirFiles.paths := nil;
  end;

  FreeIcons;

  // Load directories and files
  LoadDirectoryContents;

  totalItems := FDirectories.Count + FFiles.Count;

  if totalItems = 0 then
  begin
    FDirFiles.count := 0;
    Exit;
  end;

  // Allocate TFilePathList
  FDirFiles.count := totalItems;
  GetMem(FDirFiles.paths, SizeOf(PChar) * totalItems);

  // Initialize icons array
  SetLength(FDirFilesIcon, totalItems);
  for i := 0 to totalItems - 1 do
  begin
    GetMem(FDirFilesIcon[i], MAX_ICON_PATH_LENGTH);
    FillChar(FDirFilesIcon[i]^, MAX_ICON_PATH_LENGTH, 0);
  end;

  // Fill directories first
  for i := 0 to FDirectories.Count - 1 do
  begin
    dirName := FDirectories[i];

    // ИСПРАВЛЕНО: правильное формирование пути
    if dirName = '..' then
      fullPath := GetPrevDirectoryPath(FDirPathText)
    else
      fullPath := IncludeTrailingPathDelimiter(FDirPathText) + dirName;

    FDirFiles.paths[i] := StrNew(PChar(fullPath));

    if dirName = '..' then
      iconText := '#1# ' + dirName
    else
      iconText := '#1# ' + dirName;

    StrLCopy(FDirFilesIcon[i], PChar(iconText), MAX_ICON_PATH_LENGTH - 1);
  end;

  // Then files
  for i := 0 to FFiles.Count - 1 do
  begin
    fileNameItem := FFiles[i];
    fullPath := IncludeTrailingPathDelimiter(FDirPathText) + fileNameItem;
    FDirFiles.paths[FDirectories.Count + i] := StrNew(PChar(fullPath));

    if IsFileExtension(PChar(fileNameItem), '.ay;.ayc;.sqt;.stc;.pt1;.pt2;.pt3;.asc;.psg;.stp;.psc;.vtx;.sng;.sap;.str;.sid;.dmm;.pld;.cop;.mp3;.xm;.mod;.it;.s3m;.m') then
      iconText := '#11# ' + fileNameItem
    else if IsFileExtension(PChar(fileNameItem), '.txt;.md;.nfo;.xml;.json') then
      iconText := '#10# ' + fileNameItem
    else
      iconText := '#218# ' + fileNameItem;

    StrLCopy(FDirFilesIcon[FDirectories.Count + i], PChar(iconText), MAX_ICON_PATH_LENGTH - 1);
  end;

  FItemFocused := 0;
  FFilesListActive := -1;
  FPrevFilesListActive := -1;

  // Restore file name
  if savedFileName <> '' then
  begin
    FFileName := savedFileName;
    StrLCopy(FFileNameText, PChar(ExtractFileName(savedFileName)), SizeOf(FFileNameText) - 1);
  end;


end;

procedure TCustomFileDialog.FreeIcons;
var
  i: Integer;
begin
  for i := 0 to High(FDirFilesIcon) do
    if Assigned(FDirFilesIcon[i]) then
      FreeMem(FDirFilesIcon[i]);
  SetLength(FDirFilesIcon, 0);
end;

function TCustomFileDialog.GetPrevDirectoryPath(const DirPath: string): string;
var
  NormalizedPath: string;
begin
  NormalizedPath := ExcludeTrailingPathDelimiter(DirPath);

  if NormalizedPath = '' then
    Result := ExtractFileDrive(DirPath)
  else
    Result := ExtractFilePath(NormalizedPath);

  // Удаляем завершающий разделитель для корня
  if (Result = PATH_SEPARATOR) or (Result = ExtractFileDrive(DirPath) + PATH_SEPARATOR) then
    Result := ExcludeTrailingPathDelimiter(Result);

  if Result = '' then
    Result := ExtractFileDrive(DirPath);

  Result := ExcludeTrailingPathDelimiter(Result);
end;

procedure TCustomFileDialog.LoadDirectoryContents;
var
  searchRec: TSearchRec;
  searchResult: Integer;
  searchPath: string;
  itemName: string;
begin
  FDirectories.Clear;
  FFiles.Clear;

  // Используем нормализованный путь
  FDirPathText := ExpandFileName(FDirPathText);
  FDirPathText := ExcludeTrailingPathDelimiter(FDirPathText);

  // Add parent directory
  if (FDirPathText <> '') and
     (FDirPathText <> ExtractFileDrive(FDirPathText)) and
     (ExtractFilePath(FDirPathText) <> FDirPathText) then
  begin
    FDirectories.Add('..');
  end;

  searchPath := IncludeTrailingPathDelimiter(FDirPathText) + '*';
  searchResult := FindFirst(searchPath, faDirectory or faAnyFile, searchRec);

  try
    while searchResult = 0 do
    begin
      itemName := searchRec.Name;

      if (itemName = '.') then
      begin
        searchResult := FindNext(searchRec);
        Continue;
      end;

      if ((searchRec.Attr and faDirectory) <> 0) and ((searchRec.Attr and faHidden) = 0) then
      begin
        if itemName <> '..' then
          FDirectories.Add(itemName);
      end
      else if (searchRec.Attr and faHidden) = 0 then
      begin
        if (FFilter = '') or (Pos(LowerCase(FFilter), LowerCase(itemName)) > 0) then
          FFiles.Add(itemName);
      end;

      searchResult := FindNext(searchRec);
    end;
  finally
    FindClose(searchRec);
  end;

  FDirectories.Sort;
  FFiles.Sort;
end;

procedure TCustomFileDialog.UpdateWindowTitle;
var
  title: string;
begin
  title := GetDialogTitle;
  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);
  GuiLabel(RectangleCreate(
    FWindowBounds.x + 8,
    FWindowBounds.y + 8,
    FWindowBounds.width - 16,
    20), PChar(title));
end;

function TCustomFileDialog.ValidateBeforeClose: Boolean;
begin
  Result := FFileName <> '';
end;

procedure TCustomFileDialog.OnFileSelected(const FilePath: string);
begin
  // Can be overridden by descendants
end;

{ TOpenDialog }

function TOpenDialog.GetDialogTitle: string;
begin
  Result := 'Open File';
end;

function TOpenDialog.GetActionButtonText: string;
begin
  Result := 'Select';
end;

function TOpenDialog.ValidateBeforeClose: Boolean;
var
  fullPath: string;
begin
  Result := False;

  if FFileName = '' then
    Exit;

  fullPath := IncludeTrailingPathDelimiter(FDirPathText) + FFileName;

  if FileExists(PChar(fullPath)) then
    Result := True
  else
    Result := False;
end;

procedure TOpenDialog.OnFileSelected(const FilePath: string);
begin
  FFileName := FilePath;
end;

procedure TOpenDialog.CancelDialog;
begin
  inherited CancelDialog;
end;

{ TSaveDialog }

constructor TSaveDialog.Create;
begin
  inherited Create;
  FOverwriteWarningShown := False;
  FShowWarningModal := False;
  FSaveAfterWarning := False;
end;

destructor TSaveDialog.Destroy;
begin
  inherited Destroy;
end;

function TSaveDialog.GetDialogTitle: string;
begin
  Result := 'Save File';
end;

function TSaveDialog.GetActionButtonText: string;
begin
  Result := 'Save';
end;

function TSaveDialog.ValidateBeforeClose: Boolean;
var
  fullPath: string;
begin
  Result := False;

  if FFileName = '' then
    Exit;

  fullPath := IncludeTrailingPathDelimiter(FDirPathText) + FFileName;

  if CheckFileExists(fullPath) then
  begin
    FShowWarningModal := True;
    FSaveAfterWarning := True;
    Result := False;
  end
  else
    Result := True;
end;

procedure TSaveDialog.OnFileSelected(const FilePath: string);
begin
  FFileName := FilePath;
end;

procedure TSaveDialog.CancelDialog;
begin
  inherited CancelDialog;
  FShowWarningModal := False;
  FSaveAfterWarning := False;
end;

function TSaveDialog.CheckFileExists(const FileName_: string): Boolean;
begin
  Result := FileExists(PChar(FileName_));
end;

procedure TSaveDialog.DrawOverwriteWarning;
var
  warningBounds: TRectangle;
  buttonYes, buttonNo: TRectangle;
  resultYes, resultNo: Integer;
  oldTextAlignment: Integer;
begin
  warningBounds := RectangleCreate(
    FWindowBounds.x + FWindowBounds.width / 2 - 150,
    FWindowBounds.y + FWindowBounds.height / 2 - 75,
    300, 150
  );

  oldTextAlignment := GuiGetStyle(DEFAULT, TEXT_ALIGNMENT);

  DrawRectangle(0, 0, GetScreenWidth, GetScreenHeight, ColorCreate(0, 0, 0, 180));

  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);
  GuiWindowBox(warningBounds, 'Warning');

  GuiLabel(RectangleCreate(
    warningBounds.x + 10,
    warningBounds.y + 30,
    warningBounds.width - 20,
    40), PChar(Format('File "%s" already exists!', [ExtractFileName(FFileName)])));

  GuiLabel(RectangleCreate(
    warningBounds.x + 10,
    warningBounds.y + 55,
    warningBounds.width - 20,
    40), 'Overwrite?');

  buttonYes := RectangleCreate(
    warningBounds.x + warningBounds.width - 200,
    warningBounds.y + warningBounds.height - 40,
    90, 30
  );
  resultYes := GuiButton(buttonYes, 'Yes');

  buttonNo := RectangleCreate(
    warningBounds.x + warningBounds.width - 100,
    warningBounds.y + warningBounds.height - 40,
    90, 30
  );
  resultNo := GuiButton(buttonNo, 'No');

  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, oldTextAlignment);

  if resultYes <> 0 then
  begin
    FShowWarningModal := False;
    if FSaveAfterWarning then
    begin
      OnFileSelected(IncludeTrailingPathDelimiter(FDirPathText) + FFileName);
      Close;
    end;
  end;

  if resultNo <> 0 then
  begin
    FShowWarningModal := False;
    FSaveAfterWarning := False;
  end;
end;

procedure TSaveDialog.Update;
begin
  if FShowWarningModal then
  begin
    DrawOverwriteWarning;
    Exit;
  end;

  inherited Update;
end;

function TSaveDialog.IsActive: Boolean;
begin
  if FShowWarningModal then
    Result := True
  else
    Result := inherited IsActive;
end;

end.
