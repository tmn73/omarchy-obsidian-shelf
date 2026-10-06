import json
import os
import unittest

from shelf_settings import create_list, known_vaults, scan, trash_list, vault_paths
from tests.vault_case import VaultCase


class KnownVaultsTest(VaultCase):
    def test_open_vault_first_then_most_recent(self):
        registry = self.write("obsidian.json", json.dumps({"vaults": {
            "a": {"path": "/home/u/Old", "ts": 100},
            "b": {"path": "/home/u/Notes", "ts": 50, "open": True},
            "c": {"path": "/home/u/Work", "ts": 200},
        }}))
        self.assertEqual(known_vaults(registry), [
            {"path": "/home/u/Notes", "name": "Notes", "open": True},
            {"path": "/home/u/Work", "name": "Work", "open": False},
            {"path": "/home/u/Old", "name": "Old", "open": False},
        ])

    def test_missing_or_broken_registry_gives_no_vault(self):
        self.assertEqual(known_vaults(self.vault / "nope.json"), [])
        self.assertEqual(known_vaults(self.write("bad.json", "{oops")), [])


class ScanTest(VaultCase):
    def test_suggests_link_folders_checklists_and_section_files(self):
        self.write("Read Later/a.md", "# A\n\nhttps://example.org/a\n")
        self.write("Read Later/b.md", "# B\n\nhttps://example.org/b\n")
        self.write("Todo.md", "- [ ] one\n- [ ] two\n- [x] done\n")
        self.write("Meeting.md", "## To discuss\n- budget\n- hiring\n\n## Decided\n- date\n")
        self.write("Journal/2026-10-06.md", "Just words, no links.\n")
        found = {(s["type"], s["path"]): s["count"] for s in scan(self.vault)}
        self.assertEqual(found, {("folder", "Read Later"): 2, ("checklist", "Todo.md"): 2, ("sections", "Meeting.md"): 3})

    def test_skips_dot_folders(self):
        self.write(".obsidian/x.md", "- [ ] hidden\n")
        self.write(".trash/y.md", "- [ ] gone\n")
        self.assertEqual(scan(self.vault), [])

    def test_largest_lists_first(self):
        self.write("Small.md", "- [ ] a\n")
        self.write("Big.md", "- [ ] a\n- [ ] b\n- [ ] c\n")
        self.assertEqual([s["path"] for s in scan(self.vault)], ["Big.md", "Small.md"])


class VaultPathsTest(VaultCase):
    def test_lists_folders_or_files_without_dot_folders(self):
        self.write("Read Later/a.md", "x")
        self.write("Projects/Shelf/plan.md", "x")
        self.write("Todo.md", "x")
        self.write(".obsidian/app.md", "x")
        self.assertEqual(vault_paths(self.vault, "folder"), ["Projects", "Projects/Shelf", "Read Later"])
        self.assertEqual(vault_paths(self.vault, "file"), ["Projects/Shelf/plan.md", "Read Later/a.md", "Todo.md"])


class CreateListTest(VaultCase):
    def test_creates_a_folder(self):
        out = create_list(self.vault, {"id": "w", "type": "folder", "path": "Watch later"}, [])
        self.assertEqual(out, {"ok": True, "created": True})
        self.assertTrue((self.vault / "Watch later").is_dir())

    def test_creates_an_empty_checklist_in_a_new_subfolder(self):
        create_list(self.vault, {"id": "g", "type": "checklist", "path": "Lists/Groceries.md"}, [])
        self.assertEqual(self.read("Lists/Groceries.md"), "")

    def test_creates_a_sections_file_with_its_headings(self):
        create_list(self.vault, {"id": "m", "type": "sections", "path": "Meeting agenda.md"}, ["To discuss", "Decided"])
        self.assertEqual(self.read("Meeting agenda.md"), "## To discuss\n\n## Decided\n")

    def test_never_overwrites(self):
        self.write("Todo.md", "- [ ] keep me\n")
        out = create_list(self.vault, {"id": "t", "type": "checklist", "path": "Todo.md"}, [])
        self.assertEqual(out, {"ok": True, "created": False})
        self.assertEqual(self.read("Todo.md"), "- [ ] keep me\n")

    def test_refuses_a_path_outside_the_vault(self):
        out = create_list(self.vault, {"id": "x", "type": "checklist", "path": "../x.md"}, [])
        self.assertEqual(out["error"], "invalid")


