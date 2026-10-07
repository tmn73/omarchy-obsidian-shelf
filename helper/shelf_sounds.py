"""The sounds a reminder can play: only the ones already on the system.

Sound themes live in <data dir>/sounds/<theme>/ (freedesktop.org sound theme
layout): the user's data dir first, then the system ones. The plugin ships
no sound of its own.
"""

import subprocess
from pathlib import Path

EXTENSIONS = {".oga", ".ogg", ".wav", ".flac"}
DEFAULT_NAME = "alarm-clock-elapsed"
LIMIT = 300
# Sounds of the freedesktop sound naming spec that are no alert: speaker
# tests, device and power events, and feedback for actions the user just did.
NOT_ALERTS = ("audio-channel-", "audio-test-signal", "audio-volume-change", "device-", "power-",
              "network-connectivity-", "service-", "camera-shutter", "screen-capture", "trash-empty",
              "phone-outgoing-", "suspend-", "desktop-log", "system-", "lid-", "item-", "file-trash")


def is_alert(name: str) -> bool:
    return not any(name.startswith(prefix) for prefix in NOT_ALERTS)


def sound_roots(env: dict, home: Path) -> list:
    data_home = Path(env.get("XDG_DATA_HOME") or Path(home) / ".local" / "share")
    dirs = [d for d in (env.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
    return [data_home / "sounds"] + [Path(d) / "sounds" for d in dirs]


def list_sounds(roots: list) -> list:
    """[{name, theme, path}] by theme then name; the first root wins a name.

    The first root is the user's own: any folder there counts. In a system
    root only a real theme counts, one with an index.theme, so speaker test
    files (alsa) stay out.
    """
    found = {}
    for position, root in enumerate(roots):
        if not Path(root).is_dir():
            continue
        themes = sorted(p for p in Path(root).iterdir() if p.is_dir())
        if position > 0:
            themes = [t for t in themes if (t / "index.theme").is_file()]
        for theme in themes:
            for path in sorted(theme.rglob("*")):
                key = (theme.name, path.stem)
                if path.suffix.lower() in EXTENSIONS and is_alert(path.stem) and path.is_file() and key not in found:
                    found[key] = {"name": path.stem, "theme": theme.name, "path": str(path)}
                    if len(found) >= LIMIT:
                        break
    return [found[key] for key in sorted(found)]


def default_sound(sounds: list) -> str:
    alarm = next((s for s in sounds if s["name"] == DEFAULT_NAME), None)
    if alarm:
        return alarm["path"]
    return sounds[0]["path"] if sounds else ""


def play(path: str, which, popen) -> bool:
    """Start the sound and return at once; the player outlives the helper."""
    if not path or not Path(path).is_file():
        return False
    for player in ("pw-play", "paplay"):
        if which(player):
            try:
                popen([player, path], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL, start_new_session=True)
                return True
            except OSError:
                return False
    return False
