"""Tweet previews (author avatar, first photo or video thumbnail) from fxtwitter.

A ReadItLater tweet note holds only the text and a pic.twitter.com link. The
helper asks api.fxtwitter.com once per tweet, keeps the answer in a local
cache, and every later read merges the cache without any network call. A
failure is remembered for a day, so a dead service never causes a fetch on
every refresh. Notes in the vault are never changed.
"""

import json
import re
import time
import urllib.request
from pathlib import Path

from shelf_io import atomic_write

STATUS_RE = re.compile(r"^https?://(?:www\.|mobile\.)?(?:x|twitter)\.com/([A-Za-z0-9_]{1,15})/status/(\d+)")
RETRY_AFTER = 86400
TIMEOUT = 5


def tweet_api_url(url: str) -> str:
    match = STATUS_RE.match(url or "")
    if not match:
        return ""
    return f"https://api.fxtwitter.com/{match.group(1)}/status/{match.group(2)}"


def small(photo_url: str) -> str:
    """The X image CDN serves a 680 px variant with name=small."""
    return re.sub(r"name=\w+", "name=small", photo_url) if "name=" in photo_url else photo_url


def preview_from_fxtwitter(data: dict) -> dict:
    tweet = data.get("tweet") or {}
    media = tweet.get("media") or {}
    photos = media.get("photos") or []
    videos = media.get("videos") or []
    image = ""
    if photos and photos[0].get("url"):
        image = small(photos[0]["url"])
    elif videos and videos[0].get("thumbnail_url"):
        image = videos[0]["thumbnail_url"]
    return {"avatar": (tweet.get("author") or {}).get("avatar_url", "") or "", "image": image}


def load_cache(path: Path) -> dict:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def fetch_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "obsidian-shelf"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def enrich(vault: Path, lists: list, cache_path: Path, fetch=fetch_json, now=None) -> dict:
    """Fetch the preview of every tweet that has none yet, and save the cache."""
    from shelf_folder import read_folder

    now = time.time() if now is None else now
    cache = load_cache(cache_path)
    fetched = 0
    for cfg in lists:
        if cfg.get("type") != "folder":
            continue
        for item in read_folder(vault, cfg, cache).get("items", []):
            key = tweet_api_url(item["url"])
            entry = cache.get(key)
            if not key:
                continue
            if entry and "failedAt" not in entry:
                continue
            if entry and now - entry["failedAt"] < RETRY_AFTER:
                continue
            try:
                cache[key] = preview_from_fxtwitter(fetch(key))
                fetched += 1
            except (OSError, ValueError):
                cache[key] = {"failedAt": now}
    Path(cache_path).parent.mkdir(parents=True, exist_ok=True)
    atomic_write(Path(cache_path), json.dumps(cache, ensure_ascii=False))
    return {"ok": True, "fetched": fetched}


def merge_preview(item: dict, cache: dict) -> dict:
    key = tweet_api_url(item["url"])
    entry = cache.get(key) if key else None
    item["avatar"] = (entry or {}).get("avatar", "")
    if not item["image"]:
        item["image"] = (entry or {}).get("image", "")
    item["previewPending"] = bool(key) and entry is None
    return item
