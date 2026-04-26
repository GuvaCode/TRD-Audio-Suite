unit Toolbar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, raylib, raygui, math;

type
  TButtonType = (btNormal, btToggle, btCombo, btSeparator);

  TToolbarButton = record
    IconId: Integer;
    Hint: string;
    Bounds: TRectangle;
    ToggleState: Boolean;  // Состояние toggle (вкл/выкл)
    //ComboNumber: Integer;
    ButtonType: TButtonType;
    IsPressed: Boolean;     // Для отслеживания нажатия обычных кнопок
    ComboIndex: Integer;    // Текущий выбранный элемент для btCombo
  end;

  { TToolbar }

  TToolbar = class
  private
    FButtons: array of TToolbarButton;
    FButtonCount: Integer;
    FDriveIsFull: Boolean;
    FHeight: Integer;
    FLeft: Integer;
    FOnAboutClick: TNotifyEvent;
    FOnAddFileClick: TNotifyEvent;
    FOnDeleteFileClick: TNotifyEvent;
    FOnExportClick: TNotifyEvent;
    FOnNewDriveClick: TNotifyEvent;
    FTop: Integer;
    FWidth: Integer;
    FMargin: Integer;
    FButtonLeftPadding: Integer;
    FOnOpenClick: TNotifyEvent;
    FOnPreviousClick: TNotifyEvent;
    FOnPlayClick: TNotifyEvent;
    FOnPauseClick: TNotifyEvent;
    FOnStopClick: TNotifyEvent;
    FOnNextClick: TNotifyEvent;
    FOnLoopClick: TNotifyEvent;
    FOnShuffleClick: TNotifyEvent;
    FOnColorThemeChange: TNotifyEvent; // Событие при смене темы
    FIsPlaying: Boolean;
    FIsPaused: Boolean;
    FHasDiskLoaded: Boolean;
    FHasFileSelected: Boolean;


    procedure CalculateButtonsLayout;
    procedure DrawSeparator(const Bounds: TRectangle);

  public
    constructor Create;
    destructor Destroy; override;
    procedure Draw;
    procedure Update;
    procedure SetBounds(X, Y, Width, Height, Margin, ButtonPadding: Integer);
    procedure SetPlaybackState(IsPlaying, IsPaused: Boolean);
    procedure SetFileState(HasDiskLoaded, HasFileSelected: Boolean);
    function IsLoopEnabled: Boolean;
    procedure SetLoopEnabled(Loop:Boolean);
    function IsShuffleEnabled: Boolean;
    procedure SetShuffle(state: Boolean);
    function GetColorThemeIndex: Integer; // Получить текущую тему

    property OnOpenClick: TNotifyEvent read FOnOpenClick write FOnOpenClick;
    property OnExportClick: TNotifyEvent read FOnExportClick write FOnExportClick;
    property OnNewDriveClick:  TNotifyEvent read FOnNewDriveClick write FOnNewDriveClick;
    property OnAddFileClick:  TNotifyEvent read FOnAddFileClick write FOnAddFileClick;
    property OnDeleteFileClick: TNotifyEvent read FOnDeleteFileClick write FOnDeleteFileClick;
    property OnPreviousClick: TNotifyEvent read FOnPreviousClick write FOnPreviousClick;
    property OnPlayClick: TNotifyEvent read FOnPlayClick write FOnPlayClick;
    property OnPauseClick: TNotifyEvent read FOnPauseClick write FOnPauseClick;
    property OnStopClick: TNotifyEvent read FOnStopClick write FOnStopClick;
    property OnNextClick: TNotifyEvent read FOnNextClick write FOnNextClick;
    property OnLoopClick: TNotifyEvent read FOnLoopClick write FOnLoopClick;
    property OnShuffleClick: TNotifyEvent read FOnShuffleClick write FOnShuffleClick;
    property OnAboutClick: TNotifyEvent read FOnAboutClick write FOnAboutClick;
    property OnColorThemeChange: TNotifyEvent read FOnColorThemeChange write FOnColorThemeChange;
    property Height: Integer read FHeight;
    property DriveIsFull: Boolean read FDriveIsFull write FDriveIsFull;
  end;

