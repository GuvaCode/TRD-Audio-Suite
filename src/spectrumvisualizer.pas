unit SpectrumVisualizer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, raylib, Math;

type

  { TSpectrumVisualizer }

  TSpectrumVisualizer = class
  private
    FLabelColor: TColor;
    FLeft: Integer;
    FTop: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FBarWidth: Integer;        // Фиксированная ширина полоски (0 = авто)
    FBarSpacing: Integer;
    FBackgroundColor: TColor;
    FBarColor: TColor;
    FPeakColor: TColor;
    FBarCount: Integer;
    FPeakHold: array of Single;
    FPeakDecayTimer: array of Double;
    FLastUpdateTime: Double;
    FDecaySpeed: Single;
    FHoldTime: Single;
    FShowGrid: Boolean;
    FShowLabels: Boolean;
    FBarStyle: Integer;        // 0 = прямоугольные, 1 = с закруглением, 2 = треугольные
    FGradientMode: Boolean;    // Градиентная заливка полосок
  public
    constructor Create;
    procedure Draw(SpectrumData: PSingle; SpectrumSize: Integer);
    procedure ResetPeaks;

    // Настройки позиции
    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;

    // Настройки внешнего вида
    property BarWidth: Integer read FBarWidth write FBarWidth;        // 0 = авто, >0 = фиксированная
    property BarSpacing: Integer read FBarSpacing write FBarSpacing;
    property BackgroundColor: TColor read FBackgroundColor write FBackgroundColor;
    property LabelColor: TColor read FLabelColor write FLabelColor;
    property BarColor: TColor read FBarColor write FBarColor;
    property PeakColor: TColor read FPeakColor write FPeakColor;
    property ShowGrid: Boolean read FShowGrid write FShowGrid;
    property ShowLabels: Boolean read FShowLabels write FShowLabels;

    property BarStyle: Integer read FBarStyle write FBarStyle;        // 0,1,2
    property GradientMode: Boolean read FGradientMode write FGradientMode;

    // Настройки поведения
    property DecaySpeed: Single read FDecaySpeed write FDecaySpeed;
    property HoldTime: Single read FHoldTime write FHoldTime;
  end;

implementation

constructor TSpectrumVisualizer.Create;
begin
  inherited Create;
  FLeft := 0;
  FTop := 0;
  FWidth := 400;
  FHeight := 100;
  FBarWidth := 0;          // 0 = авто-подбор
  FBarSpacing := 2;
  FBackgroundColor := ColorFromNormalized(Vector4Create(0.1, 0.1, 0.1, 1.0));
  FBarColor := DARKGREEN;
  FPeakColor := PEACHPUFF;
  FLabelColor := RayWhite;
  FBarCount := 0;
  FLastUpdateTime := 0;
  FDecaySpeed := 1.5;
  FHoldTime := 0.5;
  FShowGrid := True;
  FShowLabels := True;
  FBarStyle := 0;
  FGradientMode := True;
end;

procedure TSpectrumVisualizer.ResetPeaks;
var
  i: Integer;
begin
  for i := 0 to FBarCount - 1 do
  begin
    FPeakHold[i] := 0;
    FPeakDecayTimer[i] := 0;
  end;
end;

procedure TSpectrumVisualizer.Draw(SpectrumData: PSingle; SpectrumSize: Integer);
var
  i, barIndex: Integer;
  barHeight, peakHeight: Integer;
  barX, barY: Integer;
  actualBarWidth: Integer;
  numBars: Integer;
  value: Single;
  currentTime: Double;
  deltaTime: Single;
  gradientColor: TColor;
  intensity: Single;
  barRect: TRectangle;
