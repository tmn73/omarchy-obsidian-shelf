import os
import tempfile
import unittest
from pathlib import Path

from shelf_folder import read_folder

TWEET = """[[ReadItLater]] [[Tweet]]

# [WitcherHour](https://x.com/WitcherHour/status/2107244538465231193)

> Roach noooo! [pic.twitter.com/y0nddS1RLR](https://t.co/y0nddS1RLR)
"""
CFG = {"id": "read-later", "type": "folder", "path": "Read Later"}


class FolderReadTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.vault = Path(self._tmp.name)
        self.folder = self.vault / "Read Later"
        self.folder.mkdir()

    def tearDown(self):
        self._tmp.cleanup()

    def note(self, name, text, mtime=None):
        path = self.folder / name
        path.write_text(text, encoding="utf-8")
        if mtime is not None:
            os.utime(path, (mtime, mtime))
        return path

    def items(self):
        return read_folder(self.vault, CFG)["items"]

    def test_title_url_excerpt_domain_from_readitlater_note(self):
        self.note("Tweet from WitcherHour.md", TWEET)
        out = read_folder(self.vault, CFG)
        self.assertEqual(out["state"], "ok")
        item = out["items"][0]
        self.assertEqual(item["title"], "WitcherHour")
        self.assertEqual(item["url"], "https://x.com/WitcherHour/status/2107244538465231193")
        self.assertEqual(item["excerpt"], "Roach noooo! pic.twitter.com/y0nddS1RLR")
        self.assertEqual(item["domain"], "x.com")
        self.assertEqual(item["key"], "Read Later/Tweet from WitcherHour.md")
        self.assertRegex(item["modifiedAt"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$")

    def test_front_matter_url_wins_over_body(self):
        self.note("a.md", "---\nurl: https://example.org/a\n---\n# A\n\nSee https://other.net/b\n")
        item = self.items()[0]
        self.assertEqual(item["url"], "https://example.org/a")
        self.assertEqual(item["domain"], "example.org")

    def test_source_key_is_read_from_front_matter(self):
        self.note("a.md", "---\nsource: https://example.org/s\n---\nBody\n")
        self.assertEqual(self.items()[0]["url"], "https://example.org/s")

    def test_www_is_stripped_from_domain(self):
        self.note("a.md", "# A\n\nhttps://www.youtube.com/watch?v=abc\n")
        self.assertEqual(self.items()[0]["domain"], "youtube.com")

    def test_title_falls_back_to_file_name(self):
        self.note("Some article.md", "Just a line https://example.org\n")
        self.assertEqual(self.items()[0]["title"], "Some article")

    def test_note_without_url_has_empty_url(self):
        self.note("a.md", "# A\n\nNo link here\n")
        item = self.items()[0]
        self.assertEqual(item["url"], "")
        self.assertEqual(item["domain"], "")

    def test_excerpt_stops_at_200_characters(self):
        self.note("a.md", "# A\n\n" + "x" * 300 + "\n")
        self.assertEqual(len(self.items()[0]["excerpt"]), 200)

    def test_newest_first(self):
        self.note("old.md", "# Old\n", mtime=1_700_000_000)
        self.note("new.md", "# New\n", mtime=1_800_000_000)
        self.assertEqual([i["title"] for i in self.items()], ["New", "Old"])

    def test_subfolders_and_non_md_files_are_ignored(self):
        self.note("a.md", "# A\n")
        (self.folder / "assets").mkdir()
        (self.folder / "assets" / "b.md").write_text("# B\n", encoding="utf-8")
        (self.folder / "c.png").write_bytes(b"\x89PNG")
        self.assertEqual([i["title"] for i in self.items()], ["A"])

    def test_missing_folder_state_missing(self):
        self.folder.rmdir()
        out = read_folder(self.vault, CFG)
        self.assertEqual(out["state"], "missing")
        self.assertEqual(out["message"], "Read Later not found")

    def test_path_outside_vault_is_refused(self):
        out = read_folder(self.vault, {"id": "x", "type": "folder", "path": "../outside"})
        self.assertEqual(out["state"], "error")
        self.assertIn("outside the vault", out["message"])

    def test_read_missing_vault_reports_every_list_missing(self):
        out = read_folder(self.vault / "gone", CFG)
        self.assertEqual(out["state"], "missing")


if __name__ == "__main__":
    unittest.main()
