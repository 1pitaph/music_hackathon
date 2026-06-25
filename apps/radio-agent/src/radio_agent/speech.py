from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import tempfile
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass, replace
from collections.abc import Iterator
from pathlib import Path

import httpx

from radio_agent.schemas import (
  RadioSpeechAudio,
  RadioSpeechAudioConfig,
  RadioSpeechCue,
  RadioSpeechSegment,
  RadioSpeechSynthesisResult,
  RadioSpeechTimingWord,
)
from radio_agent.voices import resolve_speech_speaker

DEFAULT_OPENAI_SPEECH_MODEL = "gpt-4o-mini-tts"
DEFAULT_OPENAI_SPEECH_VOICE = "coral"
DEFAULT_VOLCENGINE_SPEECH_MODEL = "seed-tts-1.0"
DEFAULT_VOLCENGINE_RESOURCE_ID = "seed-tts-1.0"
DEFAULT_VOLCENGINE_ENDPOINT = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
DEFAULT_SPEECH_FORMAT = "mp3"
DEFAULT_VOLCENGINE_SAMPLE_RATE = 24000
DEFAULT_VOLCENGINE_BIT_RATE = 128000
DEFAULT_VOLCENGINE_TIMEOUT_SECONDS = 30.0
DEFAULT_SPEECH_SYNTHESIS_MAX_WORKERS = 4
SPEECH_SUBTITLE_CACHE_VERSION = "subtitle-v1"
VOLCENGINE_FINISH_CODE = 20000000
SENTENCE_TERMINATORS = set(".!?。！？")

MIME_TYPES = {
  "aac": "audio/aac",
  "mp3": "audio/mpeg",
  "wav": "audio/wav",
  "pcm": "audio/pcm",
  "ogg_opus": "audio/ogg",
}


@dataclass(frozen=True)
class SpeechSynthesisContext:
  provider: str
  model: str
  voice: str
  resource_id: str
  audio_format: str
  sample_rate: int
  bit_rate: int
  speech_rate: int
  loudness_rate: int
  pitch: int | None
  explicit_language: str | None
  emotion: str | None


@dataclass(frozen=True)
class VolcengineSettings:
  endpoint: str
  api_key: str
  resource_id: str
  timeout_seconds: float
  require_usage_tokens: bool


def synthesize_speech_segments(
  segments: list[RadioSpeechSegment],
  config: RadioSpeechAudioConfig,
) -> tuple[list[RadioSpeechSynthesisResult], list[str]]:
  diagnostics: list[str] = []
  results: list[RadioSpeechSynthesisResult] = []
  context, volcengine_settings, runtime_diagnostics = _configured_speech_runtime(config)
  diagnostics.extend(runtime_diagnostics)

  if not segments:
    return [], diagnostics

  if config.delivery == "stream":
    return _prepare_streaming_speech_segments(
      segments,
      context,
      volcengine_settings,
      diagnostics,
    )

  if context.provider == "volcengine" and _speech_is_configured() and volcengine_settings:
    results, synthesis_diagnostics = _synthesize_volcengine_segments(
      segments,
      context,
      volcengine_settings,
    )
    diagnostics.extend(synthesis_diagnostics)
    return results, diagnostics

  for segment in segments:
    audio = _unavailable_audio(segment, context)
    if context.provider == "mock":
      audio_url = _mock_audio_url(audio.cacheKey, context.audio_format)
      audio = audio.model_copy(update={
        "audioURL": audio_url,
        "status": "ready" if audio_url else "unavailable",
      })

    results.append(RadioSpeechSynthesisResult(
      **segment.model_dump(),
      audio=audio,
    ))

  return results, diagnostics


def _configured_speech_runtime(
  config: RadioSpeechAudioConfig,
) -> tuple[SpeechSynthesisContext, VolcengineSettings | None, list[str]]:
  diagnostics: list[str] = []
  context = _speech_context(config)
  volcengine_settings: VolcengineSettings | None = None

  if context.provider == "mock":
    diagnostics.append("Using mock speech synthesis metadata.")
  elif not _speech_is_configured():
    diagnostics.append("Speech synthesis is not configured; returning text-only speech metadata.")
  elif context.provider == "volcengine":
    speaker, speaker_diagnostics = resolve_speech_speaker(context.voice)
    context = replace(context, voice=speaker)
    diagnostics.extend(speaker_diagnostics)
    volcengine_settings, settings_diagnostics = _volcengine_settings(context)
    diagnostics.extend(settings_diagnostics)
  else:
    diagnostics.append(
      f"Speech provider '{context.provider}' is not implemented; returning text-only speech metadata."
    )

  return context, volcengine_settings, diagnostics


