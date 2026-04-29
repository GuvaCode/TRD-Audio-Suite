unit gui_window_visualizer_settings;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$packrecords c}

interface

uses
  raylib, raygui, extratools, SpectrumVisualizer, TuneZXPlayer,
  SysUtils, Classes;

type
  PGuiWindowVisSettingsState = ^TGuiWindowVisSettingsState;
  TGuiWindowVisSettingsState = record
    windowActive: Boolean;
    windowBounds: TRectangle;
    panOffset: TVector2;
    dragMode: Boolean;
    supportDrag: Boolean;

    // Настройки визуализатора (хранятся как float для слайдеров)
    barWidth: Single;      // 0 = auto, 1-20
    barSpacing: Single;    // 0-8
    decaySpeed: Single;    // 0.5-5.0
    holdTime: Single;      // 0.1-2.0

    // Настройки спектроанализатора
    smoothing: Single;     // 0.3-0.98
    attackTime: Single;    // 0.01-0.5
    releaseTime: Single;   // 0.05-1.0
    sensitivity: Single;   // 0.3-3.0
    highBoost: Single;     // 0.5-2.5
    lowBoost: Single;      // 0.5-2.5
  end;

function InitGuiWindowVisSettings: TGuiWindowVisSettingsState;
procedure GuiWindowVisSettings(var state: TGuiWindowVisSettingsState; visualizer: TSpectrumVisualizer; Player: TZXTunePlayer);
procedure GuiWindowVisResetSettings(var state: TGuiWindowVisSettingsState; visualizer: TSpectrumVisualizer; Player: TZXTunePlayer);

// Процедуры для сохранения и загрузки настроек
procedure SaveVisualizerSettings(const state: TGuiWindowVisSettingsState; const filename: string = 'visualizer_settings.ini');
function LoadVisualizerSettings(var state: TGuiWindowVisSettingsState; const filename: string = 'visualizer_settings.ini'): Boolean;
procedure ApplySettingsToVisualizer(const state: TGuiWindowVisSettingsState; visualizer: TSpectrumVisualizer; Player: TZXTunePlayer);

implementation

uses
  Math, IniFiles;

//============================================================================
//  PRIVATE CONSTANTS
//============================================================================

const
  WINDOW_WIDTH = 370;
  WINDOW_HEIGHT = 380;

  // Отступы
  MARGIN = 18;
  ROW_HEIGHT = 22;
  LABEL_WIDTH = 100;
  SLIDER_WIDTH = 180;
  GROUP_TOP_OFFSET = 18;

  // Диапазоны для визуализатора
  BAR_WIDTH_MIN = 1;
  BAR_WIDTH_MAX = 20;

  BAR_SPACING_MIN = 1;
  BAR_SPACING_MAX = 8;

  DECAY_SPEED_MIN = 0.5;
  DECAY_SPEED_MAX = 5.0;

  HOLD_TIME_MIN = 0.1;
  HOLD_TIME_MAX = 2.0;

  // Диапазоны для спектроанализатора
  SMOOTHING_MIN = 0.3;
  SMOOTHING_MAX = 0.98;

  ATTACK_MIN = 0.01;
  ATTACK_MAX = 0.5;

  RELEASE_MIN = 0.05;
  RELEASE_MAX = 1.0;

  SENSITIVITY_MIN = 0.3;
  SENSITIVITY_MAX = 3.0;

  BOOST_MIN = 0.5;
  BOOST_MAX = 2.5;

  // Тексты
  BTN_CLOSE = '#159#Close';
  BTN_RESET = '#56#Reset';

  // Секции INI файла
  INI_SECTION_VISUALIZER = 'Visualizer';
  INI_SECTION_SPECTRUM = 'SpectrumAnalyzer';

//============================================================================
//  PRIVATE FUNCTIONS
//============================================================================

function GetWindowCenterX(width: Integer): Integer;
begin
  Result := (GetScreenWidth div 2) - (width div 2);
