unit gui_speccy;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$packrecords c}

interface

uses
  raylib, raygui, extratools,  SysUtils, Classes, math;

type
  { TSpeccyWindow }
  TSpeccyWindow = class
  private
    FWindowActive: Boolean;
    FWindowBounds: TRectangle;
    FPanOffset: TVector2;
    FDragMode: Boolean;
    FSupportDrag: Boolean;

    // Размеры
    FTextureWidth: Integer;   // Оригинальный размер текстуры (всегда 320x256)
    FTextureHeight: Integer;
    FDisplayWidth: Integer;   // Размер отображения (масштабированный)
    FDisplayHeight: Integer;
    FDestRect: TRectangle;    // Финальная позиция и размер на экране

    // Константы окна
    FTitleBarHeight: Integer;    // Высота заголовка
    FWindowBorder: Integer;       // Толщина рамки

    // Кэш состояния клавиш
    FKeyStates: array[0..400] of Boolean;

    // Приватные методы
    procedure PaintCallback(Sender: TObject; const AImage, ABorder: PByte;
      const AWidth, AHeight, AScanline: Integer);
    procedure UpdateWindowBounds;
    procedure UpdateDestRect;
    procedure HandleKeys;
    procedure HandleFileDrop;
    function IsKeyCodeValid(KeyCode: Integer): Boolean;

  public
    constructor Create(x, y, displayWidth, displayHeight: Integer);
    destructor Destroy; override;

    // Отображение и обновление
    procedure Update;
    procedure Draw;

    // Управление окном
    procedure Show;
    procedure Hide;
    procedure Close;
    procedure Reset;
    procedure SetDisplaySize(displayWidth, displayHeight: Integer);
    property Active: Boolean read FWindowActive;

    // Управление эмулятором
    procedure LoadFile(const filename: string);
    procedure SetModel(model: Integer);
    function GetModel: Integer;
  end;

implementation

{ TSpeccyWindow }

constructor TSpeccyWindow.Create(x, y, displayWidth, displayHeight: Integer);
var
  i: Integer;
begin
  inherited Create;

  // Инициализация констант окна
  FTitleBarHeight := 24;  // Высота заголовка (RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT)
  FWindowBorder := 1;      // Толщина рамки

  // Размеры текстуры эмулятора (всегда 320x256)
  FTextureWidth := 320;
  FTextureHeight := 256;

  // Размеры отображения (масштабированные)
  FDisplayWidth := displayWidth;
  FDisplayHeight := displayHeight;

  // Инициализация окна (размер с учетом рамки и заголовка)
  FWindowActive := False;
  FWindowBounds := RectangleCreate(
    x, y,
    FDisplayWidth + (FWindowBorder * 2),
    FDisplayHeight + FTitleBarHeight + FWindowBorder
  );
  FPanOffset := Vector2Create(0, 0);
  FDragMode := False;
  FSupportDrag := True;

  // Инициализация кэша клавиш
  for i := 0 to 399 do
    FKeyStates[i] := False;



  UpdateDestRect;
end;

destructor TSpeccyWindow.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TSpeccyWindow.PaintCallback(Sender: TObject; const AImage, ABorder: PByte;
  const AWidth, AHeight, AScanline: Integer);
begin
  if FTexture.id <> 0 then
    UpdateTexture(FTexture, AImage);
end;

procedure TSpeccyWindow.UpdateWindowBounds;
begin
  // Обновляем размеры окна при изменении размеров отображения
  FWindowBounds.width := FDisplayWidth + (FWindowBorder * 2);
  FWindowBounds.height := FDisplayHeight + FTitleBarHeight + FWindowBorder;
end;

procedure TSpeccyWindow.UpdateDestRect;
var
  WindowWidth, WindowHeight: Integer;
  ContentWidth, ContentHeight: Integer;
begin
  WindowWidth := Round(FWindowBounds.width);
  WindowHeight := Round(FWindowBounds.height);

  // Доступное место под содержимое (вычитаем рамку и заголовок)
  ContentWidth := WindowWidth - (FWindowBorder * 2);
  ContentHeight := WindowHeight - FTitleBarHeight - FWindowBorder;

  // Масштабируем текстуру до размера отображения
  // Текстура всегда 320x256, масштабируем до FDisplayWidth x FDisplayHeight
  FDestRect.x := FWindowBounds.x + FWindowBorder + (ContentWidth - FDisplayWidth) / 2;
  FDestRect.y := FWindowBounds.y + FTitleBarHeight + (ContentHeight - FDisplayHeight) / 2;
  FDestRect.width := FDisplayWidth;
  FDestRect.height := FDisplayHeight;
end;

procedure TSpeccyWindow.SetDisplaySize(displayWidth, displayHeight: Integer);
begin
  FDisplayWidth := displayWidth;
  FDisplayHeight := displayHeight;
  UpdateWindowBounds;
  UpdateDestRect;
