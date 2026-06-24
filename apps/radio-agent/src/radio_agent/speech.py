from __future__ import annotations

import hashlib
import os

from radio_agent.schemas import (
  RadioSpeechAudio,
  RadioSpeechAudioConfig,
  RadioSpeechSegment,
  RadioSpeechSynthesisResult,
)

DEFAULT_SPEECH_MODEL = "gpt-4o-mini-tts"
DEFAULT_SPEECH_VOICE = "coral"
DEFAULT_SPEECH_FORMAT = "mp3"

MIME_TYPES = {
  "aac": "audio/aac",
  "mp3": "audio/mpeg",
  "wav": "audio/wav",
  "pcm": "audio/pcm",
}


def synthesize_speech_segments(
  segments: list[RadioSpeechSegment],
  config: RadioSpeechAudioConfig,
) -> tuple[list[RadioSpeechSynthesisResult], list[str]]:
  diagnostics: list[str] = []
  results: list[RadioSpeechSynthesisResult] = []
  provider = (config.provider or os.getenv("SPEECH_PROVIDER") or "openai").lower()
  model = config.model or os.getenv("SPEECH_MODEL") or DEFAULT_SPEECH_MODEL
  voice = config.voice or os.getenv("SPEECH_DEFAULT_VOICE") or DEFAULT_SPEECH_VOICE
  audio_format = (config.format or os.getenv("SPEECH_FORMAT") or DEFAULT_SPEECH_FORMAT).lower()

  if not segments:
    return [], diagnostics

  if provider == "mock":
    diagnostics.append("Using mock speech synthesis metadata.")
  elif not _speech_is_configured():
    diagnostics.append("Speech synthesis is not configured; returning text-only speech metadata.")

  for segment in segments:
    cache_key = cache_key_for(segment.text, provider, model, voice, audio_format)
    audio_url = _mock_audio_url(cache_key, audio_format) if provider == "mock" else None
    status = "ready" if audio_url else "unavailable"
    audio = RadioSpeechAudio(
      audioURL=audio_url,
      mimeType=MIME_TYPES.get(audio_format, "audio/mpeg"),
      durationSeconds=_estimated_duration(segment.text),
      cacheKey=cache_key,
      voice=voice,
      model=model,
      status=status,
    )
    results.append(RadioSpeechSynthesisResult(
      **segment.model_dump(),
      audio=audio,
    ))

  return results, diagnostics


def cache_key_for(text: str, provider: str, model: str, voice: str, audio_format: str) -> str:
  digest = hashlib.sha256(
    f"{provider}|{model}|{voice}|{audio_format}|{text.strip()}".encode("utf-8")
  ).hexdigest()[:24]
  return f"speech_{digest}"


def _mock_audio_url(cache_key: str, audio_format: str) -> str | None:
  public_base_url = os.getenv("SPEECH_PUBLIC_BASE_URL", "").rstrip("/")
  if not public_base_url:
    return None

  return f"{public_base_url}/{cache_key}.{audio_format}"


def _speech_is_configured() -> bool:
  return os.getenv("SPEECH_ENABLED", "false").lower() == "true"


def _estimated_duration(text: str) -> float:
  words = max(1, len(text.split()))
  return round(max(1.2, words / 2.7), 2)
