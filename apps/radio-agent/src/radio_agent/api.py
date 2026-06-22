from __future__ import annotations

from fastapi import FastAPI

from radio_agent.graph import generate_radio
from radio_agent.schemas import RadioGenerateRequest, RadioGenerateResponse

app = FastAPI(title="Airset Radio Agent", version="0.1.0")


@app.get("/healthz")
def healthz() -> dict[str, str]:
  return {"status": "ok"}


@app.post("/v1/radio/generate", response_model=RadioGenerateResponse)
def generate(request: RadioGenerateRequest) -> RadioGenerateResponse:
  return generate_radio(request)