end;

function TSpeccyWindow.IsKeyCodeValid(KeyCode: Integer): Boolean;
begin
  Result := (KeyCode >= 32) and (KeyCode <= 126) or
            (KeyCode >= 256) and (KeyCode <= 265) or
            (KeyCode >= 340) and (KeyCode <= 348);
end;

procedure TSpeccyWindow.HandleKeys;
var
  Shift: TShiftState;
  KeyCode: Integer;
  Pressed: Boolean;
begin
  if not FWindowActive then
    Exit;

  Shift := [];

  if IsKeyDown(KEY_LEFT_SHIFT) or IsKeyDown(KEY_RIGHT_SHIFT) then
    Include(Shift, ssShift);
  if IsKeyDown(KEY_LEFT_CONTROL) or IsKeyDown(KEY_RIGHT_CONTROL) then
    Include(Shift, ssCtrl);
  if IsKeyDown(KEY_LEFT_ALT) or IsKeyDown(KEY_RIGHT_ALT) then
    Include(Shift, ssAlt);

  // Буквы A-Z
  for KeyCode := KEY_A to KEY_Z do
  begin
    Pressed := IsKeyDown(KeyCode);
    if Pressed <> FKeyStates[KeyCode] then
    begin
      FKeyStates[KeyCode] := Pressed;
      if FHardware <> nil then
        FHardware.doKey(Pressed, KeyCode, Shift);
    end;
  end;

  // Цифры 0-9
  for KeyCode := KEY_ZERO to KEY_NINE do
  begin
    Pressed := IsKeyDown(KeyCode);
    if Pressed <> FKeyStates[KeyCode] then
    begin
      FKeyStates[KeyCode] := Pressed;
      if FHardware <> nil then
        FHardware.doKey(Pressed, KeyCode, Shift);
    end;
  end;

  // SPACE
  KeyCode := KEY_SPACE;
  Pressed := IsKeyDown(KeyCode);
  if Pressed <> FKeyStates[KeyCode] then
  begin
    FKeyStates[KeyCode] := Pressed;
    if FHardware <> nil then
      FHardware.doKey(Pressed, 32, Shift);
  end;

  // ENTER
  KeyCode := KEY_ENTER;
  Pressed := IsKeyDown(KeyCode);
  if Pressed <> FKeyStates[KeyCode] then
  begin
    FKeyStates[KeyCode] := Pressed;
    if FHardware <> nil then
      FHardware.doKey(Pressed, 13, Shift);
  end;

  // BACKSPACE
  KeyCode := KEY_BACKSPACE;
  Pressed := IsKeyDown(KeyCode);
  if Pressed <> FKeyStates[KeyCode] then
  begin
    FKeyStates[KeyCode] := Pressed;
    if FHardware <> nil then
      FHardware.doKey(Pressed, 8, Shift);
  end;

  // Стрелки
  KeyCode := KEY_UP;
  Pressed := IsKeyDown(KeyCode);
  if Pressed <> FKeyStates[KeyCode] then
  begin
    FKeyStates[KeyCode] := Pressed;
    if FHardware <> nil then
      FHardware.doKey(Pressed, KeyCode, Shift);
  end;

  KeyCode := KEY_DOWN;
  Pressed := IsKeyDown(KeyCode);
  if Pressed <> FKeyStates[KeyCode] then
  begin
    FKeyStates[KeyCode] := Pressed;
    if FHardware <> nil then
      FHardware.doKey(Pressed, KeyCode, Shift);
  end;

  KeyCode := KEY_LEFT;
  Pressed := IsKeyDown(KeyCode);
  if Pressed <> FKeyStates[KeyCode] then
  begin
    FKeyStates[KeyCode] := Pressed;
    if FHardware <> nil then
      FHardware.doKey(Pressed, KeyCode, Shift);
  end;

  KeyCode := KEY_RIGHT;
  Pressed := IsKeyDown(KeyCode);
  if Pressed <> FKeyStates[KeyCode] then
  begin
    FKeyStates[KeyCode] := Pressed;
    if FHardware <> nil then
      FHardware.doKey(Pressed, KeyCode, Shift);
  end;

  // Смена модели (Alt+1..4)
  if IsKeyDown(KEY_LEFT_ALT) or IsKeyDown(KEY_RIGHT_ALT) then
  begin
    if IsKeyPressed(KEY_ONE) then SetModel(0);
    if IsKeyPressed(KEY_TWO) then SetModel(1);
    if IsKeyPressed(KEY_THREE) then SetModel(2);
    if IsKeyPressed(KEY_FOUR) then SetModel(3);
  end;
end;

