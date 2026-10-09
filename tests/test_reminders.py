import io
import json
import threading
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

from shelf_cli import main
from shelf_reminders import due, run
from tests.vault_case import VaultCase

BOARD = {"id": "todo", "name": "Todo", "type": "board", "path": "Todo.md"}


def card(text, date="", time="", key=None):
    return {"key": key or text, "text": text, "date": date, "time": time, "checked": False}


def board(*cards, done=(), dates_on=True):
    return {"id": "todo", "state": "ok", "datesOn": dates_on, "lanes": [
        {"title": "To do", "complete": False, "items": list(cards)},
        {"title": "Done", "complete": True, "items": list(done)}]}


def at(clock, day="2026-10-06"):
    return datetime.fromisoformat(f"{day}T{clock}")


class TimedCardTest(unittest.TestCase):
    def test_rings_once_at_its_time(self):
        payload = [board(card("Slides", "2026-10-06", "14:00"))]
        messages, state = due(payload, [BOARD], {}, at("13:59"), "09:00")
        self.assertEqual([m for m in messages if m["kind"] == "card"], [])
        messages, state = due(payload, [BOARD], state, at("14:00"), "09:00")
        self.assertEqual([m["cards"] for m in messages if m["kind"] == "card"], [["Slides"]])
        self.assertEqual(messages[-1]["headline"], "Card due at 14:00")
        self.assertEqual(messages[-1]["body"], "Todo · open the shelf to see the card")
        messages, state = due(payload, [BOARD], state, at("14:01"), "09:00")
        self.assertEqual([m for m in messages if m["kind"] == "card"], [])

    def test_a_missed_time_rings_later_the_same_day(self):
        payload = [board(card("Slides", "2026-10-06", "14:00"))]
        messages, _ = due(payload, [BOARD], {"summary": "2026-10-06"}, at("16:30"), "09:00")
        self.assertEqual([m["cards"] for m in messages], [["Slides"]])

    def test_never_rings_on_a_later_day(self):
        payload = [board(card("Slides", "2026-10-05", "14:00"))]
        messages, _ = due(payload, [BOARD], {"summary": "2026-10-06"}, at("16:30"), "09:00")
        self.assertEqual(messages, [])

    def test_done_cards_and_quiet_lists_never_ring(self):
        payload = [board(done=[card("Slides", "2026-10-06", "14:00")])]
        self.assertEqual(due(payload, [BOARD], {"summary": "2026-10-06"}, at("15:00"), "09:00")[0], [])
        quiet = dict(BOARD, remind=False)
        payload = [board(card("Slides", "2026-10-06", "14:00"))]
        self.assertEqual(due(payload, [quiet], {}, at("15:00"), "09:00")[0], [])

    def test_a_board_with_another_date_format_never_rings(self):
        payload = [board(card("Slides", "06/10/2026", "14:00"), dates_on=False)]
        self.assertEqual(due(payload, [BOARD], {}, at("15:00"), "09:00")[0], [])


class SummaryTest(unittest.TestCase):
    def test_once_a_day_after_the_summary_time(self):
        payload = [board(card("Dentist", "2026-10-06"), card("Landlord", "2026-10-03"), card("Later", "2026-10-09"))]
        messages, state = due(payload, [BOARD], {}, at("08:59"), "09:00")
        self.assertEqual(messages, [])
        messages, state = due(payload, [BOARD], state, at("09:00"), "09:00")
        self.assertEqual(len(messages), 1)
        self.assertEqual(messages[0]["kind"], "summary")
        self.assertEqual(messages[0]["headline"], "1 card for today, 1 late")
        self.assertEqual(messages[0]["cards"], ["Dentist", "Landlord"])
        self.assertEqual(messages[0]["body"], "Open the shelf to see the cards")
        self.assertEqual(due(payload, [BOARD], state, at("12:00"), "09:00")[0], [])

    def test_late_timed_cards_are_in_the_summary_and_today_timed_cards_are_not(self):
        payload = [board(card("Old", "2026-10-04", "10:00"), card("Now", "2026-10-06", "18:00"))]
        messages, _ = due(payload, [BOARD], {}, at("09:30"), "09:00")
        self.assertEqual(messages[0]["headline"], "1 card is late")
        self.assertEqual(messages[0]["cards"], ["Old"])

    def test_a_day_with_nothing_due_sends_nothing_and_is_done(self):
        payload = [board(card("Later", "2026-10-09"))]
        messages, state = due(payload, [BOARD], {}, at("09:30"), "09:00")
        self.assertEqual(messages, [])
        self.assertEqual(state["summary"], "2026-10-06")


class NoVaultTextTest(unittest.TestCase):
    def test_no_card_or_lane_text_reaches_a_notification(self):
        payload = [board(card("Call the bank", "2026-10-06", "14:00"), card("Pay rent", "2026-10-06"),
                         card("Renew passport", "2026-10-01"))]
        messages, _ = due(payload, [BOARD], {}, at("14:00"), "09:00")
        self.assertEqual(sorted(m["kind"] for m in messages), ["card", "summary"])
        for m in messages:
            for secret in ("Call the bank", "Pay rent", "Renew passport", "To do"):
                self.assertNotIn(secret, m["headline"] + m["body"])


class SendTest(unittest.TestCase):
    MESSAGE = {"kind": "card", "cards": ["Reply to the landlord"],
               "headline": "Card due at 14:00", "body": "Tasks · open the shelf to see the card"}

    def test_goes_over_the_bus_with_a_click_that_opens_the_shelf(self):
        import shelf_cli
        with mock.patch("shelf_notify.notify", return_value=True) as sent:
            shelf_cli.send_notification(self.MESSAGE)
        args = sent.call_args[0]
        self.assertEqual(args[:2], ("Card due at 14:00", "Tasks · open the shelf to see the card"))
        self.assertEqual(args[3], ["omarchy-shell", "tmn73.obsidian", "open"])

    def test_never_puts_the_text_in_a_process(self):
        import shelf_cli
        with mock.patch("subprocess.run", side_effect=AssertionError("a process got the text")), \
             mock.patch("subprocess.Popen", side_effect=AssertionError("a process got the text")), \
             mock.patch("shelf_notify.bus_address", return_value=""):
            shelf_cli.send_notification(self.MESSAGE)


class RunTest(VaultCase):
    def test_two_bars_at_once_send_one_notification(self):
        path = self.vault / "state" / "reminders.json"
        payload = [board(card("Slides", "2026-10-06", "14:00"))]
        sent = []
        def compute(state):
            return due(payload, [BOARD], dict(state, summary="2026-10-06"), at("14:05"), "09:00")
        threads = [threading.Thread(target=run, args=(path, compute, sent.append)) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual([m["cards"] for m in sent], [["Slides"]])

    def test_cli_remind_reads_the_boards(self):
        self.write("Todo.md", "## To do\n- [ ] Slides @{2026-10-06} @@{14:00}\n")
        sent = []
        with mock.patch("shelf_cli.reminder_clock", return_value=at("14:05")), \
             mock.patch("shelf_cli.send_notification", side_effect=sent.append):
            code, out = main(["remind", "--vault", str(self.vault), "--lists", json.dumps([BOARD])], io.StringIO(""))
        self.assertEqual((code, out["ok"]), (0, True))
        self.assertEqual([(m["kind"], m["headline"]) for m in sent], [("card", "Card due at 14:00")])
        self.assertTrue((Path(self.state_home) / "obsidian-shelf" / "reminders.json").exists())


if __name__ == "__main__":
    unittest.main()
