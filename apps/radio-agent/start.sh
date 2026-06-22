#!/usr/bin/env sh
set -eu

if [ -z "${PORT:-}" ]; then
  PORT=8000
fi

echo "Starting Airset Radio Agent on 0.0.0.0:${PORT}"
exec python -m uvicorn radio_agent.api:app --host 0.0.0.0 --port "${PORT}" --proxy-headers
