FROM python:3.13-slim

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY pyproject.toml ./
COPY src ./src
COPY start.sh ./

RUN python -m pip install --upgrade pip \
    && python -m pip install .

CMD ["sh", "./start.sh"]
