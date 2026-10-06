"""Previews for saved links: tweets through fxtwitter, other pages through
their own OpenGraph tags.

A ReadItLater tweet note holds only the text and a pic.twitter.com link, and a
link ReadItLater could not parse (an Instagram reel, say) holds only the
address. The helper fetches what is missing once per link, keeps it in a
local cache, and every later read merges the cache without any network call.
A failure is remembered for a day, so a dead site never causes a fetch on
every refresh. Notes in the vault are never changed.
"""

import html
import ipaddress
import json
import re
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

from shelf_io import atomic_write

STATUS_RE = re.compile(r"^https?://(?:www\.|mobile\.)?(?:x|twitter)\.com/([A-Za-z0-9_]{1,15})/status/(\d+)")
META_RE = re.compile(r"<meta\b[^>]*>", re.IGNORECASE)
ATTR_RE = re.compile(r'([a-zA-Z:-]+)\s*=\s*(?:"([^"]*)"|\'([^\']*)\')', re.DOTALL)
RETRY_AFTER = 86400
TIMEOUT = 5
PAGE_LIMIT = 1_500_000
# Many sites, Instagram among them, give their preview tags only to link
# preview crawlers; this is the agent chat apps use for the same purpose.
PAGE_AGENT = "facebookexternalhit/1.1 (compatible; obsidian-shelf)"


def tweet_api_url(url: str) -> str:
    match = STATUS_RE.match(url or "")
    if not match:
        return ""
    return f"https://api.fxtwitter.com/{match.group(1)}/status/{match.group(2)}"


LOCAL_SUFFIXES = (".local", ".localhost", ".internal", ".lan", ".home.arpa")


def is_public_url(url: str) -> bool:
    """False for localhost, private or link-local addresses and local names.

    A note can hold any address; the helper must never probe the user's own
    machine or network on its own.
    """
    host = (urlparse(url).hostname or "").lower().rstrip(".")
    if not host or host == "localhost" or host.endswith(LOCAL_SUFFIXES):
        return False
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return "." in host
    return not (address.is_private or address.is_loopback or address.is_link_local
                or address.is_reserved or address.is_multicast or address.is_unspecified)


def preview_key(url: str) -> str:
    """The cache key of a link: its fxtwitter address for a tweet, else og:<url>."""
    if tweet_api_url(url):
        return tweet_api_url(url)
    return "og:" + url if re.match(r"^https?://", url or "") and is_public_url(url) else ""


def meta_tags(page: str) -> dict:
    """Every <meta property|name=... content=...> of a page; the first one wins."""
    tags = {}
    for tag in META_RE.findall(page):
        attrs = {m.group(1).lower(): (m.group(2) if m.group(2) is not None else m.group(3)) for m in ATTR_RE.finditer(tag)}
        name = (attrs.get("property") or attrs.get("name") or "").lower()
        if name and "content" in attrs and name not in tags:
            tags[name] = " ".join(html.unescape(attrs["content"]).split())
    return tags


def og_from_html(page: str) -> dict:
    tags = meta_tags(page)
    return {
        "title": tags.get("og:title", "")[:160],
        "description": tags.get("og:description", "")[:200],
        "image": tags.get("og:image") or tags.get("twitter:image", ""),
    }


TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
SUBREDDIT_SUFFIX_RE = re.compile(r"\s*:\s*r/[A-Za-z0-9_]+\s*$")


def page_preview(url: str, page: str) -> dict:
    """OpenGraph tags, with fixes for sites whose tags say nothing.

    Reddit gives crawlers a generic og:title and a brand card for every post;
    the real title is in <title> and the real summary in the description.
    """
    preview = og_from_html(page)
    host = (urlparse(url).hostname or "").lower()
    if host == "reddit.com" or host.endswith(".reddit.com"):
        title = TITLE_RE.search(page)
        if title:
            preview["title"] = SUBREDDIT_SUFFIX_RE.sub("", " ".join(html.unescape(title.group(1)).split()))[:160]
        description = meta_tags(page).get("description", "")
        if description:
            preview["description"] = description[:200]
        if "share.redd.it/" in preview["image"]:
            preview["image"] = ""
    return preview


def fetch_html(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": PAGE_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read(PAGE_LIMIT).decode("utf-8", errors="replace")


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


def enrich(vault: Path, lists: list, cache_path: Path, fetch=fetch_json, now=None,
           fetch_page=fetch_html, tweets=True, links=True) -> dict:
    """Fetch the preview of every link that still needs one, and save the cache."""
    from shelf_folder import read_folder

    now = time.time() if now is None else now
    cache = load_cache(cache_path)
    allowed = {"tweet": tweets, "link": links}
    fetched = 0
    for cfg in lists:
        if cfg.get("type") != "folder":
            continue
        for item in read_folder(vault, cfg, cache).get("items", []):
            kind = needed_kind(item)
            key = preview_key(item["url"])
            entry = cache.get(key)
            if not kind or not allowed[kind]:
                continue
            if entry and "failedAt" not in entry:
                continue
            if entry and now - entry["failedAt"] < RETRY_AFTER:
                continue
            try:
                if kind == "tweet":
                    cache[key] = preview_from_fxtwitter(fetch(key))
                else:
                    cache[key] = page_preview(item["url"], fetch_page(item["url"]))
                fetched += 1
            except (OSError, ValueError):
                cache[key] = {"failedAt": now}
    Path(cache_path).parent.mkdir(parents=True, exist_ok=True)
    atomic_write(Path(cache_path), json.dumps(cache, ensure_ascii=False))
    return {"ok": True, "fetched": fetched}


def needed_kind(item: dict) -> str:
    """Which preview a note still lacks: tweet, link or nothing."""
    if tweet_api_url(item["url"]):
        return "tweet"
    if preview_key(item["url"]) and (not item["image"] or not item.get("titleFromNote", True)):
        return "link"
    return ""


def merge_preview(item: dict, cache: dict) -> dict:
    kind = needed_kind(item)
    key = preview_key(item["url"]) if kind else ""
    entry = cache.get(key) if key else None
    ready = entry if entry and "failedAt" not in entry else {}
    item["avatar"] = ready.get("avatar", "")
    if kind == "link":
        if not item.get("titleFromNote", True) and ready.get("title"):
            item["title"] = ready["title"]
        if (not item["excerpt"] or item["excerpt"].startswith("http")) and ready.get("description"):
            item["excerpt"] = ready["description"]
    if not item["image"]:
        item["image"] = ready.get("image", "")
    item["previewKind"] = kind if entry is None else ""
    item["previewPending"] = item["previewKind"] != ""
    return item
