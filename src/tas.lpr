program tas;

{$mode objfpc}{$H+}

uses
  {$IFDEF LINUX} cthreads,{$ENDIF}
  Classes, CustApp, raylib, raygui, SysUtils, trdos_reader, ctypes, math,
  libzxtune, playerUi, TuneZXPlayer, SpectrumPanel, Toolbar, rayfiledialog,
  fontTools, extratools, gui_window_about, IniFiles;

const
  SCREEN_WIDTH = 640;
  SCREEN_HEIGHT = 500;
  FONT_SIZE = 10;

  TOOLBAR_HEIGHT = 38;
  LISTVIEW_WIDTH = 200;
  PANEL_MARGIN = 10;
  BOTTOM_PANEL_HEIGHT = 20;

  {$IFDEF WINDOWS}
  PATH_SEPARATOR = '\';
  {$ELSE}
  PATH_SEPARATOR = '/';
  {$ENDIF}

type
  { TRayApplication }
  TRayApplication = class(TCustomApplication)
  protected
    procedure DoRun; override;
    procedure HandleFileDrop;
    procedure UpdateUI;
    procedure LoadDiskImage(const FileName: string);
    procedure PlaySelectedFile;
    procedure PlayNextFile;
    procedure PlayPreviousFile;
    procedure StopPlayback;
    procedure ExportFileToPath(const FilePath: string);
    procedure OnPlayerStateChanged(Sender: TObject);
    procedure OnPlayerProgressChanged(Sender: TObject);
    procedure OnPlayerTrackEnd(Sender: TObject);
    procedure OnFileSelected(Sender: TObject);
    procedure ApplyStyleIndex(StyleIndex: Integer);
  private
    // Gui
    InfoPanel: TInfoPanel;
    DriveInfoPanel: TDriveInfoPanel;
    ModuleInfoPanel: TModuleInfoPanel;
    FileListView: TFileListView;
    SpeccyFont: TFont;
    // Диалоги
    FOpenDialog: TOpenDialog;
    FSaveDialog: TSaveDialog;
    FExportDialog: TSaveDialog;
    FAddFileDialog: TOpenDialog;

    SpectrumPanel: TSpectrumPanel;
    FToolbar: TToolbar;
    FReader: TTRDOSReader;
    FStatusMessage: string;
    FCurrentFileName: string;

    FIsDraggingSlider: Boolean;
    FSliderProgressValue: Single;

    // Audio playback
    FPlayer: TZXTunePlayer;
    FSelectedFileInfo: TFileInfo;
    FAutoAdvance: boolean;
    FShuffle: boolean;
    FAboutState: TGuiWindowAboutState;

    // Toolbar handlers
    procedure OnToolbarOpenClick(Sender: TObject);
    procedure OnToolbarExportClick(Sender: TObject);
    procedure OnToolbarPreviousClick(Sender: TObject);
    procedure OnToolbarPlayClick(Sender: TObject);
    procedure OnToolbarPauseClick(Sender: TObject);
    procedure OnToolbarStopClick(Sender: TObject);
    procedure OnToolbarNextClick(Sender: TObject);
    procedure OnToolbarLoopClick(Sender: TObject);
    procedure OnToolbarShuffleClick(Sender: TObject);
    procedure OnToolbarNewDriveClick(Sender: TObject);
    procedure OnToolbarAddFileClick(Sender: TObject);
    procedure OnToolbarDeleteFileClick(Sender: TObject);
    procedure OnToolbarColorThemeClick(Sender: TObject);
    procedure OnToolbarAboutClick(Sender: TObject);

  public
    procedure SaveSetting;
    procedure LoadSetting;
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

{ TRayApplication }



