import json
import os
import unittest
from pathlib import Path

from shelf_sync import find_ob, install_service, service_unit, sync_state
from tests.vault_case import VaultCase


class SyncStateTest(VaultCase):
    def setUp(self):
        super().setUp()
        self.config = self.vault / "config-home"
        self.config.mkdir()
        self.notes = self.vault / "notes"
        self.notes.mkdir()

    def login(self):
        (self.config / "obsidian-headless").mkdir(exist_ok=True)
        (self.config / "obsidian-headless" / "auth_token").write_text("token", encoding="utf-8")

    def link(self, path):
        folder = self.config / "obsidian-headless" / "sync" / "abc123"
        folder.mkdir(parents=True)
        (folder / "config.json").write_text(json.dumps({"vaultId": "abc123", "vaultPath": str(path)}), encoding="utf-8")

    def state(self, ob="/bin/ob", active=False, env=None):
        return sync_state(self.notes, ob, self.config, lambda: active, env or {})

    def test_no_client(self):
        self.assertEqual(self.state(ob="")["state"], "no-client")

    def test_logged_out(self):
        self.assertEqual(self.state()["state"], "logged-out")

    def test_token_from_environment_counts_as_logged_in(self):
        self.assertEqual(self.state(env={"OBSIDIAN_AUTH_TOKEN": "t"})["state"], "unlinked")

    def test_empty_token_file_is_logged_out(self):
        self.login()
        (self.config / "obsidian-headless" / "auth_token").write_text("  \n", encoding="utf-8")
        self.assertEqual(self.state()["state"], "logged-out")

    def test_unlinked_when_another_vault_is_linked(self):
        self.login()
        self.link(self.vault / "other")
        self.assertEqual(self.state()["state"], "unlinked")

    def test_stopped_when_linked_and_service_inactive(self):
        self.login()
        self.link(self.notes)
        self.assertEqual(self.state()["state"], "stopped")

    def test_running_when_linked_and_service_active(self):
        self.login()
        self.link(str(self.notes) + "/")
        out = self.state(active=True)
        self.assertEqual(out["state"], "running")
        self.assertEqual(out["client"], "/bin/ob")


class FindClientTest(VaultCase):
    def test_finds_client_on_path(self):
        bin_dir = self.vault / "bin"
        bin_dir.mkdir()
        ob = bin_dir / "ob"
        ob.write_text("#!/bin/sh\n", encoding="utf-8")
        ob.chmod(0o755)
        self.assertEqual(find_ob({"PATH": str(bin_dir)}, self.vault), str(ob))

    def test_finds_client_in_bun_folder_when_path_lacks_it(self):
        ob = self.vault / ".cache" / ".bun" / "bin" / "ob"
        ob.parent.mkdir(parents=True)
        ob.write_text("#!/bin/sh\n", encoding="utf-8")
        ob.chmod(0o755)
        self.assertEqual(find_ob({"PATH": "/nonexistent"}, self.vault), str(ob))

    def test_no_client(self):
        self.assertEqual(find_ob({"PATH": "/nonexistent"}, self.vault), "")


class ServiceTest(VaultCase):
    def test_unit_runs_continuous_sync_on_the_vault(self):
        unit = service_unit("/home/u/.cache/.bun/bin/ob", Path("/home/u/My Vault"))
        self.assertIn('ExecStart=/home/u/.cache/.bun/bin/ob sync --continuous --path "/home/u/My Vault"', unit)
        self.assertIn("Restart=on-failure", unit)
        self.assertIn("WantedBy=default.target", unit)

    def test_percent_in_the_vault_path_is_escaped_for_systemd(self):
        unit = service_unit("/bin/ob", Path("/home/u/100% notes"))
        self.assertIn('--path "/home/u/100%% notes"', unit)

    def test_a_vault_path_with_a_quote_is_refused(self):
        out = install_service("/bin/ob", self.vault / 'say "hi"', self.vault / "cfg", lambda cmd: 0)
        self.assertEqual(out["error"], "invalid")

    def test_install_writes_unit_then_enables_it(self):
        calls = []
        out = install_service("/bin/ob", self.vault / "notes", self.vault / "config-home", lambda cmd: calls.append(cmd) or 0)
        unit = self.vault / "config-home" / "systemd" / "user" / "obsidian-headless.service"
        self.assertEqual(out, {"ok": True})
        self.assertIn("sync --continuous", unit.read_text(encoding="utf-8"))
        self.assertEqual(calls, [
            ["systemctl", "--user", "daemon-reload"],
            ["systemctl", "--user", "enable", "--now", "obsidian-headless.service"],
        ])

    def test_install_reports_a_failing_systemctl(self):
        out = install_service("/bin/ob", self.vault, self.vault / "config-home", lambda cmd: 1)
        self.assertEqual(out["error"], "io")


if __name__ == "__main__":
    unittest.main()
