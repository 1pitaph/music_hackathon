from radio_agent.llm import (
  DEFAULT_OPENAI_BASE_URL,
  DEFAULT_OPENAI_MODEL,
  DEFAULT_TIMEOUT_SECONDS,
  chat_model,
)


def test_chat_model_defaults_to_api_mart_deepseek_v4_pro(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.delenv("OPENAI_BASE_URL", raising=False)
  monkeypatch.delenv("OPENAI_MODEL", raising=False)

  model = chat_model(temperature=0.2)

  assert model.model_name == DEFAULT_OPENAI_MODEL == "deepseek-v4-pro"
  assert model.openai_api_base == DEFAULT_OPENAI_BASE_URL == "https://api.apimart.ai/v1"


def test_chat_model_allows_openai_compatible_overrides(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.setenv("OPENAI_BASE_URL", "https://example.test/v1")
  monkeypatch.setenv("OPENAI_MODEL", "custom-model")

  model = chat_model(temperature=0.2)

  assert model.model_name == "custom-model"
  assert model.openai_api_base == "https://example.test/v1"


def test_chat_model_uses_default_timeout(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.delenv("OPENAI_BASE_URL", raising=False)
  monkeypatch.delenv("OPENAI_MODEL", raising=False)
  monkeypatch.delenv("OPENAI_TIMEOUT_SECONDS", raising=False)
  monkeypatch.delenv("RADIO_AGENT_LLM_TIMEOUT_SECONDS", raising=False)

  model = chat_model(temperature=0.2)

  assert model.request_timeout == DEFAULT_TIMEOUT_SECONDS


def test_chat_model_uses_configured_timeout(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.setenv("OPENAI_TIMEOUT_SECONDS", "45")

  model = chat_model(temperature=0.2)

  assert model.request_timeout == 45.0