constructor TRayApplication.Create(TheOwner: TComponent);
var MyIcon: TImage;
begin
  inherited Create(TheOwner);
  InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, 'TR-DOS Audio Suite');
  SetWindowState(FLAG_WINDOW_ALWAYS_RUN or FLAG_WINDOW_RESIZABLE or FLAG_WINDOW_HIGHDPI or FLAG_VSYNC_HINT);
  SetWindowMinSize(SCREEN_WIDTH, SCREEN_HEIGHT);
  MyIcon := LoadImage('data/icon.png');
  SetWindowIcon(MyIcon);





 // GuiLoadStyleDefault();
 // GuiSetFont(LoadUnicodeFont('data/2a03_memesbruh03.ttf', 16, TEXTURE_FILTER_POINT));
 // GuiSetStyle(DEFAULT, TEXT_SIZE, 16);

  SpeccyFont := LoadFont('data/ZXSpectrum.ttf');

  FReader := TTRDOSReader.Create;
  FStatusMessage := 'The disk image is not loaded. Open or Drag the *.trd file here.';
  FCurrentFileName := '';
  FAutoAdvance := False;
  FShuffle := False;

  FillChar(FSelectedFileInfo, SizeOf(TFileInfo), 0);

  FPlayer := TZXTunePlayer.Create;
  FPlayer.OnStateChanged := @OnPlayerStateChanged;
  FPlayer.OnProgressChanged := @OnPlayerProgressChanged;
  FPlayer.OnTrackEnd := @OnPlayerTrackEnd;


  if not FPlayer.IsInitialized then
    FStatusMessage := 'Failed to initialize ZXTune or audio system';

  // Создание диалогов
  FOpenDialog := TOpenDialog.Create;
  FOpenDialog.Filter := '.trd';
 // FOpenDialog.InitialDir := GetWorkingDirectory();

  FSaveDialog := TSaveDialog.Create;
  FSaveDialog.Filter := '.trd';
 // FSaveDialog.InitialDir := GetWorkingDirectory();
  FSaveDialog.FileName := 'newdisk.trd';

  FExportDialog := TSaveDialog.Create;
  FExportDialog.Filter := '';
  //FExportDialog.InitialDir := GetWorkingDirectory();

  FAddFileDialog := TOpenDialog.Create;
  FAddFileDialog.Filter := '';
 // FAddFileDialog.InitialDir := GetWorkingDirectory();

  InfoPanel := TInfoPanel.Create;
  ModuleInfoPanel := TModuleInfoPanel.Create;
  ModuleInfoPanel.Player := FPlayer;
  DriveInfoPanel := TDriveInfoPanel.Create;
  DriveInfoPanel.Reader := FReader;
  SpectrumPanel := TSpectrumPanel.Create;
  SpectrumPanel.Title := 'Audio Spectrum Analyzer';
  SpectrumPanel.Visualizer.BarColor := SKYBLUE;
  SpectrumPanel.Visualizer.PeakColor := LIGHTBLUE;
  SpectrumPanel.Visualizer.DecaySpeed := 1.5;
  SpectrumPanel.Visualizer.HoldTime := 0.4;
  SpectrumPanel.Visualizer.BarWidth := 2;
  SpectrumPanel.Visualizer.BarSpacing := 1;
  SpectrumPanel.Visualizer.BarStyle := 0;
  SpectrumPanel.Visualizer.GradientMode := True;
  SpectrumPanel.Visualizer.ShowGrid := True;
  SpectrumPanel.Visualizer.ShowLabels := True;
  SpectrumPanel.Visualizer.BackgroundColor := GetColor(GuiGetStyle(DEFAULT, BACKGROUND_COLOR));
  SpectrumPanel.Visualizer.LabelColor := GetColor(GuiGetStyle(DEFAULT, TEXT_COLOR_NORMAL));

  FileListView := TFileListView.Create(FReader);
  FileListView.OnFileSelected := @OnFileSelected;

  FToolbar := TToolbar.Create;
  FToolbar.SetBounds(0, PANEL_MARGIN div 2, SCREEN_WIDTH, TOOLBAR_HEIGHT, PANEL_MARGIN, 10);
  FToolbar.OnOpenClick := @OnToolbarOpenClick;
  FToolbar.OnExportClick := @OnToolbarExportClick;
  FToolbar.OnPreviousClick := @OnToolbarPreviousClick;
  FToolbar.OnPlayClick := @OnToolbarPlayClick;
  FToolbar.OnPauseClick := @OnToolbarPauseClick;
  FToolbar.OnStopClick := @OnToolbarStopClick;
  FToolbar.OnNextClick := @OnToolbarNextClick;
  FToolbar.OnLoopClick := @OnToolbarLoopClick;
  FToolbar.OnShuffleClick:= @OnToolbarShuffleClick;
  FToolbar.OnNewDriveClick := @OnToolbarNewDriveClick;
  FToolbar.OnAddFileClick := @OnToolbarAddFileClick;
  FToolbar.OnDeleteFileClick := @OnToolbarDeleteFileClick;
  FToolbar.OnColorThemeChange:= @OnToolbarColorThemeClick;
  FToolbar.OnAboutClick:=@OnToolbarAboutClick;

  FaboutState := InitGuiWindowAbout;
  FaboutState.supportDrag := True; // Опционально
  FaboutState.ImageLogo := LoadTextureFromImage(MyIcon);
  UnloadImage(MyIcon);
  LoadSetting;

end;

destructor TRayApplication.Destroy;
begin
  StopPlayback;
  SaveSetting;
  FOpenDialog.Free;
  FSaveDialog.Free;
  FExportDialog.Free;
  FAddFileDialog.Free;

  FToolbar.Free;
  SpectrumPanel.Free;
  FileListView.Free;
  InfoPanel.Free;
  ModuleInfoPanel.Free;
  FPlayer.Free;
  FReader.Free;
  UnloadFont(SpeccyFont);

  CloseWindow();
  inherited Destroy;
end;

procedure TRayApplication.OnToolbarOpenClick(Sender: TObject);
begin
  FOpenDialog.Execute;
end;

procedure TRayApplication.OnToolbarExportClick(Sender: TObject);
var
  TmpFile, ExtFile, OutputFileName: string;
  SelectedIndex: Integer;
