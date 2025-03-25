FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev --group lambda

ADD src /app/src
ADD pyproject.toml /app/pyproject.toml
ADD uv.lock /app/uv.lock

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --group lambda

RUN cp -r /app/.venv/lib/python3.13/site-packages/* /app/. && \
    rm -rf /app/.venv

FROM public.ecr.aws/lambda/python:3.13 AS main

COPY --from=builder /app ${LAMBDA_TASK_ROOT}

CMD ["src.lambda.handler"]
