unit playerUi;

{$mode ObjFPC}{$H+}

interface

uses
  raylib, raymath, raygui,
  Classes, SysUtils, trdos_reader, TuneZXPlayer;

type

  { TInfoPanel }
  TInfoPanel = class
  private
    FCaption: string;
    FFileInfo: TFileInfo;
    FHeight: Integer;
    FLeft: Integer;
    FTop: Integer;
    FWidth: Integer;
    FName, FType, FSize, FPosition: PAnsiChar;
    procedure SetFileInfo(AValue: TFileInfo);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Draw;
    property FileInfo: TFileInfo read FFileInfo write SetFileInfo;
    property Top: Integer read FTop write FTop;
    property Left: Integer read FLeft write FLeft;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
  end;

  { TModuleInfoPanel }
  TModuleInfoPanel = class
  private
    FAuthor: string;
    FCaption: string;
    FHeight: Integer;
    FLeft: Integer;
    FModuleInfo: string;
    FModuleType: string;
    FPlayer: TZXTunePlayer;
    FTimeStr: string ;
    FTitle: string;
    FTop: Integer;
    FWidth: Integer;

  public
    constructor Create;
    destructor Destroy; override;
    procedure UpdateInfo;
    procedure Draw;
    property Top: Integer read FTop write FTop;
    property Left: Integer read FLeft write FLeft;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property Player: TZXTunePlayer read FPlayer write FPLayer;
  end;

  { TDriveInfoPanel }

  TDriveInfoPanel = class
  private
    FReader: TZXImageReader;
    FTitle: string;
    FHeight: Integer;
    FLeft: Integer;
    FTop: Integer;
    FWidth: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Draw;
    property Top: Integer read FTop write FTop;
    property Left: Integer read FLeft write FLeft;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property Reader: TZXImageReader read FReader write FReader;
  end;

  { TPlayBackPanel }

  TPlayBackPanel = class
  private
    FHeight: Integer;
    FLeft: Integer;
    FPlayer: TZXTunePlayer;
    FTop: Integer;
    FWidth: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Draw;
    property Top: Integer read FTop write FTop;
    property Left: Integer read FLeft write FLeft;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property Player: TZXTunePlayer read FPlayer write FPLayer;
  end;

  { TFileListView - класс для отображения списка файлов }
  TFileListView = class
  private
    FLeft: Integer;
    FPlayLabelIndex: Integer;
    FTop: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FReader: TZXImageReader;
    FScrollIndex: Integer;
    FActiveIndex: Integer;
    FOnFileSelected: TNotifyEvent;
    FItemsList: TStringList;        // Список для хранения имен файлов
    procedure SetActiveIndex(AValue: Integer);
    procedure UpdateItemsList;
  public
    constructor Create(Reader: TZXImageReader);
    destructor Destroy; override;
    procedure Draw;
    procedure Refresh;
    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property ScrollIndex: Integer read FScrollIndex write FScrollIndex;
    property ActiveIndex: Integer read FActiveIndex write SetActiveIndex;
    property PlayLabelIndex:Integer read FPlayLabelIndex write FPlayLabelIndex;
    property OnFileSelected: TNotifyEvent read FOnFileSelected write FOnFileSelected;
  end;

  function TimeMsToStr(TimeMS: integer): string;

implementation

function TimeMsToStr(TimeMS: integer): string;
var hours, minutes, seconds: integer;
begin
  if TimeMS <= 0 then
  begin
    Result := '-';
    Exit;
  end;

  hours := TimeMS div 3600000;  // 1 hour = 3,600,000 ms
  minutes := (TimeMS mod 3600000) div 60000;
  seconds := (TimeMS mod 60000) div 1000;

  if hours > 0 then
    Result := Format('%.2d:%.2d:%.2d', [hours, minutes, seconds])
  else
    Result := Format('%.2d:%.2d', [minutes, seconds]);
end;

{ TInfoPanel }

procedure TInfoPanel.SetFileInfo(AValue: TFileInfo);
begin
  FFileInfo := AValue;
  FName := PAnsiChar(FFileInfo.Name + '.' + FFileInfo.FileType);
  FType := PAnsiChar(FFileInfo.FileTypeDesc);
  FSize := PAnsiChar(Format('%d bytes', [FFileInfo.RawSize]));  // Исправлено: SizeBytes -> RawSize
  FPosition := PAnsiChar(Format('Track %d, Sector %d', [FFileInfo.StartTrack, FFileInfo.StartSector]));
end;