class BoardSettingsTest(VaultCase):
    def test_scan_suggests_a_board_and_not_a_checklist(self):
        self.write("Plan.md", "---\nkanban-plugin: board\n---\n\n## To do\n- [ ] a\n- [ ] b\n\n## Done\n**Complete**\n- [x] c\n")
        self.assertEqual(scan(self.vault), [{"type": "board", "path": "Plan.md", "count": 2}])

    def test_create_writes_a_board_with_the_last_lane_complete(self):
        out = create_list(self.vault, {"id": "b", "type": "board", "path": "Plan.md"}, ["To do", "In progress", "Done"])
        self.assertEqual(out, {"ok": True, "created": True})
        self.assertEqual(self.read("Plan.md"), "---\n\nkanban-plugin: board\n\n---\n\n## To do\n\n\n\n## In progress\n\n\n\n## Done\n\n**Complete**\n\n\n\n%% kanban:settings\n```\n{\"kanban-plugin\":\"board\"}\n```\n%%\n")


class TrashListTest(VaultCase):
    def test_moves_the_file_to_the_vault_trash(self):
        self.write("Todo.md", "- [ ] a\n")
        out = trash_list(self.vault, {"type": "checklist", "path": "Todo.md"})
        self.assertEqual(out, {"ok": True, "trashed": ".trash/Todo.md"})
        self.assertFalse((self.vault / "Todo.md").exists())
        self.assertEqual(self.read(".trash/Todo.md"), "- [ ] a\n")

    def test_keeps_a_name_already_in_the_trash(self):
        self.write("Todo.md", "new\n")
        self.write(".trash/Todo.md", "old\n")
        out = trash_list(self.vault, {"type": "checklist", "path": "Todo.md"})
        self.assertEqual(out["trashed"], ".trash/Todo 1.md")
        self.assertEqual(self.read(".trash/Todo.md"), "old\n")

    def test_moves_an_empty_folder(self):
        (self.vault / "Read Later").mkdir()
        out = trash_list(self.vault, {"type": "folder", "path": "Read Later"})
        self.assertEqual(out["trashed"], ".trash/Read Later")
        self.assertTrue((self.vault / ".trash" / "Read Later").is_dir())

    def test_refuses_a_folder_that_holds_files(self):
        self.write("Read Later/a.md", "# A\n")
        out = trash_list(self.vault, {"type": "folder", "path": "Read Later"})
        self.assertEqual(out["error"], "not-empty")
        self.assertTrue((self.vault / "Read Later" / "a.md").exists())

    def test_a_missing_path_is_missing(self):
        out = trash_list(self.vault, {"type": "checklist", "path": "Gone.md"})
        self.assertEqual(out["error"], "missing")

    def test_refuses_a_path_outside_the_vault(self):
        out = trash_list(self.vault, {"type": "checklist", "path": "../x.md"})
        self.assertEqual(out["error"], "invalid")

    def test_refuses_the_vault_itself_its_trash_and_its_config(self):
        (self.vault / ".trash").mkdir()
        self.write(".obsidian/app.json", "{}")
        for path in (".", "", ".trash", ".obsidian", ".obsidian/app.json"):
            out = trash_list(self.vault, {"type": "folder", "path": path})
            self.assertEqual(out["error"], "invalid", path)
        self.assertTrue((self.vault / ".trash").is_dir())
        self.assertTrue((self.vault / ".obsidian" / "app.json").exists())


if __name__ == "__main__":
    unittest.main()