begin
  if (SpectrumData = nil) or (SpectrumSize = 0) then
    Exit;

  currentTime := GetTime();
  if FLastUpdateTime = 0 then
    FLastUpdateTime := currentTime;

  deltaTime := currentTime - FLastUpdateTime;

  if deltaTime > 0.033 then
    deltaTime := 0.033;
  if deltaTime < 0.001 then
    deltaTime := 0.016;

  FLastUpdateTime := currentTime;

  // Расчет количества столбцов
  if FBarWidth > 0 then
  begin
    // Фиксированная ширина полосок
    actualBarWidth := FBarWidth;
    numBars := FWidth div (actualBarWidth + FBarSpacing);
    if numBars < 1 then
      numBars := 1;
    if numBars > SpectrumSize then
      numBars := SpectrumSize;
  end
  else
  begin
    // Автоматический подбор ширины
    numBars := SpectrumSize;
    actualBarWidth := (FWidth - (numBars - 1) * FBarSpacing) div numBars;
    if actualBarWidth < 1 then
    begin
      actualBarWidth := 1;
      numBars := FWidth div (actualBarWidth + FBarSpacing);
    end;
    if numBars > SpectrumSize then
      numBars := SpectrumSize;
  end;

  // Инициализация массивов если изменилось количество столбцов
  if numBars <> FBarCount then
  begin
    FBarCount := numBars;
    SetLength(FPeakHold, FBarCount);
    SetLength(FPeakDecayTimer, FBarCount);
    for i := 0 to FBarCount - 1 do
    begin
      FPeakHold[i] := 0;
      FPeakDecayTimer[i] := 0;
    end;
  end;

  // Ограничиваем минимальную ширину
  if actualBarWidth < 1 then
    actualBarWidth := 1;
  if actualBarWidth > 20 then
    actualBarWidth := 20;

  // Рисуем фон
  DrawRectangle(FLeft, FTop, FWidth, FHeight, FBackgroundColor);

  // Рисуем сетку
  if FShowGrid then
  begin
    for i := 1 to 4 do
    begin
      DrawLine(FLeft, FTop + (FHeight * i) div 4,
               FLeft + FWidth, FTop + (FHeight * i) div 4,
               Fade(FLabelColor, 0.1));
    end;

    // Вертикальные линии сетки
    if FBarCount < 50 then
    begin
      for i := 1 to 7 do
      begin
        DrawLine(FLeft + (FWidth * i) div 8, FTop,
                 FLeft + (FWidth * i) div 8, FTop + FHeight,
                 Fade(FLabelColor, 0.05));
      end;
    end;
  end;

  // Рисуем полоски спектра
  for i := 0 to numBars - 1 do
  begin
    // Логарифмическая шкала частот
    barIndex := Round(Power(i / numBars, 1.2) * SpectrumSize);
    if barIndex >= SpectrumSize then
      barIndex := SpectrumSize - 1;

    value := SpectrumData[barIndex];

    // Вычисляем высоту
    barHeight := Round(value * FHeight);
    if barHeight < 1 then
      barHeight := 1;
    if barHeight > FHeight then
      barHeight := FHeight;

    barX := FLeft + i * (actualBarWidth + FBarSpacing);
    barY := FTop + FHeight - barHeight;

    // Выбираем цвет с градиентом
    if FGradientMode then
    begin
      intensity := value;
      if intensity < 0.33 then
        gradientColor := DARKGREEN
      else if intensity < 0.66 then
        gradientColor := ORANGE
      else
        gradientColor := RED;
    end
    else
      gradientColor := FBarColor;

    // Рисуем полоску в зависимости от стиля
    case FBarStyle of
      0: // Прямоугольные
        DrawRectangle(barX, barY, actualBarWidth, barHeight, Fade(gradientColor,0.8));

      1: // С закруглением
        begin
          barRect := RectangleCreate(barX, barY, actualBarWidth, barHeight);
          DrawRectangleRounded(barRect, 0.3, 4, gradientColor);
        end;

      2: // Треугольные
        begin
          DrawRectangle(barX, barY, actualBarWidth, barHeight, gradientColor);
          // Добавляем треугольную вершину
          DrawTriangle(
            Vector2Create(barX, barY),
            Vector2Create(barX + actualBarWidth div 2, barY - actualBarWidth div 2),
            Vector2Create(barX + actualBarWidth, barY),
            gradientColor
          );
        end;
    end;

    // Обновляем пик
    if value > FPeakHold[i] then
    begin
      FPeakHold[i] := value;
      FPeakDecayTimer[i] := currentTime + FHoldTime;
    end;

    // Рисуем пик
    if FPeakHold[i] > 0.01 then
    begin
      if currentTime > FPeakDecayTimer[i] then
      begin
        FPeakHold[i] := FPeakHold[i] - deltaTime * FDecaySpeed;
        if FPeakHold[i] < 0 then
          FPeakHold[i] := 0;
      end;

      if FPeakHold[i] > 0.01 then
      begin
        peakHeight := Round(FPeakHold[i] * FHeight);
        if peakHeight < 1 then
          peakHeight := 1;
        if peakHeight > FHeight then
          peakHeight := FHeight;

        // Рисуем пик
        case FBarStyle of
          0: DrawLine(barX, FTop + FHeight - peakHeight,
                      barX + actualBarWidth, FTop + FHeight - peakHeight, Fade(FPeakColor, 0.8));
          1,2: DrawRectangle(barX, FTop + FHeight - peakHeight - 1,
                             actualBarWidth, 2, FPeakColor);
        end;

        // Маленький маркер на пике
        DrawRectangle(barX, FTop + FHeight - peakHeight - 1,
                     actualBarWidth, 2, FPeakColor);
      end;
    end;
  end;

  // Рисуем рамку
 // DrawRectangleLines(FLeft, FTop, FWidth, FHeight, Fade(FLabelColor, 1));

  // Рисуем метки
  if FShowLabels then
  begin
    DrawText('20Hz', FLeft + 5, FTop + FHeight - 12, 8, Fade(FLabelColor, 0.5));
    DrawText('20kHz', FLeft + FWidth - 35, FTop + FHeight - 12, 8, Fade(FLabelColor, 0.5));

    // Децибелы
    DrawText('0dB', FLeft + 5, FTop + 2, 8, Fade(RAYWHITE, 0.3));
    DrawText('-24dB', FLeft + 5, FTop + FHeight div 4 - 4, 8, Fade(FLabelColor, 0.3));
    DrawText('-48dB', FLeft + 5, FTop + FHeight div 2 - 4, 8, Fade(FLabelColor, 0.3));
    DrawText('-72dB', FLeft + 5, FTop + 3 * FHeight div 4 - 4, 8, Fade(FLabelColor, 0.3));
  end;
end;

end.
