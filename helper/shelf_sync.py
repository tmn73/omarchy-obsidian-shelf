"""Obsidian Sync on this machine through Obsidian Headless (the `ob` client).

The plugin never logs in and never handles a password: `ob login` runs in a
terminal the user sees. This module only reads where `ob` keeps its state, so
the popup can show which setup step is next, and writes the systemd unit
that keeps the sync running.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

from shelf_io import atomic_write, fail, ok

SERVICE = "obsidian-headless.service"
CLIENT_DIRS = (".cache/.bun/bin", ".bun/bin", ".local/bin")


def find_ob(env: dict, home: Path) -> str:
    """The path of the `ob` client, or "" when it is not installed.

    The shell often runs with a PATH that lacks the user's tool folders, so the
    usual install places are checked too.
    """
    found = shutil.which("ob", path=env.get("PATH", ""))
    if found:
        return found
    for folder in CLIENT_DIRS:
        candidate = Path(home) / folder / "ob"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return ""


def client_home(config_home: Path) -> Path:
    return Path(config_home) / "obsidian-headless"


def logged_in(config_home: Path, env: dict) -> bool:
    if env.get("OBSIDIAN_AUTH_TOKEN", "").strip():
        return True
    token = client_home(config_home) / "auth_token"
    try:
        return token.read_text(encoding="utf-8").strip() != ""
    except OSError:
        return False


def linked(config_home: Path, vault: Path) -> bool:
    target = Path(vault).expanduser().resolve()
    for config in (client_home(config_home) / "sync").glob("*/config.json"):
        try:
            path = json.loads(config.read_text(encoding="utf-8")).get("vaultPath", "")
        except (OSError, ValueError):
            continue
        if path and Path(path).expanduser().resolve() == target:
            return True
    return False


def sync_state(vault: Path, ob: str, config_home: Path, service_active, env: dict) -> dict:
    """The next setup step: no-client, logged-out, unlinked, stopped or running."""
    if not ob:
        state = "no-client"
    elif not logged_in(config_home, env):
        state = "logged-out"
    elif not linked(config_home, vault):
        state = "unlinked"
    elif not service_active():
        state = "stopped"
    else:
        state = "running"
    return {"ok": True, "state": state, "client": ob}


def service_unit(ob: str, vault: Path) -> str:
    return "\n".join([
        "[Unit]",
        "Description=Obsidian Sync for the vault, without the desktop app (Obsidian Headless)",
        "After=network-online.target",
        "Wants=network-online.target",
        "",
        "[Service]",
        "Type=simple",
        # systemd reads % as a specifier, so a literal one is written %%.
        f'ExecStart={ob} sync --continuous --path "{str(vault).replace("%", "%%")}"',
        "Restart=on-failure",
        "RestartSec=10",
        "",
        "[Install]",
        "WantedBy=default.target",
        "",
    ])


def install_service(ob: str, vault: Path, config_home: Path, run) -> dict:
    """Write the user unit, then reload systemd and start the sync at login and now."""
    if any(c in str(vault) for c in '"\\\n'):
        return fail("invalid", "The vault path holds a quote, a backslash or a line break; systemd cannot run it")
    unit = Path(config_home) / "systemd" / "user" / SERVICE
    try:
        unit.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(unit, service_unit(ob, Path(vault).expanduser().resolve()))
    except OSError as err:
        return fail("io", str(err))
    for command in (["systemctl", "--user", "daemon-reload"], ["systemctl", "--user", "enable", "--now", SERVICE]):
        if run(command) != 0:
            return fail("io", "Could not run: " + " ".join(command))
    return ok()


def service_active() -> bool:
    result = subprocess.run(["systemctl", "--user", "is-active", "--quiet", SERVICE], check=False)
    return result.returncode == 0


def run_quietly(command: list) -> int:
    return subprocess.run(command, capture_output=True, check=False).returncode
