import os
import socket
import struct
import threading
import unittest
from unittest import mock

from shelf_notify import Reader, bus_address, notify
from tests.vault_case import VaultCase


class FakeBus:
    """A session bus that accepts one client, answers Hello and Notify, and
    keeps the body of each Notify call."""

    def __init__(self, path):
        self.path = path
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        self.server.listen(1)
        self.notify_bodies = []
        self.auth = b""
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def read_line(self, conn):
        line = b""
        while not line.endswith(b"\r\n"):
            line += conn.recv(1)
        return line

    def read_message(self, conn):
        head = self.read_exact(conn, 16)
        body_len, serial, fields_len = struct.unpack_from("<III", head, 4)
        fields = self.read_exact(conn, fields_len + (-(16 + fields_len)) % 8)
        body = self.read_exact(conn, body_len)
        member = Reader(head + fields).header_fields().get(3, "")
        return serial, member, body

    def read_exact(self, conn, size):
        data = b""
        while len(data) < size:
            chunk = conn.recv(size - len(data))
            if not chunk:
                raise EOFError
            data += chunk
        return data

    def reply(self, conn, serial, sig, body):
        fields = bytearray()
        # REPLY_SERIAL (5, u) and SIGNATURE (8, g), each struct aligned to 8.
        fields += struct.pack("<BBcB", 5, 1, b"u", 0) + struct.pack("<I", serial)
        fields += struct.pack("<BB", 8, 1) + b"g\0" + struct.pack("<B", len(sig)) + sig.encode() + b"\0"
        head = struct.pack("<cBBBIII", b"l", 2, 0, 1, len(body), 99, len(fields))
        message = head + bytes(fields)
        message += b"\0" * ((-len(message)) % 8)
        conn.sendall(message + body)

    def serve(self):
        conn, _ = self.server.accept()
        with conn:
            conn.recv(1)
            self.auth = self.read_line(conn)
            conn.sendall(b"OK 0123456789abcdef\r\n")
            self.read_line(conn)
            try:
                while True:
                    serial, member, body = self.read_message(conn)
                    if member == "Hello":
                        self.reply(conn, serial, "s", struct.pack("<I", 4) + b":1.9\0")
                    elif member == "Notify":
                        self.notify_bodies.append(body)
                        self.reply(conn, serial, "u", struct.pack("<I", 7))
            except (EOFError, OSError):
                pass

    def close(self):
        self.server.close()


class NotifyTest(VaultCase):
    def setUp(self):
        super().setUp()
        self.socket_path = os.path.join(self.state_home, "bus")
        os.makedirs(self.state_home, exist_ok=True)
        self.bus = FakeBus(self.socket_path)
        self.env = {"DBUS_SESSION_BUS_ADDRESS": "unix:path=" + self.socket_path}

    def tearDown(self):
        self.bus.close()
        super().tearDown()

    def test_sends_the_text_over_the_bus_with_the_omarchy_hints(self):
        sent = notify("Reply to the landlord", "Tasks · To do · today 14:00", "\U000f00ed", ["omarchy-shell", "tmn73.obsidian", "open"], self.env)
        self.assertTrue(sent)
        self.bus.thread.join(2)
        self.assertEqual(len(self.bus.notify_bodies), 1)
        body = Reader(self.bus.notify_bodies[0])
        app, replaces, icon, summary, text = body.string(), body.uint32(), body.string(), body.string(), body.string()
        actions, hints, timeout = body.string_array(), body.hints(), body.int32()
        self.assertEqual((app, replaces, icon, summary, text), ("Obsidian Shelf", 0, "", "Reply to the landlord", "Tasks · To do · today 14:00"))
        self.assertEqual(actions, [])
        self.assertEqual(hints["urgency"], 1)
        self.assertEqual(hints["omarchy-glyph"], "\U000f00ed")
        self.assertEqual(hints["omarchy-exec-argv"], '["omarchy-shell","tmn73.obsidian","open"]')
        self.assertEqual(timeout, -1)

    def test_authenticates_as_the_current_user(self):
        notify("a", "b", "", [], self.env)
        self.bus.thread.join(2)
        self.assertEqual(self.bus.auth, b"AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")

    def test_never_starts_a_process(self):
        with mock.patch("subprocess.run", side_effect=AssertionError("a process got the text")), \
             mock.patch("subprocess.Popen", side_effect=AssertionError("a process got the text")):
            self.assertTrue(notify("secret task", "secret body", "", [], self.env))

    def test_no_bus_sends_nothing_and_says_so(self):
        env = {"DBUS_SESSION_BUS_ADDRESS": "unix:path=" + os.path.join(self.state_home, "nothing-here")}
        self.assertFalse(notify("a", "b", "", [], env))


class AddressTest(unittest.TestCase):
    def test_reads_a_path_and_an_abstract_address(self):
        self.assertEqual(bus_address({"DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus"}), "/run/user/1000/bus")
        self.assertEqual(bus_address({"DBUS_SESSION_BUS_ADDRESS": "unix:abstract=/tmp/dbus-x,guid=ab"}), "\0/tmp/dbus-x")

    def test_falls_back_to_the_runtime_dir(self):
        self.assertEqual(bus_address({"XDG_RUNTIME_DIR": "/run/user/1000"}), "/run/user/1000/bus")
        self.assertEqual(bus_address({}), "")


if __name__ == "__main__":
    unittest.main()
