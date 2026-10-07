"""Command line contract of the helper (spec section 6).

main() never prints and never exits: it returns the exit code and the JSON
object, so the tests drive it directly and bin/obsidian-shelf only prints.
"""

import argparse
import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

import shelf_board
from shelf_checklist import add_checklist, done_checklist, edit_checklist, read_checklist, remove_checklist
from shelf_folder import done_folder, edit_folder, read_folder
from shelf_io import fail
import shelf_previews
import shelf_notify
import shelf_reminders
import shelf_seen
import shelf_sounds
import shelf_settings
import shelf_sync
from shelf_sections import add_sections, clear_sections, edit_sections, read_sections, remove_sections

READERS = {"folder": read_folder, "checklist": read_checklist, "sections": read_sections, "board": shelf_board.read_board}


ACTIONS = ("add", "done", "clear", "edit", "remove", "move", "date", "lane")
NEEDS_ITEM = ("done", "edit", "remove", "move", "date")


class ArgumentError(ValueError):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ArgumentError(message)


def build_parser() -> Parser:
    parser = Parser(prog="obsidian-shelf", add_help=False)
    commands = parser.add_subparsers(dest="command", parser_class=Parser)
    for name in ("read", "enrich"):
        sub = commands.add_parser(name, add_help=False)
        sub.add_argument("--vault", required=True)
        sub.add_argument("--lists", required=True)
        if name == "enrich":
            sub.add_argument("--previews", default="", help="comma list: tweets, links")
    commands.add_parser("vaults", add_help=False)
    remind = commands.add_parser("remind", add_help=False)
    remind.add_argument("--vault", required=True)
    remind.add_argument("--lists", required=True)
    remind.add_argument("--summary-time", default="09:00")
    remind.add_argument("--sound", default="none", help="none, default, or a sound file")
    commands.add_parser("sounds", add_help=False)
    play = commands.add_parser("play-sound", add_help=False)
    play.add_argument("--path", required=True)
    seen = commands.add_parser("seen", add_help=False)
    seen.add_argument("--lists", required=True)
    scan = commands.add_parser("scan", add_help=False)
    scan.add_argument("--vault", required=True)
    paths = commands.add_parser("paths", add_help=False)
    paths.add_argument("--vault", required=True)
    paths.add_argument("--kind", required=True, choices=["folder", "file"])
    create = commands.add_parser("create", add_help=False)
    create.add_argument("--vault", required=True)
    create.add_argument("--list", required=True)
    trash = commands.add_parser("trash", add_help=False)
    trash.add_argument("--vault", required=True)
    trash.add_argument("--list", required=True)
    for name in ("sync-state", "sync-service"):
        sub = commands.add_parser(name, add_help=False)
        sub.add_argument("--vault", required=True)
    # The arguments name the vault and the list, from the settings. Text from
    # the vault (an item, a lane, new text) comes on stdin as JSON: a command
    # line is readable by every local user.
    for name in ACTIONS:
        sub = commands.add_parser(name, add_help=False)
        sub.add_argument("--vault", required=True)
        sub.add_argument("--list", required=True)
    return parser


def config_home() -> Path:
    home = Path(os.environ.get("HOME", str(Path.home())))
    return Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")


def preview_cache() -> Path:
    home = Path(os.environ.get("HOME", str(Path.home())))
    return Path(os.environ.get("XDG_CACHE_HOME") or home / ".cache") / "obsidian-shelf" / "previews.json"


def seen_file() -> Path:
    return shelf_seen.state_file(os.environ, Path(os.environ.get("HOME", str(Path.home()))))


def reminder_clock() -> datetime:
    return datetime.now()


def send_notification(message: dict) -> None:
    """Over the session bus: the card text never goes into a command line."""
    shelf_notify.notify(message["headline"], message["body"], shelf_reminders.GLYPH, shelf_reminders.OPEN_SHELF)


def sound_list() -> list:
    return shelf_sounds.list_sounds(shelf_sounds.sound_roots(os.environ, Path(os.environ.get("HOME", str(Path.home())))))


def play_sound(path: str) -> bool:
    return shelf_sounds.play(path, shutil.which, subprocess.Popen)


