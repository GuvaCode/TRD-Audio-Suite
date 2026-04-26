unit SpectrumPanel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, raylib, raygui, SpectrumVisualizer;

type
  { TSpectrumPanel - панель для отображения спектра }
  TSpectrumPanel = class
  private
    FLeft: Integer;
    FTop: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FTitle: string;
    FVisualizer: TSpectrumVisualizer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Draw(SpectrumData: PSingle; SpectrumSize: Integer);

    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property Title: string read FTitle write FTitle;

    // Доступ к настройкам визуализатора
    property Visualizer: TSpectrumVisualizer read FVisualizer;
  end;

implementation

const
  PANEL_PADDING = 6;

constructor TSpectrumPanel.Create;
begin
  inherited Create;
  FLeft := 0;
  FTop := 0;
  FWidth := 300;
  FHeight := 120;
  FTitle := 'Spectrum Analyzer';

  FVisualizer := TSpectrumVisualizer.Create;
  FVisualizer.BackgroundColor := ColorFromNormalized(Vector4Create(0.08, 0.08, 0.10, 1.0));
  FVisualizer.BarColor := SKYBLUE;
  FVisualizer.PeakColor := YELLOW;
  FVisualizer.DecaySpeed := 1.2;
  FVisualizer.HoldTime := 0.3;
  FVisualizer.BarWidth := 0;
  FVisualizer.BarSpacing := 1;
  FVisualizer.ShowGrid := True;
  FVisualizer.ShowLabels := True;
  FVisualizer.BarStyle := 1;
  FVisualizer.GradientMode := True;
end;

destructor TSpectrumPanel.Destroy;
begin
  FVisualizer.Free;
  inherited Destroy;
end;

procedure TSpectrumPanel.Draw(SpectrumData: PSingle; SpectrumSize: Integer);
var
  panelRect: TRectangle;
  contentRect: TRectangle;
  visualizerHeight: Integer;
  tempText: string;
begin
  if (FWidth <= 0) or (FHeight <= 0) then
    Exit;

  panelRect := RectangleCreate(FLeft, FTop, FWidth, FHeight);

  // Используем стандартную панель raygui с заголовком
  GuiPanel(panelRect, PChar('#125#' + FTitle));

  // Область для содержимого (внутри панели, с отступом от краев и заголовка)
  contentRect := RectangleCreate(FLeft + PANEL_PADDING,
                                  FTop + 24 + PANEL_PADDING,  // 24 - высота заголовка панели
                                  FWidth - PANEL_PADDING * 2,
                                  FHeight - 24 - PANEL_PADDING * 2);

  // Рисуем спектр
  if (contentRect.height > 20) then
  begin
    if (SpectrumData <> nil) and (SpectrumSize > 0) then
    begin
      visualizerHeight := Round(contentRect.height);

      FVisualizer.Left := Round(contentRect.x);
      FVisualizer.Top := Round(contentRect.y);
      FVisualizer.Width := Round(contentRect.width);
      FVisualizer.Height := visualizerHeight;
      FVisualizer.Draw(SpectrumData, SpectrumSize);
    end
    else
    begin
      // Нет данных - показываем сообщение
      tempText := 'No audio data';
     // GuiSetStyle(DEFAULT, TEXT_SIZE, 10);
      GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);
      GuiLabel(RectangleCreate(contentRect.x,
                                contentRect.y + contentRect.height / 2 - 10,
                                contentRect.width, 20),
                PChar(tempText));
      GuiSetStyle(DEFAULT, TEXT_ALIGNMENT, TEXT_ALIGN_LEFT);
    end;
  end;
end;

end.
