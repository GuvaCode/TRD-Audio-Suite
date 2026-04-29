unit TuneZXPlayer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, raylib, libzxtune, Math, raymath, SyncObjs;

type
  TPlaybackState = (psStopped, psPlaying, psPaused);

  // Настройки спектроанализатора
  TFFTSettings = record
    SmoothingTimeConstant: Single;      // Сглаживание во времени (0.0-1.0, выше = плавнее)
    AttackTime: Single;                 // Время атаки (быстрый рост)
    ReleaseTime: Single;                // Время затухания (медленный спад)
    MinDecibels: Single;                // Минимальный уровень в dB
    MaxDecibels: Single;                // Максимальный уровень в dB
    NormalizationFactor: Single;        // Фактор нормализации (усиление)
    UseLogScale: Boolean;               // Использовать логарифмическую шкалу частот
    BoostHighFrequencies: Single;       // Усиление высоких частот
    BoostLowFrequencies: Single;        // Усиление низких частот
    Sensitivity: Single;                // Чувствительность (1.0 = стандарт)
  end;

  PFFTComplex = ^TFFTComplex;
  TFFTComplex = record
    real: Single;
    imaginary: Single;
  end;

  TFFTBuffer = array[0..511] of Single;
  PFFTBuffer = ^TFFTBuffer;

  { TZXTunePlayer }
  TZXTunePlayer = class
  private
    class procedure AudioCallback(bufferData: pointer; frames: LongWord); static; cdecl;
  private
    FZXTuneData: ZXTuneHandle;
    FZXTuneModule: ZXTuneHandle;
    FZXTunePlayer: ZXTuneHandle;
    FAudioStream: TAudioStream;
    FPlaybackState: TPlaybackState;
    FIsPaused: boolean;
    FCurrentSongName: string;
    FCurrentAuthor: string;
    FCurrentModuleType: string;
    FPlaybackProgress: single;
    FModuleInfo: ZXTuneModuleInfo;
    FInitialized: boolean;
    FOnStateChanged: TNotifyEvent;
    FOnProgressChanged: TNotifyEvent;
    FOnLoop: TNotifyEvent;
    FOnTrackEnd: TNotifyEvent;

    FLoopMode: boolean;
    FTrackEndTriggered: boolean;

    // FFT Analysis
    FFTWindowSize: Integer;
    FFTBufferSize: Integer;
    FFTWorkBuffer: PFFTComplex;
    FFTSpectrum: PFFTComplex;
    FFTPrevMagnitudes: PSingle;
    FFTAttackMagnitudes: PSingle;      // Для быстрой атаки
    FFTReleaseMagnitudes: PSingle;     // Для медленного затухания
    FFTSpectrumData: array[0..511] of Single;
    FFTDataReady: boolean;

    // Настройки спектра
    FFTConfig: TFFTSettings;
    FLastFFTTime: Double;

    // FFT Accumulator
    FFTAccumulator: array of SmallInt;
    FFTAccumulatorPos: Integer;
    FFTAccumulatorLock: TCriticalSection;
    FFFTProcessCount: Integer;

    // Ring buffer
    FAudioRingBuffer: array of SmallInt;
    FRingBufferSize: Integer;
    FRingBufferWritePos: Integer;
    FRingBufferReadPos: Integer;
    FRingBufferDataAvailable: Integer;
    FRingBufferCriticalSection: TCriticalSection;
    FPositionLock: TCriticalSection;
    FSampleRate: Integer;
    FFFTUpdateCounter: Integer;

    procedure InitFFT;
    procedure FreeFFT;
    procedure ProcessFFT(const AudioSamples: array of SmallInt);
    procedure CooleyTukeyFFT(spectrum: PFFTComplex; n: Integer);
    procedure AddSampleToFFT(Sample: SmallInt);
    procedure UpdateFFTFromRingBuffer;
    procedure ApplyFrequencyWeights(var Magnitudes: array of Single; Size: Integer);
    function GetFrequencyWeight(BinIndex: Integer; TotalBins: Integer): Single;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Seek(PositionMs: Integer);
    procedure SeekPercent(Percent: Single);
    function LoadFromMemory(Data: Pointer; Size: LongWord; const FileName: string = ''): boolean;
    procedure Play;
    procedure Stop;
    procedure Pause;
    procedure Resume;
    procedure UpdateProgress;
    function IsPlaying: boolean;
    function IsPaused: boolean;
    function IsStopped: boolean;

    function GetSpectrumData: PSingle;
    function GetSpectrumSize: Integer;

    // Настройка спектроанализатора
    procedure SetFFTSmoothing(Value: Single);  // 0.5 = быстро, 0.95 = плавно
    procedure SetFFTAttack(Value: Single);      // Время атаки (0.1-1.0)
    procedure SetFFTRelease(Value: Single);     // Время затухания (0.1-1.0)
    procedure SetFFTSensitivity(Value: Single); // Чувствительность (0.5-2.0)
    procedure SetFFTBoost(HighBoost, LowBoost: Single); // Усиление частот
    function GetFFTSettings: TFFTSettings;
    procedure ApplyPreset(presetName: string);  // "smooth", "sharp", "club", "classic"

    // Сброс настроек к стандартным
    procedure ResetFFTSettings;

    function GetPosition: Integer;
    function GetDuration: Integer;
    function GetProgressPercent: Single;

    procedure SetLoopMode(Mode: Boolean);
    function GetLoopMode: Boolean;
    property LoopMode: boolean read GetLoopMode write SetLoopMode;

    property SpectrumReady: boolean read FFTDataReady;
    property PlaybackState: TPlaybackState read FPlaybackState;
    property CurrentSongName: string read FCurrentSongName;
    property CurrentAuthor: string read FCurrentAuthor;
    property CurrentModuleType: string read FCurrentModuleType;
    property PlaybackProgress: single read FPlaybackProgress;
    property IsInitialized: boolean read FInitialized;
    property FFTSettings: TFFTSettings read GetFFTSettings;

    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
    property OnProgressChanged: TNotifyEvent read FOnProgressChanged write FOnProgressChanged;
    property OnLoop: TNotifyEvent read FOnLoop write FOnLoop;
    property OnTrackEnd: TNotifyEvent read FOnTrackEnd write FOnTrackEnd;
  end;