end;

function GetWindowCenterY(height: Integer): Integer;
begin
  Result := (GetScreenHeight div 2) - (height div 2);
end;

function BarWidthToStr(value: Single): string;
begin
  if Round(value) = 0 then
    Result := 'auto'
  else
    Result := IntToStr(Round(value)) + 'px';
end;

function FloatToStr2(value: Single): string;
begin
  Result := Format('%.2f', [value]);
end;

//============================================================================
//  PUBLIC FUNCTIONS
//============================================================================

function InitGuiWindowVisSettings: TGuiWindowVisSettingsState;
begin
  Result.windowActive := False;
  Result.windowBounds := RectangleCreate(
    GetWindowCenterX(WINDOW_WIDTH),
    GetWindowCenterY(WINDOW_HEIGHT),
    WINDOW_WIDTH, WINDOW_HEIGHT
  );
  Result.panOffset := Vector2Create(0, 0);
  Result.dragMode := False;
  Result.supportDrag := True;
  {
  // Значения по умолчанию для визуализатора
  Result.barWidth := 0;
  Result.barSpacing := 2;
  Result.decaySpeed := 1.5;
  Result.holdTime := 0.5;

  // Значения по умолчанию для спектроанализатора
  Result.smoothing := 0.85;
  Result.attackTime := 0.03;
  Result.releaseTime := 0.2;
  Result.sensitivity := 1.0;
  Result.highBoost := 1.0;
  Result.lowBoost := 1.0;
 }

 // Значения по умолчанию для визуализатора
 Result.barWidth := 2;
 Result.barSpacing := 1;
 Result.decaySpeed := 0.5;
 Result.holdTime := 0.1;

 // Значения по умолчанию для спектроанализатора
 Result.smoothing := 0.85;
 Result.attackTime := 0.20;
 Result.releaseTime := 0.57;
 Result.sensitivity := 1.0;
 Result.highBoost := 1.0;
 Result.lowBoost := 1.0;



end;

// Сохранение настроек в INI файл
procedure SaveVisualizerSettings(const state: TGuiWindowVisSettingsState; const filename: string = 'visualizer_settings.ini');
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetApplicationDirectory + filename);
  try
    // Сохраняем настройки визуализатора
    Ini.WriteFloat(INI_SECTION_VISUALIZER, 'BarWidth', state.barWidth);
    Ini.WriteFloat(INI_SECTION_VISUALIZER, 'BarSpacing', state.barSpacing);
    Ini.WriteFloat(INI_SECTION_VISUALIZER, 'DecaySpeed', state.decaySpeed);
    Ini.WriteFloat(INI_SECTION_VISUALIZER, 'HoldTime', state.holdTime);

    // Сохраняем настройки спектроанализатора
    Ini.WriteFloat(INI_SECTION_SPECTRUM, 'Smoothing', state.smoothing);
    Ini.WriteFloat(INI_SECTION_SPECTRUM, 'AttackTime', state.attackTime);
    Ini.WriteFloat(INI_SECTION_SPECTRUM, 'ReleaseTime', state.releaseTime);
    Ini.WriteFloat(INI_SECTION_SPECTRUM, 'Sensitivity', state.sensitivity);
    Ini.WriteFloat(INI_SECTION_SPECTRUM, 'HighBoost', state.highBoost);
    Ini.WriteFloat(INI_SECTION_SPECTRUM, 'LowBoost', state.lowBoost);
  finally
    Ini.Free;
  end;
end;

// Загрузка настроек из INI файла
function LoadVisualizerSettings(var state: TGuiWindowVisSettingsState; const filename: string = 'visualizer_settings.ini'): Boolean;
var
  Ini: TIniFile;
  fullPath: string;
