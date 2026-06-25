from radio_agent.llm import DEFAULT_TIMEOUT_SECONDS, chat_model


def test_chat_model_uses_default_timeout(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.delenv("OPENAI_TIMEOUT_SECONDS", raising=False)
  monkeypatch.delenv("RADIO_AGENT_LLM_TIMEOUT_SECONDS", raising=False)

  model = chat_model(temperature=0.2)

  assert model.request_timeout == DEFAULT_TIMEOUT_SECONDS


def test_chat_model_uses_configured_timeout(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.setenv("OPENAI_TIMEOUT_SECONDS", "45")

  model = chat_model(temperature=0.2)

  assert model.request_timeout == 45.0
