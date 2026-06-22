from __future__ import annotations

import os
from typing import Any

from dotenv import load_dotenv
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

load_dotenv()

DEFAULT_OPENAI_MODEL = "gpt-4.1-mini"
DEFAULT_TIMEOUT_SECONDS = 8


def has_openai_api_key() -> bool:
  return bool(os.getenv("OPENAI_API_KEY"))


def chat_model(*, temperature: float, timeout: int = DEFAULT_TIMEOUT_SECONDS) -> ChatOpenAI:
  return ChatOpenAI(
    model=os.getenv("OPENAI_MODEL") or DEFAULT_OPENAI_MODEL,
    api_key=os.getenv("OPENAI_API_KEY"),
    base_url=os.getenv("OPENAI_BASE_URL") or None,
    temperature=temperature,
    timeout=timeout,
  )


def invoke_chat(system_prompt: str, user_prompt: str, *, temperature: float) -> Any:
  result = chat_model(temperature=temperature).invoke([
    SystemMessage(content=system_prompt),
    HumanMessage(content=user_prompt),
  ])
  return result.content
