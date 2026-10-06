import unittest

from shelf_sections import read_sections
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


if __name__ == "__main__":
    unittest.main()