constructor TInfoPanel.Create;
begin
  FCaption := '#15# File Information:';
  FLeft := 5;
  FTop := 5;
  FWidth := 220;
  FHeight := 140;
end;

destructor TInfoPanel.Destroy;
begin
  inherited Destroy;
end;

procedure TInfoPanel.Draw;
var
  yOffset, labelLeft, valueLeft: integer;
begin
  GuiPanel(RectangleCreate(FLeft, FTop, FWidth, FHeight), PAnsiChar(FCaption));
  yOffset := FTop + 25;
  labelLeft := FLeft + 10;
  valueLeft := FLeft + 80;

  // Draw Name
  GuiLabel(RectangleCreate(labelLeft, yOffset, 80, 20), 'Name: ');
  GuiLabel(RectangleCreate(valueLeft, yOffset, 250, 20), FName);

  // Draw Type
  yOffset := yOffset + 16;
  GuiLabel(RectangleCreate(labelLeft, yOffset, 80, 20), 'Type: ');
  GuiLabel(RectangleCreate(valueLeft, yOffset, 250, 20), FType);

  // Draw Size
  yOffset := yOffset + 16;
  GuiLabel(RectangleCreate(labelLeft, yOffset, 80, 20), 'Size: ');
  GuiLabel(RectangleCreate(valueLeft, yOffset, 250, 20), FSize);

  // Draw Position track
  yOffset := yOffset + 16;
  GuiLabel(RectangleCreate(labelLeft, yOffset, 80, 20), 'Position: ');
  GuiLabel(RectangleCreate(valueLeft, yOffset, 250, 20), FPosition);

  FHeight := (yOffset + 22) - FTop;
end;

{ TModuleInfoPanel }

constructor TModuleInfoPanel.Create;
begin
  FCaption := '#11# Module Information:';
  FLeft := 5;
  FTop := 0;
  FWidth := 220;
  FHeight := 140;
  FTitle := '';
  FAuthor := '';
  FModuleType := '';
  FModuleInfo := '';
end;

destructor TModuleInfoPanel.Destroy;
begin
  inherited Destroy;
end;

procedure TModuleInfoPanel.UpdateInfo;
begin
  if Assigned(FPlayer) then
  begin
    FTitle := FPlayer.CurrentSongName;
    FAuthor := FPlayer.CurrentAuthor;
    FModuleType := FPlayer.CurrentModuleType;
    FTimeStr := TimeMsToStr(FPlayer.GetDuration);
  end;
end;

procedure TModuleInfoPanel.Draw;
var
  yOffset, leftCol, rightCol: integer;
begin
  GuiPanel(RectangleCreate(FLeft, FTop, FWidth, FHeight), PAnsiChar(FCaption));
  yOffset := FTop + 25;
  leftCol := FLeft + 10;
  rightCol := FLeft + 115;

  // Draw Title
  GuiLabel(RectangleCreate(leftCol, yOffset, 50, 20), 'Title:');
  GuiLabel(RectangleCreate(leftCol + 55, yOffset, 290, 20), PAnsiChar(FTitle));

  // Draw Author
  yOffset := yOffset + 16;
  GuiLabel(RectangleCreate(leftCol, yOffset, 50, 20), 'Author:');
  GuiLabel(RectangleCreate(leftCol + 55, yOffset, 290, 20), PAnsiChar(FAuthor));

  // Draw Type + Time в одной строке
  yOffset := yOffset + 16;
  GuiLabel(RectangleCreate(leftCol, yOffset, 40, 20), 'Type:');
  GuiLabel(RectangleCreate(leftCol + 40, yOffset, 70, 20), PAnsiChar(FModuleType));
  GuiLabel(RectangleCreate(rightCol, yOffset, 40, 20), 'Time:');
  GuiLabel(RectangleCreate(rightCol + 40, yOffset, 60, 20), PAnsiChar(FTimeStr));

  FHeight := (yOffset + 22) - FTop;
end;


{ TDriveInfoPanel }

constructor TDriveInfoPanel.Create;
begin
  FTitle := '#2# Disk Information:';
  FLeft := 5;
  FTop := 5;
  FWidth := 220;
  FHeight := 140;  // Такая же высота, как у TInfoPanel и TModuleInfoPanel
end;

destructor TDriveInfoPanel.Destroy;
begin
  inherited Destroy;
end;



procedure TDriveInfoPanel.Draw;
var
  yOffset, leftCol, rightCol: integer;
