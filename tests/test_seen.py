import io
import json
import unittest
from pathlib import Path

from shelf_cli import main
from shelf_seen import load, mark, settle, state_file
from tests.vault_case import VaultCase

TODO = {"id": "todo", "name": "Todo", "type": "checklist", "path": "Todo.md"}
LATER = {"id": "read-later", "name": "Read later", "type": "folder", "path": "Read Later"}


def todo_payload(*texts, state="ok"):
    return {"id": "todo", "state": state, "items": [{"key": f"- [ ] {t}"} for t in texts]}


class StateFileTest(unittest.TestCase):
    def test_follows_xdg_state_home(self):
        path = state_file({"XDG_STATE_HOME": "/s"}, Path("/home/u"))
        self.assertEqual(path, Path("/s/obsidian-shelf/seen.json"))

    def test_defaults_to_local_state(self):
        self.assertEqual(state_file({}, Path("/home/u")), Path("/home/u/.local/state/obsidian-shelf/seen.json"))


class SettleTest(unittest.TestCase):
    def test_a_new_list_starts_with_every_item_seen(self):
        seen, changed = settle({}, [TODO], [todo_payload("a", "b")])
        self.assertTrue(changed)
        self.assertEqual(seen, {"todo": {"path": "Todo.md", "type": "checklist", "keys": ["- [ ] a", "- [ ] b"]}})

    def test_a_known_list_keeps_its_seen_keys(self):
        before = {"todo": {"path": "Todo.md", "type": "checklist", "keys": ["- [ ] a"]}}
        seen, changed = settle(before, [TODO], [todo_payload("a", "new")])
        self.assertFalse(changed)
        self.assertEqual(seen, before)

    def test_a_list_pointed_at_another_path_starts_seen_again(self):
        before = {"todo": {"path": "Old.md", "keys": []}}
        seen, changed = settle(before, [TODO], [todo_payload("a")])
        self.assertTrue(changed)
        self.assertEqual(seen["todo"], {"path": "Todo.md", "type": "checklist", "keys": ["- [ ] a"]})

    def test_a_list_that_changes_type_starts_seen_again(self):
        before = {"todo": {"path": "Todo.md", "type": "checklist", "keys": ["- [ ] a"]}}
        board = dict(TODO, type="board")
        payload = {"id": "todo", "state": "ok", "lanes": [{"title": "To do", "complete": False, "items": [{"key": "a"}]}]}
        seen, changed = settle(before, [board], [payload])
        self.assertTrue(changed)
        self.assertEqual(seen["todo"], {"path": "Todo.md", "type": "board", "keys": ["a"]})

    def test_an_entry_written_before_types_were_stored_is_kept(self):
        before = {"todo": {"path": "Todo.md", "keys": ["- [ ] a"]}}
        seen, changed = settle(before, [TODO], [todo_payload("a", "b")])
        self.assertEqual(seen["todo"]["keys"], ["- [ ] a"])

    def test_a_missing_list_is_left_alone(self):
        before = {"todo": {"path": "Todo.md", "keys": ["- [ ] a"]}}
        seen, changed = settle(before, [TODO], [{"id": "todo", "state": "missing"}])
        self.assertFalse(changed)
        self.assertEqual(seen, before)

    def test_a_list_no_longer_on_the_shelf_is_dropped(self):
        before = {"todo": {"path": "Todo.md", "keys": []}, "gone": {"path": "Gone.md", "keys": []}}
        seen, changed = settle(before, [TODO], [todo_payload()])
        self.assertTrue(changed)
        self.assertEqual(list(seen), ["todo"])

    def test_section_items_are_keyed_like_the_model(self):
        retro = {"id": "retro", "type": "sections", "path": "R.md"}
        payload = {"id": "retro", "state": "ok", "sections": [{"heading": "Good", "items": [{"key": "Good\n- x"}]}]}
        seen, _ = settle({}, [retro], [payload])
        self.assertEqual(seen["retro"]["keys"], ["Good\n- x"])