def _prepare_streaming_speech_segments(
  segments: list[RadioSpeechSegment],
  context: SpeechSynthesisContext,
  volcengine_settings: VolcengineSettings | None,
  diagnostics: list[str],
) -> tuple[list[RadioSpeechSynthesisResult], list[str]]:
  if context.provider == "mock":
    return _mock_streaming_speech_segments(segments, context, diagnostics)

  if context.provider != "volcengine" or not _speech_is_configured() or not volcengine_settings:
    results = [
      RadioSpeechSynthesisResult(
        **segment.model_dump(),
        audio=_unavailable_audio(segment, context),
      )
      for segment in segments
    ]
    return results, diagnostics

  results: list[RadioSpeechSynthesisResult] = []
  for segment in segments:
    cache_key = _cache_key_for_context(segment.text, context)
    file_name = f"{cache_key}.{context.audio_format}"
    file_path = speech_audio_file_path(file_name)
    audio_url = _speech_audio_url(file_name)
    stream_url = _speech_stream_url(file_name)

    if not file_path:
      diagnostics.append(f"Speech audio cache path is invalid for {file_name}.")
      audio = _unavailable_audio(segment, context, cache_key)
    elif not audio_url or not stream_url:
      diagnostics.append("SPEECH_PUBLIC_BASE_URL is required before returning streamable speech audio.")
      audio = _unavailable_audio(segment, context, cache_key)
    elif file_path.exists() and file_path.stat().st_size > 0:
      metadata = _read_speech_metadata(file_path)
      audio = _ready_audio(
        segment,
        context,
        cache_key,
        audio_url,
        stream_url=stream_url,
        cues=metadata["cues"],
        duration_seconds=metadata["durationSeconds"],
      )
    else:
      duration_seconds = _estimated_duration(segment.text)
      _write_speech_metadata(
        file_path,
        duration_seconds,
        [],
        segment=segment,
        context=context,
      )
      audio = _ready_audio(
        segment,
        context,
        cache_key,
        audio_url,
        stream_url=stream_url,
        duration_seconds=duration_seconds,
      )

    results.append(RadioSpeechSynthesisResult(
      **segment.model_dump(),
      audio=audio,
    ))

  return results, diagnostics


def _mock_streaming_speech_segments(
  segments: list[RadioSpeechSegment],
  context: SpeechSynthesisContext,
  diagnostics: list[str],
) -> tuple[list[RadioSpeechSynthesisResult], list[str]]:
  results: list[RadioSpeechSynthesisResult] = []
  for segment in segments:
    cache_key = _cache_key_for_context(segment.text, context)
    audio_url = _mock_audio_url(cache_key, context.audio_format)
    stream_url = _mock_stream_url(cache_key, context.audio_format)
    audio = RadioSpeechAudio(
      audioURL=audio_url,
      streamURL=stream_url,
      mimeType=MIME_TYPES.get(context.audio_format, "audio/mpeg"),
      durationSeconds=_estimated_duration(segment.text),
      cacheKey=cache_key,
      voice=context.voice or DEFAULT_OPENAI_SPEECH_VOICE,
      model=context.model,
      status="ready" if audio_url or stream_url else "unavailable",
      cues=[],
    )
    results.append(RadioSpeechSynthesisResult(
      **segment.model_dump(),
      audio=audio,
    ))
  return results, diagnostics


def _synthesize_volcengine_segments(
  segments: list[RadioSpeechSegment],
  context: SpeechSynthesisContext,
  settings: VolcengineSettings,
) -> tuple[list[RadioSpeechSynthesisResult], list[str]]:
  diagnostics: list[str] = []
  unique_segments: dict[str, RadioSpeechSegment] = {}
  for segment in segments:
    cache_key = _cache_key_for_context(segment.text, context)
    unique_segments.setdefault(cache_key, segment)

  audio_by_cache_key: dict[str, RadioSpeechAudio] = {}
  diagnostics_by_cache_key: dict[str, list[str]] = {}
  max_workers = min(DEFAULT_SPEECH_SYNTHESIS_MAX_WORKERS, max(1, len(unique_segments)))

  with ThreadPoolExecutor(max_workers=max_workers) as executor:
    futures = {
      cache_key: executor.submit(_synthesize_volcengine_segment, segment, context, settings)
      for cache_key, segment in unique_segments.items()
    }
    for cache_key, segment in unique_segments.items():
      try:
        audio, segment_diagnostics = futures[cache_key].result()
      except Exception as exc:  # pragma: no cover - defensive around third-party clients.
        audio = _unavailable_audio(segment, context, cache_key)
        segment_diagnostics = [
          f"Volcengine TTS request failed for segment '{segment.id}': {exc.__class__.__name__}."
        ]
      audio_by_cache_key[cache_key] = audio
      diagnostics_by_cache_key[cache_key] = segment_diagnostics

  for cache_key in unique_segments:
    diagnostics.extend(diagnostics_by_cache_key.get(cache_key, []))

  results = []
  for segment in segments:
    cache_key = _cache_key_for_context(segment.text, context)
    audio = audio_by_cache_key.get(cache_key) or _unavailable_audio(segment, context, cache_key)
    results.append(RadioSpeechSynthesisResult(
      **segment.model_dump(),
      audio=audio,
    ))

  return results, diagnostics


def cache_key_for(
  text: str,
  provider: str,
  model: str,
  voice: str,
  audio_format: str,
  *,
  resource_id: str | None = None,
  sample_rate: int | None = None,
  bit_rate: int | None = None,
  speech_rate: int | None = None,
  loudness_rate: int | None = None,
  pitch: int | None = None,
  explicit_language: str | None = None,
  emotion: str | None = None,
) -> str:
  digest = hashlib.sha256(
    "|".join([
      provider,
      resource_id or "",
      model,
      voice,
      audio_format,
      str(sample_rate or ""),
      str(bit_rate or ""),
      str(speech_rate if speech_rate is not None else ""),
      str(loudness_rate if loudness_rate is not None else ""),
      str(pitch if pitch is not None else ""),
      explicit_language or "",
      emotion or "",
      SPEECH_SUBTITLE_CACHE_VERSION,
      text.strip(),
    ]).encode("utf-8")
  ).hexdigest()[:24]
  return f"speech_{digest}"


def speech_audio_file_path(file_name: str) -> Path | None:
  if "/" in file_name or "\\" in file_name or Path(file_name).name != file_name:
    return None

  extension = Path(file_name).suffix.removeprefix(".").lower()
  if not extension or extension not in MIME_TYPES:
    return None

  cache_dir = _speech_cache_dir()
  path = cache_dir / file_name
  try:
    if cache_dir.resolve() not in path.resolve().parents:
      return None
  except RuntimeError:
    return None
  return path


