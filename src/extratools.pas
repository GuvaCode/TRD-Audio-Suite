unit extratools;

{$mode ObjFPC}{$H+}

interface

uses
  Raylib, raygui, Classes, SysUtils, raymath, Math;

procedure DrawSpectrumLogo(X, Y, Height: Integer);
procedure DrawBetaDisk(Font: TFont);
procedure DrawTechIconLogo(posX, posY, size: Integer; const text: PChar; textSize: Integer; corner, zxLogo : Boolean;  color: TColorB);
function CreateTechIconLogoImage(size: Integer; zxLogo: Boolean; color: TColorB): TImage;
function ShortenFileName(const Input: string; MaxLength: Integer = 8): string;
function DetectFileTypeAndParams(const FileName: string; out LoadAddr, CodeSize: Word; out FileType: Char): Boolean;
function CreateTechIconLogoImageWithText(size: Integer; const text: PChar;
  textSize: Integer; zxLogo: Boolean; color: TColorB): TImage;
function SanitizeFileName(const FileName: string): string;
// Shader functions
//procedure InitLoadingShader;
//procedure UninitLoadingShader;
//procedure DrawLoadingShader(Width, Height: Integer);
//procedure ResetLoadingShader;  // Новая функция для сброса шейдера
// Функция для установки пользовательской текстуры
//procedure SetLoadingTexture(Texture: TTexture2D);

implementation

var
  FLoadingShader: TShader;
  FLoadingTexture: TTexture2D;
  FLoadingTextureCreated: Boolean = False;
  FShaderStartTime: Double = 0;
  FUseCustomTexture: Boolean = False;

//  {$I myicon.inc}

procedure CreateDefaultLoadingTexture(Width, Height: Integer);
var
  Image: TImage;
  x, y: Integer;
  Color1, Color2: TColorB;
begin
  if FLoadingTextureCreated then
    UnloadTexture(FLoadingTexture);

  // Create a ZX Spectrum style test pattern
  Image := GenImageColor(Width, Height, ColorCreate(0, 0, 0, 255));

  Color1 := ColorCreate(0, 0, 84, 255);   // Dark blue
  Color2 := ColorCreate(84, 84, 0, 255);  // Dark yellow

  for y := 0 to Height - 1 do
    for x := 0 to Width - 1 do
      if ((x div 8) + (y div 8)) mod 2 = 0 then
        ImageDrawPixel(@Image, x, y, Color1)
      else
        ImageDrawPixel(@Image, x, y, Color2);

  FLoadingTexture := LoadTextureFromImage(Image);
  UnloadImage(Image);
  FLoadingTextureCreated := True;
end;

procedure InitLoadingShader;
begin
  if IsShaderValid(FLoadingShader) then
    UnloadShader(FLoadingShader);

  // Загружаем шейдер (без изменений)
  FLoadingShader := LoadShader(nil, 'spectrum_loading.glsl');

  if not IsShaderValid(FLoadingShader) then
  begin
    // Fallback: create a simple passthrough shader
    FLoadingShader := LoadShader(nil, nil);
  end;

  FShaderStartTime := GetTime();
  // Создаем текстуру по умолчанию
  CreateDefaultLoadingTexture(192, 256);
  FUseCustomTexture := False;
end;

procedure ResetLoadingShader;
begin
    FShaderStartTime := GetTime();
end;

// Функция для установки вашей текстуры
procedure SetLoadingTexture(Texture: TTexture2D);
begin
  if IsTextureValid(Texture) then
  begin
    if FLoadingTextureCreated then
      UnloadTexture(FLoadingTexture);

    FLoadingTexture := Texture;
    FLoadingTextureCreated := True;
    FUseCustomTexture := True;
  end;
end;



procedure DrawLoadingShader(Width, Height: Integer);
var
  Resolution: array[0..2] of Single;
  CurrentTime: Single;
begin
  if not IsShaderValid(FLoadingShader) then
    Exit;

  if not FLoadingTextureCreated then
    CreateDefaultLoadingTexture(192, 256);

  BeginShaderMode(FLoadingShader);

  CurrentTime := Single(GetTime() - FShaderStartTime);
  Resolution[0] := Width;
  Resolution[1] := Height;
  Resolution[2] := 1.0;

  // Устанавливаем uniform-переменные
  SetShaderValue(FLoadingShader, GetShaderLocation(FLoadingShader, 'iResolution'),
                 @Resolution, SHADER_UNIFORM_VEC3);
  SetShaderValue(FLoadingShader, GetShaderLocation(FLoadingShader, 'iTime'),
                 @CurrentTime, SHADER_UNIFORM_FLOAT);

  // Устанавливаем текстуру в iChannel0
  SetShaderValueTexture(FLoadingShader, GetShaderLocation(FLoadingShader, 'iChannel0'),
                        FLoadingTexture);

  // Рисуем текстуру во весь экран
  DrawTexturePro(FLoadingTexture,
    RectangleCreate(0, 0, FLoadingTexture.Width, FLoadingTexture.Height),
    RectangleCreate(0, 0, Width, Height),
    Vector2Create(0, 0), 0, WHITE);

  EndShaderMode();