class BoardKeysTest(unittest.TestCase):
    def test_board_cards_are_keyed_in_every_lane(self):
        board = {"id": "b", "type": "board", "path": "B.md"}
        payload = {"id": "b", "state": "ok", "lanes": [
            {"title": "To do", "complete": False, "items": [{"key": "a"}]},
            {"title": "Done", "complete": True, "items": [{"key": "z"}]}]}
        seen, _ = settle({}, [board], [payload])
        self.assertEqual(seen["b"]["keys"], ["a", "z"])


class LoadAndMarkTest(VaultCase):
    def test_a_missing_or_broken_file_loads_empty(self):
        path = self.vault / "state" / "seen.json"
        self.assertEqual(load(path), {})
        self.write("state/seen.json", "{not json")
        self.assertEqual(load(path), {})
        self.write("state/seen.json", json.dumps({"todo": "wrong shape"}))
        self.assertEqual(load(path), {})

    def test_mark_replaces_the_given_lists_and_keeps_the_others(self):
        path = self.vault / "state" / "seen.json"
        later = {"path": "Read Later", "keys": ["l1"]}
        self.write("state/seen.json", json.dumps({"todo": {"path": "Todo.md", "keys": []}, "read-later": later}))
        out = mark(path, [TODO, LATER], {"todo": ["- [ ] a"]})
        self.assertEqual(out, {"ok": True})
        self.assertEqual(load(path), {"todo": {"path": "Todo.md", "type": "checklist", "keys": ["- [ ] a"]}, "read-later": later})

    def test_mark_ignores_lists_that_are_not_on_the_shelf(self):
        path = self.vault / "state" / "seen.json"
        mark(path, [TODO], {"intruder": ["x"]})
        self.assertEqual(load(path), {})


class CliSeenTest(VaultCase):
    def run_cli(self, *argv, stdin=""):
        return main(list(argv), io.StringIO(stdin))

    def seen_file(self):
        return Path(self.state_home) / "obsidian-shelf" / "seen.json"

    def test_read_reports_and_stores_what_was_seen(self):
        self.write("Todo.md", "- [ ] a\n")
        code, out = self.run_cli("read", "--vault", str(self.vault), "--lists", json.dumps([TODO]))
        self.assertEqual(code, 0)
        self.assertEqual(out["seen"], {"todo": {"path": "Todo.md", "type": "checklist", "keys": ["- [ ] a"]}})
        self.assertEqual(out["seenPath"], str(self.seen_file()))
        self.assertEqual(load(self.seen_file()), out["seen"])

    def test_read_creates_the_file_even_without_lists(self):
        self.run_cli("read", "--vault", str(self.vault), "--lists", "[]")
        self.assertTrue(self.seen_file().exists())

    def test_an_item_added_after_the_first_read_stays_unseen(self):
        self.write("Todo.md", "- [ ] a\n")
        self.run_cli("read", "--vault", str(self.vault), "--lists", json.dumps([TODO]))
        self.write("Todo.md", "- [ ] a\n- [ ] b\n")
        code, out = self.run_cli("read", "--vault", str(self.vault), "--lists", json.dumps([TODO]))
        self.assertEqual(out["seen"]["todo"]["keys"], ["- [ ] a"])

    def test_seen_command_reads_keys_from_stdin(self):
        code, out = self.run_cli("seen", "--lists", json.dumps([TODO]), stdin=json.dumps({"todo": ["- [ ] a", "- [ ] b"]}))
        self.assertEqual((code, out), (0, {"ok": True}))
        self.assertEqual(load(self.seen_file())["todo"]["keys"], ["- [ ] a", "- [ ] b"])

    def test_seen_command_refuses_bad_input(self):
        code, out = self.run_cli("seen", "--lists", json.dumps([TODO]), stdin="[1, 2]")
        self.assertEqual((code, out["error"]), (2, "invalid"))


if __name__ == "__main__":
    unittest.main()
