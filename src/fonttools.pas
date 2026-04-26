unit fontTools;

{$mode ObjFPC}{$H+}

interface

uses
  raylib, raygui, Classes, SysUtils;


 procedure LoadFontWithPreset(var font: TFont; const fontPath: PChar; size: Integer; preset: Integer);
 function LoadUnicodeFont(FileName: String; FontSize: Integer; TextureFilter: TTextureFilter = TEXTURE_FILTER_POINT): TFont;

implementation

//--------------------------------------------------------------------------------------
// Процедура загрузки шрифта с указанными Unicode диапазонами
//--------------------------------------------------------------------------------------
procedure LoadFontWithRanges(var font: TFont; const fontPath: PChar; size: Integer; ranges: array of Integer);
var
  i, j, totalCodepoints, rangeStart, rangeStop, currentRangeSize: Integer;
  updatedCodepoints: PInteger;
  tempFont: TFont;
begin
  // Если шрифт уже загружен, выгружаем его
  if font.texture.id <> 0 then
    UnloadFont(font);

  // Загружаем базовый шрифт с ASCII диапазоном [32-127]
  tempFont := LoadFont(fontPath);

  // Вычисляем общее количество кодовых точек
  totalCodepoints := 0;
  i := 0;
  while i < Length(ranges) do
  begin
    rangeStart := ranges[i];
    rangeStop := ranges[i + 1];
    totalCodepoints := totalCodepoints + (rangeStop - rangeStart + 1);
    Inc(i, 2);
  end;

  // Добавляем базовые ASCII символы
  totalCodepoints := totalCodepoints + tempFont.glyphCount;

  // Выделяем память для массива кодовых точек
  updatedCodepoints := GetMem(totalCodepoints * SizeOf(Integer));

  try
    // Копируем существующие кодовые точки (ASCII)
    for i := 0 to tempFont.glyphCount - 1 do
      updatedCodepoints[i] := tempFont.glyphs[i].value;

    currentRangeSize := tempFont.glyphCount;

    // Добавляем новые кодовые точки из указанных диапазонов
    i := 0;
    while i < Length(ranges) do
    begin
      rangeStart := ranges[i];
      rangeStop := ranges[i + 1];

      for j := rangeStart to rangeStop do
      begin
        updatedCodepoints[currentRangeSize] := j;
        Inc(currentRangeSize);
      end;

      Inc(i, 2);
    end;

    // Загружаем шрифт со всеми кодовыми точками
    font := LoadFontEx(fontPath, size, updatedCodepoints, totalCodepoints);

  finally
    FreeMem(updatedCodepoints);
    UnloadFont(tempFont);
  end;
end;


procedure LoadFontWithPreset(var font: TFont; const fontPath: PChar;
  size: Integer; preset: Integer);
var
  ranges: array of Integer;
begin
  SetLength(ranges, 0);

  case preset of
    0: // Только ASCII
      begin
        // Базовый диапазон уже загружается по умолчанию
        if font.texture.id <> 0 then
          UnloadFont(font);
        font := LoadFont(fontPath);
        Exit;
      end;

    1: // Европейские языки
      begin
        SetLength(ranges, 4);
        ranges[0] := $00C0; ranges[1] := $017F; // Latin-1 Supplement + Latin Extended-A
        ranges[2] := $0180; ranges[3] := $024F; // Latin Extended-B
      end;

    2: // Греческий
      begin
        SetLength(ranges, 4);
        ranges[0] := $0370; ranges[1] := $03FF; // Greek and Coptic
        ranges[2] := $1F00; ranges[3] := $1FFF; // Greek Extended
      end;

    3: // Кириллица
      begin
        SetLength(ranges, 8);
        ranges[0] := $0400; ranges[1] := $04FF; // Cyrillic
        ranges[2] := $0500; ranges[3] := $052F; // Cyrillic Supplement
        ranges[4] := $2DE0; ranges[5] := $2DFF; // Cyrillic Extended-A
        ranges[6] := $A640; ranges[7] := $A69F; // Cyrillic Extended-B
      end;

    4: // CJK (китайский, японский, корейский)
      begin
        SetLength(ranges, 18);
        ranges[0]  := $4E00; ranges[1]  := $9FFF;  // CJK Unified Ideographs
        ranges[2]  := $3400; ranges[3]  := $4DBF;  // CJK Unified Ideographs Extension A
        ranges[4]  := $3000; ranges[5]  := $303F;  // CJK Symbols and Punctuation
        ranges[6]  := $3040; ranges[7]  := $309F;  // Hiragana
        ranges[8]  := $30A0; ranges[9]  := $30FF;  // Katakana
        ranges[10] := $31F0; ranges[11] := $31FF;  // Katakana Phonetic Extensions
        ranges[12] := $FF00; ranges[13] := $FFEF;  // Halfwidth and Fullwidth Forms
        ranges[14] := $AC00; ranges[15] := $D7AF;  // Hangul Syllables
        ranges[16] := $1100; ranges[17] := $11FF;  // Hangul Jamo
      end;
  end;

  LoadFontWithRanges(font, fontPath, size, ranges);
end;

function LoadUnicodeFont(FileName: String; FontSize: Integer;
  TextureFilter: TTextureFilter): TFont;
var
  cp: array of Integer;  // Array to store Unicode codepoints
  count: Integer;        // Counter for codepoints

  // Helper procedure to add a range of Unicode codepoints
  procedure AddRange(start, stop: Integer);
  begin
    while start <= stop do
    begin
      // Dynamically expand array if needed
      if count >= Length(cp) then
        SetLength(cp, Length(cp) + 1024);
      // Add current codepoint and increment
      cp[count] := start;
      Inc(count);
      Inc(start);
    end;
  end;

begin
  // Initialize codepoint array with initial capacity
  SetLength(cp, 65536);
  count := 0;

  // --------------------------------------------------
  // 1. BASIC ASCII CHARACTERS
  // --------------------------------------------------
  AddRange(32, 126);  // Basic Latin (letters, digits, punctuation)

  // --------------------------------------------------
  // 2. EUROPEAN LANGUAGES (LATIN SCRIPT)
  // --------------------------------------------------
  AddRange($C0, $17F);  // Latin-1 Supplement + Latin Extended-A
  AddRange($180, $24F); // Latin Extended-B
  AddRange($1E00, $1EFF); // Latin Extended Additional
  AddRange($2C60, $2C7F); // Latin Extended-C


  // --------------------------------------------------
  // 4. CYRILLIC SCRIPTS
  // --------------------------------------------------
  AddRange($400, $4FF); // Basic Cyrillic
  AddRange($500, $52F); // Cyrillic Supplement
  AddRange($2DE0, $2DFF); // Cyrillic Extended-A
  AddRange($A640, $A69F); // Cyrillic Extended-B



  // Trim the array to actual used size
  SetLength(cp, count);

  // Attempt to load the specified font file with all collected codepoints
  if FileExists(FileName) then
    Result := LoadFontEx(PChar(FileName), FontSize, @cp[0], Length(cp));

  // Fallback to default font if loading fails
  if Result.texture.id = 0 then
    Result := GetFontDefault();

  // Apply requested texture filter (defaults to point filtering)
  SetTextureFilter(Result.texture, TextureFilter);
end;

end.

