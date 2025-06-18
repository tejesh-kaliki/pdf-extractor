FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app

ADD pyproject.toml /app/pyproject.toml
ADD uv.lock /app/uv.lock
RUN uv sync --frozen --no-install-project --no-dev --group lambda

ADD src /app/src

RUN uv sync --frozen --no-dev --group lambda

RUN cp -r /app/.venv/lib/python3.13/site-packages/* /app/. && \
  rm -rf /app/.venv

FROM public.ecr.aws/lambda/python:3.13 AS main

COPY --from=builder /app ${LAMBDA_TASK_ROOT}

CMD ["src.lambda.handler"]