begin
  SelectedIndex := FileListView.ActiveIndex;
  if (SelectedIndex < 0) or (SelectedIndex >= FReader.FileCount) then
  begin
    FStatusMessage := 'No file selected for export';
    Exit;
  end;

  FSelectedFileInfo := FReader.Files[SelectedIndex];

  if FPlayer.CurrentSongName = '-' then
    TmpFile := FSelectedFileInfo.Name
  else
    TmpFile := LowerCase(FPlayer.CurrentSongName);

  if FPlayer.CurrentModuleType = '-' then
    ExtFile := FSelectedFileInfo.FileType
  else
    ExtFile := LowerCase(FPlayer.CurrentModuleType);

  OutputFileName := SanitizeFileName(TmpFile + '.' + ExtFile);

  FExportDialog.FileName := OutputFileName;
  FExportDialog.Execute;
end;

procedure TRayApplication.OnToolbarPreviousClick(Sender: TObject);
begin
  PlayPreviousFile;
end;

procedure TRayApplication.OnToolbarPlayClick(Sender: TObject);
begin
  if FPlayer.IsPaused then
    FPlayer.Resume
  else if (FileListView.ActiveIndex >= 0) then
    PlaySelectedFile
  else
    FStatusMessage := 'No file selected';
end;

procedure TRayApplication.OnToolbarPauseClick(Sender: TObject);
begin
  if FPlayer.IsPlaying then
    FPlayer.Pause;
end;

procedure TRayApplication.OnToolbarStopClick(Sender: TObject);
begin
  StopPlayback;
end;

procedure TRayApplication.OnToolbarNextClick(Sender: TObject);
begin
  PlayNextFile;
end;

procedure TRayApplication.OnToolbarLoopClick(Sender: TObject);
begin
  If FToolbar.IsShuffleEnabled then
  begin
    FToolbar.SetShuffle(False);
    FShuffle := False;
  end;
  FPLayer.LoopMode := not FPLayer.LoopMode ;

end;

procedure TRayApplication.OnToolbarShuffleClick(Sender: TObject);
begin
  If FToolbar.IsLoopEnabled then
  begin
    FToolbar.SetLoopEnabled(False);
    FPlayer.LoopMode:=False;
  end;
  FShuffle := FToolbar.IsShuffleEnabled;


end;

procedure TRayApplication.OnToolbarNewDriveClick(Sender: TObject);
begin
  FSaveDialog.Execute;
end;

procedure TRayApplication.OnToolbarAddFileClick(Sender: TObject);
begin
  if not FReader.IsLoaded then
  begin
    FStatusMessage := 'Please load or create a disk image first';
    Exit;
  end;

  FAddFileDialog.Execute;
end;

procedure TRayApplication.OnToolbarDeleteFileClick(Sender: TObject);
var
  SelectedIndex: Integer;
  FileName: string;
begin
  if not FReader.IsLoaded then
  begin
    FStatusMessage := 'Please load or create a disk image first';
    Exit;
  end;

  SelectedIndex := FileListView.ActiveIndex;
  if (SelectedIndex < 0) or (SelectedIndex >= FReader.FileCount) then
  begin
    FStatusMessage := 'No file selected for delete';
    Exit;
  end;

  FileName := FReader.Files[SelectedIndex].Name + '.' +
              FReader.Files[SelectedIndex].FileType;

  if FileListView.PlayLabelIndex = SelectedIndex then
    StopPlayback;

  if FReader.DeleteFile(SelectedIndex) then
  begin
    if not FReader.SaveToCurrentFile then
      FStatusMessage := 'Warning: Failed to save disk after delete';

    FStatusMessage := Format('Deleted: %s', [FileName]);
    FileListView.Refresh;
    FToolbar.DriveIsFull := (FReader.GetFreeSectorsCount = 0);
  end
  else
    FStatusMessage := 'Delete failed: ' + FReader.ErrorMessage;
end;

procedure TRayApplication.OnToolbarColorThemeClick(Sender: TObject);
begin
  ApplyStyleIndex(FToolbar.GetColorThemeIndex);
end;

procedure TRayApplication.OnToolbarAboutClick(Sender: TObject);
begin
  FAboutState.windowActive := true;
end;

procedure TRayApplication.SaveSetting;
var
  MyIni: TIniFile;
begin
  // Create object (creates the file if it doesn't exist)
  MyIni := TIniFile.Create('data/config.ini');
  try
//    MyIni.WriteString('General', 'Username', 'JohnDoe');
    MyIni.WriteInteger('General', 'StyleIndex', fToolbar.GetColorThemeIndex);
//    MyIni.WriteBool('Window', 'Maximized', True);
  finally
    MyIni.Free; // Always free memory
  end;
end;

procedure TRayApplication.LoadSetting;
var
  MyIni: TIniFile;
//  User: string;
  I: Integer;
begin
  MyIni := TIniFile.Create('data/config.ini');
  try
    // ReadString('Section', 'Key', 'DefaultValue')
   // User := MyIni.ReadString('General', 'Username', 'Guest');
    i := MyIni.ReadInteger('General', 'StyleIndex', 0);
    ApplyStyleIndex(I);
   Ftoolbar.SetColorThemeIndex(I);
  finally
    MyIni.Free;
  end;