implementation

constructor TToolbar.Create;
begin
  inherited Create;
  FHeight := 38;
  FLeft := 0;
  FTop := 0;
  FWidth := 0;
  FMargin := 0;
  FButtonLeftPadding := 10;
//  FLogoWidth := 80;
  FIsPlaying := False;
  FIsPaused := False;
  FHasDiskLoaded := False;
  FHasFileSelected := False;

  FButtonCount := 19;
  SetLength(FButtons, FButtonCount);
  FDriveIsFull := False;
  GuiEnableTooltip();


  {
  GuiSetStyle(TOGGLE, BORDER_WIDTH, 2);
  GuiSetStyle(BUTTON, BORDER_WIDTH, 2);
  GuiSetStyle(COMBOBOX, BORDER_WIDTH, 2);
  }

  // Button 0: Open (Normal)
  FButtons[0].IconId := ICON_FOLDER_FILE_OPEN;
  FButtons[0].Hint := 'Open disk image (Ctrl+O)';
  FButtons[0].ButtonType := btNormal;
  FButtons[0].IsPressed := False;

  // Button 1: Export (Normal)
  FButtons[1].IconId := ICON_FILE_EXPORT;
  FButtons[1].Hint := 'Export current file (Ctrl+E)';
  FButtons[1].ButtonType := btNormal;
  FButtons[1].IsPressed := False;

  // Button 2: Separator
  FButtons[2].IconId := 0;
  FButtons[2].Hint := '';
  FButtons[2].ButtonType := btSeparator;

  // Button 3: New Drive (Normal)
  FButtons[3].IconId := ICON_FILE_SAVE_CLASSIC;
  FButtons[3].Hint := 'Create a new TR-DOS disk (Ctrl+N)';
  FButtons[3].ButtonType := btNormal;
  FButtons[3].IsPressed := False;

  // Button 4: Add File (Normal)
  FButtons[4].IconId := ICON_FILE_ADD;
  FButtons[4].Hint := 'Adding file to drive (Ctrl+A)';
  FButtons[4].ButtonType := btNormal;
  FButtons[4].IsPressed := False;

  // Button 5: Delete File (Normal)
  FButtons[5].IconId := ICON_FILE_DELETE;
  FButtons[5].Hint := 'Delete file';
  FButtons[5].ButtonType := btNormal;
  FButtons[5].IsPressed := False;

  // Button 6: Separator
  FButtons[6].IconId := 0;
  FButtons[6].Hint := '';
  FButtons[6].ButtonType := btSeparator;

  // Button 7: Previous (Normal)
  FButtons[7].IconId := ICON_PLAYER_PREVIOUS;
  FButtons[7].Hint := 'Previous track (Ctrl+Left)';
  FButtons[7].ButtonType := btNormal;
  FButtons[7].IsPressed := False;

  // Button 8: Play (Normal)
  FButtons[8].IconId := ICON_PLAYER_PLAY;
  FButtons[8].Hint := 'Play (Space)';
  FButtons[8].ButtonType := btNormal;
  FButtons[8].IsPressed := False;

  // Button 9: Pause (Normal)
  FButtons[9].IconId := ICON_PLAYER_PAUSE;
  FButtons[9].Hint := 'Pause (Space)';
  FButtons[9].ButtonType := btNormal;
  FButtons[9].IsPressed := False;

  // Button 10: Stop (Normal)
  FButtons[10].IconId := ICON_PLAYER_STOP;
  FButtons[10].Hint := 'Stop (S)';
  FButtons[10].ButtonType := btNormal;
  FButtons[10].IsPressed := False;

  // Button 11: Next (Normal)
  FButtons[11].IconId := ICON_PLAYER_NEXT;
  FButtons[11].Hint := 'Next track (Ctrl+Right)';
  FButtons[11].ButtonType := btNormal;
  FButtons[11].IsPressed := False;

  // Button 12: Separator
  FButtons[12].IconId := 0;
  FButtons[12].Hint := '';
  FButtons[12].ButtonType := btSeparator;

  // Button 13: Loop (Toggle)
  FButtons[13].IconId := ICON_REPEAT_FILL;
  FButtons[13].Hint := 'Track Loop (Ctrl+L)';
  FButtons[13].ButtonType := btToggle;
  FButtons[13].ToggleState := False;

  // Button 14: Shuffle (Toggle)
  FButtons[14].IconId := ICON_SHUFFLE_FILL;
  FButtons[14].Hint := 'Shuffle (Ctrl+S)';
  FButtons[14].ButtonType := btToggle;
  FButtons[14].ToggleState := False;

  // Button 15: separator
  FButtons[15].IconId := 0;
  FButtons[15].Hint := '';
  FButtons[15].ButtonType := btSeparator;

  // Button 16: Color Theme (Combo)
  FButtons[16].IconId := 0;
  FButtons[16].Hint := 'Color Theme';
  FButtons[16].ButtonType := btCombo;
  FButtons[16].ComboIndex := 0;  // Индекс выбранной темы (0 - default)

   // Button 17: Separator
  FButtons[17].IconId := 0;
  FButtons[17].Hint := '';
  FButtons[17].ButtonType := btSeparator;

  // Button 11: Next (Normal)
  FButtons[18].IconId := ICON_INFO;
  FButtons[18].Hint := 'About';
  FButtons[18].ButtonType := btNormal;
  FButtons[18].IsPressed := False;