begin
  fullPath := GetApplicationDirectory + filename;
  Result := FileExists(fullPath);

  if not Result then
    Exit;

  Ini := TIniFile.Create(fullPath);
  try
    // Загружаем настройки визуализатора
    state.barWidth := Ini.ReadFloat(INI_SECTION_VISUALIZER, 'BarWidth', state.barWidth);
    state.barSpacing := Ini.ReadFloat(INI_SECTION_VISUALIZER, 'BarSpacing', state.barSpacing);
    state.decaySpeed := Ini.ReadFloat(INI_SECTION_VISUALIZER, 'DecaySpeed', state.decaySpeed);
    state.holdTime := Ini.ReadFloat(INI_SECTION_VISUALIZER, 'HoldTime', state.holdTime);

    // Загружаем настройки спектроанализатора
    state.smoothing := Ini.ReadFloat(INI_SECTION_SPECTRUM, 'Smoothing', state.smoothing);
    state.attackTime := Ini.ReadFloat(INI_SECTION_SPECTRUM, 'AttackTime', state.attackTime);
    state.releaseTime := Ini.ReadFloat(INI_SECTION_SPECTRUM, 'ReleaseTime', state.releaseTime);
    state.sensitivity := Ini.ReadFloat(INI_SECTION_SPECTRUM, 'Sensitivity', state.sensitivity);
    state.highBoost := Ini.ReadFloat(INI_SECTION_SPECTRUM, 'HighBoost', state.highBoost);
    state.lowBoost := Ini.ReadFloat(INI_SECTION_SPECTRUM, 'LowBoost', state.lowBoost);
  finally
    Ini.Free;
  end;
end;

// Применение загруженных настроек к визуализатору и плееру
procedure ApplySettingsToVisualizer(const state: TGuiWindowVisSettingsState;
  visualizer: TSpectrumVisualizer; Player: TZXTunePlayer);
begin
  // Применяем настройки визуализатора
  if Round(state.barWidth) = 0 then
    visualizer.BarWidth := 0
  else
    visualizer.BarWidth := Round(state.barWidth);
  visualizer.BarSpacing := Round(state.barSpacing);
  visualizer.DecaySpeed := state.decaySpeed;
  visualizer.HoldTime := state.holdTime;

  // Применяем настройки спектроанализатора
  Player.SetFFTSmoothing(state.smoothing);
  Player.SetFFTAttack(state.attackTime);
  Player.SetFFTRelease(state.releaseTime);
  Player.SetFFTSensitivity(state.sensitivity);
  Player.SetFFTBoost(state.highBoost, state.lowBoost);
end;

procedure GuiWindowVisSettings(var state: TGuiWindowVisSettingsState; visualizer: TSpectrumVisualizer; Player: TZXTunePlayer);
var
  mousePosition: TVector2;
  y: Integer;
  labelX, sliderX: Integer;
  oldWidth, oldSpacing, oldDecay, oldHold: Single;
  oldSmoothing, oldAttack, oldRelease, oldSensitivity, oldHighBoost, oldLowBoost: Single;
  intValue: Integer;
  groupBounds: TRectangle;