implementation

const
  DEFAULT_FREQ = 44100;
  DEFAULT_BITS = 16;
  BUFFER_SIZE = 8192;
  DEFAULT_CHANNELS = 2;
  FFT_WINDOW_SIZE = 1024;
  FFT_BUFFER_SIZE = 512;

  // Стандартные настройки
  DEFAULT_SMOOTHING = 0.85;        // Плавное затухание
  DEFAULT_ATTACK = 0.3;            // Быстрая атака
  DEFAULT_RELEASE = 0.92;          // Медленное затухание
  DEFAULT_MIN_DB = -100.0;
  DEFAULT_MAX_DB = -30.0;
  DEFAULT_NORMALIZATION = 1.2;
  DEFAULT_SENSITIVITY = 1.0;
  DEFAULT_HIGH_BOOST = 1.0;
  DEFAULT_LOW_BOOST = 1.0;

var
  GlobalCurrentPlayer: TZXTunePlayer = nil;

{ FFT Implementation }

procedure TZXTunePlayer.CooleyTukeyFFT(spectrum: PFFTComplex; n: Integer);
var
  i, j, bit, len: Integer;
  angle: Single;
  twiddleUnit, twiddleCurrent, even, odd, twiddledOdd: TFFTComplex;
  temp: TFFTComplex;
  twiddleRealNext: Single;
begin
  // Bit-reversal permutation
  j := 0;
  for i := 1 to n - 2 do
  begin
    bit := n shr 1;
    while j >= bit do
    begin
      j := j - bit;
      bit := bit shr 1;
    end;
    j := j + bit;
    if i < j then
    begin
      temp := spectrum[i];
      spectrum[i] := spectrum[j];
      spectrum[j] := temp;
    end;
  end;

  // FFT iterations
  len := 2;
  while len <= n do
  begin
    angle := -2.0 * PI / len;
    twiddleUnit.real := Cos(angle);
    twiddleUnit.imaginary := Sin(angle);

    i := 0;
    while i < n do
    begin
      twiddleCurrent.real := 1.0;
      twiddleCurrent.imaginary := 0.0;

      for j := 0 to (len div 2) - 1 do
      begin
        even := spectrum[i + j];
        odd := spectrum[i + j + len div 2];

        twiddledOdd.real := odd.real * twiddleCurrent.real - odd.imaginary * twiddleCurrent.imaginary;
        twiddledOdd.imaginary := odd.real * twiddleCurrent.imaginary + odd.imaginary * twiddleCurrent.real;

        spectrum[i + j].real := even.real + twiddledOdd.real;
        spectrum[i + j].imaginary := even.imaginary + twiddledOdd.imaginary;
        spectrum[i + j + len div 2].real := even.real - twiddledOdd.real;
        spectrum[i + j + len div 2].imaginary := even.imaginary - twiddledOdd.imaginary;

        twiddleRealNext := twiddleCurrent.real * twiddleUnit.real - twiddleCurrent.imaginary * twiddleUnit.imaginary;
        twiddleCurrent.imaginary := twiddleCurrent.real * twiddleUnit.imaginary + twiddleCurrent.imaginary * twiddleUnit.real;
        twiddleCurrent.real := twiddleRealNext;
      end;

      i := i + len;
    end;

    len := len shl 1;
  end;
end;

