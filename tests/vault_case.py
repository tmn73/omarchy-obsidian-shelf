import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


class VaultCase(unittest.TestCase):
    """A test case with an empty vault in a temporary folder.

    The helper keeps state under XDG_STATE_HOME, so every test points it at
    the temporary folder: a test never writes the real state of the user.
    """

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.vault = Path(self._tmp.name)
        self.state_home = os.path.join(self._tmp.name, ".state")
        self._env = mock.patch.dict("os.environ", {"XDG_STATE_HOME": self.state_home})
        self._env.start()

    def tearDown(self):
        self._env.stop()
        self._tmp.cleanup()

    def write(self, rel, text):
        path = self.vault / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def read(self, rel):
        return (self.vault / rel).read_text(encoding="utf-8")
