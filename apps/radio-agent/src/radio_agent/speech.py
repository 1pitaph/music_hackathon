from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path

import httpx

from radio_agent.schemas import (
  RadioSpeechAudio,
  RadioSpeechAudioConfig,
  RadioSpeechSegment,
  RadioSpeechSynthesisResult,
)

DEFAULT_OPENAI_SPEECH_MODEL = "gpt-4o-mini-tts"
DEFAULT_OPENAI_SPEECH_VOICE = "coral"
DEFAULT_VOLCENGINE_SPEECH_MODEL = "seed-tts-2.0-standard"
DEFAULT_VOLCENGINE_RESOURCE_ID = "seed-tts-2.0"
DEFAULT_VOLCENGINE_ENDPOINT = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
DEFAULT_SPEECH_FORMAT = "mp3"
DEFAULT_VOLCENGINE_SAMPLE_RATE = 24000
DEFAULT_VOLCENGINE_BIT_RATE = 128000
DEFAULT_VOLCENGINE_TIMEOUT_SECONDS = 30.0
VOLCENGINE_FINISH_CODE = 20000000

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
  context = _speech_context(config)

  if not segments:
    return [], diagnostics

  volcengine_settings: VolcengineSettings | None = None
  if context.provider == "mock":
    diagnostics.append("Using mock speech synthesis metadata.")
  elif not _speech_is_configured():
    diagnostics.append("Speech synthesis is not configured; returning text-only speech metadata.")
  elif context.provider == "volcengine":
    volcengine_settings, settings_diagnostics = _volcengine_settings(context)
    diagnostics.extend(settings_diagnostics)
  else:
    diagnostics.append(
      f"Speech provider '{context.provider}' is not implemented; returning text-only speech metadata."
    )

  for segment in segments:
    if context.provider == "volcengine" and _speech_is_configured() and volcengine_settings:
      audio, segment_diagnostics = _synthesize_volcengine_segment(
        segment,
        context,
        volcengine_settings,
      )
      diagnostics.extend(segment_diagnostics)
    else:
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
      return _ready_audio(segment, context, cache_key, audio_url), diagnostics
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

      audio_bytes, response_diagnostics = _volcengine_audio_bytes(response, segment.id)
      diagnostics.extend(response_diagnostics)
  except (httpx.HTTPError, ValueError) as exc:
    diagnostics.append(
      f"Volcengine TTS request failed for segment '{segment.id}': {exc.__class__.__name__}."
    )
    return _unavailable_audio(segment, context, cache_key), diagnostics

  if not audio_bytes:
    diagnostics.append(f"Volcengine TTS response for segment '{segment.id}' included empty audio data.")
    return _unavailable_audio(segment, context, cache_key), diagnostics

  _write_audio_file(file_path, audio_bytes)
  return _ready_audio(segment, context, cache_key, audio_url), diagnostics


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
    "enable_subtitle": False,
  }
  req_params: dict[str, object] = {
    "text": segment.text,
    "model": context.model,
    "speaker": context.voice,
    "audio_params": audio_params,
  }
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


def _volcengine_audio_bytes(response, segment_id: str) -> tuple[bytes, list[str]]:
  diagnostics: list[str] = []
  audio_parts: list[bytes] = []

  for chunk_body in _volcengine_response_bodies(response):
    code = chunk_body.get("code")
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

  return b"".join(audio_parts), diagnostics


def _volcengine_response_bodies(response) -> list[dict]:
  bodies: list[dict] = []
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
    bodies.extend(parsed)

  if buffered.strip():
    parsed, remaining = _consume_json_objects(buffered.strip())
    bodies.extend(parsed)
    if remaining.strip():
      raise ValueError(f"Unexpected Volcengine TTS response chunk: {remaining[:80]}")
  return bodies


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
) -> RadioSpeechAudio:
  return RadioSpeechAudio(
    audioURL=audio_url,
    mimeType=MIME_TYPES.get(context.audio_format, "audio/mpeg"),
    durationSeconds=_estimated_duration(segment.text),
    cacheKey=cache_key,
    voice=context.voice,
    model=context.model,
    status="ready",
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


def _speech_audio_url(file_name: str) -> str | None:
  public_base_url = _speech_public_base_url()
  if not public_base_url:
    return None
  return f"{public_base_url}/{file_name}"


def _speech_public_base_url() -> str:
  return os.getenv("SPEECH_PUBLIC_BASE_URL", "").rstrip("/")


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
