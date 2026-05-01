unit gui_window_about;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$packrecords c}

interface

uses
  raylib, raygui, extratools;

type
  PGuiWindowAboutState = ^TGuiWindowAboutState;
  TGuiWindowAboutState = record
    windowActive: Boolean;
    windowBounds: TRectangle;
    panOffset: TVector2;
    dragMode: Boolean;
    supportDrag: Boolean;
    ImageLogo: TTexture2D;
  end;

function InitGuiWindowAbout: TGuiWindowAboutState;
procedure GuiWindowAbout(var state: TGuiWindowAboutState);

implementation

uses
  Math;


//============================================================================
//  PRIVATE CONSTANTS
//============================================================================

const
  LBL_USED_LIBS_TEXT = 'Powered by:';
  LINK_RAYLIB_TEXT = 'www.raylib.com';
  LINK_GIT_RAYLIB_TEXT = 'github.com/raysan5/raylib';
  LINK_GIT_RAYGUI_TEXT = 'github.com/raysan5/raygui';
  LBL_COPYRIGHT_TEXT = 'Copyright (c) 2026 Vadim Gunko.';
  LINK_RAYLIBTECH_TEXT = '[@GuvaCode]';
  LBL_MORE_INFO_TEXT = 'More info:';
  LINK_MAIL_TEXT = 'guvacode@gmail.com';
  LBL_SUPPORT_TEXT = 'Support:';
  BTN_SPONSOR_TEXT = 'Boosty';
  BTN_SPONSOR_TEXT2 = 'ЮMoney';
  BTN_SPONSOR_TEXT3 = 'Itch.io';
  BTN_CLOSE_TEXT = '#159#Close';

  TOOL_NAME = 'TR-DOS Audio Suite';
  TOOL_SHORT_NAME = 'tAs';
  TOOL_VERSION = '1.0';
  TOOL_DESCRIPTION = 'My awesome tool description';
  TOOL_DESCRIPTION_BREAK ='Is a music player for tracker formats';
  TOOL_DESCRIPTION_BREAK2 ='inside ZX Spectrum .trd disk images';
  TOOL_RELEASE_DATE = 'April.2026';


//============================================================================
//  PRIVATE FUNCTIONS
//============================================================================



function FadeColor(c: TColorB; alpha: Single): TColorB;
begin
  Result.r := c.r;
  Result.g := c.g;
  Result.b := c.b;
  Result.a := Round(c.a * alpha);
end;

procedure DrawTechIcon(posX, posY, size: Integer; const text: PChar; textSize: Integer; corner: Boolean;  color: TColorB);
var
  borderSize: Single;
  offsetY: Boolean;
  textPosX, textPosY: Integer;
  i: Integer;
  c: TColorB;
  lineColor: TColorB;
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

// Добавьте эту процедуру в раздел implementation после функции FadeColor

procedure DrawTechIconsWithLinks(windowBounds: TRectangle; startY: Integer);
var
  iconStartX, iconSpacing, iconSize: Integer;
  iconRect: TRectangle;
  mousePos: TVector2;
  iconColor: TColorB;
  i: Integer;
  iconTexts: array[0..2] of PChar;
  iconUrls: array[0..2] of string;
  iconColors: array[0..2] of TColorB;
  hoverColors: array[0..2] of TColorB;
begin
  iconSize := 64;
  iconSpacing := 16;

  // Инициализация данных иконок
  iconTexts[0] := 'raylib';
  iconTexts[1] := 'raygui';
  iconTexts[2] := 'ray4laz';

  iconUrls[0] := 'https://github.com/raysan5/raylib';
  iconUrls[1] := 'https://github.com/raysan5/raygui';
  iconUrls[2] := 'https://github.com/guvacode/ray4laz';

  iconColors[0] := BLACK;
  iconColors[1] := GRAY;
  iconColors[2] := BLUE;

  hoverColors[0] := GREEN;
  hoverColors[1] := ORANGE;
  hoverColors[2] := SKYBLUE;

  // Расчет центрирования трех иконок
  iconStartX := Round(windowBounds.x) + (Round(windowBounds.width) - (iconSize * 3 + iconSpacing * 2)) div 2;

  mousePos := GetMousePosition;

  // Рисуем три иконки
  for i := 0 to 2 do
  begin
    iconRect := RectangleCreate(
      iconStartX + i * (iconSize + iconSpacing),
      Round(windowBounds.y) + startY,
      iconSize,
      iconSize
    );

    // Проверка наведения мыши
    if CheckCollisionPointRec(mousePos, iconRect) then
    begin
      iconColor := hoverColors[i];

      // Рисуем рамку подсветки
      DrawRectangleLines(
        Round(iconRect.x) - 2,
        Round(iconRect.y) - 2,
        Round(iconRect.width) + 4,
        Round(iconRect.height) + 4,
        hoverColors[i]
      );

      // Обработка клика
      if IsMouseButtonPressed(MOUSE_LEFT_BUTTON) then
        OpenURL(PChar(iconUrls[i]));
    end
    else
      iconColor := iconColors[i];

    // Рисуем иконку
    DrawTechIcon(
      Round(iconRect.x),
      Round(iconRect.y),
      iconSize,
      iconTexts[i],
      10,
      False,
      iconColor
    );
  end;
