from __future__ import annotations

import os
from typing import Any

from dotenv import load_dotenv
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

load_dotenv()

DEFAULT_OPENAI_MODEL = "gpt-4.1-mini"
DEFAULT_TIMEOUT_SECONDS = 60.0


def has_openai_api_key() -> bool:
  return bool(os.getenv("OPENAI_API_KEY"))


def chat_model(*, temperature: float, timeout: float = DEFAULT_TIMEOUT_SECONDS) -> ChatOpenAI:
  return ChatOpenAI(
    model=os.getenv("OPENAI_MODEL") or DEFAULT_OPENAI_MODEL,
    api_key=os.getenv("OPENAI_API_KEY"),
    base_url=os.getenv("OPENAI_BASE_URL") or None,
    temperature=temperature,
    timeout=_timeout_seconds(timeout),
  )


def invoke_chat(system_prompt: str, user_prompt: str, *, temperature: float) -> Any:
  result = chat_model(temperature=temperature).invoke([
    SystemMessage(content=system_prompt),
    HumanMessage(content=user_prompt),
  ])
  return result.content


def _timeout_seconds(default: float) -> float:
  raw_timeout = (
    os.getenv("OPENAI_TIMEOUT_SECONDS")
    or os.getenv("RADIO_AGENT_LLM_TIMEOUT_SECONDS")
    or ""
  ).strip()
  if not raw_timeout:
    return default

  try:
    return max(1.0, float(raw_timeout))
  except ValueError:
    return default
