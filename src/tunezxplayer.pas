unit TuneZXPlayer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, raylib, libzxtune, Math, raymath, SyncObjs;

type
  TPlaybackState = (psStopped, psPlaying, psPaused);

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
    FFTSpectrumData: array[0..511] of Single;
    FFTDataReady: boolean;

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
    procedure UpdateFFTFromRingBuffer;
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
  SMOOTHING_TIME_CONSTANT = 0.8;
  MIN_DECIBELS = -100.0;
  MAX_DECIBELS = -30.0;

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

  FFTSpectrum := GetMem(SizeOf(TFFTComplex) * FFTWindowSize);
  FFTWorkBuffer := GetMem(SizeOf(TFFTComplex) * FFTWindowSize);
  FFTPrevMagnitudes := GetMem(SizeOf(Single) * FFTBufferSize);

  FillChar(FFTSpectrum^, SizeOf(TFFTComplex) * FFTWindowSize, 0);
  FillChar(FFTWorkBuffer^, SizeOf(TFFTComplex) * FFTWindowSize, 0);
  FillChar(FFTPrevMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
  FillChar(FFTSpectrumData, SizeOf(FFTSpectrumData), 0);

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

  SetLength(FAudioRingBuffer, 0);
end;

procedure TZXTunePlayer.ProcessFFT(const AudioSamples: array of SmallInt);
var
  i, bin: Integer;
  x, blackmanWeight, re, im, linearMagnitude, smoothedMagnitude, db, normalized: Single;
  sampleCount: Integer;
begin
  sampleCount := Length(AudioSamples);
  if sampleCount < FFTWindowSize then
    Exit;

  for i := 0 to FFTWindowSize - 1 do
  begin
    x := (2.0 * PI * i) / (FFTWindowSize - 1.0);
    blackmanWeight := 0.42 - 0.5 * Cos(x) + 0.08 * Cos(2.0 * x);

    FFTWorkBuffer[i].real := (AudioSamples[i] / 32767.0) * blackmanWeight;
    FFTWorkBuffer[i].imaginary := 0.0;
  end;

  CooleyTukeyFFT(FFTWorkBuffer, FFTWindowSize);
  Move(FFTWorkBuffer^, FFTSpectrum^, SizeOf(TFFTComplex) * FFTWindowSize);

  for bin := 0 to FFTBufferSize - 1 do
  begin
    re := FFTWorkBuffer[bin].real;
    im := FFTWorkBuffer[bin].imaginary;
    linearMagnitude := Sqrt(re * re + im * im) / FFTWindowSize;

    smoothedMagnitude := SMOOTHING_TIME_CONSTANT * FFTPrevMagnitudes[bin] +
                        (1.0 - SMOOTHING_TIME_CONSTANT) * linearMagnitude;
    FFTPrevMagnitudes[bin] := smoothedMagnitude;

    if smoothedMagnitude > 1e-40 then
      db := Ln(smoothedMagnitude) * 20.0 / Ln(10)
    else
      db := MIN_DECIBELS;

    normalized := (db - MIN_DECIBELS) / (MAX_DECIBELS - MIN_DECIBELS);
    FFTSpectrumData[bin] := Clamp(normalized, 0.0, 1.0);
  end;

  FFTDataReady := True;
end;

procedure TZXTunePlayer.UpdateFFTFromRingBuffer;
var
  samplesToRead: Integer;
  audioSamples: array of SmallInt;
  i: Integer;
begin
  if FRingBufferCriticalSection = nil then
    Exit;

  Inc(FFFTUpdateCounter);
  if FFFTUpdateCounter < 4 then
    Exit;
  FFFTUpdateCounter := 0;

  FRingBufferCriticalSection.Enter;
  try
    samplesToRead := FRingBufferDataAvailable;
    if samplesToRead < FFTWindowSize then
      Exit;

    samplesToRead := FFTWindowSize;
    SetLength(audioSamples, samplesToRead);

    for i := 0 to samplesToRead - 1 do
    begin
      audioSamples[i] := FAudioRingBuffer[FRingBufferReadPos];
      FRingBufferReadPos := (FRingBufferReadPos + 1) mod FRingBufferSize;
    end;

    FRingBufferDataAvailable := FRingBufferDataAvailable - samplesToRead;
  finally
    FRingBufferCriticalSection.Leave;
  end;

  ProcessFFT(audioSamples);
end;

{ TZXTunePlayer - Main Implementation }

class procedure TZXTunePlayer.AudioCallback(bufferData: pointer; frames: LongWord); cdecl;
var
  i: Integer;
  samples: PSmallInt;
  writePos: Integer;
  player: TZXTunePlayer;
  SamplesRendered: Integer;
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

  if player.FRingBufferCriticalSection <> nil then
  begin
    player.FRingBufferCriticalSection.Enter;
    try
      for i := 0 to frames - 1 do
      begin
        if player.FRingBufferDataAvailable < player.FRingBufferSize - 1 then
        begin
          writePos := player.FRingBufferWritePos;
          player.FAudioRingBuffer[writePos] := (samples[i * 2] + samples[i * 2 + 1]) div 2;
          player.FRingBufferWritePos := (writePos + 1) mod player.FRingBufferSize;
          player.FRingBufferDataAvailable := player.FRingBufferDataAvailable + 1;
        end;
      end;
    finally
      player.FRingBufferCriticalSection.Leave;
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
      // Получаем частоту дискретизации (уже загружена)
      Frequency := ZXTune_GetSoundFrequency(FZXTunePlayer);
      if Frequency <= 0 then
        Frequency := 44100;  // Значение по умолчанию

      // Конвертируем миллисекунды в семплы
      SamplePos := (NativeUInt(PositionMs) * Frequency) div 1000;

      // Используем ZXTune_SeekSound для перемотки
      if ZXTune_SeekSound(FZXTunePlayer, SamplePos) >= 0 then
      begin
        // Сбрасываем флаг конца трека
        FTrackEndTriggered := False;

        // Обновляем буфер FFT
        if FRingBufferCriticalSection <> nil then
        begin
          FRingBufferCriticalSection.Enter;
          try
            FRingBufferWritePos := 0;
            FRingBufferReadPos := 0;
            FRingBufferDataAvailable := 0;
            FillChar(FAudioRingBuffer[0], FRingBufferSize * SizeOf(SmallInt), 0);
            FillChar(FFTPrevMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
            FillChar(FFTSpectrumData, SizeOf(FFTSpectrumData), 0);
          finally
            FRingBufferCriticalSection.Leave;
          end;
        end;
        FFTDataReady := False;
        FFFTUpdateCounter := 0;
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
    // Ограничиваем диапазон
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
      FCurrentSongName := String(attrBuffer);

    FillChar(attrBuffer, SizeOf(attrBuffer), 0);
    if ZXTune_GetModuleAttribute(FZXTuneModule, 'Author', @attrBuffer, SizeOf(attrBuffer)) then
      FCurrentAuthor := String(attrBuffer);

    FillChar(attrBuffer, SizeOf(attrBuffer), 0);
    if ZXTune_GetModuleAttribute(FZXTuneModule, 'Type', @attrBuffer, SizeOf(attrBuffer)) then
      FCurrentModuleType := String(attrBuffer);

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

    if FRingBufferCriticalSection <> nil then
    begin
      FRingBufferCriticalSection.Enter;
      try
        FillChar(FFTPrevMagnitudes^, SizeOf(Single) * FFTBufferSize, 0);
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

    Result := True;

  except
    Result := False;
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

    UpdateFFTFromRingBuffer;

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

{ TZXTunePlayer - Position and Duration Methods }
function TZXTunePlayer.GetPosition: Integer;
begin
  Result := 0;
  FPositionLock.Enter;
  try
    if FZXTunePlayer <> nil then
    begin
      // Используем новую функцию, которая сама корректирует позицию при loop
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