end;


function GetWindowCenterX(width: Integer): Integer;
begin
  Result := (GetScreenWidth div 2) - (width div 2);
end;

function GetWindowCenterY(height: Integer): Integer;
begin
  Result := (GetScreenHeight div 2) - (height div 2);
end;

//============================================================================
//  PUBLIC FUNCTIONS
//============================================================================

function InitGuiWindowAbout: TGuiWindowAboutState;
begin
  Result.windowActive := False;
  Result.windowBounds := RectangleCreate(
    GetWindowCenterX(360),
    GetWindowCenterY(340),
    360, 340
  );
  Result.panOffset := Vector2Create(0, 0);
  Result.dragMode := False;
  Result.supportDrag := False;
end;

procedure GuiWindowAbout(var state: TGuiWindowAboutState);
var
  mousePosition: TVector2;
  labelTextAlign, buttonTextAlign: Integer;
  linkMailTextWidth: Single;

  bgColor: TColorB;
  logoColor: TColorB;

begin
  if state.windowActive then
  begin
     if IsWindowResized then
  begin
     state.windowBounds.x := GetWindowCenterX(Round(state.windowBounds.width));
    state.windowBounds.y := GetWindowCenterY(Round(state.windowBounds.height));
  end;
    // Update window dragging
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

        // Check screen limits
        if state.windowBounds.x < 0 then
          state.windowBounds.x := 0
        else if state.windowBounds.x > (GetScreenWidth - state.windowBounds.width) then
          state.windowBounds.x := GetScreenWidth - state.windowBounds.width;

        if state.windowBounds.y < 40 then
          state.windowBounds.y := 40
        else if state.windowBounds.y > (GetScreenHeight - state.windowBounds.height - 24) then
          state.windowBounds.y := GetScreenHeight - state.windowBounds.height - 24;

        if IsMouseButtonReleased(MOUSE_LEFT_BUTTON) then
          state.dragMode := False;
      end;
    end;

    // Draw window and controls
    state.windowActive := not (GuiWindowBox(state.windowBounds, PChar('#191#About ' + TOOL_NAME)) = 1);

    labelTextAlign := GuiGetStyle(UILABEL, TEXT_ALIGNMENT);
    GuiSetStyle(UILABEL, TEXT_ALIGNMENT, TEXT_ALIGN_LEFT);

    logoColor := Red;//GetColor(TOOL_LOGO_COLOR);

    //DrawTechIconLogo(Round(state.windowBounds.x) + 10, Round(state.windowBounds.y) + 35, 64,
    //             TOOL_SHORT_NAME, 20, True, True, logoColor);

   // DrawTextureRec(State.ImageLogo, RectangleCreate(Round(state.windowBounds.x) + 10, Round(state.windowBounds.y) + 35,64,64),
   // Vector2Create(state.windowBounds.x, state.windowBounds.y),WHITE);

   DrawTextureEx(State.ImageLogo,
     Vector2Create(Round(state.windowBounds.x) + 10, Round(state.windowBounds.y) + 35),0.0, 0.5, WHITE);


    GuiLabel(RectangleCreate(state.windowBounds.x + 85, state.windowBounds.y + (Ord(0) * 20 + 35), 220, 30),
             PChar(TOOL_NAME + ' ' + TOOL_VERSION + ' (' + TOOL_RELEASE_DATE + ')'));

   GuiLabel(RectangleCreate(state.windowBounds.x + 85, state.windowBounds.y + 52, state.windowBounds.width, 40),
               TOOL_DESCRIPTION_BREAK);
      GuiLabel(RectangleCreate(state.windowBounds.x + 85, state.windowBounds.y + 66, state.windowBounds.width, 40),
               TOOL_DESCRIPTION_BREAK2);

    // Draw background rectangle
    bgColor := GetColor(GuiGetStyle(DEFAULT, BASE_COLOR_NORMAL));
    bgColor.a := Round(bgColor.a * 0.5);
    DrawRectangle(Round(state.windowBounds.x) + 1, Round(state.windowBounds.y) + 110,
                  Round(state.windowBounds.width) - 2, 100, bgColor);

    GuiLine(RectangleCreate(state.windowBounds.x, state.windowBounds.y + 100, state.windowBounds.width, 20), nil);

    GuiLabel(RectangleCreate(state.windowBounds.x + 8, state.windowBounds.y + 110, 126, 24), LBL_USED_LIBS_TEXT);

    DrawTechIconsWithLinks(state.windowBounds, 135);


    GuiLine(RectangleCreate(state.windowBounds.x, state.windowBounds.y + 200, state.windowBounds.width, 20), nil);

    GuiLabel(RectangleCreate(state.windowBounds.x + 10, state.windowBounds.y + 220, 289, 20), LBL_COPYRIGHT_TEXT);
    GuiLabel(RectangleCreate(state.windowBounds.x + 10, state.windowBounds.y + 250, 120, 16), LBL_MORE_INFO_TEXT);

    linkMailTextWidth := MeasureTextEx(GuiGetFont(), LINK_MAIL_TEXT, GuiGetStyle(DEFAULT, TEXT_SIZE),
                                       GuiGetStyle(DEFAULT, TEXT_SPACING)).x;

    if GuiLabelButton(RectangleCreate(state.windowBounds.x + 90, state.windowBounds.y + 250, 165, 16),
                      PChar('github.com/GuvaCode' {+ LowerCase(TOOL_NAME)})) = 1 then
      OpenURL('https://github.com/GuvaCode');

    if GuiLabelButton(RectangleCreate(state.windowBounds.x + 90, state.windowBounds.y + 270, linkMailTextWidth, 16),
                      LINK_MAIL_TEXT) = 1 then
      OpenURL('mailto:guvacode@gmail.com');
   {
    if GuiLabelButton(RectangleCreate(state.windowBounds.x + 90 + linkMailTextWidth + 4, state.windowBounds.y + 270,
                      MeasureTextEx(GuiGetFont(), LINK_RAYLIBTECH_TEXT, GuiGetStyle(DEFAULT, TEXT_SIZE),
                      GuiGetStyle(DEFAULT, TEXT_SPACING)).x, 16), LINK_RAYLIBTECH_TEXT) = 1 then
      OpenURL('https://github.com/raylibtech'); }

    GuiLabel(RectangleCreate(state.windowBounds.x + 10, state.windowBounds.y + 270, 65, 16), LBL_SUPPORT_TEXT);
    GuiLine(RectangleCreate(state.windowBounds.x, state.windowBounds.y + 285, state.windowBounds.width, 20), nil);

    GuiSetStyle(UILABEL, TEXT_ALIGNMENT, labelTextAlign);

    bgColor := GetColor(GuiGetStyle(DEFAULT, BASE_COLOR_NORMAL));
    bgColor.a := Round(bgColor.a * 0.5);
    DrawRectangle(Round(state.windowBounds.x) + 1, Round(state.windowBounds.y) + 285 + 11,
                  Round(state.windowBounds.width) - 2, 43, bgColor);

    buttonTextAlign := GuiGetStyle(BUTTON, TEXT_ALIGNMENT);
    GuiSetStyle(BUTTON, TEXT_ALIGNMENT, TEXT_ALIGN_CENTER);

    if GuiButton(RectangleCreate(state.windowBounds.x + state.windowBounds.width - 255 - 90,
                                 state.windowBounds.y + 305, 80, 24), BTN_SPONSOR_TEXT3) = 1 then
      OpenURL('https://guvacode.itch.io/tr-dos-audio-suite');

    if GuiButton(RectangleCreate(state.windowBounds.x + state.windowBounds.width - 170 - 90,
                                 state.windowBounds.y + 305, 80, 24), BTN_SPONSOR_TEXT2) = 1 then
      OpenURL('https://yoomoney.ru/to/4100118048054657');



    if GuiButton(RectangleCreate(state.windowBounds.x + state.windowBounds.width - 85 - 90,
                                 state.windowBounds.y + 305, 80, 24), BTN_SPONSOR_TEXT) = 1 then
      OpenURL('https://boosty.to/guvacode');

    if GuiButton(RectangleCreate(state.windowBounds.x + state.windowBounds.width - 80,
                                 state.windowBounds.y + 305, 70, 24), BTN_CLOSE_TEXT) = 1 then
      state.windowActive := False;

    GuiSetStyle(BUTTON, TEXT_ALIGNMENT, buttonTextAlign);
  end
  else
  begin
    state.windowBounds := RectangleCreate(
      GetWindowCenterX(Round(state.windowBounds.width)),
      GetWindowCenterY(Round(state.windowBounds.height)),
      state.windowBounds.width,
      state.windowBounds.height
    );
  end;

end;

end.