end;

// Остальные ваши существующие функции (DrawSpectrumLogo, DrawBetaDisk,
// GetLogoImage128, ShortenFileName, DetectFileTypeAndParams) остаются без изменений

procedure DrawSpectrumLogo(X, Y, Height: Integer);
var
  StripeWidth: Single;
  Offset: Single;
  Colors: array[0..3] of TColorB;
  i: Integer;
begin
  StripeWidth := 14.0;
  Offset := 20.0;

  Colors[0] := ColorCreate(255, 31, 31, 180);
  Colors[1] := ColorCreate(255, 198, 16, 180);
  Colors[2] := ColorCreate(61, 155, 0, 180);
  Colors[3] := ColorCreate(0, 167, 225, 180);

  for i := 0 to 3 do
  begin
    DrawTriangle(
      Vector2Create(X + i * StripeWidth, Y),
      Vector2Create(X + (i + 1) * StripeWidth - Offset, Y + Height),
      Vector2Create(X + (i + 1) * StripeWidth, Y),
      Colors[i]
    );

    DrawTriangle(
      Vector2Create(X + i * StripeWidth, Y),
      Vector2Create(X + i * StripeWidth - Offset, Y + Height),
      Vector2Create(X + (i + 1) * StripeWidth - Offset, Y + Height),
      Colors[i]
    );
  end;
end;

procedure DrawBetaDisk(Font: TFont);
var
  TextPos: TVector2;
  TextSize: TVector2;
  ScreenWidth, ScreenHeight: Integer;
  RectWidth: Integer;
  RectHeight: Integer;
  RectX: Integer;
  RectY: Integer;
begin
  ScreenWidth := GetScreenWidth;
  ScreenHeight := GetScreenHeight;
  DrawRectangle(0, 0, ScreenWidth, ScreenHeight, RayWhite);
  // Overlay text on top of shader
  TextSize := MeasureTextEx(Font, '* TR-DOS Ver 5.03 *', 16, 1.0);
  TextPos.X := (ScreenWidth - TextSize.X) / 2;
  TextPos.Y := 30;
  DrawTextPro(Font, '* TR-DOS Ver 5.03 *', TextPos, Vector2Zero, 0, 16, 1.0, BLACK);

  TextSize := MeasureTextEx(Font, '© 1986 Technology Research Ltd.', 16, 1.0);
  TextPos.X := (ScreenWidth - TextSize.X) / 2;
  TextPos.Y := TextPos.Y + 30;
  DrawTextPro(Font, '(C) 1986 Technology Research Ltd.', TextPos, Vector2Zero, 0, 16, 1.0, BLACK);

  TextSize := MeasureTextEx(Font, '(U.K.)', 16, 1.0);
  TextPos.X := (ScreenWidth - TextSize.X) / 2;
  TextPos.Y := TextPos.Y + 30;
  DrawTextPro(Font, '(U.K.)', TextPos, Vector2Zero, 0, 16, 1.0, BLACK);

  RectWidth := 250;
  RectHeight := 18;
  RectX := (ScreenWidth - RectWidth) div 2;
  RectY := Trunc(TextPos.Y + 30);

  DrawRectangle(RectX, RectY, RectWidth, RectHeight, ColorCreate(0, 0, 0, 200));
  DrawSpectrumLogo(RectX + 190, RectY, 18);

  TextSize := MeasureTextEx(Font, 'BETA 128', 16, 1.0);
  TextPos.X := RectX;
  TextPos.Y := RectY + (RectHeight - TextSize.Y) / 2;
  DrawTextPro(Font, 'BETA 128', TextPos, Vector2Zero, 0, 16, 1.0, Fade(WHITE, 0.9));

  TextSize := MeasureTextEx(Font, 'A>K', 16, 1.0);
  TextPos.X := 10;
  TextPos.Y := ScreenHeight - 30;
  DrawTextPro(Font, 'A>K', TextPos, Vector2Zero, 0, 16, 1.0, BLACK);
end;

