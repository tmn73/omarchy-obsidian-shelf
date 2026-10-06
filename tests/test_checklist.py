import unittest

from shelf_checklist import add_checklist, done_checklist, edit_checklist, read_checklist, remove_checklist
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


class ChecklistActionTest(VaultCase):
    def first_key(self):
        return read_checklist(self.vault, CFG)["items"][0]["key"]

    def test_done_delete_removes_line(self):
        self.write("Todo.md", "# Todo\n- [ ] a\n- [ ] b\n")
        self.assertEqual(done_checklist(self.vault, CFG, "- [ ] a"), {"ok": True})
        self.assertEqual(self.read("Todo.md"), "# Todo\n- [ ] b\n")

    def test_done_check_mode_writes_x(self):
        self.write("Todo.md", "- [ ] a\n")
        cfg = dict(CFG, onDone="check")
        self.assertEqual(done_checklist(self.vault, cfg, "- [ ] a"), {"ok": True})
        self.assertEqual(self.read("Todo.md"), "- [x] a\n")

    def test_done_delete_purges_checked_lines(self):
        self.write("Todo.md", "- [x] old\n- [ ] a\n- [X] older\n- [ ] b\n")
        done_checklist(self.vault, CFG, "- [ ] a")
        self.assertEqual(self.read("Todo.md"), "- [ ] b\n")

    def test_done_check_mode_keeps_checked_lines(self):
        self.write("Todo.md", "- [x] old\n- [ ] a\n")
        done_checklist(self.vault, dict(CFG, onDone="check"), "- [ ] a")
        self.assertEqual(self.read("Todo.md"), "- [x] old\n- [x] a\n")

    def test_done_removes_only_first_duplicate(self):
        self.write("Todo.md", "- [ ] same\n- [ ] same\n")
        done_checklist(self.vault, CFG, "- [ ] same")
        self.assertEqual(self.read("Todo.md"), "- [ ] same\n")

    def test_done_keeps_line_added_after_read(self):
        self.write("Todo.md", "- [ ] a\n- [ ] b\n")
        key = self.first_key()
        self.write("Todo.md", "- [ ] a\n- [ ] b\n- [ ] from phone\n")
        self.assertEqual(done_checklist(self.vault, CFG, key), {"ok": True})
        self.assertEqual(self.read("Todo.md"), "- [ ] b\n- [ ] from phone\n")

    def test_done_unknown_key_returns_changed(self):
        self.write("Todo.md", "- [ ] a\n")
        out = done_checklist(self.vault, CFG, "- [ ] gone")
        self.assertEqual(out["error"], "changed")
        self.assertEqual(self.read("Todo.md"), "- [ ] a\n")

    def test_done_missing_file_returns_missing(self):
        self.assertEqual(done_checklist(self.vault, CFG, "- [ ] a")["error"], "missing")

    def test_add_appends_open_item(self):
        self.write("Todo.md", "- [ ] a")
        self.assertEqual(add_checklist(self.vault, CFG, "buy filters"), {"ok": True})
        self.assertEqual(self.read("Todo.md"), "- [ ] a\n- [ ] buy filters\n")

    def test_add_creates_missing_file(self):
        self.assertEqual(add_checklist(self.vault, CFG, "a"), {"ok": True})
        self.assertEqual(self.read("Todo.md"), "- [ ] a\n")

    def test_add_empty_text_is_invalid(self):
        self.assertEqual(add_checklist(self.vault, CFG, "   ")["error"], "invalid")

    def test_add_multiline_text_becomes_one_line(self):
        add_checklist(self.vault, CFG, "a\nb")
        self.assertEqual(self.read("Todo.md"), "- [ ] a b\n")



class ChecklistEditRemoveTest(VaultCase):
    def test_remove_deletes_line_even_in_check_mode(self):
        self.write("Todo.md", "- [ ] a\n- [ ] b\n")
        self.assertEqual(remove_checklist(self.vault, dict(CFG, onDone="check"), "- [ ] a"), {"ok": True})
        self.assertEqual(self.read("Todo.md"), "- [ ] b\n")

    def test_remove_unknown_key_returns_changed(self):
        self.write("Todo.md", "- [ ] a\n")
        self.assertEqual(remove_checklist(self.vault, CFG, "- [ ] gone")["error"], "changed")

    def test_edit_keeps_bullet_and_box(self):
        self.write("Todo.md", "* [ ] old text\n- [ ] b\n")
        self.assertEqual(edit_checklist(self.vault, CFG, "* [ ] old text", "new text"), {"ok": True})
        self.assertEqual(self.read("Todo.md"), "* [ ] new text\n- [ ] b\n")

    def test_edit_keeps_line_added_after_read(self):
        self.write("Todo.md", "- [ ] a\n")
        self.write("Todo.md", "- [ ] a\n- [ ] from phone\n")
        edit_checklist(self.vault, CFG, "- [ ] a", "A")
        self.assertEqual(self.read("Todo.md"), "- [ ] A\n- [ ] from phone\n")

    def test_edit_unknown_key_returns_changed(self):
        self.write("Todo.md", "- [ ] a\n")
        self.assertEqual(edit_checklist(self.vault, CFG, "- [ ] gone", "x")["error"], "changed")

    def test_edit_empty_text_is_invalid(self):
        self.write("Todo.md", "- [ ] a\n")
        self.assertEqual(edit_checklist(self.vault, CFG, "- [ ] a", "")["error"], "invalid")

if __name__ == "__main__":
    unittest.main()
