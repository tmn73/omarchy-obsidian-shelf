import json
import unittest

from shelf_folder import read_folder
from unittest import mock
from shelf_previews import download_image, enrich, fetch_html, is_public_url, load_cache, og_from_html, page_preview, preview_from_fxtwitter, preview_key, tweet_api_url
from tests.vault_case import VaultCase

CFG = {"id": "read-later", "type": "folder", "path": "Read Later"}
TWEET = "# [Wes Bos](https://x.com/wesbos/status/2107467615635480614)\n\n> 4 months ago\n"
FX = {
    "code": 200,
    "tweet": {
        "author": {"name": "Wes Bos", "avatar_url": "https://pbs.twimg.com/profile_images/1/a_200x200.jpg"},
        "media": {"photos": [{"url": "https://pbs.twimg.com/media/HT857.jpg?name=orig", "type": "photo"}]},
    },
}


class TweetApiUrlTest(unittest.TestCase):
    def test_status_links_map_to_fxtwitter(self):
        self.assertEqual(tweet_api_url("https://x.com/wesbos/status/2107467615635480614?ref_src=x"),
                         "https://api.fxtwitter.com/wesbos/status/2107467615635480614")
        self.assertEqual(tweet_api_url("https://twitter.com/dhh/status/42"), "https://api.fxtwitter.com/dhh/status/42")

    def test_other_links_have_no_api_url(self):
        self.assertEqual(tweet_api_url("https://x.com/wesbos"), "")
        self.assertEqual(tweet_api_url("https://youtube.com/watch?v=abc"), "")


class PreviewFromFxtwitterTest(unittest.TestCase):
    def test_avatar_and_first_photo_in_small_size(self):
        self.assertEqual(preview_from_fxtwitter(FX), {
            "avatar": "https://pbs.twimg.com/profile_images/1/a_200x200.jpg",
            "image": "https://pbs.twimg.com/media/HT857.jpg?name=small",
        })

    def test_video_thumbnail_when_there_is_no_photo(self):
        data = {"tweet": {"author": {}, "media": {"videos": [{"thumbnail_url": "https://pbs.twimg.com/v.jpg"}]}}}
        self.assertEqual(preview_from_fxtwitter(data)["image"], "https://pbs.twimg.com/v.jpg")

    def test_text_only_tweet_has_no_image(self):
        data = {"tweet": {"author": {"avatar_url": "https://pbs.twimg.com/a.jpg"}}}
        self.assertEqual(preview_from_fxtwitter(data), {"avatar": "https://pbs.twimg.com/a.jpg", "image": ""})


class EnrichTest(VaultCase):
    def setUp(self):
        super().setUp()
        self.write("Read Later/wes.md", TWEET)
        self.cache = self.vault / "cache" / "previews.json"
        self.calls = []

    def fetch(self, url):
        self.calls.append(url)
        return FX

    def test_enrich_fetches_each_tweet_once(self):
        self.assertEqual(enrich(self.vault, [CFG], self.cache, self.fetch, now=1000), {"ok": True, "fetched": 1})
        self.assertEqual(enrich(self.vault, [CFG], self.cache, self.fetch, now=1001), {"ok": True, "fetched": 0})
        self.assertEqual(len(self.calls), 1)

    def test_enrich_remembers_a_failure_for_a_day(self):
        def broken(url):
            self.calls.append(url)
            raise OSError("down")
        enrich(self.vault, [CFG], self.cache, broken, now=1000)
        enrich(self.vault, [CFG], self.cache, broken, now=1000 + 3600)
        self.assertEqual(len(self.calls), 1)
        enrich(self.vault, [CFG], self.cache, broken, now=1000 + 86400 + 1)
        self.assertEqual(len(self.calls), 2)

    def test_read_merges_the_cached_preview(self):
        enrich(self.vault, [CFG], self.cache, self.fetch, now=1000)
        item = read_folder(self.vault, CFG, load_cache(self.cache), local=False)["items"][0]
        self.assertEqual(item["avatar"], "https://pbs.twimg.com/profile_images/1/a_200x200.jpg")
        self.assertEqual(item["image"], "https://pbs.twimg.com/media/HT857.jpg?name=small")
        self.assertFalse(item["previewPending"])

    def test_read_marks_an_unfetched_tweet_as_pending(self):
        item = read_folder(self.vault, CFG, {})["items"][0]
        self.assertTrue(item["previewPending"])
        self.assertEqual(item["avatar"], "")

    def test_a_missing_cache_file_reads_as_empty(self):
        self.assertEqual(load_cache(self.vault / "nope.json"), {})