begin
  GuiPanel(RectangleCreate(FLeft, FTop, FWidth, FHeight), PAnsiChar(FTitle));
  yOffset := FTop + 25;
  leftCol := FLeft + 10;
  rightCol := FLeft + 115;



  // Строка 1: Disk type + Disk label
  GuiLabel(RectangleCreate(leftCol, yOffset, 70, 20), 'Type:');
  if (FReader = nil) or (FReader.FileCount = 0) then
  GuiLabel(RectangleCreate(leftCol + 45, yOffset, 400, 20), 'No disk loaded' ) else
  GuiLabel(RectangleCreate(leftCol + 45, yOffset, 400, 20), PAnsiChar(FReader.GetDiskTypeString));


  // Строка 2: Total + Used
  yOffset := yOffset + 16;
  GuiLabel(RectangleCreate(leftCol, yOffset, 70, 20), 'Total:');
  GuiLabel(RectangleCreate(leftCol + 45, yOffset, 60, 20), PAnsiChar(IntToStr(FReader.GetTotalSpace)));
  GuiLabel(RectangleCreate(rightCol, yOffset, 50, 20), 'Used:');
  GuiLabel(RectangleCreate(rightCol + 45, yOffset, 60, 20), PAnsiChar(IntToStr(FReader.GetUsedSpace)));

  // Строка 3: Free + Usage
  yOffset := yOffset + 16;
  GuiLabel(RectangleCreate(leftCol, yOffset, 70, 20), 'Free:');
  GuiLabel(RectangleCreate(leftCol + 45, yOffset, 60, 20), PAnsiChar(IntToStr(FReader.GetFreeSpace)));
  GuiLabel(RectangleCreate(rightCol, yOffset, 50, 20), 'Usage:');
  GuiLabel(RectangleCreate(rightCol + 45, yOffset, 60, 20), PAnsiChar(Format('%.1f', [FReader.GetUsagePercent]) + '%'));

  // Строка 4: Files + Free sectors
  yOffset := yOffset + 16;
  GuiLabel(RectangleCreate(leftCol, yOffset, 70, 20), 'Files:');
  GuiLabel(RectangleCreate(leftCol + 45, yOffset, 60, 20), PAnsiChar(IntToStr(FReader.GetFilesCount)));
  GuiLabel(RectangleCreate(rightCol, yOffset, 90, 20), 'Free sectors:');
  GuiLabel(RectangleCreate(rightCol + 90, yOffset, 40, 20), PAnsiChar(IntToStr(FReader.GetFreeSectorsCount)));



  FHeight := (yOffset + 22) - FTop;
end;
{ TPlayBackPanel }

constructor TPlayBackPanel.Create;
begin
  FLeft := 5;
  FTop := 5;
  FWidth := 220;
  FHeight := 80;
end;

destructor TPlayBackPanel.Destroy;
begin
  inherited Destroy;
end;

procedure TPlayBackPanel.Draw;
var
  yOffset: Integer;
  progress: Single;
  volume: Single;
  posText, durText: string;
  progressBarRect: TRectangle;
  volumeBarRect: TRectangle;
  progressChanged: integer;
  volumeChanged: integer;
begin
  if not Assigned(FPlayer) then
    Exit;

  GuiPanel(RectangleCreate(FLeft, FTop, FWidth, FHeight), '#15# Playback Controls');
  yOffset := FTop + 30;

  // Progress slider
  GuiLabel(RectangleCreate(FLeft + 10, yOffset, 40, 20), 'Time:');

  if FPlayer.GetDuration > 0 then
    progress := FPlayer.GetProgressPercent / 100
  else
    progress := 0;

  progressBarRect := RectangleCreate(FLeft + 55, yOffset, FWidth - 120, 20);
  progressChanged := GuiSlider(progressBarRect, nil, nil, @progress, 0.0, 1.0);

  posText := TimeMsToStr(FPlayer.GetPosition);
  durText := TimeMsToStr(FPlayer.GetDuration);
  GuiLabel(RectangleCreate(FLeft + FWidth - 55, yOffset, 50, 20), PAnsiChar(posText + '/' + durText));

  if progressChanged > 0 then
  begin
    // Seek to position (you need to implement Seek method in TZXTunePlayer)
    // FPlayer.Seek(Round(progress * FPlayer.GetDuration));
  end;

  // Volume slider
  yOffset := yOffset + 25;
  GuiLabel(RectangleCreate(FLeft + 10, yOffset, 40, 20), 'Vol:');

  volume := GetMasterVolume();
  volumeBarRect := RectangleCreate(FLeft + 55, yOffset, FWidth - 70, 20);
  volumeChanged := GuiSlider(volumeBarRect, nil, nil, @volume, 0.0, 1.0);
  GuiLabel(RectangleCreate(FLeft + FWidth - 15, yOffset, 15, 20), PAnsiChar(Format('%.0f%%', [volume * 100])));

  if volumeChanged > 0 then
    SetMasterVolume(volume);

  FHeight := (yOffset + 30) - FTop;
