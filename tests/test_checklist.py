import unittest

from shelf_checklist import read_checklist
from tests.vault_case import VaultCase

CFG = {"id": "todo", "type": "checklist", "path": "Todo.md"}


class ChecklistReadTest(VaultCase):
    def texts(self):
        return [i["text"] for i in read_checklist(self.vault, CFG)["items"]]

    def test_reads_open_items_in_file_order(self):
        self.write("Todo.md", "- [ ] video skill marketplace\n- [ ] tuto upload marketplace\n")
        out = read_checklist(self.vault, CFG)
        self.assertEqual(out["state"], "ok")
        self.assertEqual(out["items"][0], {"key": "- [ ] video skill marketplace", "text": "video skill marketplace"})
        self.assertEqual(self.texts(), ["video skill marketplace", "tuto upload marketplace"])

    def test_star_bullet_counts(self):
        self.write("Todo.md", "* [ ] a\n")
        self.assertEqual(self.texts(), ["a"])

    def test_checked_lines_are_hidden(self):
        self.write("Todo.md", "- [x] a\n- [X] b\n- [ ] c\n")
        self.assertEqual(self.texts(), ["c"])

    def test_indented_items_are_ignored(self):
        self.write("Todo.md", "- [ ] a\n  - [ ] sub\n\t- [ ] tab\n")
        self.assertEqual(self.texts(), ["a"])

    def test_other_lines_are_ignored(self):
        self.write("Todo.md", "# Todo\nsome note\n- plain bullet\n- [ ] a\n")
        self.assertEqual(self.texts(), ["a"])

    def test_missing_file_state_missing(self):
        out = read_checklist(self.vault, CFG)
        self.assertEqual(out["state"], "missing")
        self.assertEqual(out["message"], "Todo.md not found")

    def test_path_outside_vault_is_refused(self):
        out = read_checklist(self.vault, {"id": "x", "type": "checklist", "path": "../x.md"})
        self.assertEqual(out["state"], "error")


if __name__ == "__main__":
    unittest.main()
