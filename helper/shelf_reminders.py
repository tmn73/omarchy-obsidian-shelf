"""Reminders for the cards of board lists.

Every bar on every screen asks for reminders, so the work happens under a
lock, and the state file remembers what went out:

    {"fired": {"<list>\\u0000<card>\\u0000<date> <time>": "<day it rang>"},
     "summary": "<last day of the morning summary>"}

A card with a date and a time rings once, at that time or at the first run
later that same day. The morning summary rings once a day after the summary
time, for the cards due today without a time and every late card.
"""

import fcntl
import json
import re
from pathlib import Path

from shelf_io import atomic_write

ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
CLOCK = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
APP_NAME = "Obsidian Shelf"
GLYPH = "\U000f00ed"
OPEN_SHELF = ["omarchy-shell", "tmn73.obsidian", "open"]


def open_cards(payload: dict):
    """(lane title, card) for every card of the lanes that are not Complete."""
    for lane in payload.get("lanes") or []:
        if not lane.get("complete"):
            for item in lane.get("items") or []:
                yield lane.get("title", ""), item


def plural(count: int, word: str) -> str:
    return f"{count} {word}" + ("" if count == 1 else "s")


def summary_headline(today: int, late: int) -> str:
    if today and late:
        return f"{plural(today, 'card')} for today, {late} late"
    if today:
        return f"{plural(today, 'card')} for today"
    return f"{plural(late, 'card')} " + ("is late" if late == 1 else "are late")


def due(payloads: list, lists: list, state: dict, now, summary_time: str) -> tuple:
    """The messages to send now, and the state that remembers them."""
    today = now.date().isoformat()
    clock = now.strftime("%H:%M")
    fired = {k: v for k, v in (state.get("fired") or {}).items() if v == today}
    by_id = {p.get("id"): p for p in payloads}
    messages, today_cards, late_cards = [], [], []
    for cfg in lists:
        payload = by_id.get(cfg.get("id"))
        if cfg.get("type") != "board" or cfg.get("remind") is False:
            continue
        if not payload or payload.get("state") != "ok" or not payload.get("datesOn"):
            continue
        for lane, card in open_cards(payload):
            date, time = card.get("date", ""), card.get("time", "")
            if not ISO_DATE.match(date):
                continue
            if date < today:
                late_cards.append(card["text"])
            elif date == today and not time:
                today_cards.append(card["text"])
            elif date == today and CLOCK.match(time) and time <= clock:
                key = "\u0000".join([cfg["id"], card["key"], f"{date} {time}"])
                if key not in fired:
                    fired[key] = today
                    messages.append({"kind": "card", "headline": card["text"],
                                     "body": f"{cfg.get('name', '')} · {lane} · today {time}"})
    summary = state.get("summary", "")
    if clock >= summary_time and summary != today:
        summary = today
        if today_cards or late_cards:
            body = [" · ".join(today_cards)] if today_cards else []
            body += ["Late: " + " · ".join(late_cards)] if late_cards else []
            messages.append({"kind": "summary", "headline": summary_headline(len(today_cards), len(late_cards)),
                             "body": "\n".join(body)})
    return messages, {"fired": fired, "summary": summary}


def notify_command(message: dict, which) -> list:
    """The command for one notification. Text from the vault stays one argument."""
    if which("omarchy-notification-send"):
        return ["omarchy-notification-send", "--app-name", APP_NAME, "-g", GLYPH, "-u", "normal",
                message["headline"], message["body"], "--exec"] + OPEN_SHELF
    return ["notify-send", "--app-name", APP_NAME, "--", message["headline"], message["body"]]


def load_state(path: Path) -> dict:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def run(path: Path, compute, send) -> dict:
    """Under the lock: read the state, compute, send, store."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        messages, state = compute(load_state(path))
        for message in messages:
            send(message)
        atomic_write(path, json.dumps(state, ensure_ascii=False) + "\n")
    return {"ok": True, "sent": len(messages)}
