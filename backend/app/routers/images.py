"""Crest and emblem images, passed through for the web version of the app.

Browsers only let a web app draw an image from another site if that site allows it
(CORS), and the providers' image servers don't. The phone apps load the images
directly; the web app loads them through here. Only the providers' image hosts are
allowed, so this can't be used to fetch anything else.
"""
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response

router = APIRouter(tags=["images"])

ALLOWED_HOSTS = ("crests.football-data.org", "media.api-sports.io")
ALLOWED_TYPES = ("image/png", "image/svg+xml", "image/jpeg", "image/webp", "image/gif")
MAX_BYTES = 2_000_000
# Crests almost never change: browsers keep them a week, Vercel's CDN a month.
CACHE = "public, max-age=604800, s-maxage=2592000, stale-while-revalidate=86400"


def is_allowed(url: str) -> bool:
    p = urlparse(url)
    host = p.hostname or ""
    return p.scheme == "https" and any(host == h or host.endswith("." + h) for h in ALLOWED_HOSTS)


async def fetch_image(url: str) -> tuple[bytes, str]:
    async with httpx.AsyncClient(timeout=10, follow_redirects=False) as client:
        resp = await client.get(url)
    if resp.status_code != 200:
        raise HTTPException(404, "Image not found")
    return resp.content, resp.headers.get("content-type", "").split(";")[0].strip()


@router.get("/img")
async def image(url: str = Query(max_length=500)):
    if not is_allowed(url):
        raise HTTPException(400, "Only crest and emblem images can be loaded here")
    try:
        content, content_type = await fetch_image(url)
    except httpx.HTTPError:
        raise HTTPException(502, "Image server unavailable")
    if content_type not in ALLOWED_TYPES or len(content) > MAX_BYTES:
        raise HTTPException(415, "Not an image")
    return Response(content, media_type=content_type, headers={"Cache-Control": CACHE})
