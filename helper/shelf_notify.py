"""Desktop notifications over the session D-Bus, without starting a process.

A reminder carries text from the vault. The command line of a process is
readable by every local user (/proc/<pid>/cmdline), so that text must never
go into one: notify-send, busctl and omarchy-notification-send all take it
as arguments. This module speaks the D-Bus wire protocol on the session bus
socket instead, which only the user can open, and calls
org.freedesktop.Notifications.Notify directly.

Only what one call needs is here: EXTERNAL authentication, Hello, Notify, and
reading the replies. Everything is little-endian.
"""

import json
import os
import socket
import struct

APP_NAME = "Obsidian Shelf"
TIMEOUT = 3


class Writer:
    """Marshals D-Bus values; alignment counts from the start of the buffer."""

    def __init__(self):
        self.buf = bytearray()

    def align(self, size):
        self.buf += b"\0" * ((-len(self.buf)) % size)

    def byte(self, value):
        self.buf += struct.pack("<B", value)

    def uint32(self, value):
        self.align(4)
        self.buf += struct.pack("<I", value)

    def int32(self, value):
        self.align(4)
        self.buf += struct.pack("<i", value)

    def string(self, value):
        data = value.encode("utf-8")
        self.uint32(len(data))
        self.buf += data + b"\0"

    def signature(self, value):
        data = value.encode("ascii")
        self.byte(len(data))
        self.buf += data + b"\0"

    def array(self, element_alignment, write_elements):
        self.uint32(0)
        length_at = len(self.buf) - 4
        self.align(element_alignment)
        start = len(self.buf)
        write_elements()
        struct.pack_into("<I", self.buf, length_at, len(self.buf) - start)

    def value(self, sig, value):
        if sig in ("s", "o"):
            self.string(value)
        elif sig == "g":
            self.signature(value)
        elif sig == "y":
            self.byte(value)
        elif sig == "u":
            self.uint32(value)
        else:
            raise ValueError(f"cannot write a {sig}")


class Reader:
    """Reads D-Bus values; alignment counts from the start of the buffer."""

    def __init__(self, data, offset=0):
        self.data = bytes(data)
        self.at = offset

    def align(self, size):
        self.at += (-self.at) % size

    def byte(self):
        self.at += 1
        return self.data[self.at - 1]

    def uint32(self):
        self.align(4)
        self.at += 4
        return struct.unpack_from("<I", self.data, self.at - 4)[0]

    def int32(self):
        self.align(4)
        self.at += 4
        return struct.unpack_from("<i", self.data, self.at - 4)[0]

    def string(self):
        size = self.uint32()
        text = self.data[self.at:self.at + size].decode("utf-8")
        self.at += size + 1
        return text

    def signature(self):
        size = self.byte()
        text = self.data[self.at:self.at + size].decode("ascii")
        self.at += size + 1
        return text

    def value(self, sig):
        readers = {"s": self.string, "o": self.string, "g": self.signature, "y": self.byte, "u": self.uint32, "i": self.int32}
        if sig not in readers:
            raise ValueError(f"cannot read a {sig}")
        return readers[sig]()

    def string_array(self):
        end = self.uint32() + self.at
        items = []
        while self.at < end:
            items.append(self.string())
        return items

    def hints(self):
        size = self.uint32()
        self.align(8)
        end = self.at + size
        out = {}
        while self.at < end:
            self.align(8)
            key = self.string()
            out[key] = self.value(self.signature())
        return out

    def header_fields(self):
        """The header fields of a whole message, as {code: value}."""
        self.at = 12
        size = self.uint32()
        self.align(8)
        end = self.at + size
        out = {}
        while self.at < end:
            self.align(8)
            code = self.byte()
            out[code] = self.value(self.signature())
        return out


def method_call(serial, destination, path, interface, member, sig="", body=b""):
    fields = [(1, "o", path), (2, "s", interface), (3, "s", member), (6, "s", destination)]
    if sig:
        fields.append((8, "g", sig))
    head = Writer()
    head.buf += b"l"
    head.byte(1)
    head.byte(0)
    head.byte(1)
    head.uint32(len(body))
    head.uint32(serial)

    def write_fields():
        for code, field_sig, value in fields:
            head.align(8)
            head.byte(code)
            head.signature(field_sig)
            head.value(field_sig, value)
    head.array(8, write_fields)
    head.align(8)
    return bytes(head.buf) + body


def notify_body(summary, body, glyph, open_argv):
    w = Writer()
    w.string(APP_NAME)
    w.uint32(0)
    w.string("")
    w.string(summary)
    w.string(body)
    w.array(4, lambda: None)
    hints = [("urgency", "y", 1)]
    if glyph:
        hints.append(("omarchy-glyph", "s", glyph))
    if open_argv:
        hints.append(("omarchy-exec-argv", "s", json.dumps(open_argv, separators=(",", ":"))))

    def write_hints():
        for key, sig, value in hints:
            w.align(8)
            w.string(key)
            w.signature(sig)
            w.value(sig, value)
    w.array(8, write_hints)
    w.int32(-1)
    return bytes(w.buf)


def bus_address(env):
    """The socket of the session bus, or "" when there is none."""
    for address in str(env.get("DBUS_SESSION_BUS_ADDRESS", "")).split(";"):
        if not address.startswith("unix:"):
            continue
        keys = dict(part.split("=", 1) for part in address[5:].split(",") if "=" in part)
        if "path" in keys:
            return keys["path"]
        if "abstract" in keys:
            return "\0" + keys["abstract"]
    runtime = env.get("XDG_RUNTIME_DIR")
    return os.path.join(runtime, "bus") if runtime else ""


def read_exact(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("the bus closed the connection")
        data += chunk
    return data


def wait_reply(sock, serial):
    """Read messages until the reply to serial; True when it is not an error."""
    while True:
        head = read_exact(sock, 16)
        body_len, _, fields_len = struct.unpack_from("<III", head, 4)
        fields = read_exact(sock, fields_len + (-(16 + fields_len)) % 8)
        read_exact(sock, body_len)
        kind = head[1]
        if kind in (2, 3) and Reader(head + fields).header_fields().get(5) == serial:
            return kind == 2


def notify(summary, body, glyph, open_argv, env=None):
    """Show a desktop notification. False when no bus took it."""
    path = bus_address(os.environ if env is None else env)
    if not path:
        return False
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT)
            sock.connect(path)
            sock.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
            line = b""
            while not line.endswith(b"\r\n"):
                line += read_exact(sock, 1)
            if not line.startswith(b"OK"):
                return False
            sock.sendall(b"BEGIN\r\n")
            sock.sendall(method_call(1, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello"))
            if not wait_reply(sock, 1):
                return False
            sock.sendall(method_call(2, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                                     "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
                                     notify_body(summary, body, glyph, open_argv)))
            return wait_reply(sock, 2)
    except (OSError, ConnectionError, ValueError, struct.error):
        return False