def speech_audio_mime_type(file_name: str) -> str:
  extension = Path(file_name).suffix.removeprefix(".").lower()
  return MIME_TYPES.get(extension, "application/octet-stream")


def ensure_speech_audio_file(file_name: str) -> Path | None:
  file_path = speech_audio_file_path(file_name)
  if not file_path:
    return None
  if file_path.is_file():
    return file_path

  prepared = _read_prepared_speech(file_path)
  if not prepared:
    return None

  segment, context = prepared
  settings, _ = _settings_for_prepared_stream(context)
  if not settings:
    return None

  audio, _ = _synthesize_volcengine_segment(segment, context, settings)
  if audio.status != "ready":
    return None
  return file_path if file_path.is_file() else None


def can_stream_speech_audio(file_name: str) -> bool:
  file_path = speech_audio_file_path(file_name)
  if not file_path:
    return False
  return file_path.is_file() or _read_prepared_speech(file_path) is not None


def stream_speech_audio_file(file_name: str) -> Iterator[bytes]:
  file_path = speech_audio_file_path(file_name)
  if not file_path:
    return iter(())
  if file_path.is_file():
    return _iter_file_chunks(file_path)

  prepared = _read_prepared_speech(file_path)
  if not prepared:
    return iter(())

  segment, context = prepared
  settings, diagnostics = _settings_for_prepared_stream(context)
  if not settings:
    return _iter_raise(ValueError("; ".join(diagnostics) or "Speech stream is not configured."))
  return _stream_volcengine_segment_to_cache(segment, context, settings, file_path)


def _speech_context(config: RadioSpeechAudioConfig) -> SpeechSynthesisContext:
  provider = _normalize_provider(config.provider)
  model = _resolve_model(config, provider)
  voice = _resolve_voice(config, provider)
  resource_id = _resolve_resource_id(config, provider)
  audio_format = (config.format or os.getenv("SPEECH_FORMAT") or DEFAULT_SPEECH_FORMAT).lower()
  sample_rate = config.sampleRate or _int_env("VOLCENGINE_TTS_SAMPLE_RATE", DEFAULT_VOLCENGINE_SAMPLE_RATE)
  bit_rate = config.bitRate or _int_env("VOLCENGINE_TTS_BIT_RATE", DEFAULT_VOLCENGINE_BIT_RATE)
  speech_rate = _resolve_speech_rate(config)
  loudness_rate = _resolve_loudness_rate(config)
  pitch = config.pitch if config.pitch is not None else _optional_int_env("VOLCENGINE_TTS_PITCH")
  explicit_language = config.explicitLanguage or config.language or os.getenv("VOLCENGINE_TTS_EXPLICIT_LANGUAGE")
  return SpeechSynthesisContext(
    provider=provider,
    model=model,
    voice=voice,
    resource_id=resource_id,
    audio_format=audio_format,
    sample_rate=sample_rate,
    bit_rate=bit_rate,
    speech_rate=speech_rate,
    loudness_rate=loudness_rate,
    pitch=pitch,
    explicit_language=explicit_language,
    emotion=config.emotion,
  )


def _normalize_provider(request_provider: str | None) -> str:
  requested = (request_provider or "").strip().lower()
  env_provider = (os.getenv("SPEECH_PROVIDER") or "").strip().lower()

  if requested == "mock":
    return "mock"
  if env_provider and env_provider != "openai":
    return "volcengine" if env_provider == "doubao" else env_provider
  if requested == "doubao":
    return "volcengine"
  return requested or env_provider or "openai"


def _resolve_model(config: RadioSpeechAudioConfig, provider: str) -> str:
  request_model = (config.model or "").strip()
  speech_model = (os.getenv("SPEECH_MODEL") or "").strip()
  if provider == "volcengine":
    volcengine_model = (os.getenv("VOLCENGINE_TTS_MODEL") or "").strip()
    if request_model and request_model not in {DEFAULT_OPENAI_SPEECH_MODEL, "volcengine-tts"}:
      return request_model
    if volcengine_model:
      return volcengine_model
    if speech_model and speech_model not in {DEFAULT_OPENAI_SPEECH_MODEL, "volcengine-tts"}:
      return speech_model
    return DEFAULT_VOLCENGINE_SPEECH_MODEL
  return request_model or speech_model or DEFAULT_OPENAI_SPEECH_MODEL


def _resolve_voice(config: RadioSpeechAudioConfig, provider: str) -> str:
  request_voice = (config.voice or "").strip()
  speech_voice = (os.getenv("SPEECH_DEFAULT_VOICE") or "").strip()
  if provider == "volcengine":
    request_speaker = (config.speaker or "").strip()
    volcengine_voice = (
      os.getenv("VOLCENGINE_TTS_SPEAKER")
      or os.getenv("VOLCENGINE_TTS_VOICE_TYPE")
      or ""
    ).strip()
    if request_speaker:
      return request_speaker
    if volcengine_voice:
      return volcengine_voice
    if request_voice and request_voice != DEFAULT_OPENAI_SPEECH_VOICE:
      return request_voice
    return speech_voice or request_voice
  return request_voice or speech_voice or DEFAULT_OPENAI_SPEECH_VOICE


