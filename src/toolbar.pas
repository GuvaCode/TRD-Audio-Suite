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
    // FOnNewDriveClick удалено
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
    procedure SetColorThemeIndex(Indx: Integer);
    property OnOpenClick: TNotifyEvent read FOnOpenClick write FOnOpenClick;
    property OnExportClick: TNotifyEvent read FOnExportClick write FOnExportClick;
    // property OnNewDriveClick удалено
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

  FButtonCount := 18;  // Было 19, стало 18 (удалили кнопку New Drive)
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

  // Кнопка New Drive (индекс 3) УДАЛЕНА

  // Button 3: Add File (Normal) - теперь индекс 3 (был 4)
  FButtons[3].IconId := ICON_FILE_ADD;
  FButtons[3].Hint := 'Adding file to drive (Ctrl+A)';
  FButtons[3].ButtonType := btNormal;
  FButtons[3].IsPressed := False;

  // Button 4: Delete File (Normal) - теперь индекс 4 (был 5)
  FButtons[4].IconId := ICON_FILE_DELETE;
  FButtons[4].Hint := 'Delete file';
  FButtons[4].ButtonType := btNormal;
  FButtons[4].IsPressed := False;

  // Button 5: Separator - теперь индекс 5 (был 6)
  FButtons[5].IconId := 0;
  FButtons[5].Hint := '';
  FButtons[5].ButtonType := btSeparator;

  // Button 6: Previous (Normal) - теперь индекс 6 (был 7)
  FButtons[6].IconId := ICON_PLAYER_PREVIOUS;
  FButtons[6].Hint := 'Previous track (Ctrl+Left)';
  FButtons[6].ButtonType := btNormal;
  FButtons[6].IsPressed := False;

  // Button 7: Play (Normal) - теперь индекс 7 (был 8)
  FButtons[7].IconId := ICON_PLAYER_PLAY;
  FButtons[7].Hint := 'Play (Space)';
  FButtons[7].ButtonType := btNormal;
  FButtons[7].IsPressed := False;

  // Button 8: Pause (Normal) - теперь индекс 8 (был 9)
  FButtons[8].IconId := ICON_PLAYER_PAUSE;
  FButtons[8].Hint := 'Pause (Space)';
  FButtons[8].ButtonType := btNormal;
  FButtons[8].IsPressed := False;

  // Button 9: Stop (Normal) - теперь индекс 9 (был 10)
  FButtons[9].IconId := ICON_PLAYER_STOP;
  FButtons[9].Hint := 'Stop (S)';
  FButtons[9].ButtonType := btNormal;
  FButtons[9].IsPressed := False;

  // Button 10: Next (Normal) - теперь индекс 10 (был 11)
  FButtons[10].IconId := ICON_PLAYER_NEXT;
  FButtons[10].Hint := 'Next track (Ctrl+Right)';
  FButtons[10].ButtonType := btNormal;
  FButtons[10].IsPressed := False;

  // Button 11: Separator - теперь индекс 11 (был 12)
  FButtons[11].IconId := 0;
  FButtons[11].Hint := '';
  FButtons[11].ButtonType := btSeparator;

  // Button 12: Loop (Toggle) - теперь индекс 12 (был 13)
  FButtons[12].IconId := ICON_REPEAT_FILL;
  FButtons[12].Hint := 'Track Loop';
  FButtons[12].ButtonType := btToggle;
  FButtons[12].ToggleState := False;

  // Button 13: Shuffle (Toggle) - теперь индекс 13 (был 14)
  FButtons[13].IconId := ICON_SHUFFLE_FILL;
  FButtons[13].Hint := 'Shuffle';
  FButtons[13].ButtonType := btToggle;
  FButtons[13].ToggleState := False;

  // Button 14: separator - теперь индекс 14 (был 15)
  FButtons[14].IconId := 0;
  FButtons[14].Hint := '';
  FButtons[14].ButtonType := btSeparator;

  // Button 15: Color Theme (Combo) - теперь индекс 15 (был 16)
  FButtons[15].IconId := 0;
  FButtons[15].Hint := 'Color Theme';
  FButtons[15].ButtonType := btCombo;
  FButtons[15].ComboIndex := 0;  // Индекс выбранной темы (0 - default)

   // Button 16: Separator - теперь индекс 16 (был 17)
  FButtons[16].IconId := 0;
  FButtons[16].Hint := '';
  FButtons[16].ButtonType := btSeparator;

  // Button 17: About (Normal) - теперь индекс 17 (был 18)
  FButtons[17].IconId := ICON_INFO;
  FButtons[17].Hint := 'About';
  FButtons[17].ButtonType := btNormal;
  FButtons[17].IsPressed := False;
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
  Result := FButtons[12].ToggleState;  // Индекс 12 вместо 13