procedure DrawTechIconLogo(posX, posY, size: Integer; const text: PChar;
  textSize: Integer; corner, zxLogo: Boolean; color: TColorB);
var
  borderSize: Single;
  offsetY: Boolean;
  textPosX, textPosY: Integer;
  i: Integer;
  lineColor: TColorB;
  colors: array[0..3] of TColorB;
  stripeWidth: Single;
  offset: Single;
  v1, v2, v3, v4: TVector2;
begin
  borderSize := Ceil(size / 16.0);
  offsetY := True;

  // Make sure there is no character with pixels down the text baseline
  i := 0;
  while text[i] <> #0 do
  begin
    if (text[i] = 'q') or (text[i] = 'y') or (text[i] = 'p') or
       (text[i] = 'j') or (text[i] = 'g') then
    begin
      offsetY := False;
      Break;
    end;
    Inc(i);
  end;

  textPosX := posX + size - Round(2.0 * borderSize) - MeasureText(text, textSize);
  textPosY := posY + size - Round(2.0 * borderSize) - textSize;
  if offsetY then
    textPosY := textPosY + (2 * textSize div 10);

  lineColor := GetColor(GuiGetStyle(DEFAULT, LINE_COLOR));
  DrawRectangle(posX - 1, posY - 1, size + 2, size + 2, lineColor);
  DrawRectangle(posX, posY, size, size, RAYWHITE);

  // Draw Spectrum logo with stripes filling the entire square
  if zxLogo then
  begin
    colors[0] := ColorCreate(255, 31, 31, 255);   // Red
    colors[1] := ColorCreate(255, 198, 16, 255);  // Yellow
    colors[2] := ColorCreate(61, 155, 0, 255);    // Green
    colors[3] := ColorCreate(0, 167, 225, 255);   // Blue

    stripeWidth := size / 2.8;
    offset := stripeWidth * 1.2;  // Increased offset for more slant

    // Enable scissor test to clip drawing to square boundaries
    BeginScissorMode(posX, posY, size, size);

    for i := 0 to 3 do
    begin
      // Left slanted triangle
      v1 := Vector2Create(posX + i * stripeWidth, posY);
      v2 := Vector2Create(posX + (i + 1) * stripeWidth - offset, posY + size);
      v3 := Vector2Create(posX + (i + 1) * stripeWidth, posY);
      DrawTriangle(v1, v2, v3, colors[i]);

      // Right slanted triangle (bottom part)
      v1 := Vector2Create(posX + i * stripeWidth, posY);
      v2 := Vector2Create(posX + i * stripeWidth - offset, posY + size);
      v3 := Vector2Create(posX + (i + 1) * stripeWidth - offset, posY + size);
      DrawTriangle(v1, v2, v3, colors[i]);
    end;

    EndScissorMode();
  end;

  DrawRectangleLines(posX, posY, size, size, color);
  DrawText(text, textPosX, textPosY, textSize, color);

  if corner then
  begin
    DrawTriangle(
      Vector2Create(posX + size - Round(2 * borderSize) - (size div 4), posY + Round(2 * borderSize)),
      Vector2Create(posX + size - Round(2 * borderSize), posY + Round(2 * borderSize) + (size div 4)),
      Vector2Create(posX + size - Round(2 * borderSize), posY + Round(2 * borderSize)),
      color
    );
  end;
end;

function CreateTechIconLogoImage(size: Integer; zxLogo: Boolean; color: TColorB): TImage;
var
  img: TImage;
  colors: array[0..3] of TColorB;
  stripeWidth: Single;
  offset: Single;
  i: Integer;
  posX, posY: Integer;
  v1, v2, v3: TVector2;
begin
  // Create blank image
  img := GenImageColor(size, size, RAYWHITE);

  // Draw border
  for i := 0 to size - 1 do
  begin
    ImageDrawPixel(@img, 0, i, color);
    ImageDrawPixel(@img, size-1, i, color);
    ImageDrawPixel(@img, i, 0, color);
    ImageDrawPixel(@img, i, size-1, color);
  end;

  // Draw Spectrum logo
  if zxLogo then
  begin
    colors[0] := ColorCreate(255, 31, 31, 255);   // Red
    colors[1] := ColorCreate(255, 198, 16, 255);  // Yellow
    colors[2] := ColorCreate(61, 155, 0, 255);    // Green
    colors[3] := ColorCreate(0, 167, 225, 255);   // Blue

    stripeWidth := size / 2.8;
    offset := stripeWidth * 1.2;
    posX := 0;
    posY := 0;

    for i := 0 to 3 do
    begin
      // Left slanted triangle
      v1 := Vector2Create(posX + i * stripeWidth, posY);
      v2 := Vector2Create(posX + (i + 1) * stripeWidth - offset, posY + size);
      v3 := Vector2Create(posX + (i + 1) * stripeWidth, posY);
      ImageDrawTriangle(@img, v1, v2, v3, colors[i]);

      // Right slanted triangle (bottom part)
      v1 := Vector2Create(posX + i * stripeWidth, posY);
      v2 := Vector2Create(posX + i * stripeWidth - offset, posY + size);
      v3 := Vector2Create(posX + (i + 1) * stripeWidth - offset, posY + size);
      ImageDrawTriangle(@img, v1, v2, v3, colors[i]);
    end;
  end;

  Result := img;
