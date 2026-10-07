import io
import json
from datetime import datetime
from pathlib import Path
from unittest import mock

from shelf_cli import main
from shelf_sounds import default_sound, list_sounds, play, sound_roots
from tests.vault_case import VaultCase


class SoundsTest(VaultCase):
    def make(self, rel):
        path = self.vault / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"OggS")
        return path

    def test_roots_follow_the_xdg_data_dirs(self):
        env = {"XDG_DATA_HOME": "/h/data", "XDG_DATA_DIRS": "/usr/local/share:/usr/share"}
        self.assertEqual(sound_roots(env, Path("/home/u")), [Path("/h/data/sounds"), Path("/usr/local/share/sounds"), Path("/usr/share/sounds")])
        self.assertEqual(sound_roots({}, Path("/home/u")), [Path("/home/u/.local/share/sounds"), Path("/usr/local/share/sounds"), Path("/usr/share/sounds")])

    def test_lists_the_sound_files_of_every_theme(self):
        alarm = self.make("sys/sounds/freedesktop/stereo/alarm-clock-elapsed.oga")
        self.make("sys/sounds/freedesktop/stereo/bell.oga")
        self.make("sys/sounds/freedesktop/index.theme")
        self.make("user/sounds/mine/ding.wav")
        sounds = list_sounds([self.vault / "user/sounds", self.vault / "sys/sounds"])
        self.assertEqual([(s["name"], s["theme"]) for s in sounds], [("alarm-clock-elapsed", "freedesktop"), ("bell", "freedesktop"), ("ding", "mine")])
        self.assertEqual(sounds[0]["path"], str(alarm))

    def test_a_system_folder_without_index_theme_is_not_a_theme(self):
        self.make("sys/sounds/freedesktop/index.theme")
        self.make("sys/sounds/freedesktop/stereo/bell.oga")
        self.make("sys/sounds/alsa/Front_Center.wav")
        sounds = list_sounds([self.vault / "user/sounds", self.vault / "sys/sounds"])
        self.assertEqual([s["theme"] for s in sounds], ["freedesktop"])

    def test_only_alert_and_message_sounds_are_offered(self):
        self.make("sys/sounds/freedesktop/index.theme")
        for name in ("alarm-clock-elapsed", "bell", "message-new-instant", "audio-channel-front-left",
                     "audio-test-signal", "audio-volume-change", "device-added", "power-plug",
                     "network-connectivity-lost", "service-login", "camera-shutter", "screen-capture",
                     "trash-empty", "phone-outgoing-busy", "suspend-error"):
            self.make(f"sys/sounds/freedesktop/stereo/{name}.oga")
        sounds = list_sounds([self.vault / "user/sounds", self.vault / "sys/sounds"])
        self.assertEqual([s["name"] for s in sounds], ["alarm-clock-elapsed", "bell", "message-new-instant"])

    def test_a_missing_root_is_skipped(self):
        self.assertEqual(list_sounds([self.vault / "nothing"]), [])

    def test_the_default_is_the_alarm_sound_when_there_is_one(self):
        sounds = [{"name": "bell", "theme": "freedesktop", "path": "/s/bell.oga"},
                  {"name": "alarm-clock-elapsed", "theme": "freedesktop", "path": "/s/alarm.oga"}]
        self.assertEqual(default_sound(sounds), "/s/alarm.oga")
        self.assertEqual(default_sound(sounds[:1]), "/s/bell.oga")
        self.assertEqual(default_sound([]), "")

    def test_play_uses_pipewire_and_never_waits(self):
        path = self.make("sys/sounds/freedesktop/stereo/bell.oga")
        calls = []
        ok = play(str(path), lambda name: "/usr/bin/" + name, lambda cmd, **kw: calls.append((cmd, kw)))
        self.assertTrue(ok)
        self.assertEqual(calls[0][0], ["pw-play", str(path)])
        self.assertTrue(calls[0][1].get("start_new_session"))

    def test_play_falls_back_to_paplay(self):
        path = self.make("a.oga")
        calls = []
        play(str(path), lambda name: None if name == "pw-play" else "/usr/bin/" + name, lambda cmd, **kw: calls.append(cmd))
        self.assertEqual(calls, [["paplay", str(path)]])

    def test_play_refuses_a_file_that_is_not_there(self):
        self.assertFalse(play(str(self.vault / "gone.oga"), lambda name: "/usr/bin/" + name, lambda cmd, **kw: None))


class CliSoundsTest(VaultCase):
    def env(self):
        return {"PATH": "/nonexistent", "HOME": str(self.vault), "XDG_DATA_DIRS": str(self.vault / "share"), "XDG_STATE_HOME": self.state_home}

    def test_sounds_lists_the_system_sounds_and_the_default(self):
        p = self.vault / "share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
        p.parent.mkdir(parents=True)
        p.write_bytes(b"OggS")
        (self.vault / "share/sounds/freedesktop/index.theme").write_text("[Sound Theme]\n")
        with mock.patch.dict("os.environ", self.env(), clear=True):
            code, out = main(["sounds"], io.StringIO(""))
        self.assertEqual(code, 0)
        self.assertEqual(out["default"], str(p))
        self.assertEqual(out["sounds"][0]["name"], "alarm-clock-elapsed")

    def test_remind_plays_one_sound_when_something_rang(self):
        self.write("Todo.md", "## To do\n- [ ] Slides @{2026-10-06} @@{14:00}\n- [ ] Deck @{2026-10-06} @@{14:01}\n")
        board = {"id": "todo", "name": "Todo", "type": "board", "path": "Todo.md"}
        played = []
        with mock.patch("shelf_cli.reminder_clock", return_value=datetime.fromisoformat("2026-10-06T14:05")), \
             mock.patch("shelf_cli.send_notification"), \
             mock.patch("shelf_cli.play_sound", side_effect=played.append):
            main(["remind", "--vault", str(self.vault), "--lists", json.dumps([board]), "--sound", "/s/bell.oga"], io.StringIO(""))
            main(["remind", "--vault", str(self.vault), "--lists", json.dumps([board]), "--sound", "/s/bell.oga"], io.StringIO(""))
        self.assertEqual(played, ["/s/bell.oga"])

    def test_remind_with_sound_none_stays_silent(self):
        self.write("Todo.md", "## To do\n- [ ] Slides @{2026-10-06} @@{14:00}\n")
        board = {"id": "todo", "name": "Todo", "type": "board", "path": "Todo.md"}
        with mock.patch("shelf_cli.reminder_clock", return_value=datetime.fromisoformat("2026-10-06T14:05")), \
             mock.patch("shelf_cli.send_notification"), \
             mock.patch("shelf_cli.play_sound", side_effect=AssertionError("a sound played")):
            code, out = main(["remind", "--vault", str(self.vault), "--lists", json.dumps([board]), "--sound", "none"], io.StringIO(""))
        self.assertEqual(out["sent"], 1)