def remind(vault: Path, lists: list, summary_time: str, sound: str = "none") -> dict:
    if not shelf_reminders.CLOCK.match(summary_time):
        raise ArgumentError("--summary-time is HH:MM")
    boards = [cfg for cfg in lists if isinstance(cfg, dict) and cfg.get("type") == "board"]
    payloads = [shelf_board.read_board(vault, cfg) for cfg in boards]
    now = reminder_clock()
    path = seen_file().parent / "reminders.json"

    def compute(state):
        return shelf_reminders.due(payloads, boards, state, now, summary_time)
    try:
        result = shelf_reminders.run(path, compute, send_notification)
    except OSError as err:
        return fail("io", str(err))
    # One sound per run, however many reminders rang.
    if result.get("sent") and sound != "none":
        play_sound(shelf_sounds.default_sound(sound_list()) if sound == "default" else sound)
    return result


def settle_seen(lists: list, payloads: list) -> tuple:
    """The seen state for this read. Failing to store it never fails the read.

    The file always exists after a read, so every screen has a file to watch.
    """
    path = seen_file()
    seen, changed = shelf_seen.settle(shelf_seen.load(path), lists, payloads)
    if changed or not path.exists():
        try:
            shelf_seen.save(path, seen)
        except OSError:
            pass
    return seen, path


def read_lists(vault: Path, lists: list) -> dict:
    previews = shelf_previews.load_cache(preview_cache())
    out = []
    for cfg in lists:
        reader = READERS.get(cfg.get("type"))
        if reader is None:
            out.append({"id": cfg.get("id", ""), "state": "error", "message": "Unknown list type"})
        elif cfg.get("type") == "folder":
            out.append(reader(vault, cfg, previews))
        else:
            out.append(reader(vault, cfg))
    stamp = datetime.now().astimezone().isoformat(timespec="seconds")
    seen, path = settle_seen(lists, out)
    return {"ok": True, "readAt": stamp, "lists": out, "seen": seen, "seenPath": str(path)}


def read_payload(stdin) -> dict:
    """The JSON object an action reads on stdin; an empty stdin is {}."""
    text = stdin.read()
    if not text.strip():
        return {}
    payload = json.loads(text)
    if not isinstance(payload, dict):
        raise ArgumentError("stdin must be a JSON object")
    return {key: value if isinstance(value, list) else str(value) for key, value in payload.items()}


def run_board(command: str, vault: Path, cfg: dict, payload: dict) -> dict:
    item = payload.get("item", "")
    if command == "add":
        if not payload.get("section"):
            raise ArgumentError("add on a board needs a section, the lane")
        return shelf_board.add_board(vault, cfg, payload["section"], payload.get("text", ""))
    if command == "move":
        return shelf_board.move_board(vault, cfg, item, payload.get("lane", ""))
    if command == "lane":
        return shelf_board.add_lane(vault, cfg, payload.get("title", ""))
    if command == "date":
        today = datetime.now().astimezone().date().isoformat()
        return shelf_board.date_board(vault, cfg, item, payload.get("date", ""), payload.get("time", ""), today)
    if command == "edit":
        return shelf_board.edit_board(vault, cfg, item, payload.get("text", ""))
    if command == "clear":
        return shelf_board.clear_board(vault, cfg)
    actions = {"done": shelf_board.done_board, "remove": shelf_board.remove_board}
    return actions[command](vault, cfg, item)


def run_action(command: str, vault: Path, cfg: dict, payload: dict) -> dict:
    if command in NEEDS_ITEM and not payload.get("item"):
        raise ArgumentError(f"{command} needs an item")
    if cfg.get("type") == "board":
        return run_board(command, vault, cfg, payload)
    if command in ("move", "date", "lane"):
        raise ArgumentError(f"{command} applies to a board only")
    item, text = payload.get("item", ""), payload.get("text", "")
    kind = (command, cfg.get("type"))
    if kind == ("add", "checklist"):
        return add_checklist(vault, cfg, text)
    if kind == ("add", "sections"):
        if not payload.get("section"):
            raise ArgumentError("add on a sections list needs a section")
        return add_sections(vault, cfg, payload["section"], text)
    if kind == ("done", "folder"):
        return done_folder(vault, cfg, item)
    if kind == ("done", "checklist"):
        return done_checklist(vault, cfg, item)
    if kind == ("clear", "sections"):
        return clear_sections(vault, cfg)
    removers = {"folder": done_folder, "checklist": remove_checklist, "sections": remove_sections}
    editors = {"folder": edit_folder, "checklist": edit_checklist, "sections": edit_sections}
    if command == "remove" and cfg.get("type") in removers:
        return removers[cfg["type"]](vault, cfg, item)
    if command == "edit" and cfg.get("type") in editors:
        return editors[cfg["type"]](vault, cfg, item, text)
    raise ArgumentError(f"{command} does not apply to a {cfg.get('type')} list")