IG_NOTE = """[[ReadItLater]] [[Article]]

[https://www.instagram.com/reel/DeJJ1cMj6W8/?stkn=x](https://www.instagram.com/reel/DeJJ1cMj6W8/?stkn=x)
"""
IG_HTML = """<html><head>
<meta property="og:site_name" content="Instagram" />
<meta property="og:title" content="ana beatriz on Instagram: &quot;TAKE MOZART AI AWAY FROM HER

#beefing&quot;" />
<meta content="457 likes, 26 comments" property="og:description" />
<meta property="og:image" content="https://scontent.cdninstagram.com/v/a.jpg?stp=x&amp;_nc_cat=101" />
</head></html>"""


class OpenGraphTest(unittest.TestCase):
    def test_reads_og_tags_in_both_attribute_orders_and_unescapes(self):
        self.assertEqual(og_from_html(IG_HTML), {
            "title": 'ana beatriz on Instagram: "TAKE MOZART AI AWAY FROM HER #beefing"',
            "description": "457 likes, 26 comments",
            "image": "https://scontent.cdninstagram.com/v/a.jpg?stp=x&_nc_cat=101",
        })

    def test_twitter_image_is_a_fallback(self):
        html = '<meta name="twitter:image" content="https://example.org/t.png">'
        self.assertEqual(og_from_html(html)["image"], "https://example.org/t.png")

    def test_preview_keys(self):
        self.assertEqual(preview_key("https://x.com/a/status/1"), "https://api.fxtwitter.com/a/status/1")
        self.assertEqual(preview_key("https://www.instagram.com/reel/X/"), "og:https://www.instagram.com/reel/X/")
        self.assertEqual(preview_key(""), "")


REDDIT_HTML = """<html><head><title>Can someone explain how Omarchy is bloated or insecure? : r/omarchy</title>
<meta name="description" content="18 votes, 73 comments. I&#x27;ve used Omarchy pretty regularly since 4.0">
<meta property="og:title" content="From the omarchy community on Reddit">
<meta property="og:description" content="Explore this post and more from the omarchy community">
<meta property="og:image" content="https://share.redd.it/preview/post/1wyz0ar">
</head></html>"""


class PublicUrlTest(unittest.TestCase):
    def test_local_and_private_addresses_are_never_fetched(self):
        for url in ("http://localhost:8080/x", "http://127.0.0.1/", "http://192.168.1.10/admin", "http://10.0.0.2/",
                    "http://172.16.5.4/", "http://[::1]/", "http://printer.local/", "http://169.254.169.254/latest"):
            self.assertFalse(is_public_url(url), url)

    def test_public_sites_are_fetched(self):
        self.assertTrue(is_public_url("https://www.instagram.com/reel/X/"))
        self.assertTrue(is_public_url("https://8.8.8.8/"))

    def test_a_local_link_gets_no_link_preview(self):
        self.assertEqual(preview_key("http://localhost:3000/dashboard"), "")


class SitePreviewTest(unittest.TestCase):
    def test_reddit_uses_the_page_title_and_description_not_its_brand_card(self):
        self.assertEqual(page_preview("https://www.reddit.com/r/omarchy/s/llwz8QfrQR", REDDIT_HTML), {
            "title": "Can someone explain how Omarchy is bloated or insecure?",
            "description": "18 votes, 73 comments. I've used Omarchy pretty regularly since 4.0",
            "image": "",
        })

    def test_other_sites_keep_their_opengraph_tags(self):
        self.assertEqual(page_preview("https://www.instagram.com/reel/X/", IG_HTML), og_from_html(IG_HTML))