end;

{
function GetLogoImage128: TImage;
var
  FIconData: TMemoryStream;
  //image: TImage;
  srcPtr, dstPtr: PByte;
  i: Integer;
  totalPixels: Integer;
  r, g, b: Byte;
begin
  // Создаём изображение в формате RGBA
  //image
  result := GenImageColor(LOGO_WIDTH, LOGO_HEIGHT, WHITE);
  FIconData := TMemoryStream.Create;
  FIconData.Write(MyIcon, LOGO_SIZE);
  FIconData.Position := 0;

  srcPtr := FIconData.Memory;
  dstPtr := result.data;
  totalPixels := LOGO_WIDTH * LOGO_HEIGHT;

  for i := 0 to totalPixels - 1 do
  begin
    // Читаем RGB
    r := srcPtr^; Inc(srcPtr);
    g := srcPtr^; Inc(srcPtr);
    b := srcPtr^; Inc(srcPtr);

    // Записываем RGBA (альфа = 255 - полностью непрозрачный)
    dstPtr^ := r; Inc(dstPtr);
    dstPtr^ := g; Inc(dstPtr);
    dstPtr^ := b; Inc(dstPtr);
    dstPtr^ := 255; Inc(dstPtr);
  end;
  FIconData.Free;
  //Result := Image;
end;
 }
function ShortenFileName(const Input: string; MaxLength: Integer = 8): string;
begin
  if Length(Input) <= MaxLength then
    Result := Input
  else
    Result := Copy(Input, 1, MaxLength);
end;

function DetectFileTypeAndParams(const FileName: string; out LoadAddr, CodeSize: Word; out FileType: Char): Boolean;
var
  Ext: string;
  FileStream: TFileStream;
  Header: array[0..$1F] of Byte;
  FileSize: Integer;
  i: Integer;
begin
  Result := True;
  Ext := UpperCase(ExtractFileExt(FileName));
  LoadAddr := 0;
  CodeSize := 0;
  FileType := 'C';

  FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    FileSize := FileStream.Size;
    CodeSize := FileSize;
  finally
    FileStream.Free;
  end;

  if (Ext = '.B') or (Ext = '.BAS') then
  begin
    FileType := 'B';
    LoadAddr := 23755;
  end
  else if Ext = '.C' then
  begin
    FileType := 'C';
    LoadAddr := 32768;
  end
  else if (Ext = '.D') or (Ext = '.DAT') then
  begin
    FileType := 'D';
    LoadAddr := 32768;
  end
  else if (Ext = '.SNA') then
  begin
    FileType := 'C';
    LoadAddr := 16384;
  end
  else if (Ext = '.SCR') then
  begin
    FileType := 'D';
    LoadAddr := 16384;
  end
  else if (Ext = '.BIN') or (Ext = '.ROM') then
  begin
    FileType := 'C';
    LoadAddr := 0;
    try
      FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
      try
        if FileSize >= 2 then
        begin
          FileStream.Position := 0;
          FileStream.Read(Header, Min(32, FileSize));
          if (Header[0] = $F3) or (Header[0] = $C3) or (Header[0] = $ED) or
             (Header[0] = $21) or (Header[0] = $01) then
            LoadAddr := 32768
          else
            LoadAddr := 0;
        end;
      finally
        FileStream.Free;
      end;
    except
    end;
  end
  else
  begin
    FileType := 'C';
    LoadAddr := 32768;

    try
      FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
      try
        if FileSize >= 32 then
        begin
          FileStream.Read(Header, 32);
          for i := 0 to Min(16, FileSize-1) do
          begin
            if (Header[i] >= 32) and (Header[i] <= 126) then
            begin
              if (Header[0] = $0A) or (Header[0] = $0D) then
              begin
                FileType := 'B';
                LoadAddr := 23755;
                Break;
              end;
            end;
          end;
          if (Header[0] = $F3) or (Header[0] = $C3) or (Header[0] = $ED) then
          begin
            FileType := 'C';
            LoadAddr := 32768;
          end;
        end;
      finally
        FileStream.Free;
      end;
    except
    end;
  end;
