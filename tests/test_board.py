import json
import unittest

from shelf_board import (add_board, add_lane, clear_board, date_board, done_board, edit_board, move_board,
                         parse_board, read_board, remove_board)
from tests.vault_case import VaultCase

CFG = {"id": "todo", "type": "board", "path": "Todo.md"}

BOARD = """---

kanban-plugin: board

---

## To do

- [ ] Reply to the landlord @{2026-10-03}
- [ ] Book the dentist
\tCall before noon.


## In progress (3)

- [ ] Draft the slides @{2026-10-06} @@{14:00}


## Done

**Complete**
- [x] Pay the bill




%% kanban:settings
```
{"kanban-plugin":"board"}
```
%%
"""

TAIL = """%% kanban:settings
```
{"kanban-plugin":"board"}
```
%%
"""


class ParseTest(unittest.TestCase):
    def board(self, text=BOARD):
        return parse_board(text.split("\n"))

    def test_lanes_in_file_order_without_the_card_limit(self):
        self.assertEqual([lane["title"] for lane in self.board()["lanes"]], ["To do", "In progress", "Done"])

    def test_the_lane_with_the_complete_marker_is_complete(self):
        self.assertEqual([lane["complete"] for lane in self.board()["lanes"]], [False, False, True])

    def test_cards_carry_text_date_time_and_check(self):
        cards = [c for lane in self.board()["lanes"] for c in lane["cards"]]
        self.assertEqual([(c["text"], c["date"], c["time"], c["checked"]) for c in cards], [
            ("Reply to the landlord", "2026-10-03", "", False),
            ("Book the dentist", "", "", False),
            ("Draft the slides", "2026-10-06", "14:00", False),
            ("Pay the bill", "", "", True),
        ])

    def test_indented_lines_belong_to_the_card_above(self):
        card = self.board()["lanes"][0]["cards"][1]
        self.assertEqual(card["end"] - card["start"], 2)

    def test_the_same_text_twice_gets_a_numbered_key(self):
        board = self.board("## A\n- [ ] Same\n## B\n- [ ] Same @{2026-10-09}\n")
        self.assertEqual([c["key"] for lane in board["lanes"] for c in lane["cards"]], ["Same", "Same #2"])

    def test_the_board_stops_at_the_archive_and_at_the_settings(self):
        board = self.board("## A\n- [ ] a\n***\n\n## Archive\n- [x] old\n")
        self.assertEqual([lane["title"] for lane in board["lanes"]], ["A"])
        board = self.board("## A\n- [ ] a\n" + TAIL + "## After\n- [ ] no\n")
        self.assertEqual([lane["title"] for lane in board["lanes"]], ["A"])

    def test_triggers_come_from_the_settings_block(self):
        text = '## A\n- [ ] a !{2026-10-09} !!{08:30}\n%% kanban:settings\n```\n{"date-trigger":"!","time-trigger":"!!"}\n```\n%%\n'
        card = self.board(text)["lanes"][0]["cards"][0]
        self.assertEqual((card["text"], card["date"], card["time"]), ("a", "2026-10-09", "08:30"))

    def test_another_date_format_turns_dates_off(self):
        text = '## A\n- [ ] a @{09/10/2026}\n%% kanban:settings\n```\n{"date-format":"DD/MM/YYYY"}\n```\n%%\n'
        board = self.board(text)
        self.assertFalse(board["datesOn"])
        self.assertEqual(board["lanes"][0]["cards"][0]["date"], "09/10/2026")


class ReadTest(VaultCase):
    def test_read_gives_lanes_with_items(self):
        self.write("Todo.md", BOARD)
        out = read_board(self.vault, CFG)
        self.assertEqual(out["state"], "ok")
        self.assertTrue(out["datesOn"])
        self.assertEqual(out["lanes"][1], {"title": "In progress", "complete": False, "items": [
            {"key": "Draft the slides", "text": "Draft the slides", "date": "2026-10-06", "time": "14:00", "checked": False}]})

    def test_a_missing_file_is_missing(self):
        self.assertEqual(read_board(self.vault, CFG)["state"], "missing")


