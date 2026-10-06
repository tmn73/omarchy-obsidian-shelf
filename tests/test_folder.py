import os
import tempfile
import unittest
from pathlib import Path

from shelf_folder import done_folder, edit_folder, read_folder

TWEET = """[[ReadItLater]] [[Tweet]]

# [WitcherHour](https://x.com/WitcherHour/status/2107244538465231193)

> Roach noooo! [pic.twitter.com/y0nddS1RLR](https://t.co/y0nddS1RLR)
"""
CFG = {"id": "read-later", "type": "folder", "path": "Read Later"}


class FolderCase(unittest.TestCase):
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


class FolderReadTest(FolderCase):
    def test_title_url_excerpt_domain_from_readitlater_note(self):
        self.note("Tweet from WitcherHour.md", TWEET)
        out = read_folder(self.vault, CFG)
        self.assertEqual(out["state"], "ok")
        item = out["items"][0]
        self.assertEqual(item["title"], "WitcherHour")
        self.assertEqual(item["url"], "https://x.com/WitcherHour/status/2107244538465231193")
        self.assertEqual(item["excerpt"], "Roach noooo!")
        self.assertEqual(item["image"], "")
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


class FolderDoneTest(FolderCase):
    def test_done_moves_note_to_trash(self):
        self.note("a.md", "# A\n")
        self.assertEqual(done_folder(self.vault, CFG, "Read Later/a.md"), {"ok": True})
        self.assertFalse((self.folder / "a.md").exists())
        self.assertEqual((self.vault / ".trash" / "a.md").read_text(encoding="utf-8"), "# A\n")

    def test_done_trash_conflict_adds_suffix(self):
        (self.vault / ".trash").mkdir()
        (self.vault / ".trash" / "a.md").write_text("older", encoding="utf-8")
        self.note("a.md", "# A\n")
        self.assertEqual(done_folder(self.vault, CFG, "Read Later/a.md"), {"ok": True})
        self.assertEqual((self.vault / ".trash" / "a 1.md").read_text(encoding="utf-8"), "# A\n")
        self.assertEqual((self.vault / ".trash" / "a.md").read_text(encoding="utf-8"), "older")

    def test_done_unknown_key_returns_changed(self):
        out = done_folder(self.vault, CFG, "Read Later/gone.md")
        self.assertEqual(out["ok"], False)
        self.assertEqual(out["error"], "changed")

    def test_done_key_outside_folder_is_invalid(self):
        (self.vault / "Todo.md").write_text("- [ ] a\n", encoding="utf-8")
        for key in ("Todo.md", "Read Later/../Todo.md", "../x.md"):
            out = done_folder(self.vault, CFG, key)
            self.assertEqual(out["error"], "invalid", key)
        self.assertTrue((self.vault / "Todo.md").exists())



YOUTUBE = """[[ReadItLater]] [[Youtube]]

# [France 4-1 Belgique](https://youtube.com/watch?v=pg5PZk_PhP4)

<iframe width="560" height="315" src="https://www.youtube-nocookie.com/embed/pg5PZk_PhP4" allowfullscreen></iframe>
"""


class FolderImageTest(FolderCase):
    def test_youtube_note_gets_its_thumbnail_and_no_html_excerpt(self):
        self.note("v.md", YOUTUBE)
        item = self.items()[0]
        self.assertEqual(item["image"], "https://i.ytimg.com/vi/pg5PZk_PhP4/mqdefault.jpg")
        self.assertEqual(item["excerpt"], "")
        self.assertEqual(item["domain"], "youtube.com")

    def test_short_youtube_link_gets_its_thumbnail(self):
        self.note("v.md", "# Clip\n\nhttps://youtu.be/abcDEF12345\n")
        self.assertEqual(self.items()[0]["image"], "https://i.ytimg.com/vi/abcDEF12345/mqdefault.jpg")

    def test_first_markdown_image_is_used(self):
        self.note("a.md", "# A\n\n![cover](https://example.org/cover.png)\n\nText https://example.org/a\n")
        item = self.items()[0]
        self.assertEqual(item["image"], "https://example.org/cover.png")
        self.assertEqual(item["excerpt"], "Text https://example.org/a")

    def test_front_matter_image_wins(self):
        self.note("a.md", "---\nimage: https://example.org/fm.jpg\n---\n![x](https://example.org/b.png)\n")
        self.assertEqual(self.items()[0]["image"], "https://example.org/fm.jpg")

    def test_inline_html_tags_are_removed_from_the_excerpt(self):
        self.note("a.md", "# A\n\nSome <b>bold</b> text\n")
        self.assertEqual(self.items()[0]["excerpt"], "Some bold text")


class FolderEditTest(FolderCase):
    def test_read_prefers_front_matter_title(self):
        self.note("a.md", "---\ntitle: Witcher armor guide\n---\n" + TWEET)
        self.assertEqual(self.items()[0]["title"], "Witcher armor guide")

    def test_edit_adds_front_matter_title_and_keeps_body(self):
        self.note("a.md", TWEET)
        self.assertEqual(edit_folder(self.vault, CFG, "Read Later/a.md", "Roach"), {"ok": True})
        text = (self.folder / "a.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith('---\ntitle: "Roach"\n---\n'))
        self.assertTrue(text.endswith(TWEET))
        self.assertEqual(self.items()[0]["title"], "Roach")

    def test_edit_replaces_existing_title_and_keeps_other_keys(self):
        self.note("a.md", "---\nurl: https://example.org/a\ntitle: Old\n---\nBody\n")
        edit_folder(self.vault, CFG, "Read Later/a.md", 'New "quoted": title')
        item = self.items()[0]
        self.assertEqual(item["title"], 'New "quoted": title')
        self.assertEqual(item["url"], "https://example.org/a")

    def test_edit_unknown_key_returns_changed(self):
        self.assertEqual(edit_folder(self.vault, CFG, "Read Later/gone.md", "x")["error"], "changed")

    def test_edit_empty_text_is_invalid(self):
        self.note("a.md", "# A\n")
        self.assertEqual(edit_folder(self.vault, CFG, "Read Later/a.md", "  ")["error"], "invalid")

if __name__ == "__main__":
    unittest.main()