end;

function CreateTechIconLogoImageWithText(size: Integer; const text: PChar;
  textSize: Integer; zxLogo: Boolean; color: TColorB): TImage;
var
  img: TImage;
  colors: array[0..3] of TColorB;
  stripeWidth: Single;
  offset: Single;
  i: Integer;
  posX, posY: Integer;
  v1, v2, v3: TVector2;
  borderSize: Integer;
  textWidth: Integer;
  textPosX, textPosY: Integer;
  offsetY: Boolean;
begin
  // Create blank image
  img := GenImageColor(size, size, RAYWHITE);

  borderSize := Max(2, size div 16);

  // Draw outer border (darker)
  for i := 0 to size - 1 do
  begin
    ImageDrawPixel(@img, 0, i, DARKGRAY);
    ImageDrawPixel(@img, 1, i, DARKGRAY);
    ImageDrawPixel(@img, size-1, i, DARKGRAY);
    ImageDrawPixel(@img, size-2, i, DARKGRAY);
    ImageDrawPixel(@img, i, 0, DARKGRAY);
    ImageDrawPixel(@img, i, 1, DARKGRAY);
    ImageDrawPixel(@img, i, size-1, DARKGRAY);
    ImageDrawPixel(@img, i, size-2, DARKGRAY);
  end;

  // Draw inner border with specified color
  for i := borderSize to size - 1 - borderSize do
  begin
    ImageDrawPixel(@img, borderSize, i, color);
    ImageDrawPixel(@img, size-1-borderSize, i, color);
    ImageDrawPixel(@img, i, borderSize, color);
    ImageDrawPixel(@img, i, size-1-borderSize, color);
  end;

  // Draw Spectrum logo
  if zxLogo then
  begin
    colors[0] := ColorCreate(255, 31, 31, 255);   // Red
    colors[1] := ColorCreate(255, 198, 16, 255);  // Yellow
    colors[2] := ColorCreate(61, 155, 0, 255);    // Green
    colors[3] := ColorCreate(0, 167, 225, 255);   // Blue

    stripeWidth := size / 2.8;
    offset := stripeWidth * 1.2;
    posX := 0;
    posY := 0;

    for i := 0 to 3 do
    begin
      // Left slanted triangle
      v1 := Vector2Create(posX + i * stripeWidth, posY);
      v2 := Vector2Create(posX + (i + 1) * stripeWidth - offset, posY + size);
      v3 := Vector2Create(posX + (i + 1) * stripeWidth, posY);
      ImageDrawTriangle(@img, v1, v2, v3, colors[i]);

      // Right slanted triangle (bottom part)
      v1 := Vector2Create(posX + i * stripeWidth, posY);
      v2 := Vector2Create(posX + i * stripeWidth - offset, posY + size);
      v3 := Vector2Create(posX + (i + 1) * stripeWidth - offset, posY + size);
      ImageDrawTriangle(@img, v1, v2, v3, colors[i]);
    end;
  end;

  // Draw text centered
  if (text <> nil) and (text^ <> #0) then
  begin
    // Calculate text width
    textWidth := MeasureText(text, textSize);

    // Center text horizontally
    textPosX := (size - textWidth) div 2;

    // Check for descending characters (q, y, p, j, g)
    offsetY := True;
    i := 0;
    while text[i] <> #0 do
    begin
      if (text[i] = 'q') or (text[i] = 'y') or (text[i] = 'p') or
         (text[i] = 'j') or (text[i] = 'g') then
      begin
        offsetY := False;
        Break;
      end;
      Inc(i);
    end;

    // Center text vertically (with adjustment for descenders)
    textPosY := (size - textSize) div 2;
    if offsetY then
      textPosY := textPosY + (textSize div 4);

    ImageDrawText(@img, text, textPosX, textPosY, textSize, color);
  end;

  Result := img;
end;



// Реализация
function SanitizeFileName(const FileName: string): string;
const
  InvalidChars: set of Char = ['<', '>', ':', '"', '/', '\', '|', '?', '*'];
var
  i: Integer;
begin
  Result := FileName;
  for i := 1 to Length(Result) do
  begin
    if Result[i] in InvalidChars then
      Result[i] := '_';
  end;
  Result := Trim(Result);
  if Result = '' then
    Result := 'untitled';
end;

end.
