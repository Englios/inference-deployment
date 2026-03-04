import os
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response


app = FastAPI(title="OpenAI-Compatible LLM Gateway", version="0.1.0")

DEFAULT_UPSTREAM_BASE_URL = os.getenv(
    "DEFAULT_UPSTREAM_BASE_URL",
    "http://127.0.0.1:8000",
).rstrip("/")
UPSTREAM_BASE_URL = os.getenv("UPSTREAM_BASE_URL", DEFAULT_UPSTREAM_BASE_URL).rstrip("/")
INTERNAL_LLM_API_KEY = os.getenv("INTERNAL_LLM_API_KEY", "")
MIDDLEWARE_API_KEY = os.getenv("MIDDLEWARE_API_KEY", "")
SYSTEM_PROMPT = os.getenv("SYSTEM_PROMPT", "").strip()
REQUEST_TIMEOUT_SECONDS = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "120"))


def _extract_bearer(request: Request) -> str:
    header = request.headers.get("Authorization", "")
    if not header.lower().startswith("bearer "):
        return ""
    return header[7:].strip()


def _enforce_client_auth(request: Request) -> None:
    if not MIDDLEWARE_API_KEY:
        return
    token = _extract_bearer(request)
    if token != MIDDLEWARE_API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")


def _upstream_headers() -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if INTERNAL_LLM_API_KEY:
        headers["Authorization"] = f"Bearer {INTERNAL_LLM_API_KEY}"
    return headers


def _inject_system_prompt(payload: dict[str, Any]) -> dict[str, Any]:
    if not SYSTEM_PROMPT:
        return payload

    messages = payload.get("messages")
    if not isinstance(messages, list):
        return payload

    patched = dict(payload)
    patched_messages = list(messages)
    patched_messages.insert(0, {"role": "system", "content": SYSTEM_PROMPT})
    patched["messages"] = patched_messages
    return patched


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.api_route("/v1/models", methods=["GET"])
async def models(request: Request) -> Response:
    _enforce_client_auth(request)
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT_SECONDS) as client:
        try:
            upstream = await client.get(
                f"{UPSTREAM_BASE_URL}/v1/models",
                headers=_upstream_headers(),
            )
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=503, detail=f"Upstream error: {exc}")

    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type", "application/json"),
    )


@app.post("/v1/chat/completions")
async def chat_completions(request: Request) -> Response:
    _enforce_client_auth(request)

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    payload = _inject_system_prompt(payload)

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT_SECONDS) as client:
        try:
            upstream = await client.post(
                f"{UPSTREAM_BASE_URL}/v1/chat/completions",
                headers=_upstream_headers(),
                json=payload,
            )
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=503, detail=f"Upstream error: {exc}")

    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type", "application/json"),
    )


@app.api_route("/v1/{tail:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def passthrough_v1(tail: str, request: Request) -> Response:
    _enforce_client_auth(request)
    body = await request.body()

    headers = _upstream_headers()
    if request.headers.get("content-type"):
        headers["Content-Type"] = request.headers["content-type"]

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT_SECONDS) as client:
        try:
            upstream = await client.request(
                request.method,
                f"{UPSTREAM_BASE_URL}/v1/{tail}",
                headers=headers,
                params=dict(request.query_params),
                content=body,
            )
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=503, detail=f"Upstream error: {exc}")

    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type", "application/json"),
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"error": {"message": exc.detail}})
