"""Application settings loaded from environment / backend/.env."""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # MongoDB
    mongodb_uri: str = "mongodb://localhost:27017"
    mongodb_db: str = "myspaces"

    # Gemini
    gemini_api_key: str = ""
    gemini_chat_model: str = "gemini-flash-latest"
    gemini_embed_model: str = "gemini-embedding-2"
    embed_dim: int = 768

    # Auth: the iOS app sends `Authorization: Bearer <api_token>`
    api_token: str = "change-me"

    # Search tuning
    vector_index_name: str = "notes_vector"
    text_index_name: str = "notes_text"
    rrf_k: int = 60
    semantic_weight: float = 0.65
    keyword_weight: float = 0.35
    # Minimum cosine similarity for a semantic hit (tune after seeing real data)
    semantic_min_score: float = 0.3
    # Below this router confidence, list/todo actions are saved as a note + "Did you mean" chip
    low_confidence_threshold: float = 0.55

    # Create Atlas Search / Vector Search indexes on startup
    bootstrap_search_indexes: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()
