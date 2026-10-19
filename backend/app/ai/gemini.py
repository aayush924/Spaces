"""Thin wrapper around the google-genai SDK (chat JSON + embeddings).

Everything that talks to Gemini goes through this module so tests can monkeypatch it.
"""
from __future__ import annotations

import math
from typing import Literal, TypeVar

from google import genai
from google.genai import types
from pydantic import BaseModel

from ..config import get_settings

T = TypeVar("T", bound=BaseModel)
EmbedKind = Literal["document", "query"]

_client: genai.Client | None = None


class AIUnavailable(RuntimeError):
    """Raised when Gemini isn't configured or the call failed."""


def _get_client() -> genai.Client:
    global _client
    settings = get_settings()
    if not settings.gemini_api_key:
        raise AIUnavailable("GEMINI_API_KEY is not set")
    if _client is None:
        _client = genai.Client(api_key=settings.gemini_api_key)
    return _client


async def generate_json(system: str, prompt: str, schema: type[T], temperature: float = 0.0) -> T:
    """Ask the chat model for a JSON object that validates against `schema`."""
    settings = get_settings()
    try:
        resp = await _get_client().aio.models.generate_content(
            model=settings.gemini_chat_model,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=system,
                temperature=temperature,
                response_mime_type="application/json",
                response_json_schema=schema.model_json_schema(),
            ),
        )
    except AIUnavailable:
        raise
    except Exception as exc:  # noqa: BLE001
        raise AIUnavailable(f"Gemini generate_content failed: {exc}") from exc
    if not resp.text:
        raise AIUnavailable("Gemini returned an empty response")
    return schema.model_validate_json(resp.text)


def _format_for_embedding(text: str, kind: EmbedKind, title: str | None) -> str:
    """gemini-embedding-2 takes the task as a text prefix instead of `task_type`."""
    if kind == "query":
        return f"task: search result | query: {text}"
    return f"title: {title or 'none'} | text: {text}"


def _normalize(vec: list[float]) -> list[float]:
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


async def embed(text: str, kind: EmbedKind, title: str | None = None) -> list[float]:
    settings = get_settings()
    model = settings.gemini_embed_model
    legacy = "embedding-001" in model or "text-embedding" in model
    if legacy:
        content = text
        config = types.EmbedContentConfig(
            task_type="RETRIEVAL_QUERY" if kind == "query" else "RETRIEVAL_DOCUMENT",
            title=title if kind == "document" and title else None,
            output_dimensionality=settings.embed_dim,
        )
    else:
        content = _format_for_embedding(text, kind, title)
        config = types.EmbedContentConfig(output_dimensionality=settings.embed_dim)
    try:
        resp = await _get_client().aio.models.embed_content(model=model, contents=content, config=config)
    except AIUnavailable:
        raise
    except Exception as exc:  # noqa: BLE001
        raise AIUnavailable(f"Gemini embed_content failed: {exc}") from exc
    if not resp.embeddings or not resp.embeddings[0].values:
        raise AIUnavailable("Gemini returned no embedding")
    return _normalize(list(resp.embeddings[0].values))


async def list_models() -> list[str]:
    pager = await _get_client().aio.models.list()
    return [m.name async for m in pager]