def _resolve_resource_id(config: RadioSpeechAudioConfig, provider: str) -> str:
  if provider != "volcengine":
    return ""
  request_resource_id = (config.resourceId or "").strip()
  env_resource_id = (os.getenv("VOLCENGINE_TTS_RESOURCE_ID") or "").strip()
  deprecated_cluster = (os.getenv("VOLCENGINE_TTS_CLUSTER") or "").strip()
  if request_resource_id:
    return request_resource_id
  if env_resource_id:
    return env_resource_id
  if deprecated_cluster.startswith("seed-"):
    return deprecated_cluster
  return DEFAULT_VOLCENGINE_RESOURCE_ID


def _resolve_speech_rate(config: RadioSpeechAudioConfig) -> int:
  if config.speechRate is not None:
    return config.speechRate
  env_rate = _optional_int_env("VOLCENGINE_TTS_SPEECH_RATE")
  if env_rate is not None:
    return _clamp_int(env_rate, -50, 100)
  speed_ratio = config.speedRatio or _float_env("VOLCENGINE_TTS_DEFAULT_SPEED_RATIO", 1.0)
  return _ratio_to_v3_rate(speed_ratio)


def _resolve_loudness_rate(config: RadioSpeechAudioConfig) -> int:
  if config.loudnessRate is not None:
    return config.loudnessRate
  env_rate = _optional_int_env("VOLCENGINE_TTS_LOUDNESS_RATE")
  if env_rate is not None:
    return _clamp_int(env_rate, -50, 100)
  volume_ratio = config.volumeRatio or _float_env("VOLCENGINE_TTS_DEFAULT_VOLUME_RATIO", 1.0)
  return _ratio_to_v3_rate(volume_ratio)


def _volcengine_settings(context: SpeechSynthesisContext) -> tuple[VolcengineSettings | None, list[str]]:
  endpoint = os.getenv("VOLCENGINE_TTS_ENDPOINT") or DEFAULT_VOLCENGINE_ENDPOINT
  api_key = os.getenv("VOLCENGINE_TTS_API_KEY", "").strip()

  missing = [
    name
    for name, value in [
      ("VOLCENGINE_TTS_API_KEY", api_key),
      ("VOLCENGINE_TTS_RESOURCE_ID or speechAudio.resourceId", context.resource_id),
      ("VOLCENGINE_TTS_SPEAKER or speechAudio.speaker", context.voice),
    ]
    if not value
  ]
  if missing:
    return None, [
      "Volcengine TTS is missing required configuration: "
      + ", ".join(missing)
      + "."
    ]

  return VolcengineSettings(
    endpoint=endpoint,
    api_key=api_key,
    resource_id=context.resource_id,
    timeout_seconds=_float_env("VOLCENGINE_TTS_TIMEOUT_SECONDS", DEFAULT_VOLCENGINE_TIMEOUT_SECONDS),
    require_usage_tokens=_bool_env("VOLCENGINE_TTS_REQUIRE_USAGE_TOKENS", False),
  ), []


def _synthesize_volcengine_segment(
  segment: RadioSpeechSegment,
  context: SpeechSynthesisContext,
  settings: VolcengineSettings,
) -> tuple[RadioSpeechAudio, list[str]]:
  diagnostics: list[str] = []
  cache_key = _cache_key_for_context(segment.text, context)
  file_name = f"{cache_key}.{context.audio_format}"
  file_path = speech_audio_file_path(file_name)
  audio_url = _speech_audio_url(file_name)

  if file_path and file_path.exists() and file_path.stat().st_size > 0:
    if audio_url:
      metadata = _read_speech_metadata(file_path)
      return _ready_audio(
        segment,
        context,
        cache_key,
        audio_url,
        cues=metadata["cues"],
        duration_seconds=metadata["durationSeconds"],
      ), diagnostics
    diagnostics.append("Speech audio cache hit, but SPEECH_PUBLIC_BASE_URL is not configured.")
    return _unavailable_audio(segment, context, cache_key), diagnostics

  if not file_path:
    diagnostics.append(f"Speech audio cache path is invalid for {file_name}.")
    return _unavailable_audio(segment, context, cache_key), diagnostics

  if not audio_url:
    diagnostics.append("SPEECH_PUBLIC_BASE_URL is required before returning ready speech audio.")
    return _unavailable_audio(segment, context, cache_key), diagnostics

  payload = _volcengine_payload(segment, context)
  request_id = f"{cache_key}_{uuid.uuid4().hex[:8]}"
  headers = {
    "Content-Type": "application/json",
    "X-Api-Key": settings.api_key,
    "X-Api-Resource-Id": settings.resource_id,
    "X-Api-Request-Id": request_id,
  }
  if settings.require_usage_tokens:
    headers["X-Control-Require-Usage-Tokens-Return"] = "*"

  try:
    with httpx.stream(
      "POST",
      settings.endpoint,
      headers=headers,
      json=payload,
      timeout=settings.timeout_seconds,
    ) as response:
      if response.status_code != 200:
        diagnostics.append(
          f"Volcengine TTS request failed for segment '{segment.id}' with HTTP {response.status_code}."
        )
        return _unavailable_audio(segment, context, cache_key), diagnostics

      audio_bytes, timing_words, response_diagnostics = _volcengine_audio_bytes(response, segment.id)
      diagnostics.extend(response_diagnostics)
  except (httpx.HTTPError, ValueError) as exc:
    diagnostics.append(
      f"Volcengine TTS request failed for segment '{segment.id}': {exc.__class__.__name__}."
    )
    return _unavailable_audio(segment, context, cache_key), diagnostics

  if not audio_bytes:
    diagnostics.append(f"Volcengine TTS response for segment '{segment.id}' included empty audio data.")
    return _unavailable_audio(segment, context, cache_key), diagnostics

  cues = _speech_cues_from_timing_words(segment, timing_words)
  duration_seconds = _duration_seconds_from_cues(cues) or _estimated_duration(segment.text)
  _write_audio_file(file_path, audio_bytes)
  _write_speech_metadata(file_path, duration_seconds, cues, segment=segment, context=context)
  return _ready_audio(
    segment,
    context,
    cache_key,
    audio_url,
    cues=cues,
    duration_seconds=duration_seconds,
  ), diagnostics