begin
  if not state.windowActive then
  begin
    state.windowBounds.x := GetWindowCenterX(Round(state.windowBounds.width));
    state.windowBounds.y := GetWindowCenterY(Round(state.windowBounds.height));
    Exit;
  end;

  // Drag and drop для окна
  if state.supportDrag then
  begin
    mousePosition := GetMousePosition;

    if IsMouseButtonPressed(MOUSE_LEFT_BUTTON) then
    begin
      if CheckCollisionPointRec(mousePosition, RectangleCreate(
        state.windowBounds.x,
        state.windowBounds.y,
        state.windowBounds.width,
        RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT
      )) then
      begin
        state.dragMode := True;
        state.panOffset.x := mousePosition.x - state.windowBounds.x;
        state.panOffset.y := mousePosition.y - state.windowBounds.y;
      end;
    end;

    if state.dragMode then
    begin
      state.windowBounds.x := mousePosition.x - state.panOffset.x;
      state.windowBounds.y := mousePosition.y - state.panOffset.y;

      if state.windowBounds.x < 0 then
        state.windowBounds.x := 0
      else if state.windowBounds.x > (GetScreenWidth() - state.windowBounds.width) then
        state.windowBounds.x := GetScreenWidth() - state.windowBounds.width;

      if state.windowBounds.y < 40 then
        state.windowBounds.y := 40
      else if state.windowBounds.y > (GetScreenHeight() - state.windowBounds.height - 24) then
        state.windowBounds.y := GetScreenHeight() - state.windowBounds.height - 24;

      if IsMouseButtonReleased(MOUSE_LEFT_BUTTON) then
        state.dragMode := False;
    end;
  end;

  // Отрисовка окна
  state.windowActive := not (GuiWindowBox(state.windowBounds, PChar('#191#Visualizer & Spectrum Settings')) = 1);

  // Координаты для элементов
  labelX := Round(state.windowBounds.x) + MARGIN + 10;
  sliderX := labelX + LABEL_WIDTH;
  y := Round(state.windowBounds.y) + RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT + MARGIN;

  // ========================================================================
  // Группа: Настройки визуализатора
  // ========================================================================
  groupBounds := RectangleCreate(
    state.windowBounds.x + MARGIN,
    y,
    state.windowBounds.width - MARGIN * 2,
    110
  );
  GuiGroupBox(groupBounds, PChar('Visualizer Settings'));
  y := y + GROUP_TOP_OFFSET;

  // Bar Width
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Bar Width:');
  oldWidth := state.barWidth;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(BarWidthToStr(state.barWidth)),
            @state.barWidth, BAR_WIDTH_MIN, BAR_WIDTH_MAX);
  if oldWidth <> state.barWidth then
  begin
    intValue := Round(state.barWidth);
    if intValue = 0 then
      visualizer.BarWidth := 0
    else
      visualizer.BarWidth := intValue;
  end;

  y := y + ROW_HEIGHT;

  // Bar Spacing
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Bar Spacing:');
  oldSpacing := state.barSpacing;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(IntToStr(Round(state.barSpacing)) + 'px'),
            @state.barSpacing, BAR_SPACING_MIN, BAR_SPACING_MAX);
  if oldSpacing <> state.barSpacing then
    visualizer.BarSpacing := Round(state.barSpacing);

  y := y + ROW_HEIGHT;

  // Decay Speed
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Decay Speed:');
  oldDecay := state.decaySpeed;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(Format('%.1f', [state.decaySpeed])),
            @state.decaySpeed, DECAY_SPEED_MIN, DECAY_SPEED_MAX);
  if Abs(oldDecay - state.decaySpeed) > 0.01 then
    visualizer.DecaySpeed := state.decaySpeed;

  y := y + ROW_HEIGHT;

  // Hold Time
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Hold Time:');
  oldHold := state.holdTime;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(Format('%.2f', [state.holdTime])),
            @state.holdTime, HOLD_TIME_MIN, HOLD_TIME_MAX);
  if Abs(oldHold - state.holdTime) > 0.01 then
    visualizer.HoldTime := state.holdTime;

  y := y + ROW_HEIGHT + MARGIN;

  // ========================================================================
  // Группа: Настройки спектроанализатора
  // ========================================================================
  groupBounds := RectangleCreate(
    state.windowBounds.x + MARGIN,
    y,
    state.windowBounds.width - MARGIN * 2,
    160
  );
  GuiGroupBox(groupBounds, PChar('Spectrum Analyzer Settings'));
  y := y + GROUP_TOP_OFFSET;

  // Smoothing
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Smoothing:');
  oldSmoothing := state.smoothing;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(FloatToStr2(state.smoothing)),
            @state.smoothing, SMOOTHING_MIN, SMOOTHING_MAX);
  if Abs(oldSmoothing - state.smoothing) > 0.01 then
    player.SetFFTSmoothing(state.smoothing);

  y := y + ROW_HEIGHT;

  // Attack Time
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Attack Time:');
  oldAttack := state.attackTime;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(FloatToStr2(state.attackTime) + 's'),
            @state.attackTime, ATTACK_MIN, ATTACK_MAX);
  if Abs(oldAttack - state.attackTime) > 0.01 then
    player.SetFFTAttack(state.attackTime);

  y := y + ROW_HEIGHT;

  // Release Time
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Release Time:');
  oldRelease := state.releaseTime;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(FloatToStr2(state.releaseTime) + 's'),
            @state.releaseTime, RELEASE_MIN, RELEASE_MAX);
  if Abs(oldRelease - state.releaseTime) > 0.01 then
    player.SetFFTRelease(state.releaseTime);

  y := y + ROW_HEIGHT;

  // Sensitivity
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Sensitivity:');
  oldSensitivity := state.sensitivity;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(Format('%.1f', [state.sensitivity])),
            @state.sensitivity, SENSITIVITY_MIN, SENSITIVITY_MAX);
  if Abs(oldSensitivity - state.sensitivity) > 0.01 then
    player.SetFFTSensitivity(state.sensitivity);

  y := y + ROW_HEIGHT;

  // Low Frequency Boost
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'Low Boost:');
  oldLowBoost := state.lowBoost;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(FloatToStr2(state.lowBoost) + 'x'),
            @state.lowBoost, BOOST_MIN, BOOST_MAX);
  if Abs(oldLowBoost - state.lowBoost) > 0.01 then
    player.SetFFTBoost(state.highBoost, state.lowBoost);

  y := y + ROW_HEIGHT;

  // High Frequency Boost
  GuiLabel(RectangleCreate(labelX, y, LABEL_WIDTH, 16), 'High Boost:');
  oldHighBoost := state.highBoost;
  GuiSlider(RectangleCreate(sliderX, y, SLIDER_WIDTH, 16),
            nil, PChar(FloatToStr2(state.highBoost) + 'x'),
            @state.highBoost, BOOST_MIN, BOOST_MAX);
  if Abs(oldHighBoost - state.highBoost) > 0.01 then
    player.SetFFTBoost(state.highBoost, state.lowBoost);

  // Кнопки внизу
  y := Round(state.windowBounds.y + state.windowBounds.height - 45);
  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);
  // Reset
  if GuiButton(RectangleCreate(state.windowBounds.x + MARGIN, y, 70, 28), BTN_RESET) = 1 then
  begin
    GuiWindowVisResetSettings(state, visualizer, player);
  end;

  // Close
  if GuiButton(RectangleCreate(state.windowBounds.x + state.windowBounds.width - MARGIN - 70, y, 70, 28), BTN_CLOSE) = 1 then
    state.windowActive := False;

  GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_LEFT);
end;

procedure GuiWindowVisResetSettings(var state: TGuiWindowVisSettingsState;
  visualizer: TSpectrumVisualizer; Player: TZXTunePlayer);
begin
  // Сброс визуализатора
  state.barWidth := 2;
  state.barSpacing := 1;
  state.decaySpeed := 0.5;
  state.holdTime := 0.1;

  visualizer.BarWidth := Round(state.barWidth);
  visualizer.BarSpacing := Round(state.barSpacing);
  visualizer.DecaySpeed := state.decaySpeed;
  visualizer.HoldTime := state.holdTime;

  // Сброс спектроанализатора
  state.smoothing := 0.85;
  state.attackTime := 0.20;
  state.releaseTime := 0.57;
  state.sensitivity := 1.0;
  state.highBoost := 1.0;
  state.lowBoost := 1.0;

  player.SetFFTSmoothing(state.smoothing);
  player.SetFFTAttack(state.attackTime);
  player.SetFFTRelease(state.releaseTime);
  player.SetFFTSensitivity(state.sensitivity);
  player.SetFFTBoost(state.highBoost, state.lowBoost);
end;

end.
