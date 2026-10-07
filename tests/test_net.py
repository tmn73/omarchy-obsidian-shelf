import socket
import unittest
from unittest import mock

from shelf_net import PinnedHTTPConnection, get, is_global, public_ip


def resolver(table):
    """A getaddrinfo that answers from {host: [addresses]}."""
    def resolve(host, port, *args, **kwargs):
        if host not in table:
            raise socket.gaierror("unknown host")
        return [(socket.AF_INET6 if ":" in a else socket.AF_INET, socket.SOCK_STREAM, 6, "", (a, port)) for a in table[host]]
    return resolve


class FakeResponse:
    def __init__(self, status, headers=None, body=b""):
        self.status, self.headers, self.body = status, headers or {}, body

    def getheader(self, name, default=None):
        return self.headers.get(name, default)

    def read(self, size=-1):
        return self.body if size < 0 else self.body[:size]


class FakeWeb:
    """connect() for get(): answers by host and keeps every connection made."""

    def __init__(self, pages):
        self.pages, self.connections = pages, []

    def __call__(self, scheme, host, port, ip, timeout):
        web = self

        class Conn:
            def request(self, method, path, headers=None):
                web.connections.append((scheme, host, port, ip, path, headers))
                self.response = web.pages[host]

            def getresponse(self):
                return self.response

            def close(self):
                pass
        return Conn()


class GlobalTest(unittest.TestCase):
    def test_public_addresses_pass(self):
        for address in ("93.184.216.34", "2606:4700::1111"):
            self.assertTrue(is_global(address), address)

    def test_local_and_private_addresses_fail(self):
        for address in ("127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1",
                        "0.0.0.0", "::1", "fc00::1", "fe80::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1", "224.0.0.1"):
            self.assertFalse(is_global(address), address)


class PublicIpTest(unittest.TestCase):
    def test_every_address_must_be_public(self):
        self.assertEqual(public_ip("a.example", 443, resolver({"a.example": ["93.184.216.34"]})), "93.184.216.34")
        self.assertIsNone(public_ip("b.example", 443, resolver({"b.example": ["93.184.216.34", "10.0.0.5"]})))

    def test_a_name_that_does_not_resolve_is_refused(self):
        self.assertIsNone(public_ip("nowhere.example", 443, resolver({})))


class GetTest(unittest.TestCase):
    def test_follows_public_redirects_on_the_checked_address(self):
        web = FakeWeb({
            "a.example": FakeResponse(302, {"Location": "https://b.example/page?x=1"}),
            "b.example": FakeResponse(200, {"Content-Type": "text/html"}, b"<html>ok</html>"),
        })
        dns = resolver({"a.example": ["93.184.216.34"], "b.example": ["151.101.1.69"]})
        ctype, body = get("https://a.example/start", "text/html", 1000, resolve=dns, connect=web)
        self.assertEqual((ctype, body), ("text/html", b"<html>ok</html>"))
        self.assertEqual([(c[1], c[3], c[4]) for c in web.connections],
                         [("a.example", "93.184.216.34", "/start"), ("b.example", "151.101.1.69", "/page?x=1")])

    def test_a_redirect_to_a_private_address_is_refused(self):
        web = FakeWeb({"a.example": FakeResponse(301, {"Location": "http://127.0.0.1:8080/admin"})})
        with self.assertRaises(ValueError):
            get("https://a.example/", "text/html", 1000, resolve=resolver({"a.example": ["93.184.216.34"]}), connect=web)
        self.assertEqual(len(web.connections), 1)

    def test_a_redirect_to_a_name_on_the_local_network_is_refused(self):
        web = FakeWeb({"a.example": FakeResponse(307, {"Location": "http://router.example/"})})
        dns = resolver({"a.example": ["93.184.216.34"], "router.example": ["192.168.1.1"]})
        with self.assertRaises(ValueError):
            get("https://a.example/", "text/html", 1000, resolve=dns, connect=web)
        self.assertEqual(len(web.connections), 1)

    def test_a_public_name_that_resolves_to_a_private_address_is_never_contacted(self):
        web = FakeWeb({})
        with self.assertRaises(ValueError):
            get("https://evil.example/", "text/html", 1000, resolve=resolver({"evil.example": ["10.0.0.1"]}), connect=web)
        self.assertEqual(web.connections, [])

    def test_a_redirect_out_of_the_web_is_refused(self):
        web = FakeWeb({"a.example": FakeResponse(302, {"Location": "file:///etc/passwd"})})
        with self.assertRaises(ValueError):
            get("https://a.example/", "text/html", 1000, resolve=resolver({"a.example": ["93.184.216.34"]}), connect=web)

    def test_stops_after_five_redirects(self):
        web = FakeWeb({"a.example": FakeResponse(302, {"Location": "https://a.example/again"})})
        with self.assertRaises(ValueError):
            get("https://a.example/", "text/html", 1000, resolve=resolver({"a.example": ["93.184.216.34"]}), connect=web)
        self.assertEqual(len(web.connections), 6)

    def test_reads_no_more_than_the_limit(self):
        web = FakeWeb({"a.example": FakeResponse(200, {"Content-Type": "text/html"}, b"x" * 5000)})
        _, body = get("https://a.example/", "text/html", 100, resolve=resolver({"a.example": ["93.184.216.34"]}), connect=web)
        self.assertEqual(len(body), 100)


class PinnedConnectionTest(unittest.TestCase):
    def test_connects_to_the_checked_address_and_keeps_the_host_name(self):
        with mock.patch("socket.create_connection") as create:
            conn = PinnedHTTPConnection("a.example", 80, "93.184.216.34", 5)
            conn.connect()
        self.assertEqual(create.call_args[0][0], ("93.184.216.34", 80))
        self.assertEqual(conn.host, "a.example")


if __name__ == "__main__":
    unittest.main()
