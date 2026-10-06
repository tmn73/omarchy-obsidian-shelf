import io
import json
import subprocess
import sys
import unittest
from pathlib import Path

from shelf_cli import main
from tests.vault_case import VaultCase

ROOT = Path(__file__).resolve().parent.parent
TODO = {"id": "todo", "name": "Todo", "type": "checklist", "path": "Todo.md"}
RETRO = {"id": "retro", "name": "Retro", "type": "sections", "path": "Retrospective.md"}
LATER = {"id": "read-later", "name": "Read later", "type": "folder", "path": "Read Later"}


class CliTest(VaultCase):
    def run_cli(self, *argv, stdin=""):
        return main(list(argv), io.StringIO(stdin))

    def test_read_returns_lists_in_given_order(self):
        self.write("Todo.md", "- [ ] a\n")
        self.write("Retrospective.md", "## Good\n")
        code, out = self.run_cli("read", "--vault", str(self.vault), "--lists", json.dumps([TODO, LATER, RETRO]))
        self.assertEqual(code, 0)
        self.assertTrue(out["ok"])
        self.assertEqual([l["id"] for l in out["lists"]], ["todo", "read-later", "retro"])
        self.assertEqual([l["state"] for l in out["lists"]], ["ok", "missing", "ok"])
        self.assertRegex(out["readAt"], r"^\d{4}-\d{2}-\d{2}T")

    def test_add_reads_text_from_stdin(self):
        code, out = self.run_cli("add", "--vault", str(self.vault), "--list", json.dumps(TODO), stdin="ship it")
        self.assertEqual((code, out), (0, {"ok": True}))
        self.assertEqual(self.read("Todo.md"), "- [ ] ship it\n")

    def test_add_strips_trailing_newline_from_stdin(self):
        self.run_cli("add", "--vault", str(self.vault), "--list", json.dumps(TODO), stdin="ship it\n")
        self.assertEqual(self.read("Todo.md"), "- [ ] ship it\n")

    def test_add_with_section(self):
        self.write("Retrospective.md", "## Good\n\n## Bad\n")
        code, out = self.run_cli("add", "--vault", str(self.vault), "--list", json.dumps(RETRO), "--section", "Bad", stdin="x")
        self.assertEqual(out, {"ok": True})
        self.assertEqual(self.read("Retrospective.md"), "## Good\n\n## Bad\n- x\n")

    def test_done_and_clear_dispatch(self):
        self.write("Todo.md", "- [ ] a\n")
        self.assertEqual(self.run_cli("done", "--vault", str(self.vault), "--list", json.dumps(TODO), "--item", "- [ ] a")[1], {"ok": True})
        self.write("Retrospective.md", "## Good\n- a\n")
        self.assertEqual(self.run_cli("clear", "--vault", str(self.vault), "--list", json.dumps(RETRO))[1], {"ok": True})
        self.assertEqual(self.read("Retrospective.md"), "## Good\n")

    def test_bad_lists_json_is_invalid_exit_2(self):
        code, out = self.run_cli("read", "--vault", str(self.vault), "--lists", "[not json")
        self.assertEqual(code, 2)
        self.assertEqual(out["error"], "invalid")

    def test_unknown_command_is_invalid_exit_2(self):
        code, out = self.run_cli("explode")
        self.assertEqual(code, 2)
        self.assertEqual(out["error"], "invalid")

    def test_action_on_wrong_type_is_invalid(self):
        self.write("Todo.md", "- [ ] a\n")
        code, out = self.run_cli("clear", "--vault", str(self.vault), "--list", json.dumps(TODO))
        self.assertEqual(code, 2)
        self.assertEqual(out["error"], "invalid")
        self.assertEqual(self.read("Todo.md"), "- [ ] a\n")

    def test_script_runs_end_to_end(self):
        self.write("Todo.md", "- [ ] a\n")
        result = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "obsidian-shelf"), "read", "--vault", str(self.vault), "--lists", json.dumps([TODO])],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["lists"][0]["items"][0]["text"], "a")