end;

procedure TRayApplication.OnFileSelected(Sender: TObject);
begin
  if FileListView.ActiveIndex >= 0 then
    PlaySelectedFile;
end;

procedure TRayApplication.ApplyStyleIndex(StyleIndex: Integer);
begin
 case StyleIndex of
   0: GuiLoadStyleDefault;
   1: GuiLoadStyle(PChar(GetApplicationDirectory + 'data/style_amber.rgs'));
   2: GuiLoadStyle(PChar(GetApplicationDirectory + 'data/style_ashes.rgs'));
   3: GuiLoadStyle(PChar(GetApplicationDirectory + 'data/style_cyber.rgs'));
   4: GuiLoadStyle(PChar(GetApplicationDirectory + 'data/style_dark.rgs'));
   5: GuiLoadStyle(PChar(GetApplicationDirectory + 'data/style_genesis.rgs'));
   6: GuiLoadStyle(PChar(GetApplicationDirectory + 'data/style_jungle.rgs'));
 end;
   GuiSetFont(LoadUnicodeFont('data/2a03_memesbruh03.ttf', 16, TEXTURE_FILTER_POINT));
   GuiSetStyle(DEFAULT, TEXT_SIZE, 16);
   SpectrumPanel.Visualizer.BackgroundColor := GetColor(GuiGetStyle(DEFAULT, BACKGROUND_COLOR));
   SpectrumPanel.Visualizer.LabelColor := GetColor(GuiGetStyle(DEFAULT, TEXT_COLOR_NORMAL));
   GuiSetStyle(BUTTON, BORDER_WIDTH, 1);
end;

procedure TRayApplication.ExportFileToPath(const FilePath: string);
var
  SelectedIndex: Integer;
  ExportStream: TMemoryStream;
begin
  SelectedIndex := FileListView.ActiveIndex;
  if (SelectedIndex < 0) or (SelectedIndex >= FReader.FileCount) then
  begin
    FStatusMessage := 'No file selected for export';
    Exit;
  end;

  try
    ExportStream := FReader.ExtractFileToMemory(SelectedIndex);
    try
      if ExportStream <> nil then
      begin
        ExportStream.SaveToFile(FilePath);
        FStatusMessage := Format('File exported: %s (%d bytes)',
          [ExtractFileName(FilePath), ExportStream.Size]);
      end
      else
        FStatusMessage := 'Failed to extract file: ' + FReader.ErrorMessage;
    finally
      ExportStream.Free;
    end;
  except
    on E: Exception do
      FStatusMessage := 'Export error: ' + E.Message;
  end;
end;

procedure TRayApplication.OnPlayerStateChanged(Sender: TObject);
begin
  case FPlayer.PlaybackState of
    psPlaying: FStatusMessage := Format('Playing: %s', [FPlayer.CurrentSongName]);
    psPaused: FStatusMessage := 'Paused';
    psStopped: FStatusMessage := 'Stopped';
  end;
  ModuleInfoPanel.UpdateInfo;
end;

procedure TRayApplication.OnPlayerProgressChanged(Sender: TObject);
begin
  // Progress updated automatically
end;

procedure TRayApplication.OnPlayerTrackEnd(Sender: TObject);
begin
  FStatusMessage := 'Track ended, loading next...';
  if FileListView.ActiveIndex < FReader.FileCount - 1 then
    PlayNextFile
  else
    StopPlayback;
end;

procedure TRayApplication.PlayNextFile;
begin
  if (FReader.FileCount > 0) and (FileListView.ActiveIndex < FReader.FileCount - 1) then
  begin
    if FShuffle then
      FileListView.ActiveIndex := GetRandomValue(1, FReader.FileCount - 1)
    else
      FileListView.ActiveIndex := FileListView.ActiveIndex + 1;
    PlaySelectedFile;
  end
  else if (FReader.FileCount > 0) and (FileListView.ActiveIndex = FReader.FileCount - 1) then
    FStatusMessage := 'This is the last file';
end;

procedure TRayApplication.PlayPreviousFile;
begin
  if (FReader.FileCount > 0) and (FileListView.ActiveIndex > 0) then
  begin
    FileListView.ActiveIndex := FileListView.ActiveIndex - 1;
    PlaySelectedFile;
  end
  else if (FReader.FileCount > 0) and (FileListView.ActiveIndex = 0) then
    FStatusMessage := 'This is the first file';
end;

procedure TRayApplication.LoadDiskImage(const FileName: string);
var
  NormalizedPath: string;