end;

destructor TToolbar.Destroy;
begin
  SetLength(FButtons, 0);
  inherited Destroy;
end;

procedure TToolbar.CalculateButtonsLayout;
var
  i: Integer;
  buttonWidth: Integer;
  buttonX: Integer;
  buttonMargin: Integer;
  maxButtonX: Integer;
begin
  if FWidth = 0 then Exit;

  buttonMargin := 5;
  buttonWidth := FHeight - 10;

  buttonX := FLeft + FMargin + FButtonLeftPadding;
  maxButtonX := FLeft + FMargin + FWidth  - 15;

  for i := 0 to FButtonCount - 1 do
  begin
    if FButtons[i].ButtonType = btSeparator then
    begin
      if buttonX + 10 <= maxButtonX then
      begin
        FButtons[i].Bounds := RectangleCreate(buttonX, FTop + 5, 10, buttonWidth);
        buttonX := buttonX + 10 + buttonMargin;
      end;
    end
    else
    begin
      // Для ComboBox делаем чуть шире
      if FButtons[i].ButtonType = btCombo then
      begin
        if buttonX + 65 <= maxButtonX then
        begin
          FButtons[i].Bounds := RectangleCreate(buttonX, FTop + 5, 65, buttonWidth);
          buttonX := buttonX + 65 + buttonMargin;
        end;
      end
      else
      begin
        if buttonX + buttonWidth <= maxButtonX then
        begin
          FButtons[i].Bounds := RectangleCreate(buttonX, FTop + 5, buttonWidth, buttonWidth);
          buttonX := buttonX + buttonWidth + buttonMargin;
        end;
      end;
    end;
  end;
end;

procedure TToolbar.DrawSeparator(const Bounds: TRectangle);
var
  lineX: Integer;
  TmpColor: TColorB;
begin
  lineX := Round(Bounds.X + Bounds.Width / 2);
  TmpColor := GetColor(GuiGetStyle(Default, BORDER_COLOR_NORMAL));
  DrawLine(lineX, Round(Bounds.Y + 2), lineX, Round(Bounds.Y + Bounds.Height - 2), TmpColor);
end;

procedure TToolbar.SetBounds(X, Y, Width, Height, Margin, ButtonPadding: Integer);
begin
  FLeft := X;
  FTop := Y;
  FWidth := Width;
  FHeight := Height;
  FMargin := Margin;
  FButtonLeftPadding := ButtonPadding;
  CalculateButtonsLayout;
end;

procedure TToolbar.SetPlaybackState(IsPlaying, IsPaused: Boolean);
begin
  FIsPlaying := IsPlaying;
  FIsPaused := IsPaused;