end;

{ TFileListView }

constructor TFileListView.Create(Reader: TZXImageReader);
begin
  inherited Create;
  FReader := Reader;
  FLeft := 10;
  FTop := 40;
  FWidth := 200;
  FHeight := 300;
  FScrollIndex := 0;
  FActiveIndex := -1;
  FPlayLabelIndex := -1;
  FItemsList := TStringList.Create;
end;

destructor TFileListView.Destroy;
begin
  FItemsList.Free;
  inherited Destroy;
end;

procedure TFileListView.UpdateItemsList;
var
  i: Integer;
  FileInfo: TFileInfo;
begin
  FItemsList.Clear;

  if (FReader = nil) or (FReader.FileCount = 0) then
    Exit;

  for i := 0 to FReader.FileCount - 1 do
  begin
    FileInfo := FReader.Files[i];
    FItemsList.Add(FileInfo.Name + '.' + FileInfo.FileType);
  end;
end;

procedure TFileListView.SetActiveIndex(AValue: Integer);
begin
  if AValue <> FActiveIndex then
  begin
    FActiveIndex := AValue;
    if Assigned(FOnFileSelected) then
      FOnFileSelected(Self);
  end;
end;

procedure TFileListView.Refresh;
begin
  FActiveIndex := -1;
  FPlayLabelIndex := -1;  // сбрасываем play label
  FScrollIndex := 0;
  UpdateItemsList;
end;

procedure TFileListView.Draw;
var
  oldActive: Integer;
  ItemsArray: array of PAnsiChar;
  i: Integer;
begin
  if (FReader = nil) or (FReader.FileCount = 0) then
  begin
    GuiPanel(RectangleCreate(FLeft, FTop, FWidth, FHeight), '#228#' + 'Drive Files');
    GuiLabel(RectangleCreate(FLeft + 10, FTop + 30, FWidth - 20, 20),
             'No files');
    Exit;
  end;

  // Если список пуст, обновляем его
  if FItemsList.Count = 0 then
    UpdateItemsList;

  // Рисуем панель вокруг списка файлов
  GuiPanel(RectangleCreate(FLeft, FTop, FWidth, FHeight),
  PAnsiChar('#2# Disk label: '+ FReader.GetDiskLabel ));

  // Настраиваем стили
  GuiSetStyle(LISTVIEW, TEXT_ALIGNMENT, TEXT_ALIGN_LEFT);
  GuiSetStyle(LISTVIEW, TEXT_PADDING, 10);
  GuiSetStyle(LISTVIEW, BORDER_COLOR_NORMAL, ColorToInt(BLANK));
 // GuiSetStyle(LISTVIEW, BORDER_COLOR_FOCUSED, ColorToInt(BLANK));

  oldActive := FActiveIndex;

  // Создаем временный массив PAnsiChar для вызова GuiListViewEx
  SetLength(ItemsArray, FItemsList.Count);

  for i := 0 to FItemsList.Count - 1 do
  begin
    ItemsArray[i] := PAnsiChar(FItemsList[i]);
    if i = FPlayLabelIndex then
      ItemsArray[i] := PAnsiChar('#150#' + ItemsArray[i]);
  end;

  // Используем GuiListViewEx вместо GuiListView
  GuiListViewEx(
    RectangleCreate(FLeft + 5, FTop + 25, FWidth - 10, FHeight - 30),
    @ItemsArray[0],      // Указатель на массив строк
    FItemsList.Count,    // Количество элементов
    @FScrollIndex,       // Индекс скролла
    @FActiveIndex,       // Активный (выбранный) элемент
    nil                  // Фокус (можно nil, если не нужен)
  );

  // Проверяем, изменилось ли выделение
  if (FActiveIndex <> oldActive) and (FActiveIndex >= 0) then
  begin
    if Assigned(FOnFileSelected) then
      FOnFileSelected(Self);
  end
  else if (FActiveIndex = -1) and (oldActive >= 0) then
  begin
    FActiveIndex := oldActive;
  end;
end;

end.
