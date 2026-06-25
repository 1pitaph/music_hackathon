from __future__ import annotations

import json
import os

from pydantic import ValidationError

from radio_agent.schemas import RadioSpeechVoice, RadioSpeechVoiceCatalog

DEFAULT_RESOURCE_ID = "seed-tts-1.0"
DEFAULT_MODEL = "seed-tts-1.0"
DEFAULT_SPEAKER = "zh_female_shuangkuaisisi_moon_bigtts"
LEGACY_MODEL_NAMES = {"gpt-4o-mini-tts", "volcengine-tts"}

BUILTIN_VOICES = [
  RadioSpeechVoice(
    id="zh_female_shuangkuaisisi_moon_bigtts",
    name="爽快思思",
    gender="female",
    style="明亮活泼",
  ),
  RadioSpeechVoice(
    id="zh_female_sajiaonvyou_moon_bigtts",
    name="撒娇女友",
    gender="female",
    style="轻快亲和",
  ),
]


def speech_voice_catalog() -> RadioSpeechVoiceCatalog:
  voices = _configured_voices() or BUILTIN_VOICES
  allowed_speakers = _allowed_speakers()
  configured_default = _configured_default_speaker()
  resource_id = _resource_id()
  model = _model()

  voices = [_voice_with_defaults(voice, resource_id, model) for voice in voices]

  if configured_default and configured_default not in {voice.id for voice in voices}:
    voices.insert(0, _placeholder_voice(configured_default, resource_id, model, "默认主持人"))

  if allowed_speakers:
    voice_by_id = {voice.id: voice for voice in voices}
    voices = [
      voice_by_id.get(speaker) or _placeholder_voice(speaker, resource_id, model)
      for speaker in allowed_speakers
    ]

  if not voices:
    voices = [_placeholder_voice(configured_default or DEFAULT_SPEAKER, resource_id, model)]

  voice_ids = {voice.id for voice in voices}
  if configured_default and configured_default in voice_ids:
    default_speaker = configured_default
  else:
    default_speaker = voices[0].id

  return RadioSpeechVoiceCatalog(
    defaultSpeaker=default_speaker,
    resourceId=resource_id,
    model=model,
    voices=voices,
  )


def resolve_speech_speaker(requested_speaker: str | None) -> tuple[str, list[str]]:
  catalog = speech_voice_catalog()
  voice_ids = {voice.id for voice in catalog.voices}
  requested = (requested_speaker or "").strip()
  if requested and requested in voice_ids:
    return requested, []
  if requested and requested != catalog.defaultSpeaker:
    return catalog.defaultSpeaker, [
      f"Requested speech speaker '{requested}' is not allowed; using default speaker."
    ]
  return catalog.defaultSpeaker, []


def _configured_voices() -> list[RadioSpeechVoice]:
  raw_voices = os.getenv("VOLCENGINE_TTS_VOICES_JSON", "").strip()
  if not raw_voices:
    return []

  try:
    payload = json.loads(raw_voices)
  except json.JSONDecodeError:
    return []

  if isinstance(payload, dict):
    payload = payload.get("voices", [])
  if not isinstance(payload, list):
    return []

  voices: list[RadioSpeechVoice] = []
  for item in payload:
    try:
      voices.append(RadioSpeechVoice.model_validate(item))
    except ValidationError:
      continue
  return voices


def _allowed_speakers() -> list[str]:
  raw_speakers = os.getenv("VOLCENGINE_TTS_ALLOWED_SPEAKERS", "")
  return [
    speaker.strip()
    for speaker in raw_speakers.split(",")
    if speaker.strip()
  ]


def _configured_default_speaker() -> str:
  return (
    os.getenv("VOLCENGINE_TTS_SPEAKER")
    or os.getenv("VOLCENGINE_TTS_VOICE_TYPE")
    or ""
  ).strip()


def _resource_id() -> str:
  resource_id = os.getenv("VOLCENGINE_TTS_RESOURCE_ID", "").strip()
  deprecated_cluster = os.getenv("VOLCENGINE_TTS_CLUSTER", "").strip()
  if resource_id:
    return resource_id
  if deprecated_cluster.startswith("seed-"):
    return deprecated_cluster
  return DEFAULT_RESOURCE_ID


def _model() -> str:
  model = os.getenv("VOLCENGINE_TTS_MODEL", "").strip()
  speech_model = os.getenv("SPEECH_MODEL", "").strip()
  if model:
    return model
  if speech_model and speech_model not in LEGACY_MODEL_NAMES:
    return speech_model
  return DEFAULT_MODEL


def _voice_with_defaults(
  voice: RadioSpeechVoice,
  resource_id: str,
  model: str,
) -> RadioSpeechVoice:
  return voice.model_copy(update={
    "resourceId": voice.resourceId or resource_id,
    "model": voice.model or model,
  })


def _placeholder_voice(
  speaker: str,
  resource_id: str,
  model: str,
  name: str | None = None,
) -> RadioSpeechVoice:
  return RadioSpeechVoice(
    id=speaker,
    name=name or speaker,
    language="zh-cn",
    gender="",
    style="自定义音色",
    resourceId=resource_id,
    model=model,
  )