class CliSyncTest(VaultCase):
    def test_sync_state_reports_the_next_step(self):
        from unittest import mock
        env = {"PATH": "/nonexistent", "HOME": str(self.vault), "XDG_CONFIG_HOME": str(self.vault / "cfg")}
        with mock.patch.dict("os.environ", env, clear=True):
            code, out = main(["sync-state", "--vault", str(self.vault)], io.StringIO(""))
        self.assertEqual(code, 0)
        self.assertEqual(out, {"ok": True, "state": "no-client", "client": ""})

    def test_sync_service_without_client_is_invalid(self):
        from unittest import mock
        env = {"PATH": "/nonexistent", "HOME": str(self.vault), "XDG_CONFIG_HOME": str(self.vault / "cfg")}
        with mock.patch.dict("os.environ", env, clear=True):
            code, out = main(["sync-service", "--vault", str(self.vault)], io.StringIO(""))
        self.assertEqual(out["error"], "invalid")


class CliPreviewTest(VaultCase):
    def env(self):
        return {"PATH": "/nonexistent", "HOME": str(self.vault), "XDG_CACHE_HOME": str(self.vault / "cache")}

    def test_read_uses_the_preview_cache(self):
        from unittest import mock
        self.write("Read Later/w.md", "# [W](https://x.com/wesbos/status/1)\n")
        cache = self.vault / "cache" / "obsidian-shelf" / "previews.json"
        cache.parent.mkdir(parents=True)
        cache.write_text(json.dumps({"https://api.fxtwitter.com/wesbos/status/1": {"avatar": "https://a/x.jpg", "image": ""}}), encoding="utf-8")
        with mock.patch.dict("os.environ", self.env(), clear=True):
            code, out = main(["read", "--vault", str(self.vault), "--lists", json.dumps([LATER])], io.StringIO(""))
        self.assertEqual(out["lists"][0]["items"][0]["avatar"], "https://a/x.jpg")

    def test_enrich_without_tweets_fetches_nothing(self):
        from unittest import mock
        self.write("Read Later/a.md", "# A\nhttps://example.org\n")
        with mock.patch.dict("os.environ", self.env(), clear=True):
            code, out = main(["enrich", "--vault", str(self.vault), "--lists", json.dumps([LATER])], io.StringIO(""))
        self.assertEqual((code, out), (0, {"ok": True, "fetched": 0}))


class ScriptHygieneTest(VaultCase):
    def test_script_does_not_write_bytecode_into_the_plugin(self):
        import shutil
        cache = ROOT / "helper" / "__pycache__"
        shutil.rmtree(cache, ignore_errors=True)
        subprocess.run(
            [sys.executable, str(ROOT / "bin" / "obsidian-shelf"), "read", "--vault", str(self.vault), "--lists", "[]"],
            capture_output=True, text=True, check=True,
        )
        self.assertFalse(cache.exists(), "the helper wrote __pycache__ next to its modules")


class CliEditRemoveTest(VaultCase):
    def run_cli(self, *argv, stdin=""):
        return main(list(argv), io.StringIO(stdin))

    def test_edit_reads_text_from_stdin(self):
        self.write("Todo.md", "- [ ] a\n")
        code, out = self.run_cli("edit", "--vault", str(self.vault), "--list", json.dumps(TODO), "--item", "- [ ] a", stdin="b\n")
        self.assertEqual((code, out), (0, {"ok": True}))
        self.assertEqual(self.read("Todo.md"), "- [ ] b\n")

    def test_remove_dispatches_by_type(self):
        self.write("Todo.md", "- [ ] a\n")
        self.write("Retrospective.md", "## Good\n- a\n")
        self.write("Read Later/n.md", "# N\n")
        self.assertEqual(self.run_cli("remove", "--vault", str(self.vault), "--list", json.dumps(TODO), "--item", "- [ ] a")[1], {"ok": True})
        self.assertEqual(self.run_cli("remove", "--vault", str(self.vault), "--list", json.dumps(RETRO), "--item", "Good\n- a")[1], {"ok": True})
        self.assertEqual(self.run_cli("remove", "--vault", str(self.vault), "--list", json.dumps(LATER), "--item", "Read Later/n.md")[1], {"ok": True})
        self.assertEqual(self.read("Todo.md"), "")
        self.assertEqual(self.read("Retrospective.md"), "## Good\n")
        self.assertTrue((self.vault / ".trash" / "n.md").exists())


if __name__ == "__main__":
    unittest.main()
