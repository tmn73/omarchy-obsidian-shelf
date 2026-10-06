import json
import os
import unittest

from shelf_settings import create_list, known_vaults, scan, vault_paths
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


if __name__ == "__main__":
    unittest.main()