class ActionTest(VaultCase):
    def setUp(self):
        super().setUp()
        self.write("Todo.md", BOARD)

    def lane(self, title):
        board = parse_board(self.read("Todo.md").split("\n"))
        lane = next(l for l in board["lanes"] if l["title"] == title)
        return [c["key"] for c in lane["cards"]]

    def test_add_goes_after_the_last_card_of_the_lane(self):
        self.assertEqual(add_board(self.vault, CFG, "To do", "New one"), {"ok": True})
        self.assertEqual(self.lane("To do"), ["Reply to the landlord", "Book the dentist", "New one"])
        self.assertIn("\tCall before noon.\n- [ ] New one\n", self.read("Todo.md"))

    def test_add_to_an_empty_lane_goes_after_its_heading(self):
        self.write("Todo.md", "## A\n\n## B\n")
        add_board(self.vault, CFG, "A", "x")
        self.assertEqual(self.read("Todo.md"), "## A\n- [ ] x\n\n## B\n")

    def test_add_to_a_lane_that_is_gone_is_changed(self):
        self.assertEqual(add_board(self.vault, CFG, "Nope", "x")["error"], "changed")

    def test_move_takes_the_indented_lines(self):
        self.assertEqual(move_board(self.vault, CFG, "Book the dentist", "In progress"), {"ok": True})
        self.assertEqual(self.lane("In progress"), ["Draft the slides", "Book the dentist"])
        self.assertIn("- [ ] Book the dentist\n\tCall before noon.\n", self.read("Todo.md"))
        self.assertEqual(self.lane("To do"), ["Reply to the landlord"])

    def test_move_into_the_complete_lane_checks_and_out_unchecks(self):
        move_board(self.vault, CFG, "Draft the slides", "Done")
        self.assertIn("- [x] Draft the slides @{2026-10-06} @@{14:00}", self.read("Todo.md"))
        move_board(self.vault, CFG, "Pay the bill", "To do")
        self.assertIn("- [ ] Pay the bill", self.read("Todo.md"))

    def test_done_moves_to_the_complete_lane(self):
        done_board(self.vault, CFG, "Reply to the landlord")
        self.assertEqual(self.lane("Done"), ["Pay the bill", "Reply to the landlord"])

    def test_done_on_a_done_card_moves_it_back_to_the_first_lane(self):
        done_board(self.vault, CFG, "Pay the bill")
        self.assertEqual(self.lane("To do")[-1], "Pay the bill")
        self.assertIn("- [ ] Pay the bill", self.read("Todo.md"))

    def test_done_without_a_complete_lane_checks_in_place(self):
        self.write("Todo.md", "## A\n- [ ] a\n- [ ] b\n")
        done_board(self.vault, CFG, "a")
        self.assertEqual(self.read("Todo.md"), "## A\n- [x] a\n- [ ] b\n")

    def test_date_sets_replaces_and_clears(self):
        date_board(self.vault, CFG, "Book the dentist", "2026-10-07", "", "2026-10-06")
        self.assertIn("- [ ] Book the dentist @{2026-10-07}\n", self.read("Todo.md"))
        date_board(self.vault, CFG, "Book the dentist", "2026-10-08", "09:15", "2026-10-06")
        self.assertIn("- [ ] Book the dentist @{2026-10-08} @@{09:15}\n", self.read("Todo.md"))
        date_board(self.vault, CFG, "Book the dentist", "", "", "2026-10-06")
        self.assertIn("- [ ] Book the dentist\n", self.read("Todo.md"))

    def test_a_time_without_a_date_takes_today(self):
        date_board(self.vault, CFG, "Book the dentist", "", "18:00", "2026-10-06")
        self.assertIn("- [ ] Book the dentist @{2026-10-06} @@{18:00}\n", self.read("Todo.md"))

    def test_a_bad_date_is_invalid(self):
        self.assertEqual(date_board(self.vault, CFG, "Book the dentist", "tomorrow", "", "2026-10-06")["error"], "invalid")
        self.assertEqual(date_board(self.vault, CFG, "Book the dentist", "2026-10-07", "25:00", "2026-10-06")["error"], "invalid")

    def test_edit_keeps_the_box_and_the_date(self):
        edit_board(self.vault, CFG, "Reply to the landlord", "Reply to the agency")
        self.assertIn("- [ ] Reply to the agency @{2026-10-03}\n", self.read("Todo.md"))

    def test_remove_takes_the_indented_lines(self):
        remove_board(self.vault, CFG, "Book the dentist")
        self.assertNotIn("Book the dentist", self.read("Todo.md"))
        self.assertNotIn("Call before noon.", self.read("Todo.md"))

    def test_clear_removes_the_complete_cards_only(self):
        clear_board(self.vault, CFG)
        text = self.read("Todo.md")
        self.assertNotIn("Pay the bill", text)
        self.assertIn("**Complete**", text)
        self.assertIn("Reply to the landlord", text)

    def test_a_card_that_is_gone_is_changed(self):
        self.assertEqual(remove_board(self.vault, CFG, "Nope")["error"], "changed")

    def test_actions_never_touch_the_settings_block(self):
        move_board(self.vault, CFG, "Book the dentist", "Done")
        clear_board(self.vault, CFG)
        self.assertTrue(self.read("Todo.md").endswith(TAIL))



class LaneTest(VaultCase):
    def titles(self):
        return [lane["title"] for lane in parse_board(self.read("Todo.md").split("\n"))["lanes"]]

    def test_a_new_lane_goes_before_the_complete_lane(self):
        self.write("Todo.md", BOARD)
        self.assertEqual(add_lane(self.vault, CFG, "Waiting"), {"ok": True})
        self.assertEqual(self.titles(), ["To do", "In progress", "Waiting", "Done"])
        self.assertIn("\n## Waiting\n\n\n\n## Done\n", self.read("Todo.md"))
        self.assertTrue(self.read("Todo.md").endswith(TAIL))

    def test_without_a_complete_lane_it_goes_last(self):
        self.write("Todo.md", "## A\n- [ ] a\n" + TAIL)
        add_lane(self.vault, CFG, "B")
        self.assertEqual(self.read("Todo.md"), "## A\n- [ ] a\n\n## B\n\n\n\n" + TAIL)

    def test_a_name_that_exists_or_is_empty_is_invalid(self):
        self.write("Todo.md", BOARD)
        self.assertEqual(add_lane(self.vault, CFG, "to do")["error"], "invalid")
        self.assertEqual(add_lane(self.vault, CFG, "  ")["error"], "invalid")

if __name__ == "__main__":
    unittest.main()
