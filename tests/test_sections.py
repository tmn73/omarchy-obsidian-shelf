import unittest

from shelf_sections import add_sections, clear_sections, edit_sections, read_sections, remove_sections
from tests.vault_case import VaultCase

RETRO = "## Good\n\n## Bad\n- canal payments-sandbox-staging-errors\n- Meilleur logs payment-service car pas d'accès aws\n"
CFG = {"id": "retro", "type": "sections", "path": "Retrospective.md"}


class SectionsReadTest(VaultCase):
    def test_reads_sections_and_items(self):
        self.write("Retrospective.md", RETRO)
        out = read_sections(self.vault, CFG)
        self.assertEqual(out["state"], "ok")
        self.assertEqual([s["heading"] for s in out["sections"]], ["Good", "Bad"])
        self.assertEqual(out["sections"][0]["items"], [])
        self.assertEqual(out["sections"][1]["items"][0]["key"], "Bad\n- canal payments-sandbox-staging-errors")
        self.assertEqual(out["sections"][1]["items"][1]["text"], "Meilleur logs payment-service car pas d'accès aws")

    def test_text_before_first_heading_is_not_an_item(self):
        self.write("Retrospective.md", "- loose\n## Good\n- a\n")
        out = read_sections(self.vault, CFG)
        self.assertEqual([s["heading"] for s in out["sections"]], ["Good"])
        self.assertEqual([i["text"] for i in out["sections"][0]["items"]], ["a"])

    def test_nested_bullets_are_not_items(self):
        self.write("Retrospective.md", "## Good\n- a\n  - nested\n")
        out = read_sections(self.vault, CFG)
        self.assertEqual([i["text"] for i in out["sections"][0]["items"]], ["a"])

    def test_heading_levels_one_to_six(self):
        self.write("Retrospective.md", "# One\n###### Six\n####### Seven\n")
        out = read_sections(self.vault, CFG)
        self.assertEqual([s["heading"] for s in out["sections"]], ["One", "Six"])

    def test_missing_file_state_missing(self):
        out = read_sections(self.vault, CFG)
        self.assertEqual(out["state"], "missing")
        self.assertEqual(out["message"], "Retrospective.md not found")


class SectionsActionTest(VaultCase):
    def test_add_inserts_after_last_item_of_section(self):
        self.write("Retrospective.md", RETRO)
        self.assertEqual(add_sections(self.vault, CFG, "Good", "x"), {"ok": True})
        self.assertEqual(self.read("Retrospective.md"), "## Good\n- x\n\n## Bad\n- canal payments-sandbox-staging-errors\n- Meilleur logs payment-service car pas d'accès aws\n")

    def test_add_to_section_with_items_appends_after_last(self):
        self.write("Retrospective.md", RETRO)
        add_sections(self.vault, CFG, "Bad", "y")
        self.assertTrue(self.read("Retrospective.md").endswith("- Meilleur logs payment-service car pas d'accès aws\n- y\n"))

    def test_add_keeps_line_added_after_read(self):
        self.write("Retrospective.md", "## Good\n- a\n")
        read_sections(self.vault, CFG)
        self.write("Retrospective.md", "## Good\n- a\n- from phone\n")
        add_sections(self.vault, CFG, "Good", "b")
        self.assertEqual(self.read("Retrospective.md"), "## Good\n- a\n- from phone\n- b\n")

    def test_add_unknown_heading_returns_changed(self):
        self.write("Retrospective.md", RETRO)
        self.assertEqual(add_sections(self.vault, CFG, "Ugly", "x")["error"], "changed")
        self.assertEqual(self.read("Retrospective.md"), RETRO)

    def test_add_empty_text_is_invalid(self):
        self.write("Retrospective.md", RETRO)
        self.assertEqual(add_sections(self.vault, CFG, "Good", "")["error"], "invalid")

    def test_add_missing_file_returns_missing(self):
        self.assertEqual(add_sections(self.vault, CFG, "Good", "x")["error"], "missing")

    def test_clear_keeps_headings_and_preamble(self):
        self.write("Retrospective.md", RETRO)
        self.assertEqual(clear_sections(self.vault, CFG), {"ok": True})
        self.assertEqual(self.read("Retrospective.md"), "## Good\n\n## Bad\n")
        self.write("Retrospective.md", "Topics\n\n## Good\n- a\n\n## Bad\n- b\n")
        clear_sections(self.vault, CFG)
        self.assertEqual(self.read("Retrospective.md"), "Topics\n\n## Good\n\n## Bad\n")

    def test_clear_missing_file_returns_missing(self):
        self.assertEqual(clear_sections(self.vault, CFG)["error"], "missing")



class SectionsEditRemoveTest(VaultCase):
    TWO = "## Good\n- same\n\n## Bad\n- same\n- other\n"

    def test_remove_topic_of_the_given_section_only(self):
        self.write("Retrospective.md", self.TWO)
        self.assertEqual(remove_sections(self.vault, CFG, "Bad\n- same"), {"ok": True})
        self.assertEqual(self.read("Retrospective.md"), "## Good\n- same\n\n## Bad\n- other\n")

    def test_remove_unknown_topic_returns_changed(self):
        self.write("Retrospective.md", self.TWO)
        self.assertEqual(remove_sections(self.vault, CFG, "Bad\n- gone")["error"], "changed")
        self.assertEqual(remove_sections(self.vault, CFG, "Ugly\n- same")["error"], "changed")

    def test_edit_topic_of_the_given_section_only(self):
        self.write("Retrospective.md", self.TWO)
        self.assertEqual(edit_sections(self.vault, CFG, "Good\n- same", "better"), {"ok": True})
        self.assertEqual(self.read("Retrospective.md"), "## Good\n- better\n\n## Bad\n- same\n- other\n")

    def test_edit_key_without_newline_is_invalid(self):
        self.write("Retrospective.md", self.TWO)
        self.assertEqual(edit_sections(self.vault, CFG, "same", "x")["error"], "invalid")

if __name__ == "__main__":
    unittest.main()
