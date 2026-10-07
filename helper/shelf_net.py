"""The only way the helper reads the web: public addresses only, at every hop.

A saved link is untrusted. Its page, a redirect, or a name that resolves to
a private address could make the helper probe the user's own machine or
network. So every hop, redirects included, is checked after DNS resolution,
and the connection goes to the address that was checked, not to a second
lookup of the name. TLS still checks the certificate against the name.
"""

import http.client
import ipaddress
import socket
import ssl
from urllib.parse import urljoin, urlsplit, urlunsplit

TIMEOUT = 5
MAX_REDIRECTS = 5
REDIRECTS = (301, 302, 303, 307, 308)
AGENT = "facebookexternalhit/1.1 (compatible; obsidian-shelf)"


def is_global(address: str) -> bool:
    """True only for an address on the public internet."""
    try:
        ip = ipaddress.ip_address(address.split("%", 1)[0])
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return ip.is_global and not ip.is_multicast


def public_ip(host: str, port: int, resolve=socket.getaddrinfo):
    """The address to connect to, or None when any address of the name is not public."""
    try:
        infos = resolve(host, port, 0, socket.SOCK_STREAM)
    except (OSError, UnicodeError):
        return None
    addresses = [info[4][0] for info in infos]
    if not addresses or not all(is_global(a) for a in addresses):
        return None
    return addresses[0]


class PinnedHTTPConnection(http.client.HTTPConnection):
    """An HTTP connection to a checked address, with the name in the Host header."""

    def __init__(self, host, port, ip, timeout):
        super().__init__(host, port, timeout=timeout)
        self.ip = ip

    def connect(self):
        self.sock = socket.create_connection((self.ip, self.port), self.timeout)


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    """An HTTPS connection to a checked address; the certificate must match the name."""

    def __init__(self, host, port, ip, timeout):
        self.pinned_context = ssl.create_default_context()
        super().__init__(host, port, timeout=timeout, context=self.pinned_context)
        self.ip = ip

    def connect(self):
        sock = socket.create_connection((self.ip, self.port), self.timeout)
        self.sock = self.pinned_context.wrap_socket(sock, server_hostname=self.host)


def open_pinned(scheme, host, port, ip, timeout):
    kind = PinnedHTTPSConnection if scheme == "https" else PinnedHTTPConnection
    return kind(host, port, ip, timeout)


def get(url: str, accept: str, limit: int, timeout=TIMEOUT, resolve=socket.getaddrinfo, connect=open_pinned) -> tuple:
    """(content type, at most limit bytes) of a public web address.

    Raises ValueError when a hop is not a public http(s) address, a status is
    not 200, or there are too many redirects; OSError on network failures.
    """
    for _ in range(MAX_REDIRECTS + 1):
        parts = urlsplit(url)
        if parts.scheme not in ("http", "https") or not parts.hostname:
            raise ValueError("not a web address")
        port = parts.port or (443 if parts.scheme == "https" else 80)
        ip = public_ip(parts.hostname, port, resolve)
        if ip is None:
            raise ValueError(f"{parts.hostname} is not a public address")
        conn = connect(parts.scheme, parts.hostname, port, ip, timeout)
        try:
            path = urlunsplit(("", "", parts.path or "/", parts.query, ""))
            conn.request("GET", path, headers={"User-Agent": AGENT, "Accept": accept})
            response = conn.getresponse()
            if response.status in REDIRECTS:
                location = response.getheader("Location") or ""
                if not location:
                    raise ValueError("a redirect without a location")
                url = urljoin(url, location)
                continue
            if response.status != 200:
                raise ValueError(f"HTTP {response.status}")
            return response.getheader("Content-Type") or "", response.read(limit)
        finally:
            conn.close()
    raise ValueError("too many redirects")