procedure TZXTunePlayer.InitFFT;
begin
  FFTWindowSize := FFT_WINDOW_SIZE;
  FFTBufferSize := FFT_BUFFER_SIZE;
  FSampleRate := DEFAULT_FREQ;

  // Выделение памяти для FFT
  FFTSpectrum := GetMem(SizeOf(TFFTComplex) * FFTWindowSize);
  FFTWorkBuffer := GetMem(SizeOf(TFFTComplex) * FFTWindowSize);
  FFTPrevMagnitudes := GetMem(SizeOf(Single) * FFTBufferSize);
  FFTAttackMagnitudes := GetMem(SizeOf(Single) * FFTBufferSize);
  FFTReleaseMagnitudes := GetMem(SizeOf(Single) * FFTBufferSize);

  // Инициализация настроек
  ResetFFTSettings;

  // Инициализация аккумулятора для FFT
  SetLength(FFTAccumulator, FFTWindowSize);
  FFTAccumulatorPos := 0;
  FFTAccumulatorLock := TCriticalSection.Create;
  FLastFFTTime := 0;
  FFFTProcessCount := 0;

  // Обнуление буферов
  FillChar(FFTSpectrum^, SizeOf(TFFTComplex) * FFTWindowSize, 0);
  FillChar(FFTWorkBuffer^, SizeOf(TFFTComplex) * FFTWindowSize, 0);
  FillChar(FFTPrevMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
  FillChar(FFTAttackMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
  FillChar(FFTReleaseMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
  FillChar(FFTSpectrumData, SizeOf(FFTSpectrumData), 0);

  // Ring buffer
  FRingBufferSize := FFTWindowSize * 4;
  SetLength(FAudioRingBuffer, FRingBufferSize);
  FillChar(FAudioRingBuffer[0], FRingBufferSize * SizeOf(SmallInt), 0);
  FRingBufferWritePos := 0;
  FRingBufferReadPos := 0;
  FRingBufferDataAvailable := 0;

  FRingBufferCriticalSection := TCriticalSection.Create;

  FFTDataReady := False;
  FFFTUpdateCounter := 0;
end;

procedure TZXTunePlayer.FreeFFT;
begin
  if FFTAccumulatorLock <> nil then
  begin
    FFTAccumulatorLock.Free;
    FFTAccumulatorLock := nil;
  end;

  if FRingBufferCriticalSection <> nil then
  begin
    FRingBufferCriticalSection.Free;
    FRingBufferCriticalSection := nil;
  end;

  if FFTSpectrum <> nil then
  begin
    FreeMem(FFTSpectrum);
    FFTSpectrum := nil;
  end;

  if FFTWorkBuffer <> nil then
  begin
    FreeMem(FFTWorkBuffer);
    FFTWorkBuffer := nil;
  end;

  if FFTPrevMagnitudes <> nil then
  begin
    FreeMem(FFTPrevMagnitudes);
    FFTPrevMagnitudes := nil;
  end;

  if FFTAttackMagnitudes <> nil then
  begin
    FreeMem(FFTAttackMagnitudes);
    FFTAttackMagnitudes := nil;
  end;

  if FFTReleaseMagnitudes <> nil then
  begin
    FreeMem(FFTReleaseMagnitudes);
    FFTReleaseMagnitudes := nil;
  end;

  SetLength(FAudioRingBuffer, 0);
  SetLength(FFTAccumulator, 0);
end;

procedure TZXTunePlayer.AddSampleToFFT(Sample: SmallInt);
begin
  if FFTAccumulatorLock = nil then Exit;

  FFTAccumulatorLock.Enter;
  try
    FFTAccumulator[FFTAccumulatorPos] := Sample;
    Inc(FFTAccumulatorPos);

    // Когда аккумулятор заполнен - запускаем FFT
    if FFTAccumulatorPos >= FFTWindowSize then
    begin
      ProcessFFT(FFTAccumulator);
      FFTAccumulatorPos := 0;
      Inc(FFFTProcessCount);
    end;
  finally
    FFTAccumulatorLock.Leave;
  end;
end;

function TZXTunePlayer.GetFrequencyWeight(BinIndex: Integer; TotalBins: Integer): Single;
var
  frequency: Single;
  normalisedFreq: Single;
begin
  // Расчет частоты для бина
  frequency := (BinIndex / TotalBins) * (FSampleRate / 2);

  // Логарифмическая шкала для более естественного звучания
  if FFTConfig.UseLogScale then
  begin
    normalisedFreq := Ln(1 + frequency / 100) / Ln(1 + 20000 / 100);
    Result := 1.0;
  end
  else
  begin
    normalisedFreq := frequency / 20000;
  end;

  // Баланс низких и высоких частот
  if normalisedFreq < 0.2 then
    Result := FFTConfig.BoostLowFrequencies
  else if normalisedFreq > 0.7 then
    Result := FFTConfig.BoostHighFrequencies
  else
    Result := 1.0;

  // Применяем общую чувствительность
  Result := Result * FFTConfig.Sensitivity;
end;

procedure TZXTunePlayer.ApplyFrequencyWeights(var Magnitudes: array of Single; Size: Integer);
var
  i: Integer;
  weight: Single;
begin
  for i := 0 to Size - 1 do
  begin
    weight := GetFrequencyWeight(i, Size);
    Magnitudes[i] := Magnitudes[i] * weight * FFTConfig.NormalizationFactor;
  end;
end;

procedure TZXTunePlayer.ProcessFFT(const AudioSamples: array of SmallInt);
var
  i, bin: Integer;
  x, blackmanWeight, re, im, linearMagnitude: Single;
  sampleCount: Integer;
  attackFactor, releaseFactor: Single;
  currentMagnitude: array[0..511] of Single;
  timeDelta: Single;
begin
  sampleCount := Length(AudioSamples);
  if sampleCount < FFTWindowSize then
    Exit;

  // Применяем оконную функцию
  for i := 0 to FFTWindowSize - 1 do
  begin
    x := (2.0 * PI * i) / (FFTWindowSize - 1.0);
    blackmanWeight := 0.42 - 0.5 * Cos(x) + 0.08 * Cos(2.0 * x);

    FFTWorkBuffer[i].real := (AudioSamples[i] / 32767.0) * blackmanWeight;
    FFTWorkBuffer[i].imaginary := 0.0;
  end;

  // Выполняем FFT
  CooleyTukeyFFT(FFTWorkBuffer, FFTWindowSize);
  Move(FFTWorkBuffer^, FFTSpectrum^, SizeOf(TFFTComplex) * FFTWindowSize);

  // Расчет времени для динамических эффектов
  timeDelta := GetTime() - FLastFFTTime;
  if timeDelta > 0.1 then timeDelta := 0.033; // Ограничиваем максимальный шаг
  if timeDelta <= 0 then timeDelta := 0.016;   // Примерно 60 FPS

  FLastFFTTime := GetTime();

  // Коэффициенты атаки и затухания
  attackFactor := 1.0 - Power(0.01, timeDelta / FFTConfig.AttackTime);
  releaseFactor := 1.0 - Power(0.01, timeDelta / FFTConfig.ReleaseTime);

  // Конвертируем в спектр мощности
  for bin := 0 to FFTBufferSize - 1 do
  begin
    re := FFTWorkBuffer[bin].real;
    im := FFTWorkBuffer[bin].imaginary;
    linearMagnitude := Sqrt(re * re + im * im) / FFTWindowSize;

    // Запоминаем текущую величину для обработки
    currentMagnitude[bin] := linearMagnitude;

    // Стандартное сглаживание (простой фильтр)
    FFTPrevMagnitudes[bin] := FFTConfig.SmoothingTimeConstant * FFTPrevMagnitudes[bin] +
                             (1.0 - FFTConfig.SmoothingTimeConstant) * linearMagnitude;

    // Динамическая обработка (атака и затухание)
    if linearMagnitude > FFTAttackMagnitudes[bin] then
      // Атака - быстрый подъем
      FFTAttackMagnitudes[bin] := FFTAttackMagnitudes[bin] +
                                  (linearMagnitude - FFTAttackMagnitudes[bin]) * attackFactor
    else
      // Затухание - медленный спад
      FFTAttackMagnitudes[bin] := FFTAttackMagnitudes[bin] +
                                  (linearMagnitude - FFTAttackMagnitudes[bin]) * releaseFactor;

    // Применяем настройки к финальному значению
    FFTReleaseMagnitudes[bin] := FFTAttackMagnitudes[bin];
  end;

  // Применяем весовые коэффициенты частот
  ApplyFrequencyWeights(FFTReleaseMagnitudes^, FFTBufferSize);

  // Конвертируем в децибелы и нормализуем
  for bin := 0 to FFTBufferSize - 1 do
  begin
    // Используем обработанные значения
    FFTReleaseMagnitudes[bin] := Max(FFTReleaseMagnitudes[bin], 1e-6);

    // Конвертируем в децибелы
    if FFTReleaseMagnitudes[bin] > 1e-40 then
      FFTSpectrumData[bin] := 20 * Log10(FFTReleaseMagnitudes[bin])
    else
      FFTSpectrumData[bin] := FFTConfig.MinDecibels;

    // Нормализуем в диапазон [0..1]
    FFTSpectrumData[bin] := (FFTSpectrumData[bin] - FFTConfig.MinDecibels) /
                            (FFTConfig.MaxDecibels - FFTConfig.MinDecibels);

    // Клиппинг
    FFTSpectrumData[bin] := Clamp(FFTSpectrumData[bin], 0.0, 1.0);

    // Применяем чувствительность (экспоненциальная кривая для лучшей реакции)
    FFTSpectrumData[bin] := Power(FFTSpectrumData[bin], 1.0 / FFTConfig.Sensitivity);
  end;

  FFTDataReady := True;
end;

procedure TZXTunePlayer.UpdateFFTFromRingBuffer;
begin
  // Не используется в новой реализации
end;

{ TZXTunePlayer - Main Implementation }

class procedure TZXTunePlayer.AudioCallback(bufferData: pointer; frames: LongWord); cdecl;
var
  i: Integer;
  samples: PSmallInt;
  writePos: Integer;
  player: TZXTunePlayer;
  SamplesRendered: Integer;
  monoSample: SmallInt;
begin
  player := GlobalCurrentPlayer;
  if player = nil then Exit;

  if (player.FZXTunePlayer = nil) or player.FIsPaused then
  begin
    FillChar(bufferData^, frames * DEFAULT_CHANNELS * (DEFAULT_BITS div 8), 0);
    Exit;
  end;

  SamplesRendered := ZXTune_RenderSound(player.FZXTunePlayer, bufferData, frames);

  if (SamplesRendered < frames) and (not player.FTrackEndTriggered) then
  begin
    FillChar((bufferData + SamplesRendered * DEFAULT_CHANNELS * (DEFAULT_BITS div 8))^,
             (frames - SamplesRendered) * DEFAULT_CHANNELS * (DEFAULT_BITS div 8), 0);
    player.FTrackEndTriggered := True;
  end;

  samples := PSmallInt(bufferData);

  // Накопление буфера с немедленной FFT
  for i := 0 to frames - 1 do
  begin
    monoSample := (samples[i * 2] + samples[i * 2 + 1]) div 2;
    player.AddSampleToFFT(monoSample);

    // Сохраняем в ring buffer
    if player.FRingBufferCriticalSection <> nil then
    begin
      player.FRingBufferCriticalSection.Enter;
      try
        if player.FRingBufferDataAvailable < player.FRingBufferSize - 1 then
        begin
          writePos := player.FRingBufferWritePos;
          player.FAudioRingBuffer[writePos] := monoSample;
          player.FRingBufferWritePos := (writePos + 1) mod player.FRingBufferSize;
          player.FRingBufferDataAvailable := player.FRingBufferDataAvailable + 1;
        end;
      finally
        player.FRingBufferCriticalSection.Leave;
      end;
    end;
  end;
end;

constructor TZXTunePlayer.Create;
begin
  inherited Create;

  FZXTuneData := nil;
  FZXTuneModule := nil;
  FZXTunePlayer := nil;
  FPlaybackState := psStopped;
  FIsPaused := False;
  FPlaybackProgress := 0;
  FInitialized := False;
  FCurrentSongName := '';
  FCurrentAuthor := '';
  FCurrentModuleType := '';
  FRingBufferCriticalSection := nil;
  FPositionLock := TCriticalSection.Create;
  FLoopMode := False;
  FTrackEndTriggered := False;

  FillChar(FModuleInfo, SizeOf(FModuleInfo), 0);

  InitFFT;

  try
    LoadZXTuneLibrary;
    FInitialized := True;
  except
    on E: Exception do
    begin
      FInitialized := False;
      Exit;
    end;
  end;

  InitAudioDevice();
  if not IsAudioDeviceReady() then
  begin
    FInitialized := False;
    Exit;
  end;

  SetAudioStreamBufferSizeDefault(BUFFER_SIZE);

  FAudioStream := LoadAudioStream(DEFAULT_FREQ, DEFAULT_BITS, DEFAULT_CHANNELS);
  if IsAudioStreamValid(FAudioStream) then
  begin
    SetAudioStreamCallback(FAudioStream, @AudioCallback);
  end;
end;

destructor TZXTunePlayer.Destroy;
begin
  Stop;

  if IsAudioStreamValid(FAudioStream) then
  begin
    StopAudioStream(FAudioStream);
    UnloadAudioStream(FAudioStream);
  end;

  CloseAudioDevice();
  FreeFFT;

  if GlobalCurrentPlayer = Self then
    GlobalCurrentPlayer := nil;
  FPositionLock.Free;
  inherited Destroy;
end;

procedure TZXTunePlayer.Seek(PositionMs: Integer);
var
  SamplePos: NativeUInt;
  Frequency: LongInt;
begin
  FPositionLock.Enter;
  try
    if (FZXTunePlayer <> nil) then
    begin
      Frequency := ZXTune_GetSoundFrequency(FZXTunePlayer);
      if Frequency <= 0 then
        Frequency := 44100;

      SamplePos := (NativeUInt(PositionMs) * Frequency) div 1000;

      if ZXTune_SeekSound(FZXTunePlayer, SamplePos) >= 0 then
      begin
        FTrackEndTriggered := False;

        if FFTAccumulatorLock <> nil then
        begin
          FFTAccumulatorLock.Enter;
          try
            FFTAccumulatorPos := 0;
            FillChar(FFTAccumulator[0], Length(FFTAccumulator) * SizeOf(SmallInt), 0);
          finally
            FFTAccumulatorLock.Leave;
          end;
        end;

        if FRingBufferCriticalSection <> nil then
        begin
          FRingBufferCriticalSection.Enter;
          try
            FRingBufferWritePos := 0;
            FRingBufferReadPos := 0;
            FRingBufferDataAvailable := 0;
            FillChar(FAudioRingBuffer[0], FRingBufferSize * SizeOf(SmallInt), 0);
            FillChar(FFTPrevMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
            FillChar(FFTAttackMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
            FillChar(FFTReleaseMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
            FillChar(FFTSpectrumData, SizeOf(FFTSpectrumData), 0);
          finally
            FRingBufferCriticalSection.Leave;
          end;
        end;

        FFTDataReady := False;
        FFFTUpdateCounter := 0;
        FFFTProcessCount := 0;
      end;
    end;
  finally
    FPositionLock.Leave;
  end;
end;

procedure TZXTunePlayer.SeekPercent(Percent: Single);
var
  Duration: Integer;
  TargetMs: Integer;
begin
  Duration := GetDuration;
  if Duration > 0 then
  begin
    TargetMs := Round(Percent * Duration);
    if TargetMs < 0 then TargetMs := 0;
    if TargetMs > Duration then TargetMs := Duration;
    Seek(TargetMs);
  end;
end;

function TZXTunePlayer.LoadFromMemory(Data: Pointer; Size: LongWord; const FileName: string): boolean;
var
  attrBuffer: array[0..255] of AnsiChar;
begin
  Result := False;

  if not FInitialized then
    Exit;

  Stop;
  FTrackEndTriggered := False;

  try
    FZXTuneData := ZXTune_CreateData(Data, Size);
    if FZXTuneData = nil then
      Exit;

    FZXTuneModule := ZXTune_OpenModule(FZXTuneData);
    if FZXTuneModule = nil then
    begin
      ZXTune_CloseData(FZXTuneData);
      FZXTuneData := nil;
      Exit;
    end;

    if not ZXTune_GetModuleInfo(FZXTuneModule, FModuleInfo) then
    begin
      ZXTune_CloseModule(FZXTuneModule);
      ZXTune_CloseData(FZXTuneData);
      FZXTuneModule := nil;
      FZXTuneData := nil;
      Exit;
    end;

    FillChar(attrBuffer, SizeOf(attrBuffer), 0);
    if ZXTune_GetModuleAttribute(FZXTuneModule, 'Title', @attrBuffer, SizeOf(attrBuffer)) then
      FCurrentSongName := String(attrBuffer)
    else
      FCurrentSongName := ExtractFileName(FileName);

    if FCurrentSongName = '' then
      FCurrentSongName := 'Unknown';

    FillChar(attrBuffer, SizeOf(attrBuffer), 0);
    if ZXTune_GetModuleAttribute(FZXTuneModule, 'Author', @attrBuffer, SizeOf(attrBuffer)) then
      FCurrentAuthor := String(attrBuffer)
    else
      FCurrentAuthor := 'Unknown';

    FillChar(attrBuffer, SizeOf(attrBuffer), 0);
    if ZXTune_GetModuleAttribute(FZXTuneModule, 'Type', @attrBuffer, SizeOf(attrBuffer)) then
      FCurrentModuleType := String(attrBuffer)
    else
      FCurrentModuleType := 'Module';

    FZXTunePlayer := ZXTune_CreatePlayer(FZXTuneModule);
    if FZXTunePlayer = nil then
    begin
      ZXTune_CloseModule(FZXTuneModule);
      ZXTune_CloseData(FZXTuneData);
      FZXTuneModule := nil;
      FZXTuneData := nil;
      Exit;
    end;

    FPlaybackProgress := 0;
    FIsPaused := False;

    if FLoopMode then
      SetLoopMode(True);

    if FFTAccumulatorLock <> nil then
    begin
      FFTAccumulatorLock.Enter;
      try
        FFTAccumulatorPos := 0;
        FillChar(FFTAccumulator[0], Length(FFTAccumulator) * SizeOf(SmallInt), 0);
      finally
        FFTAccumulatorLock.Leave;
      end;
    end;

    if FRingBufferCriticalSection <> nil then
    begin
      FRingBufferCriticalSection.Enter;
      try
        FillChar(FFTPrevMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
        FillChar(FFTAttackMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
        FillChar(FFTReleaseMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
        FillChar(FFTSpectrumData, SizeOf(FFTSpectrumData), 0);
        FRingBufferWritePos := 0;
        FRingBufferReadPos := 0;
        FRingBufferDataAvailable := 0;
        FillChar(FAudioRingBuffer[0], FRingBufferSize * SizeOf(SmallInt), 0);
      finally
        FRingBufferCriticalSection.Leave;
      end;
    end;

    FFTDataReady := False;
    FFFTUpdateCounter := 0;
    FFFTProcessCount := 0;
    FLastFFTTime := 0;

    Result := True;

  except
    on E: Exception do
    begin
      Result := False;
    end;
  end;
end;

procedure TZXTunePlayer.Play;
begin
  if (FZXTunePlayer = nil) or not FInitialized then
    Exit;

  GlobalCurrentPlayer := Self;
  FPlaybackState := psPlaying;
  FIsPaused := False;
  FTrackEndTriggered := False;
  PlayAudioStream(FAudioStream);

  if Assigned(FOnStateChanged) then
    FOnStateChanged(Self);
end;

procedure TZXTunePlayer.Stop;
begin
  FCurrentSongName := '-';
  FCurrentAuthor := '-';
  FCurrentModuleType := '-';

  if GlobalCurrentPlayer = Self then
    GlobalCurrentPlayer := nil;

  FPlaybackState := psStopped;
  FPlaybackProgress := 0;
  FIsPaused := False;
  FFTDataReady := False;
  FTrackEndTriggered := False;

  if IsAudioStreamValid(FAudioStream) then
    StopAudioStream(FAudioStream);

  if FZXTunePlayer <> nil then
  begin
    ZXTune_DestroyPlayer(FZXTunePlayer);
    FZXTunePlayer := nil;
  end;

  if FZXTuneModule <> nil then
  begin
    ZXTune_CloseModule(FZXTuneModule);
    FZXTuneModule := nil;
  end;

  if FZXTuneData <> nil then
  begin
    ZXTune_CloseData(FZXTuneData);
    FZXTuneData := nil;
  end;

  if Assigned(FOnStateChanged) then
    FOnStateChanged(Self);
end;

procedure TZXTunePlayer.Pause;
begin
  if (FPlaybackState = psPlaying) and (FZXTunePlayer <> nil) then
  begin
    PauseAudioStream(FAudioStream);
    FPlaybackState := psPaused;
    FIsPaused := True;

    if Assigned(FOnStateChanged) then
      FOnStateChanged(Self);
  end;
end;

procedure TZXTunePlayer.Resume;
begin
  if (FPlaybackState = psPaused) and (FZXTunePlayer <> nil) then
  begin
    ResumeAudioStream(FAudioStream);
    FPlaybackState := psPlaying;
    FIsPaused := False;

    if Assigned(FOnStateChanged) then
      FOnStateChanged(Self);
  end;
end;

procedure TZXTunePlayer.UpdateProgress;
begin
  if (FPlaybackState = psPlaying) and (FZXTunePlayer <> nil) then
  begin
    FPlaybackProgress := GetProgressPercent / 100;

    if Assigned(FOnProgressChanged) then
      FOnProgressChanged(Self);

    if FTrackEndTriggered then
    begin
      FTrackEndTriggered := False;
      if Assigned(FOnTrackEnd) then
        FOnTrackEnd(Self);
    end;
  end;
end;

function TZXTunePlayer.GetSpectrumData: PSingle;
begin
  Result := @FFTSpectrumData[0];
end;

function TZXTunePlayer.GetSpectrumSize: Integer;
begin
  Result := FFTBufferSize;
end;

{ Настройка спектроанализатора }

procedure TZXTunePlayer.SetFFTSmoothing(Value: Single);
begin
  FFTConfig.SmoothingTimeConstant := Clamp(Value, 0.3, 0.98);
end;

procedure TZXTunePlayer.SetFFTAttack(Value: Single);
begin
  FFTConfig.AttackTime := Clamp(Value, 0.01, 0.5);
end;

procedure TZXTunePlayer.SetFFTRelease(Value: Single);
begin
  FFTConfig.ReleaseTime := Clamp(Value, 0.05, 1.0);
end;

procedure TZXTunePlayer.SetFFTSensitivity(Value: Single);
begin
  FFTConfig.Sensitivity := Clamp(Value, 0.3, 3.0);
end;

procedure TZXTunePlayer.SetFFTBoost(HighBoost, LowBoost: Single);
begin
  FFTConfig.BoostHighFrequencies := Clamp(HighBoost, 0.5, 2.5);
  FFTConfig.BoostLowFrequencies := Clamp(LowBoost, 0.5, 2.5);
end;

function TZXTunePlayer.GetFFTSettings: TFFTSettings;
begin
  Result := FFTConfig;
end;

procedure TZXTunePlayer.ApplyPreset(presetName: string);
begin
  presetName := LowerCase(presetName);

  if presetName = 'smooth' then
  begin
    // Плавный, музыкальный
    FFTConfig.SmoothingTimeConstant := 0.92;
    FFTConfig.AttackTime := 0.05;
    FFTConfig.ReleaseTime := 0.35;
    FFTConfig.Sensitivity := 0.9;
    FFTConfig.BoostHighFrequencies := 1.1;
    FFTConfig.BoostLowFrequencies := 0.9;
    FFTConfig.NormalizationFactor := 1.1;
    FFTConfig.UseLogScale := True;
  end
  else if presetName = 'sharp' then
  begin
    // Резкий, быстрый
    FFTConfig.SmoothingTimeConstant := 0.5;
    FFTConfig.AttackTime := 0.02;
    FFTConfig.ReleaseTime := 0.1;
    FFTConfig.Sensitivity := 1.5;
    FFTConfig.BoostHighFrequencies := 1.3;
    FFTConfig.BoostLowFrequencies := 1.0;
    FFTConfig.NormalizationFactor := 1.3;
    FFTConfig.UseLogScale := False;
  end
  else if presetName = 'club' then
  begin
    // Клубный (ударные и бас)
    FFTConfig.SmoothingTimeConstant := 0.7;
    FFTConfig.AttackTime := 0.03;
    FFTConfig.ReleaseTime := 0.25;
    FFTConfig.Sensitivity := 1.2;
    FFTConfig.BoostHighFrequencies := 1.2;
    FFTConfig.BoostLowFrequencies := 1.5;
    FFTConfig.NormalizationFactor := 1.0;
    FFTConfig.UseLogScale := True;
  end
  else if presetName = 'classic' then
  begin
    // Классический (как в старых плеерах)
    FFTConfig.SmoothingTimeConstant := 0.85;
    FFTConfig.AttackTime := 0.03;
    FFTConfig.ReleaseTime := 0.2;
    FFTConfig.Sensitivity := 1.0;
    FFTConfig.BoostHighFrequencies := 1.0;
    FFTConfig.BoostLowFrequencies := 1.0;
    FFTConfig.NormalizationFactor := 1.0;
    FFTConfig.UseLogScale := False;
  end;

  // Сброс накопленных значений для плавного перехода
  if FFTPrevMagnitudes <> nil then
    FillChar(FFTPrevMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
  if FFTAttackMagnitudes <> nil then
    FillChar(FFTAttackMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
  if FFTReleaseMagnitudes <> nil then
    FillChar(FFTReleaseMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
end;

procedure TZXTunePlayer.ResetFFTSettings;
begin
  FFTConfig.SmoothingTimeConstant := DEFAULT_SMOOTHING;
  FFTConfig.AttackTime := DEFAULT_ATTACK;
  FFTConfig.ReleaseTime := DEFAULT_RELEASE;
  FFTConfig.MinDecibels := DEFAULT_MIN_DB;
  FFTConfig.MaxDecibels := DEFAULT_MAX_DB;
  FFTConfig.NormalizationFactor := DEFAULT_NORMALIZATION;
  FFTConfig.Sensitivity := DEFAULT_SENSITIVITY;
  FFTConfig.BoostHighFrequencies := DEFAULT_HIGH_BOOST;
  FFTConfig.BoostLowFrequencies := DEFAULT_LOW_BOOST;
  FFTConfig.UseLogScale := True;
end;

function TZXTunePlayer.IsPlaying: boolean;
begin
  Result := FPlaybackState = psPlaying;
end;

function TZXTunePlayer.IsPaused: boolean;
begin
  Result := FPlaybackState = psPaused;
end;

function TZXTunePlayer.IsStopped: boolean;
begin
  Result := FPlaybackState = psStopped;
end;

function TZXTunePlayer.GetPosition: Integer;
begin
  Result := 0;
  FPositionLock.Enter;
  try
    if FZXTunePlayer <> nil then
    begin
      Result := ZXTune_GetPositionMsWithLoop(FZXTunePlayer, @FModuleInfo);
      if Result < 0 then Result := 0;
    end;
  finally
    FPositionLock.Leave;
  end;
end;

function TZXTunePlayer.GetDuration: Integer;
begin
  Result := 0;
  FPositionLock.Enter;
  try
    if FZXTunePlayer <> nil then
    begin
      Result := ZXTune_GetDurationMs(FZXTunePlayer, @FModuleInfo);
      if Result < 0 then Result := 0;
    end;
  finally
    FPositionLock.Leave;
  end;
end;

function TZXTunePlayer.GetProgressPercent: Single;
var
  Duration: Integer;
begin
  Duration := GetDuration;
  if Duration > 0 then
    Result := (GetPosition / Duration) * 100
  else
    Result := 0;
end;

procedure TZXTunePlayer.SetLoopMode(Mode: Boolean);
begin
  if FZXTunePlayer <> nil then
  begin
    if Mode then
      FLoopMode := ZXTune_SetPlayerLoopTrack(FZXTunePlayer, 1)
    else
      FLoopMode := not ZXTune_SetPlayerLoopTrack(FZXTunePlayer, 0);
  end;
end;

function TZXTunePlayer.GetLoopMode: Boolean;
begin
  if FZXTunePlayer <> nil then
  begin
    FLoopMode := ZXTune_GetPlayerLoopTrack(FZXTunePlayer) > 0;
  end;
  Result := FLoopMode;
end;

end.