begin
  // Нормализуем путь (удаляем повторяющиеся слеши и лишние пробелы)
  NormalizedPath := ExpandFileName(FileName);  // Приводит к абсолютному пути
  NormalizedPath := StringReplace(NormalizedPath, '//', '/', [rfReplaceAll]);

  StopPlayback;
  FReader.Clear;

  if FReader.LoadFromFile(NormalizedPath) then
  begin
    FCurrentFileName := NormalizedPath;  // ✅ СОХРАНЯЕМ нормализованный путь
    FStatusMessage := Format('Loaded: %s (%d files)',
      [ExtractFileName(NormalizedPath), FReader.FileCount]);
    FileListView.Refresh;
    FToolbar.DriveIsFull := (FReader.GetFreeSectorsCount = 0);
    if FReader.FileCount < 0 then
      FToolbar.DriveIsFull := False;
    if (FReader.FileCount > 0) and (FileListView.ActiveIndex = -1) then
      FileListView.ActiveIndex := -1;
  end
  else
  begin
    FStatusMessage := 'Error: ' + FReader.ErrorMessage;
    FCurrentFileName := '';  // Очищаем при ошибке
  end;
end;

procedure TRayApplication.PlaySelectedFile;
var
  extractedFile: TMemoryStream;
begin
  if (FileListView.ActiveIndex < 0) or (FileListView.ActiveIndex >= FReader.FileCount) then
  begin
    FStatusMessage := 'No file selected';
    Exit;
  end;

  if not FPlayer.IsInitialized then
  begin
    FStatusMessage := 'ZXTune not initialized';
    Exit;
  end;

  StopPlayback;
  FSelectedFileInfo := FReader.Files[FileListView.ActiveIndex];
  FStatusMessage := Format('Loading: %s.%s', [FSelectedFileInfo.Name, FSelectedFileInfo.FileType]);

  try
    extractedFile := TMemoryStream.Create;
    try
      if FReader.ExtractFile(FileListView.ActiveIndex, extractedFile) then
      begin
        if FPlayer.LoadFromMemory(extractedFile.Memory, extractedFile.Size,
                                   FSelectedFileInfo.Name + '.' + FSelectedFileInfo.FileType) then
        begin
          FStatusMessage := Format('Song loaded: %s', [FPlayer.CurrentSongName]);
          FileListView.PlayLabelIndex := FileListView.ActiveIndex;
          FPlayer.Play;
        end
        else
        begin
          FStatusMessage := 'Failed to load file (unsupported format)';
          if FAutoAdvance then
            PlayNextFile;
        end;
      end
      else
      begin
        FStatusMessage := 'Failed to extract file: ' + FReader.ErrorMessage;
        if FAutoAdvance then
          PlayNextFile;
      end;
    finally
      extractedFile.Free;
    end;
  except
    on E: Exception do
    begin
      FStatusMessage := 'Error: ' + E.Message;
      if FAutoAdvance then
        PlayNextFile;
    end;
  end;
end;

procedure TRayApplication.StopPlayback;
begin
  if FPlayer <> nil then
    FPlayer.Stop;
  FileListView.PlayLabelIndex := -1;
end;
{
procedure TRayApplication.HandleFileDrop;
var
  droppedFiles: TFilePathList;
  NormalizedPath: string;
begin
  if IsFileDropped() then
  begin
    droppedFiles := LoadDroppedFiles();
    if droppedFiles.count = 1 then
    begin
      // Нормализуем путь
      NormalizedPath := ExpandFileName(droppedFiles.paths[0]);
      NormalizedPath := StringReplace(NormalizedPath, '//', '/', [rfReplaceAll]);

      if IsFileExtension(PAnsiChar(NormalizedPath), '.trd') then
        LoadDiskImage(NormalizedPath)
      else
        FStatusMessage := 'Please drop a .trd file';
    end;
    UnloadDroppedFiles(droppedFiles);
  end;
end;  }


procedure TRayApplication.HandleFileDrop;
var
  droppedFiles: TFilePathList;
  NormalizedPath: string;
  i: Integer;
  LoadAddr, CodeSize: Word;
  DetectedFileType: Char;
  FileName, ShortName: string;
