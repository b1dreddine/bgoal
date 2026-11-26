"""Entry point on Vercel (pyproject.toml → [tool.vercel]): the API in serverless mode.

No worker process there, so the API fetches live scores itself and keeps its data in
/tmp and memory (see Settings.serverless). Settings in the Vercel project still win.
"""
import os

os.environ.setdefault("SERVERLESS", "true")

from app.main import app  # noqa: E402

__all__ = ["app"]