def _volcengine_payload(
  segment: RadioSpeechSegment,
  context: SpeechSynthesisContext,
) -> dict:
  audio_params: dict[str, object] = {
    "format": context.audio_format,
    "sample_rate": context.sample_rate,
    "bit_rate": context.bit_rate,
    "speech_rate": context.speech_rate,
    "loudness_rate": context.loudness_rate,
    "enable_subtitle": True,
  }
  req_params: dict[str, object] = {
    "text": segment.text,
    "speaker": context.voice,
    "audio_params": audio_params,
  }
  wire_model = _volcengine_wire_model(context.model)
  if wire_model:
    req_params["model"] = wire_model
  if context.explicit_language:
    req_params["explicit_language"] = context.explicit_language
  if context.emotion:
    req_params["emotion"] = context.emotion
  if context.pitch is not None:
    req_params["post_process"] = {"pitch": context.pitch}

  return {
    "user": {"uid": "airset-radio-agent"},
    "req_params": req_params,
  }


def _volcengine_wire_model(model: str) -> str | None:
  stripped = model.strip()
  if stripped in {"", "seed-tts-1.0", "seed-tts-1.0-concurr"}:
    return None
  return stripped


def _volcengine_audio_bytes(
  response,
  segment_id: str,
) -> tuple[bytes, list[RadioSpeechTimingWord], list[str]]:
  diagnostics: list[str] = []
  audio_parts: list[bytes] = []
  timing_words: list[RadioSpeechTimingWord] = []
  seen_timing_words: set[tuple[str, float, float]] = set()

  for chunk_body in _volcengine_response_bodies(response):
    code = chunk_body.get("code")
    for timing_word in _extract_timing_words(chunk_body):
      key = (timing_word.word, timing_word.startTime, timing_word.endTime)
      if key in seen_timing_words:
        continue
      seen_timing_words.add(key)
      timing_words.append(timing_word)

    if _is_volcengine_finish_code(code):
      break
    if not _is_volcengine_success_code(code):
      message = str(chunk_body.get("message") or chunk_body.get("Message") or "unknown error")
      diagnostics.append(
        f"Volcengine TTS returned code {code} for segment '{segment_id}': {_safe_message(message)}."
      )
      continue

    encoded_audio = chunk_body.get("data")
    if encoded_audio is None:
      continue
    if not isinstance(encoded_audio, str) or not encoded_audio:
      diagnostics.append(f"Volcengine TTS response for segment '{segment_id}' included invalid audio data.")
      continue

    try:
      audio_parts.append(base64.b64decode(encoded_audio, validate=True))
    except (binascii.Error, ValueError):
      diagnostics.append(f"Volcengine TTS response for segment '{segment_id}' included invalid base64 audio.")

  return b"".join(audio_parts), timing_words, diagnostics


def _stream_volcengine_segment_to_cache(
  segment: RadioSpeechSegment,
  context: SpeechSynthesisContext,
  settings: VolcengineSettings,
  file_path: Path,
) -> Iterator[bytes]:
  diagnostics: list[str] = []
  timing_words: list[RadioSpeechTimingWord] = []
  seen_timing_words: set[tuple[str, float, float]] = set()
  completed = False
  wrote_audio = False

  file_path.parent.mkdir(parents=True, exist_ok=True)
  temporary_path: Path | None = None
  try:
    with tempfile.NamedTemporaryFile(dir=file_path.parent, delete=False) as temporary_file:
      temporary_path = Path(temporary_file.name)
      with httpx.stream(
        "POST",
        settings.endpoint,
        headers=_volcengine_headers(settings, _cache_key_for_context(segment.text, context)),
        json=_volcengine_payload(segment, context),
        timeout=settings.timeout_seconds,
      ) as response:
        if response.status_code != 200:
          raise ValueError(f"Volcengine TTS request failed for segment '{segment.id}' with HTTP {response.status_code}.")

        for chunk_body in _iter_volcengine_response_bodies(response):
          code = chunk_body.get("code")
          for timing_word in _extract_timing_words(chunk_body):
            key = (timing_word.word, timing_word.startTime, timing_word.endTime)
            if key in seen_timing_words:
              continue
            seen_timing_words.add(key)
            timing_words.append(timing_word)

          if _is_volcengine_finish_code(code):
            break
          if not _is_volcengine_success_code(code):
            message = str(chunk_body.get("message") or chunk_body.get("Message") or "unknown error")
            diagnostics.append(
              f"Volcengine TTS returned code {code} for segment '{segment.id}': {_safe_message(message)}."
            )
            continue

          encoded_audio = chunk_body.get("data")
          if encoded_audio is None:
            continue
          if not isinstance(encoded_audio, str) or not encoded_audio:
            diagnostics.append(f"Volcengine TTS response for segment '{segment.id}' included invalid audio data.")
            continue

          try:
            audio_bytes = base64.b64decode(encoded_audio, validate=True)
          except (binascii.Error, ValueError):
            diagnostics.append(f"Volcengine TTS response for segment '{segment.id}' included invalid base64 audio.")
            continue
          if not audio_bytes:
            continue

          temporary_file.write(audio_bytes)
          wrote_audio = True
          yield audio_bytes

    if not wrote_audio:
      raise ValueError(
        "; ".join(diagnostics)
        or f"Volcengine TTS response for segment '{segment.id}' included empty audio data."
      )

    cues = _speech_cues_from_timing_words(segment, timing_words)
    duration_seconds = _duration_seconds_from_cues(cues) or _estimated_duration(segment.text)
    temporary_path.replace(file_path)
    temporary_path = None
    _write_speech_metadata(file_path, duration_seconds, cues, segment=segment, context=context)
    completed = True
  finally:
    if not completed and temporary_path and temporary_path.exists():
      try:
        temporary_path.unlink()
      except OSError:
        pass


