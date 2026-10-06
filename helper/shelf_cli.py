"""Command line contract of the helper (spec section 6).

main() never prints and never exits: it returns the exit code and the JSON
object, so the tests drive it directly and bin/obsidian-shelf only prints.
"""

import argparse
import json
import os
from datetime import datetime
from pathlib import Path

from shelf_checklist import add_checklist, done_checklist, edit_checklist, read_checklist, remove_checklist
from shelf_folder import done_folder, edit_folder, read_folder
from shelf_io import fail
import shelf_sync
from shelf_sections import add_sections, clear_sections, edit_sections, read_sections, remove_sections

READERS = {"folder": read_folder, "checklist": read_checklist, "sections": read_sections}


class ArgumentError(ValueError):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ArgumentError(message)


def build_parser() -> Parser:
    parser = Parser(prog="obsidian-shelf", add_help=False)
    commands = parser.add_subparsers(dest="command", parser_class=Parser)
    read = commands.add_parser("read", add_help=False)
    read.add_argument("--vault", required=True)
    read.add_argument("--lists", required=True)
    for name in ("sync-state", "sync-service"):
        sub = commands.add_parser(name, add_help=False)
        sub.add_argument("--vault", required=True)
    for name in ("add", "done", "clear", "edit", "remove"):
        sub = commands.add_parser(name, add_help=False)
        sub.add_argument("--vault", required=True)
        sub.add_argument("--list", required=True)
        if name == "add":
            sub.add_argument("--section", default=None)
        if name in ("done", "edit", "remove"):
            sub.add_argument("--item", required=True)
    return parser


def read_lists(vault: Path, lists: list) -> dict:
    out = []
    for cfg in lists:
        reader = READERS.get(cfg.get("type"))
        if reader is None:
            out.append({"id": cfg.get("id", ""), "state": "error", "message": "Unknown list type"})
        else:
            out.append(reader(vault, cfg))
    stamp = datetime.now().astimezone().isoformat(timespec="seconds")
    return {"ok": True, "readAt": stamp, "lists": out}


def run_action(args, vault: Path, cfg: dict, stdin) -> dict:
    kind = (args.command, cfg.get("type"))
    if kind == ("add", "checklist"):
        return add_checklist(vault, cfg, stdin.read())
    if kind == ("add", "sections"):
        if not args.section:
            raise ArgumentError("add on a sections list needs --section")
        return add_sections(vault, cfg, args.section, stdin.read())
    if kind == ("done", "folder"):
        return done_folder(vault, cfg, args.item)
    if kind == ("done", "checklist"):
        return done_checklist(vault, cfg, args.item)
    if kind == ("clear", "sections"):
        return clear_sections(vault, cfg)
    removers = {"folder": done_folder, "checklist": remove_checklist, "sections": remove_sections}
    editors = {"folder": edit_folder, "checklist": edit_checklist, "sections": edit_sections}
    if args.command == "remove" and cfg.get("type") in removers:
        return removers[cfg["type"]](vault, cfg, args.item)
    if args.command == "edit" and cfg.get("type") in editors:
        return editors[cfg["type"]](vault, cfg, args.item, stdin.read())
    raise ArgumentError(f"{args.command} does not apply to a {cfg.get('type')} list")


def run_sync(command: str, vault: Path) -> tuple:
    env = dict(os.environ)
    home = Path(env.get("HOME", str(Path.home())))
    config_home = Path(env.get("XDG_CONFIG_HOME") or home / ".config")
    ob = shelf_sync.find_ob(env, home)
    if command == "sync-state":
        return 0, shelf_sync.sync_state(vault, ob, config_home, shelf_sync.service_active, env)
    if not ob:
        raise ArgumentError("Obsidian Headless is not installed")
    return 0, shelf_sync.install_service(ob, vault, config_home, shelf_sync.run_quietly)


def main(argv: list, stdin) -> tuple:
    try:
        args = build_parser().parse_args(argv)
        if args.command is None:
            raise ArgumentError("a command is required")
        vault = Path(args.vault).expanduser()
        if args.command in ("sync-state", "sync-service"):
            return run_sync(args.command, vault)
        if args.command == "read":
            lists = json.loads(args.lists)
            if not isinstance(lists, list):
                raise ArgumentError("--lists must be a JSON array")
            return 0, read_lists(vault, lists)
        cfg = json.loads(args.list)
        if not isinstance(cfg, dict) or not cfg.get("path"):
            raise ArgumentError("--list must be a JSON object with a path")
        return 0, run_action(args, vault, cfg, stdin)
    except (ArgumentError, json.JSONDecodeError) as err:
        return 2, fail("invalid", str(err))