begin
  if IsFileDropped() then
  begin
    droppedFiles := LoadDroppedFiles();

    // Single file dropped
    if droppedFiles.count = 1 then
    begin
      NormalizedPath := ExpandFileName(droppedFiles.paths[0]);
      NormalizedPath := StringReplace(NormalizedPath, '//', '/', [rfReplaceAll]);

      if IsFileExtension(PAnsiChar(NormalizedPath), '.trd') then
        LoadDiskImage(NormalizedPath)  // Load disk image
      else if FReader.IsLoaded then
      begin
        // Try to add file to current disk
        if DetectFileTypeAndParams(NormalizedPath, LoadAddr, CodeSize, DetectedFileType) then
        begin
          FileName := ChangeFileExt(ExtractFileName(NormalizedPath), '');
          ShortName := ShortenFileName(FileName, 8);

          if FReader.AddFileFromFile(ShortName, DetectedFileType, LoadAddr, CodeSize, NormalizedPath, 0) then
          begin
            if FReader.SaveToCurrentFile then
            begin
              FStatusMessage := Format('Added: %s -> %s.%s (Load:$%X, Size:%d)',
                [ExtractFileName(NormalizedPath), ShortName, DetectedFileType, LoadAddr, CodeSize]);
              FileListView.Refresh;
              FToolbar.DriveIsFull := (FReader.GetFreeSectorsCount = 0);
            end
            else
              FStatusMessage := 'File added but failed to save disk: ' + FReader.ErrorMessage;
          end
          else
            FStatusMessage := 'Failed to add file: ' + FReader.ErrorMessage;
        end
        else
        begin
          FStatusMessage := 'Unsupported file format: ' + ExtractFileName(NormalizedPath) +
                           ' (Supported: .pt1/2/3, .stc, .asc, .ay, etc.)';
        end;
      end
      else
        FStatusMessage := 'First load a .trd disk image, or drop a .trd file';
    end

    // Multiple files dropped - works only if disk is loaded
    else if droppedFiles.count > 1 then
    begin
      if not FReader.IsLoaded then
      begin
        FStatusMessage := Format('First load a disk image (%d files dropped)', [droppedFiles.count]);
        UnloadDroppedFiles(droppedFiles);
        Exit;
      end;

      FStatusMessage := Format('Adding %d files...', [droppedFiles.count]);

      for i := 0 to droppedFiles.count - 1 do
      begin
        NormalizedPath := ExpandFileName(droppedFiles.paths[i]);
        NormalizedPath := StringReplace(NormalizedPath, '//', '/', [rfReplaceAll]);

        // Skip .trd files when adding multiple files
        if IsFileExtension(PAnsiChar(NormalizedPath), '.trd') then
          Continue;

        if DetectFileTypeAndParams(NormalizedPath, LoadAddr, CodeSize, DetectedFileType) then
        begin
          FileName := ChangeFileExt(ExtractFileName(NormalizedPath), '');
          ShortName := ShortenFileName(FileName, 8);

          // Try to add, if name already exists - rename it
          if not FReader.AddFileFromFile(ShortName, DetectedFileType, LoadAddr, CodeSize, NormalizedPath, 0) then
          begin
            // Alternative name with index
            ShortName := ShortenFileName(FileName + '_' + IntToStr(i), 8);
            if FReader.AddFileFromFile(ShortName, DetectedFileType, LoadAddr, CodeSize, NormalizedPath, 0) then
              FStatusMessage := Format('Added: %s -> %s.%s', [ExtractFileName(NormalizedPath), ShortName, DetectedFileType])
            else
              FStatusMessage := Format('Error adding: %s', [ExtractFileName(NormalizedPath)]);
          end
          else
            FStatusMessage := Format('Added: %s -> %s.%s', [ExtractFileName(NormalizedPath), ShortName, DetectedFileType]);
        end
        else
          FStatusMessage := Format('Skipped (unsupported format): %s', [ExtractFileName(NormalizedPath)]);
      end;

      // Save disk after adding all files
      if FReader.SaveToCurrentFile then
      begin
        FStatusMessage := Format('Added %d files to disk', [droppedFiles.count]);
        FileListView.Refresh;
        FToolbar.DriveIsFull := (FReader.GetFreeSectorsCount = 0);
      end
      else
        FStatusMessage := 'Files added but failed to save disk: ' + FReader.ErrorMessage;
    end;

    UnloadDroppedFiles(droppedFiles);
  end;
end;

procedure TRayApplication.UpdateUI;
var
  selectedFile: TFileInfo;
  panelLeft, panelTop, panelRight: integer;
  rightPanelWidth: integer;
  spectrumData: PSingle;
  spectrumSize: Integer;
  yOffset: Integer;
  listViewHeight: Integer;
  playbackControlsHeight: Integer;
  statusBarHeight: Integer;
  progress: Single;
  volume: Single;
  progressChanged: Integer;
  volumeChanged: Integer;
  posText, durText: string;
  sliderY: Integer;
  LoadAddr, CodeSize: Word;
  DetectedFileType: Char;
  FileName, ShortName: string;
  TmpColor: TColorB;