end;

procedure TToolbar.SetLoopEnabled(Loop: Boolean);
begin
  FButtons[12].ToggleState := Loop;  // Индекс 12 вместо 13
end;

function TToolbar.IsShuffleEnabled: Boolean;
begin
  Result := FButtons[13].ToggleState;  // Индекс 13, не меняется
end;

procedure TToolbar.SetShuffle(state: Boolean);
begin
  FButtons[13].ToggleState := state;  // Индекс 13, не меняется
end;

function TToolbar.GetColorThemeIndex: Integer;
begin
  Result := FButtons[15].ComboIndex;  // Индекс 15 вместо 16
end;

procedure TToolbar.SetColorThemeIndex(Indx: Integer);
begin
  FButtons[15].ComboIndex := Indx;  // Индекс 15 вместо 16
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
        // Кнопка New Drive (была индекс 3) - полностью удалена, индексы сдвинулись
        3: // Add File (новый индекс 3)
          begin
            if FHasDiskLoaded then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        4: // Delete File (новый индекс 4)
          begin
            if FHasFileSelected then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        6, 10: // Previous (индекс 6) / Next (индекс 10) - enabled only if disk loaded and file selected
          begin
            if (FHasDiskLoaded) and (FHasFileSelected) then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        7: // Play (индекс 7) - enabled if file selected and not playing
          begin
            if FHasFileSelected and not FIsPlaying then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        8: // Pause (индекс 8) - enabled only when playing
          begin
            if FIsPlaying and not FIsPaused then
              GuiSetState(STATE_NORMAL)
            else
              GuiSetState(STATE_DISABLED);
          end;
        9: // Stop (индекс 9) - enabled when playing or paused
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
            if i = 12 then  // Loop (новый индекс 12)
            begin
              if Assigned(FOnLoopClick) then
                FOnLoopClick(Self);
            end
            else if i = 13 then  // Shuffle (индекс 13)
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
                // 2: Separator (пропускаем)
                // Кнопка New Drive (была индекс 3) УДАЛЕНА
                3: if Assigned(FOnAddFileClick) then FOnAddFileClick(Self);    // Add File
                4: if Assigned(FOnDeleteFileClick) then FOnDeleteFileClick(Self); // Delete File
                // 5: Separator (пропускаем)
                6: if Assigned(FOnPreviousClick) then FOnPreviousClick(Self);  // Previous
                7: if Assigned(FOnPlayClick) then FOnPlayClick(Self);          // Play
                8: if Assigned(FOnPauseClick) then FOnPauseClick(Self);        // Pause
                9: if Assigned(FOnStopClick) then FOnStopClick(Self);          // Stop
                10: if Assigned(FOnNextClick) then FOnNextClick(Self);         // Next
                // 11: Separator (пропускаем)
                // 12: Loop (Toggle, пропускаем)
                // 13: Shuffle (Toggle, пропускаем)
                // 14: Separator (пропускаем)
                // 15: Color Theme (Combo, пропускаем)
                // 16: Separator (пропускаем)
                17: if Assigned(FOnAboutClick) then FOnAboutClick(Self);       // About
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

  // Удален обработчик Ctrl+N для New Drive

  if (IsKeyDown(KEY_RIGHT_CONTROL) or IsKeyDown(KEY_LEFT_CONTROL)) and IsKeyPressed(KEY_A) then
  begin
    if Assigned(FOnAddFileClick) and (not GuiIsLocked) then FOnAddFileClick(Self);
  end;
end;

end.