def _volcengine_headers(settings: VolcengineSettings, cache_key: str) -> dict[str, str]:
  request_id = f"{cache_key}_{uuid.uuid4().hex[:8]}"
  headers = {
    "Content-Type": "application/json",
    "X-Api-Key": settings.api_key,
    "X-Api-Resource-Id": settings.resource_id,
    "X-Api-Request-Id": request_id,
  }
  if settings.require_usage_tokens:
    headers["X-Control-Require-Usage-Tokens-Return"] = "*"
  return headers


def _volcengine_response_bodies(response) -> list[dict]:
  return list(_iter_volcengine_response_bodies(response))


def _iter_volcengine_response_bodies(response) -> Iterator[dict]:
  buffered = ""
  for line in response.iter_lines():
    if isinstance(line, bytes):
      line = line.decode("utf-8")
    line = line.strip()
    if not line:
      continue
    if line.startswith("data:"):
      line = line.removeprefix("data:").strip()
    buffered += line
    parsed, buffered = _consume_json_objects(buffered)
    for body in parsed:
      yield body

  if buffered.strip():
    parsed, remaining = _consume_json_objects(buffered.strip())
    for body in parsed:
      yield body
    if remaining.strip():
      raise ValueError(f"Unexpected Volcengine TTS response chunk: {remaining[:80]}")


def _extract_timing_words(body: dict) -> list[RadioSpeechTimingWord]:
  timing_words: list[RadioSpeechTimingWord] = []
  for candidate in _walk_json_like(body):
    timing_word = _timing_word_from_dict(candidate)
    if timing_word:
      timing_words.append(timing_word)

    for key in ("words", "Words", "subtitles", "Subtitles", "subtitle", "Subtitle"):
      value = candidate.get(key)
      if isinstance(value, list):
        for item in value:
          if isinstance(item, dict):
            timing_word = _timing_word_from_dict(item)
            if timing_word:
              timing_words.append(timing_word)
  return timing_words


def _walk_json_like(value: object, depth: int = 0) -> list[dict]:
  if depth > 6:
    return []
  if isinstance(value, dict):
    matches = [value]
    for nested_value in value.values():
      matches.extend(_walk_json_like(nested_value, depth + 1))
    return matches
  if isinstance(value, list):
    matches: list[dict] = []
    for item in value:
      matches.extend(_walk_json_like(item, depth + 1))
    return matches
  if isinstance(value, str):
    stripped = value.strip()
    if not stripped or stripped[0] not in "[{":
      return []
    try:
      return _walk_json_like(json.loads(stripped), depth + 1)
    except json.JSONDecodeError:
      return []
  return []


def _timing_word_from_dict(value: dict) -> RadioSpeechTimingWord | None:
  word = _first_present(value, "word", "Word", "text", "Text", "token", "Token")
  start_time = _first_present(
    value,
    "startTime",
    "StartTime",
    "start_time",
    "beginTime",
    "BeginTime",
    "begin_time",
    "start",
    "Start",
  )
  end_time = _first_present(
    value,
    "endTime",
    "EndTime",
    "end_time",
    "finishTime",
    "FinishTime",
    "finish_time",
    "end",
    "End",
  )
  if word is None or start_time is None or end_time is None:
    return None

  normalized_word = str(word).strip()
  start_seconds = _normalize_timing_seconds(start_time)
  end_seconds = _normalize_timing_seconds(end_time)
  if not normalized_word or start_seconds is None or end_seconds is None or end_seconds < start_seconds:
    return None

  confidence = _normalize_float(_first_present(value, "confidence", "Confidence", "score", "Score"))
  return RadioSpeechTimingWord(
    word=normalized_word,
    startTime=start_seconds,
    endTime=end_seconds,
    confidence=confidence,
  )


def _first_present(value: dict, *keys: str) -> object | None:
  for key in keys:
    if key in value and value[key] is not None:
      return value[key]
  return None


def _normalize_timing_seconds(value: object) -> float | None:
  normalized = _normalize_float(value)
  if normalized is None:
    return None
  if normalized > 30:
    normalized = normalized / 1000
  return round(normalized, 3)


def _normalize_float(value: object) -> float | None:
  if value is None:
    return None
  try:
    return float(value)
  except (TypeError, ValueError):
    return None