begin
  if FPlayer <> nil then
    FPlayer.UpdateProgress;



  if IsWindowMinimized then
  begin
    DrawBetaDisk(Self.SpeccyFont);
  //  DrawLoadingShader(GetScreenWidth, GetScreenHeight);
    Exit;
  end;

  if IsMouseButtonReleased(MOUSE_BUTTON_LEFT) and FIsDraggingSlider then
  begin
    if (FPlayer.GetDuration > 0) and (FSliderProgressValue >= 0) and (FSliderProgressValue <= 1) then
    begin
      FPlayer.Pause;
      FPlayer.Seek(Round(FSliderProgressValue * FPlayer.GetDuration));
      FPlayer.Play;
    end;
    FIsDraggingSlider := False;
  end;

  // Блокируем GUI если активен любой диалог
  if FOpenDialog.IsActive or FSaveDialog.IsActive or
     FExportDialog.IsActive or FAddFileDialog.IsActive or
     FAboutState.windowActive then
    GuiLock
  else
    GuiUnLock;

  FToolbar.SetPlaybackState(FPlayer.IsPlaying, FPlayer.IsPaused);
  FToolbar.SetFileState(
    {FReader.FileCount >= 0} FReader.IsLoaded,
    (FileListView.ActiveIndex >= 0) and (FileListView.ActiveIndex < FReader.FileCount)
  );

  playbackControlsHeight := 25;
  statusBarHeight := BOTTOM_PANEL_HEIGHT;
  listViewHeight := GetScreenHeight - TOOLBAR_HEIGHT - statusBarHeight -
                    playbackControlsHeight - PANEL_MARGIN * 3;

  FileListView.Left := PANEL_MARGIN;
  FileListView.Top := TOOLBAR_HEIGHT + PANEL_MARGIN;
  FileListView.Width := LISTVIEW_WIDTH;
 // FileListView.Height := GetScreenHeight() - statusBarHeight - playbackControlsHeight - yOffset - PANEL_MARGIN * 2;
  FileListView.Height := listViewHeight;
  FileListView.Draw;

  panelLeft := LISTVIEW_WIDTH + (PANEL_MARGIN * 2);
  panelTop := TOOLBAR_HEIGHT + PANEL_MARGIN;
  panelRight := GetRenderWidth - PANEL_MARGIN;
  rightPanelWidth := panelRight - panelLeft;

  yOffset := panelTop;

  if FileListView.ActiveIndex >= 0 then
    selectedFile := FReader.Files[FileListView.ActiveIndex]
  else
    FillChar(selectedFile, SizeOf(TFileInfo), 0);

  DriveInfoPanel.Left := panelLeft;
  DriveInfoPanel.Top := yOffset;
  DriveInfoPanel.Width := rightPanelWidth;
  DriveInfoPanel.Draw;

  yOffset := yOffset + DriveInfoPanel.Height + PANEL_MARGIN;
  InfoPanel.Left := panelLeft;
  InfoPanel.Top := yOffset;
  InfoPanel.Width := rightPanelWidth;
  InfoPanel.FileInfo := selectedFile;
  InfoPanel.Draw;
  yOffset := yOffset + InfoPanel.Height + PANEL_MARGIN;

  ModuleInfoPanel.Left := panelLeft;
  ModuleInfoPanel.Top := yOffset;
  ModuleInfoPanel.Width := rightPanelWidth;
  ModuleInfoPanel.Draw;
  yOffset := yOffset + ModuleInfoPanel.Height + PANEL_MARGIN;

  if yOffset + 20 < GetScreenHeight() - statusBarHeight - playbackControlsHeight - PANEL_MARGIN * 2 then
  begin
    SpectrumPanel.Left := panelLeft;
    SpectrumPanel.Top := yOffset;
    SpectrumPanel.Width := rightPanelWidth;
    SpectrumPanel.Height := GetScreenHeight() - statusBarHeight - playbackControlsHeight - yOffset - PANEL_MARGIN * 2;

    if FPlayer.IsPlaying then
    begin
      spectrumData := FPlayer.GetSpectrumData;
      spectrumSize := FPlayer.GetSpectrumSize;
      SpectrumPanel.Draw(spectrumData, spectrumSize);
    end
    else
      SpectrumPanel.Draw(nil, 0);
  end;

  FToolbar.Draw;

  sliderY := GetScreenHeight() - statusBarHeight - playbackControlsHeight - PANEL_MARGIN;
  DrawRectangle(PANEL_MARGIN, sliderY, GetScreenWidth() - PANEL_MARGIN * 2,
                playbackControlsHeight, Fade(GetColor(GuiGetStyle(DEFAULT, BACKGROUND_COLOR)), 0.9));

  if FPlayer.GetDuration > 0 then
    progress := FPlayer.GetProgressPercent / 100
  else
    progress := 0;

  posText := TimeMsToStr(FPlayer.GetPosition);
  durText := TimeMsToStr(FPlayer.GetDuration);

  progressChanged := GuiSliderBar(RectangleCreate(PANEL_MARGIN, sliderY + 3,
                               GetScreenWidth() - PANEL_MARGIN * 2 - 80, 19),
                               nil, nil, @progress, 0.0, 1.0);

  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);
  GuiLabel(RectangleCreate(PANEL_MARGIN, sliderY + 3,
             GetScreenWidth() - PANEL_MARGIN * 2 - 80, 19), PAnsiChar(posText + '/' + durText));
  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_LEFT);

  if IsMouseButtonDown(MOUSE_BUTTON_LEFT) and (progressChanged = 1) then
  begin
    FIsDraggingSlider := True;
    FSliderProgressValue := progress;
  end;

  volume := GetMasterVolume();
  volumeChanged := GuiSlider(RectangleCreate(GetScreenWidth() - PANEL_MARGIN - 70, sliderY + 3, 65, 19),
                             nil, nil, @volume, 0.0, 1.0);

  if volumeChanged = 1 then
    SetMasterVolume(volume);

  GuiStatusBar(RectangleCreate(PANEL_MARGIN,
                                GetScreenHeight() - statusBarHeight - PANEL_MARGIN div 2,
                                GetScreenWidth() - PANEL_MARGIN * 2,
                                statusBarHeight),
                                PChar(FStatusMessage));



  DrawSpectrumLogo(GetScreenWidth() - PANEL_MARGIN * 7  ,  GetScreenHeight() - statusBarHeight - PANEL_MARGIN div 2, 20);
  TmpColor := GetColor(GuiGetStyle(Default, BORDER_COLOR_NORMAL));

  DrawRectangleLines(PANEL_MARGIN,
                     GetScreenHeight() - statusBarHeight - PANEL_MARGIN div 2,
                     GetScreenWidth() - PANEL_MARGIN * 2,
                     statusBarHeight, TmpColor);

  // Обновление и обработка результатов диалогов
  if FOpenDialog.IsActive then
  begin
    GuiUnLock;
    FOpenDialog.Update;
    if not FOpenDialog.IsActive then
      if FOpenDialog.FileName <> '' then
        LoadDiskImage(FOpenDialog.FileName);
    GuiLock;
  end;

  // В методе UpdateUI, секция FSaveDialog:
  if FSaveDialog.IsActive then
  begin
    GuiUnLock;
    FSaveDialog.Update;
    if not FSaveDialog.IsActive then
      if FSaveDialog.FileName <> '' then
      begin
        WriteLn('DEBUG: New disk saved to: ', FCurrentFileName);
        // Нормализуем путь перед сохранением
        FSaveDialog.FileName := ExpandFileName(FSaveDialog.FileName);
        FSaveDialog.FileName := StringReplace(FSaveDialog.FileName, '//', '/', [rfReplaceAll]);

        if FReader.CreateNewDiskEx(dt80DS, ExtractFileName(FSaveDialog.FileName)) then
        begin
          if FReader.SaveToFile(FSaveDialog.FileName) then
          begin
            FStatusMessage := Format('Created and saved new disk: %s (%d tracks, %d sectors free)',
              [ExtractFileName(FSaveDialog.FileName),
               FReader.GetLogicalTracksCount,
               FReader.GetFreeSectorsCount]);
            FileListView.Refresh;
            FToolbar.DriveIsFull := (FReader.GetFreeSectorsCount = 0);
            FCurrentFileName := FSaveDialog.FileName;  // Обновляем

            // Дополнительная проверка
            WriteLn('DEBUG: New disk saved to: ', FCurrentFileName);
          end
          else
            FStatusMessage := 'Failed to save disk: ' + FReader.ErrorMessage;
        end
        else
          FStatusMessage := 'Failed to create disk: ' + FReader.ErrorMessage;
      end;
    GuiLock;
  end;

  if FExportDialog.IsActive then
  begin
    GuiUnLock;
    FExportDialog.Update;
    if not FExportDialog.IsActive then
      if FExportDialog.FileName <> '' then
        ExportFileToPath(FExportDialog.FileName);
    GuiLock;
  end;

  if FAddFileDialog.IsActive then
  begin
    GuiUnLock;
    FAddFileDialog.Update;
    if not FAddFileDialog.IsActive then
      if FAddFileDialog.FileName <> '' then
      begin
        if DetectFileTypeAndParams(FAddFileDialog.FileName, LoadAddr, CodeSize, DetectedFileType) then
        begin
          FileName := ChangeFileExt(ExtractFileName(FAddFileDialog.FileName), '');
          ShortName := ShortenFileName(FileName, 8);

          FStatusMessage := Format('Adding: %s as %s.%s (Load:$%X, Size:%d)',
            [ExtractFileName(FAddFileDialog.FileName), ShortName, DetectedFileType, LoadAddr, CodeSize]);

          if FReader.AddFileFromFile(ShortName, DetectedFileType, LoadAddr, CodeSize,
                                     FAddFileDialog.FileName, 0) then
          begin
            if FReader.SaveToCurrentFile then
            begin
              FStatusMessage := Format('File added: %s -> %s.%s (Load:$%X, Size:%d)',
                [ExtractFileName(FAddFileDialog.FileName), ShortName, DetectedFileType, LoadAddr, CodeSize]);
              FileListView.Refresh;
              FToolbar.DriveIsFull := (FReader.GetFreeSectorsCount = 0);
            end
            else
              FStatusMessage := 'File added but failed to save disk: ' + FReader.ErrorMessage;
          end
          else
            FStatusMessage := 'Failed to add file: ' + FReader.ErrorMessage;
        end
        else
        begin
          FStatusMessage := 'Could not determine file type/parameters for: ' + ExtractFileName(FAddFileDialog.FileName);
        end;
      end;
    GuiLock;
  end;

  if FaboutState.windowActive then
  begin
    guiUnlock;
    GuiWindowAbout(FaboutState);
    guiLock;
  end;
end;

procedure TRayApplication.DoRun;
begin
  while (not WindowShouldClose) do
  begin
    HandleFileDrop;

    BeginDrawing();
      ClearBackground(GetColor(GuiGetStyle(DEFAULT, BACKGROUND_COLOR)));
      UpdateUI;
    EndDrawing();
  end;

  Terminate;
end;

var
  Application: TRayApplication;

{$R *.res}

begin
  Application := TRayApplication.Create(nil);
  Application.Run;
  Application.Free;
end.