procedure TSpeccyWindow.HandleFileDrop;
var
  droppedFiles: TFilePathList;
begin
  if not FWindowActive then
    Exit;

  if IsFileDropped() then
  begin
    droppedFiles := LoadDroppedFiles();
    if droppedFiles.count = 1 then
    begin
      if IsFileExtension(droppedFiles.paths[0], '.tap') or
         IsFileExtension(droppedFiles.paths[0], '.sna') or
         IsFileExtension(droppedFiles.paths[0], '.tzx') or
         IsFileExtension(droppedFiles.paths[0], '.z80') then
      begin
        LoadFile(droppedFiles.paths[0]);
      end;
    end;
    UnloadDroppedFiles(droppedFiles);
  end;
end;

procedure TSpeccyWindow.Update;
begin
  if not FWindowActive then
    Exit;

  // Обновляем эмулятор
  if FHardware <> nil then
    FHardware.CycleTick;

  // Обрабатываем клавиши
  HandleKeys;

  // Обрабатываем файлы
  HandleFileDrop;
end;

procedure TSpeccyWindow.Draw;
var
  mousePos: TVector2;
  titleBarRect: TRectangle;
  resultCode: Integer;
begin
  if not FWindowActive then
    Exit;

  // Обновляем позицию окна при перетаскивании
  if FSupportDrag then
  begin
    mousePos := GetMousePosition;

    // Начинаем перетаскивание при клике на заголовок
    if IsMouseButtonPressed(MOUSE_LEFT_BUTTON) then
    begin
      titleBarRect := RectangleCreate(
        FWindowBounds.x,
        FWindowBounds.y,
        FWindowBounds.width,
        FTitleBarHeight
      );
      if CheckCollisionPointRec(mousePos, titleBarRect) then
      begin
        FDragMode := True;
        FPanOffset.x := mousePos.x - FWindowBounds.x;
        FPanOffset.y := mousePos.y - FWindowBounds.y;
      end;
    end;

    // Перемещаем окно
    if FDragMode then
    begin
      FWindowBounds.x := mousePos.x - FPanOffset.x;
      FWindowBounds.y := mousePos.y - FPanOffset.y;

      // Ограничиваем границы экрана
      if FWindowBounds.x < 0 then
        FWindowBounds.x := 0
      else if FWindowBounds.x > (GetScreenWidth() - FWindowBounds.width) then
        FWindowBounds.x := GetScreenWidth() - FWindowBounds.width;

      if FWindowBounds.y < 40 then
        FWindowBounds.y := 40
      else if FWindowBounds.y > (GetScreenHeight() - FWindowBounds.height - 24) then
        FWindowBounds.y := GetScreenHeight() - FWindowBounds.height - 24;

      // Завершаем перетаскивание
      if IsMouseButtonReleased(MOUSE_LEFT_BUTTON) then
        FDragMode := False;
    end;
  end;

  // Обновляем позицию содержимого перед отрисовкой
  UpdateDestRect;



  // Отрисовка окна через GuiWindowBox (возвращает 1 если нажат Close)
  // Это рисует рамку и заголовок ПОВЕРХ содержимого
  resultCode := GuiWindowBox(FWindowBounds, PChar('#191#Speccy Emulator'));
  if resultCode = 1 then
    FWindowActive := False;


  // Рисуем содержимое (текстуру эмулятора)
  // Исходная текстура 320x256, растягиваем до FDisplayWidth x FDisplayHeight
  DrawTexturePro(
    FTexture,
    RectangleCreate(0, 0, FTextureWidth, FTextureHeight),  // Исходный размер текстуры
    FDestRect,                                              // Целевой размер и позиция
    Vector2Create(0, 0),
    0,
    WHITE
  );

end;

procedure TSpeccyWindow.Show;
begin
  FWindowActive := True;
end;

procedure TSpeccyWindow.Hide;
begin
  FWindowActive := False;
end;

procedure TSpeccyWindow.Close;
begin
  FWindowActive := False;

  if FHardware <> nil then
    FHardware := nil;

  if FTexture.id <> 0 then
  begin
    UnloadTexture(FTexture);
    FTexture.id := 0;
  end;
end;

procedure TSpeccyWindow.Reset;
begin
  if FHardware <> nil then
    FHardware.Reset;
end;

procedure TSpeccyWindow.LoadFile(const filename: string);
begin
  if (FHardware <> nil) and FileExists(filename) then
    FHardware.LoadFromFile(filename);
end;

procedure TSpeccyWindow.SetModel(model: Integer);
begin
  if FHardware <> nil then
  begin
    FHardware.Reset;
    FHardware.SetModel(model);
  end;
end;

function TSpeccyWindow.GetModel: Integer;
begin
  if FHardware <> nil then
    Result := FHardware.GetModel
  else
    Result := -1;
end;

end.