end;

procedure TToolbar.SetFileState(HasDiskLoaded, HasFileSelected: Boolean);
begin
  FHasDiskLoaded := HasDiskLoaded;
  FHasFileSelected := HasFileSelected;
end;

function TToolbar.IsLoopEnabled: Boolean;
begin
  Result := FButtons[13].ToggleState;
end;

procedure TToolbar.SetLoopEnabled(Loop: Boolean);
begin
  FButtons[13].ToggleState := Loop;
 // FButtons[14].ToggleState := not FButtons[13].ToggleState;
end;

function TToolbar.IsShuffleEnabled: Boolean;
begin
  Result := FButtons[14].ToggleState;
end;

procedure TToolbar.SetShuffle(state: Boolean);
begin
  FButtons[14].ToggleState := state;
 // FButtons[13].ToggleState := not FButtons[14].ToggleState;
end;

function TToolbar.GetColorThemeIndex: Integer;
begin
  Result := FButtons[16].ComboIndex;
end;

procedure TToolbar.Draw;
var
  i: Integer;
  btnRect: TRectangle;
  btnText: string;
  TmpColor: TColorB;
  OldToggleState: Boolean;
  OldComboIndex: Integer;
  comboItems: PChar;
begin
  Update;

  FWidth := GetRenderWidth - 20;
  TmpColor := GetColor(GuiGetStyle(Default, BASE_COLOR_NORMAL));
  DrawRectangle(FLeft + FMargin, FTop, FWidth, FHeight, TmpColor);

  TmpColor := GetColor(GuiGetStyle(Default, BORDER_COLOR_NORMAL));
  DrawRectangleLines(FLeft + FMargin, FTop, FWidth, FHeight, TmpColor);

  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);

  for i := 0 to FButtonCount - 1 do
  begin
    if FButtons[i].ButtonType = btSeparator then
    begin
      DrawSeparator(FButtons[i].Bounds);
      Continue;
    end;

    btnRect := FButtons[i].Bounds;

    if FButtons[i].Hint <> '' then
      GuiSetTooltip(PChar(FButtons[i].Hint));

    // Set button state based on application state and button type
    if FButtons[i].ButtonType = btToggle then
    begin
      GuiSetState(STATE_NORMAL);
    end
    else if FButtons[i].ButtonType = btCombo then
    begin
      GuiSetState(STATE_NORMAL);
    end
    else // btNormal
    begin
      case i of
        0: GuiSetState(STATE_NORMAL); // Open - always enabled
        1:
          begin
            if FHasFileSelected then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        3: GuiSetState(STATE_NORMAL); // NewDrive - always enabled
        4:
          begin
            if FHasDiskLoaded then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        5:
          begin
            if FHasFileSelected then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        7, 11: // Previous/Next - enabled only if disk loaded and file selected
          begin
            if (FHasDiskLoaded) and (FHasFileSelected) then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        8: // Play - enabled if file selected and not playing
          begin
            if FHasFileSelected and not FIsPlaying then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        9: // Pause - enabled only when playing
          begin
            if FIsPlaying and not FIsPaused then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        10: // Stop - enabled when playing or paused
          begin
            if FIsPlaying then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        else
          GuiSetState(STATE_NORMAL);
      end;
    end;

    btnText := Format('#%d#', [FButtons[i].IconId]);

    // Handle based on ButtonType
    case FButtons[i].ButtonType of
      btToggle:
        begin
          OldToggleState := FButtons[i].ToggleState;


          GuiToggle(btnRect, PChar(btnText), @FButtons[i].ToggleState);

          if OldToggleState <> FButtons[i].ToggleState then
          begin
            if i = 13 then
            begin
              if Assigned(FOnLoopClick) then
                FOnLoopClick(Self);
            end
            else if i = 14 then
            begin
              if Assigned(FOnShuffleClick) then
                FOnShuffleClick(Self);
            end;
          end;
        end;

      btNormal:
        begin
          if GuiButton(btnRect, PChar(btnText)) <> 0 then
          begin
            if not FButtons[i].IsPressed then
            begin
              FButtons[i].IsPressed := True;

              case i of
                0: if Assigned(FOnOpenClick) then FOnOpenClick(Self);
                1: if Assigned(FOnExportClick) then FOnExportClick(Self);
                3: if Assigned(FOnNewDriveClick) then FOnNewDriveClick(Self);
                4: if Assigned(FOnAddFileClick) then FOnAddFileClick(Self);
                5: if Assigned(FOnDeleteFileClick) then FOnDeleteFileClick(Self);
                7: if Assigned(FOnPreviousClick) then FOnPreviousClick(Self);
                8: if Assigned(FOnPlayClick) then FOnPlayClick(Self);
                9: if Assigned(FOnPauseClick) then FOnPauseClick(Self);
                10: if Assigned(FOnStopClick) then FOnStopClick(Self);
                11: if Assigned(FOnNextClick) then FOnNextClick(Self);
                18: if  Assigned(FOnAboutClick) then FOnAboutClick(Self);
              end;
            end;
          end
          else
          begin
            FButtons[i].IsPressed := False;
          end;
        end;

      btCombo:
        begin
          // Список тем для выбора
          comboItems := '#25#;#25#;#25#;#25#;#25#;#25#;#25#';//;Bluish;Cyber;Terminal';

          // Сохраняем старое значение
          OldComboIndex := FButtons[i].ComboIndex;

          // Выравнивание текста для комбобокса
       //   GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_LEFT);

          // Отрисовка комбобокса с передачей указателя на индекс
          GuiComboBox(btnRect, comboItems, @FButtons[i].ComboIndex);

          // Возвращаем выравнивание обратно
        //  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);

          // Если индекс изменился, вызываем событие
          if (OldComboIndex <> FButtons[i].ComboIndex) and Assigned(FOnColorThemeChange) then
          begin
            FOnColorThemeChange(Self);
          end;
        end;
    end;
  end;

  GuiSetTooltip(nil);
  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_LEFT);
