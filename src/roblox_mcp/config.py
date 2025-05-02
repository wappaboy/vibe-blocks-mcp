import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from dotenv import load_dotenv

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')

    roblox_api_key: str
    roblox_universe_id: int
    roblox_place_id: int
    # Optional MCP server settings (if needed)
    mcp_host: str | None = None
    mcp_port: int | None = None

def load_config() -> Settings:
    """Loads configuration from environment variables or .env file."""
    load_dotenv()
    return Settings() 