def run_sync(command: str, vault: Path) -> tuple:
    env = dict(os.environ)
    home = Path(env.get("HOME", str(Path.home())))
    ob = shelf_sync.find_ob(env, home)
    if command == "sync-state":
        return 0, shelf_sync.sync_state(vault, ob, config_home(), shelf_sync.service_active, env)
    if not ob:
        raise ArgumentError("Obsidian Headless is not installed")
    return 0, shelf_sync.install_service(ob, vault, config_home(), shelf_sync.run_quietly)


def mark_seen(lists_json: str, keys_json: str) -> dict:
    lists = json.loads(lists_json)
    keys = json.loads(keys_json)
    if not isinstance(lists, list) or not isinstance(keys, dict) or not all(isinstance(v, list) for v in keys.values()):
        raise ArgumentError("seen needs --lists as a JSON array and stdin as {listId: [keys]}")
    try:
        return shelf_seen.mark(seen_file(), lists, keys)
    except OSError as err:
        return fail("io", str(err))


def main(argv: list, stdin) -> tuple:
    try:
        args = build_parser().parse_args(argv)
        if args.command is None:
            raise ArgumentError("a command is required")
        if args.command == "sounds":
            sounds = sound_list()
            return 0, {"ok": True, "sounds": sounds, "default": shelf_sounds.default_sound(sounds)}
        if args.command == "play-sound":
            return 0, {"ok": play_sound(args.path)}
        if args.command == "vaults":
            return 0, {"ok": True, "vaults": shelf_settings.known_vaults(config_home() / "obsidian" / "obsidian.json")}
        if args.command == "seen":
            return 0, mark_seen(args.lists, stdin.read())
        vault = Path(args.vault).expanduser()
        if args.command == "scan":
            return 0, {"ok": True, "suggestions": shelf_settings.scan(vault)}
        if args.command == "paths":
            return 0, {"ok": True, "paths": shelf_settings.vault_paths(vault, args.kind)}
        if args.command == "create":
            cfg = json.loads(args.list)
            if not isinstance(cfg, dict) or not cfg.get("path"):
                raise ArgumentError("--list must be a JSON object with a path")
            sections = [str(name).strip() for name in read_payload(stdin).get("sections", []) if str(name).strip()]
            return 0, shelf_settings.create_list(vault, cfg, sections)
        if args.command == "trash":
            cfg = json.loads(args.list)
            if not isinstance(cfg, dict):
                raise ArgumentError("--list must be a JSON object")
            return 0, shelf_settings.trash_list(vault, cfg)
        if args.command in ("sync-state", "sync-service"):
            return run_sync(args.command, vault)
        if args.command == "remind":
            lists = json.loads(args.lists)
            if not isinstance(lists, list):
                raise ArgumentError("--lists must be a JSON array")
            return 0, remind(vault, lists, args.summary_time, args.sound)
        if args.command in ("read", "enrich"):
            lists = json.loads(args.lists)
            if not isinstance(lists, list):
                raise ArgumentError("--lists must be a JSON array")
            if args.command == "enrich":
                kinds = {k.strip() for k in args.previews.split(",") if k.strip()}
                return 0, shelf_previews.enrich(vault, lists, preview_cache(), tweets="tweets" in kinds,
                                                links="links" in kinds, fetch_image=shelf_previews.download_image)
            return 0, read_lists(vault, lists)
        cfg = json.loads(args.list)
        if not isinstance(cfg, dict) or not cfg.get("path"):
            raise ArgumentError("--list must be a JSON object with a path")
        return 0, run_action(args.command, vault, cfg, read_payload(stdin))
    except (ArgumentError, json.JSONDecodeError) as err:
        return 2, fail("invalid", str(err))