end;

procedure TToolbar.Update;
begin
  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_RIGHT) then
  begin
     if Assigned(FOnNextClick) and (not GuiIsLocked) then FOnNextClick(Self);
  end;

  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_LEFT) then
  begin
    if Assigned(FOnPreviousClick) and (not GuiIsLocked) then FOnPreviousClick(Self);
  end;

  if IsKeyPressed(KEY_S) and (not GuiIsLocked) then
  begin
     if Assigned(FOnStopClick) then FOnStopClick(Self);
  end;

  if IsKeyPressed(KEY_SPACE) and (not GuiIsLocked) then
  begin
    if FIsPaused and Assigned(FOnPlayClick) then FOnPlayClick(Self)
    else if FIsPlaying and Assigned(FOnPauseClick) then FOnPauseClick(Self);
  end;

  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_E) then
  begin
    if Assigned(FOnExportClick) and (not GuiIsLocked) then FOnExportClick(Self);
  end;

  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_O) then
  begin
    if Assigned(FOnOpenClick) and (not GuiIsLocked) then FOnOpenClick(Self);
  end;

  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_N) then
  begin
    if Assigned(FOnNewDriveClick) and (not GuiIsLocked) then FOnNewDriveClick(Self);
  end;

  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_A) then
  begin
    if Assigned(FOnAddFileClick) and (not GuiIsLocked) then FOnAddFileClick(Self);
  end;

  // Shortcut for Loop toggle
  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_L) then
  begin
    if not GuiIsLocked then
    begin
      FButtons[13].ToggleState := not FButtons[13].ToggleState;
      if Assigned(FOnLoopClick) then FOnLoopClick(Self);
    end;
  end;

  // Shortcut for Shuffle toggle (Ctrl+S)
  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_S) then
  begin
    if not GuiIsLocked then
    begin
      FButtons[14].ToggleState := not FButtons[14].ToggleState;
      if Assigned(FOnShuffleClick) then FOnShuffleClick(Self);
    end;
  end;
end;

end.
