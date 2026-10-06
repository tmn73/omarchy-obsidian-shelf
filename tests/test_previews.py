import json
import unittest

from shelf_folder import read_folder
from shelf_previews import enrich, load_cache, preview_from_fxtwitter, tweet_api_url
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
        item = read_folder(self.vault, CFG, load_cache(self.cache))["items"][0]
        self.assertEqual(item["avatar"], "https://pbs.twimg.com/profile_images/1/a_200x200.jpg")
        self.assertEqual(item["image"], "https://pbs.twimg.com/media/HT857.jpg?name=small")
        self.assertFalse(item["previewPending"])

    def test_read_marks_an_unfetched_tweet_as_pending(self):
        item = read_folder(self.vault, CFG, {})["items"][0]
        self.assertTrue(item["previewPending"])
        self.assertEqual(item["avatar"], "")

    def test_a_missing_cache_file_reads_as_empty(self):
        self.assertEqual(load_cache(self.vault / "nope.json"), {})


if __name__ == "__main__":
    unittest.main()
