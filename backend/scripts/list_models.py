"""Print the Gemini models available to your API key. Usage: make models"""
import asyncio

from app.ai.gemini import list_models


async def main() -> None:
    for name in sorted(await list_models()):
        if "gemini" in name or "embedding" in name:
            print(name)


if __name__ == "__main__":
    asyncio.run(main())