def _speech_cues_from_timing_words(
  segment: RadioSpeechSegment,
  timing_words: list[RadioSpeechTimingWord],
) -> list[RadioSpeechCue]:
  if not timing_words:
    return []

  spans = _sentence_spans(segment.text)
  words_by_span: list[list[RadioSpeechTimingWord]] = [[] for _ in spans]
  cursor = 0
  current_span_index = 0

  for timing_word in timing_words:
    word_index = _find_word_index(segment.text, timing_word.word, cursor)
    if word_index is not None:
      cursor = word_index + len(timing_word.word)
      current_span_index = _span_index(for_index=word_index, spans=spans)
    else:
      current_span_index = min(current_span_index, len(spans) - 1)
    words_by_span[current_span_index].append(timing_word)

  cues: list[RadioSpeechCue] = []
  non_empty_spans = [
    (span_index, span_words)
    for span_index, span_words in enumerate(words_by_span)
    if span_words
  ]
  for cue_index, (span_index, span_words) in enumerate(non_empty_spans):
    start, end = spans[span_index]
    text = segment.text[start:end].strip() or " ".join(word.word for word in span_words)
    display_text = segment.displayText.strip() if len(non_empty_spans) == 1 else text
    if not display_text:
      display_text = text
    cues.append(RadioSpeechCue(
      id=f"{segment.id}-cue-{cue_index + 1}",
      text=text,
      displayText=display_text,
      startTime=span_words[0].startTime,
      endTime=span_words[-1].endTime,
      words=span_words,
    ))
  return cues


def _sentence_spans(text: str) -> list[tuple[int, int]]:
  stripped = text.strip()
  if not stripped:
    return [(0, 0)]

  spans: list[tuple[int, int]] = []
  start = 0
  for index, character in enumerate(text):
    if character not in SENTENCE_TERMINATORS:
      continue
    end = index + 1
    while end < len(text) and text[end] in "\"'”’）)] ":
      end += 1
    spans.append((start, end))
    start = end

  if start < len(text):
    spans.append((start, len(text)))
  return [(start, end) for start, end in spans if text[start:end].strip()] or [(0, len(text))]


def _find_word_index(text: str, word: str, cursor: int) -> int | None:
  stripped = word.strip()
  if not stripped:
    return None
  index = text.find(stripped, cursor)
  if index >= 0:
    return index
  index = text.find(stripped)
  return index if index >= 0 else None


def _span_index(for_index: int, spans: list[tuple[int, int]]) -> int:
  for index, (start, end) in enumerate(spans):
    if start <= for_index < end:
      return index
  return max(0, len(spans) - 1)


def _duration_seconds_from_cues(cues: list[RadioSpeechCue]) -> float | None:
  if not cues:
    return None
  return round(max(cue.endTime for cue in cues), 2)


def _read_speech_metadata(file_path: Path) -> dict:
  metadata_path = _speech_metadata_path(file_path)
  if not metadata_path.exists():
    return {"durationSeconds": None, "cues": []}
  try:
    raw_metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    return {"durationSeconds": None, "cues": []}

  cues = []
  raw_cues = raw_metadata.get("cues") if isinstance(raw_metadata, dict) else None
  if isinstance(raw_cues, list):
    for raw_cue in raw_cues:
      try:
        cues.append(RadioSpeechCue.model_validate(raw_cue))
      except ValueError:
        continue

  duration_seconds = _normalize_float(raw_metadata.get("durationSeconds")) if isinstance(raw_metadata, dict) else None
  return {"durationSeconds": duration_seconds, "cues": cues}


def _read_prepared_speech(file_path: Path) -> tuple[RadioSpeechSegment, SpeechSynthesisContext] | None:
  metadata_path = _speech_metadata_path(file_path)
  if not metadata_path.exists():
    return None
  try:
    raw_metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    return None
  if not isinstance(raw_metadata, dict):
    return None

  raw_segment = raw_metadata.get("segment")
  raw_context = raw_metadata.get("context")
  if not isinstance(raw_segment, dict) or not isinstance(raw_context, dict):
    return None
  try:
    segment = RadioSpeechSegment.model_validate(raw_segment)
    context = SpeechSynthesisContext(**raw_context)
  except (TypeError, ValueError):
    return None
  return segment, context


def _settings_for_prepared_stream(
  context: SpeechSynthesisContext,
) -> tuple[VolcengineSettings | None, list[str]]:
  if context.provider != "volcengine":
    return None, [f"Speech provider '{context.provider}' is not implemented for streaming."]
  if not _speech_is_configured():
    return None, ["Speech synthesis is not configured."]
  return _volcengine_settings(context)


def _write_speech_metadata(
  file_path: Path,
  duration_seconds: float | None,
  cues: list[RadioSpeechCue],
  *,
  segment: RadioSpeechSegment | None = None,
  context: SpeechSynthesisContext | None = None,
) -> None:
  metadata_path = _speech_metadata_path(file_path)
  metadata_path.parent.mkdir(parents=True, exist_ok=True)
  metadata = {
    "durationSeconds": duration_seconds,
    "cues": [cue.model_dump() for cue in cues],
  }
  if segment:
    metadata["segment"] = segment.model_dump()
  if context:
    metadata["context"] = asdict(context)
  metadata_path.write_text(json.dumps(metadata, ensure_ascii=False), encoding="utf-8")


def _speech_metadata_path(file_path: Path) -> Path:
  return file_path.with_suffix(".metadata.json")


def _iter_file_chunks(path: Path, chunk_size: int = 64 * 1024) -> Iterator[bytes]:
  with path.open("rb") as audio_file:
    while True:
      chunk = audio_file.read(chunk_size)
      if not chunk:
        break
      yield chunk


def _iter_raise(error: Exception) -> Iterator[bytes]:
  raise error
  yield b""


def _consume_json_objects(text: str) -> tuple[list[dict], str]:
  decoder = json.JSONDecoder()
  bodies: list[dict] = []
  cursor = 0
  while cursor < len(text):
    while cursor < len(text) and text[cursor].isspace():
      cursor += 1
    if cursor >= len(text):
      break
    try:
      body, end = decoder.raw_decode(text, cursor)
    except json.JSONDecodeError:
      return bodies, text[cursor:]
    if isinstance(body, dict):
      bodies.append(body)
    cursor = end
  return bodies, text[cursor:]