class LinkPreviewTest(VaultCase):
    def setUp(self):
        super().setUp()
        self.cache = self.vault / "cache" / "previews.json"
        self.pages = []

    def page(self, url):
        self.pages.append(url)
        return IG_HTML

    def test_instagram_note_takes_title_excerpt_and_image_from_the_page(self):
        self.write("Read Later/Article 2026-10-06 09-49-32.md", IG_NOTE)
        self.assertEqual(read_folder(self.vault, CFG, {})["items"][0]["previewKind"], "link")
        enrich(self.vault, [CFG], self.cache, fetch_page=self.page, now=1000)
        item = read_folder(self.vault, CFG, load_cache(self.cache), local=False)["items"][0]
        self.assertTrue(item["title"].startswith("ana beatriz on Instagram"))
        self.assertEqual(item["excerpt"], "457 likes, 26 comments")
        self.assertTrue(item["image"].startswith("https://scontent.cdninstagram.com/"))
        self.assertEqual(item["previewKind"], "")
        self.assertEqual(len(self.pages), 1)

    def test_a_note_heading_keeps_its_title(self):
        self.write("Read Later/a.md", "# My own title\n\nhttps://www.instagram.com/reel/X/\n")
        enrich(self.vault, [CFG], self.cache, fetch_page=self.page, now=1000)
        item = read_folder(self.vault, CFG, load_cache(self.cache), local=False)["items"][0]
        self.assertEqual(item["title"], "My own title")
        self.assertTrue(item["image"].startswith("https://scontent"))

    def test_a_note_with_title_and_image_needs_no_page(self):
        self.write("Read Later/v.md", "# Video\n\nhttps://youtube.com/watch?v=pg5PZk_PhP4\n")
        self.assertEqual(read_folder(self.vault, CFG, {})["items"][0]["previewKind"], "")
        enrich(self.vault, [CFG], self.cache, fetch_page=self.page, now=1000)
        self.assertEqual(self.pages, [])

    def test_link_previews_off_fetches_no_page(self):
        self.write("Read Later/i.md", IG_NOTE)
        enrich(self.vault, [CFG], self.cache, fetch_page=self.page, now=1000, links=False)
        self.assertEqual(self.pages, [])

    def test_tweet_previews_off_fetches_no_tweet(self):
        self.write("Read Later/wes.md", TWEET)
        calls = []
        enrich(self.vault, [CFG], self.cache, fetch=lambda u: calls.append(u) or FX, now=1000, tweets=False)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()


class FetchTest(unittest.TestCase):
    def test_pages_go_through_the_public_only_fetch(self):
        with mock.patch("shelf_net.get", return_value=("text/html; charset=utf-8", "<p>é</p>".encode())) as get:
            self.assertEqual(fetch_html("https://example.org/a"), "<p>é</p>")
        self.assertEqual(get.call_args[0][0], "https://example.org/a")

    def test_a_page_that_is_not_html_is_refused(self):
        with mock.patch("shelf_net.get", return_value=("application/pdf", b"%PDF")):
            with self.assertRaises(ValueError):
                fetch_html("https://example.org/a.pdf")

    def test_no_helper_module_opens_a_url_on_its_own(self):
        from pathlib import Path
        helper = Path(__file__).resolve().parent.parent / "helper"
        for path in helper.glob("*.py"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("urlopen", text, path.name)
            self.assertNotIn("urllib.request", text, path.name)


class ImageTest(VaultCase):
    PAGE = "---\ntitle: \"A\"\nurl: https://example.org/a\nimage: https://cdn.example.org/a.jpg\n---\n"

    def setUp(self):
        super().setUp()
        self.write("Read Later/a.md", self.PAGE)
        self.cache = self.vault / "cache" / "previews.json"
        self.images = self.vault / "cache" / "images"

    def test_a_remote_image_is_never_handed_to_the_shell(self):
        item = read_folder(self.vault, CFG, {})["items"][0]
        self.assertEqual(item["image"], "")
        self.assertTrue(item["imagePending"])

    def test_enrich_downloads_the_image_and_read_gives_the_local_file(self):
        saved = []

        def fetch_image(url, folder):
            saved.append(url)
            folder.mkdir(parents=True, exist_ok=True)
            path = folder / "a.jpg"
            path.write_bytes(b"jpg")
            return path
        out = enrich(self.vault, [CFG], self.cache, now=1000, links=False, tweets=False, fetch_image=fetch_image)
        self.assertEqual(out, {"ok": True, "fetched": 1})
        self.assertEqual(saved, ["https://cdn.example.org/a.jpg"])
        item = read_folder(self.vault, CFG, load_cache(self.cache))["items"][0]
        self.assertEqual(item["image"], (self.images / "a.jpg").as_uri())
        self.assertFalse(item["imagePending"])

    def test_a_failed_image_waits_a_day(self):
        def broken(url, folder):
            raise ValueError("not public")
        enrich(self.vault, [CFG], self.cache, now=1000, links=False, tweets=False, fetch_image=broken)
        item = read_folder(self.vault, CFG, load_cache(self.cache), now=1000 + 3600)["items"][0]
        self.assertFalse(item["imagePending"])
        item = read_folder(self.vault, CFG, load_cache(self.cache), now=1000 + 86400 + 1)["items"][0]
        self.assertTrue(item["imagePending"])

    def test_download_keeps_images_only_and_names_them_by_type(self):
        with mock.patch("shelf_net.get", return_value=("image/png", b"\x89PNG")):
            path = download_image("https://cdn.example.org/x", self.images)
        self.assertEqual(path.suffix, ".png")
        self.assertEqual(path.read_bytes(), b"\x89PNG")
        with mock.patch("shelf_net.get", return_value=("text/html", b"<html>")):
            with self.assertRaises(ValueError):
                download_image("https://cdn.example.org/y", self.images)