def _is_volcengine_success_code(code: object) -> bool:
  return code in (None, 0, 3000, "0", "3000")


def _is_volcengine_finish_code(code: object) -> bool:
  return code in (VOLCENGINE_FINISH_CODE, str(VOLCENGINE_FINISH_CODE))


def _ready_audio(
  segment: RadioSpeechSegment,
  context: SpeechSynthesisContext,
  cache_key: str,
  audio_url: str,
  stream_url: str | None = None,
  cues: list[RadioSpeechCue] | None = None,
  duration_seconds: float | None = None,
) -> RadioSpeechAudio:
  return RadioSpeechAudio(
    audioURL=audio_url,
    streamURL=stream_url,
    mimeType=MIME_TYPES.get(context.audio_format, "audio/mpeg"),
    durationSeconds=duration_seconds or _estimated_duration(segment.text),
    cacheKey=cache_key,
    voice=context.voice,
    model=context.model,
    status="ready",
    cues=cues or [],
  )


def _unavailable_audio(
  segment: RadioSpeechSegment,
  context: SpeechSynthesisContext,
  cache_key: str | None = None,
) -> RadioSpeechAudio:
  resolved_cache_key = cache_key or _cache_key_for_context(segment.text, context)
  return RadioSpeechAudio(
    audioURL=None,
    mimeType=MIME_TYPES.get(context.audio_format, "audio/mpeg"),
    durationSeconds=_estimated_duration(segment.text),
    cacheKey=resolved_cache_key,
    voice=context.voice or DEFAULT_OPENAI_SPEECH_VOICE,
    model=context.model,
    status="unavailable",
    cues=[],
  )


def _cache_key_for_context(text: str, context: SpeechSynthesisContext) -> str:
  return cache_key_for(
    text,
    context.provider,
    context.model,
    context.voice,
    context.audio_format,
    resource_id=context.resource_id,
    sample_rate=context.sample_rate,
    bit_rate=context.bit_rate,
    speech_rate=context.speech_rate,
    loudness_rate=context.loudness_rate,
    pitch=context.pitch,
    explicit_language=context.explicit_language,
    emotion=context.emotion,
  )


def _mock_audio_url(cache_key: str, audio_format: str) -> str | None:
  public_base_url = _speech_public_base_url()
  if not public_base_url:
    return None

  return f"{public_base_url}/{cache_key}.{audio_format}"


def _mock_stream_url(cache_key: str, audio_format: str) -> str | None:
  public_base_url = _speech_stream_public_base_url()
  if not public_base_url:
    return None

  return f"{public_base_url}/{cache_key}.{audio_format}"


def _speech_audio_url(file_name: str) -> str | None:
  public_base_url = _speech_public_base_url()
  if not public_base_url:
    return None
  return f"{public_base_url}/{file_name}"


def _speech_stream_url(file_name: str) -> str | None:
  public_base_url = _speech_stream_public_base_url()
  if not public_base_url:
    return None
  return f"{public_base_url}/{file_name}"


def _speech_public_base_url() -> str:
  return os.getenv("SPEECH_PUBLIC_BASE_URL", "").rstrip("/")


def _speech_stream_public_base_url() -> str:
  configured = os.getenv("SPEECH_STREAM_PUBLIC_BASE_URL", "").rstrip("/")
  if configured:
    return configured

  audio_base_url = _speech_public_base_url()
  if audio_base_url.endswith("/audio"):
    return f"{audio_base_url.removesuffix('/audio')}/stream"
  return f"{audio_base_url}/stream" if audio_base_url else ""


def _speech_cache_dir() -> Path:
  return Path(os.getenv("SPEECH_CACHE_DIR", "/tmp/airset-radio-speech"))


def _speech_is_configured() -> bool:
  return os.getenv("SPEECH_ENABLED", "false").lower() == "true"


def _estimated_duration(text: str) -> float:
  words = max(1, len(text.split()))
  return round(max(1.2, words / 2.7), 2)


def _write_audio_file(path: Path, audio_bytes: bytes) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary_file:
    temporary_file.write(audio_bytes)
    temporary_path = Path(temporary_file.name)
  temporary_path.replace(path)


def _float_env(name: str, default: float) -> float:
  value = os.getenv(name)
  if not value:
    return default
  try:
    return float(value)
  except ValueError:
    return default


def _int_env(name: str, default: int) -> int:
  value = os.getenv(name)
  if not value:
    return default
  try:
    return int(value)
  except ValueError:
    return default


def _optional_int_env(name: str) -> int | None:
  value = os.getenv(name)
  if not value:
    return None
  try:
    return int(value)
  except ValueError:
    return None


def _bool_env(name: str, default: bool) -> bool:
  value = os.getenv(name)
  if value is None:
    return default
  return value.strip().lower() in {"1", "true", "yes", "on"}


def _ratio_to_v3_rate(ratio: float) -> int:
  return _clamp_int(round((ratio - 1.0) * 100), -50, 100)


def _clamp_int(value: int, minimum: int, maximum: int) -> int:
  return min(maximum, max(minimum, value))


def _safe_message(message: str) -> str:
  safe_message = message
  for secret in [
    os.getenv("VOLCENGINE_TTS_API_KEY", ""),
    os.getenv("VOLCENGINE_TTS_ACCESS_TOKEN", ""),
  ]:
    if secret:
      safe_message = safe_message.replace(secret, "[redacted]")
  return safe_message
