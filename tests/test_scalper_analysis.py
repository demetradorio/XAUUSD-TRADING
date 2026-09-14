"""Synthetic contracts for the standalone TradingView CSV analyzer.

These fixtures test CSV accounting behavior only. They do not make claims
about strategy quality, TradingView fills, or future performance.
"""

from __future__ import annotations

import csv
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from analyze_scalper_trades import analyze_csv, render_markdown


HEADERS = (
    "Trade number",
    "Type",
    "Date and time",
    "Signal",
    "Size (qty)",
    "Net PnL USD",
    "Commission USD",
    "Duration (bars)",
)


def row(number: str, kind: str, stamp: str, signal: str, qty: str, pnl: str, commission: str, duration: str) -> dict[str, str]:
    return dict(zip(HEADERS, (number, kind, stamp, signal, qty, pnl, commission, duration), strict=True))


def trade_rows(number: str, pnl: str, *, entry_time: str = "2026-06-01 09:00", exit_time: str = "2026-06-01 09:05", duration: str = "1") -> list[dict[str, str]]:
    return [
        row(number, "Entry long", entry_time, f"MAIN_L_{number}", "1", pnl, "2", duration),
        row(number, "Exit long", exit_time, f"MAIN_L_X_{number}", "1", pnl, "2", duration),
    ]


def report_for(rows: list[dict[str, str]], *, extra_cost: str = "0", top: int = 5) -> dict[str, object]:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "trades.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=HEADERS)
            writer.writeheader()
            writer.writerows(rows)
        return analyze_csv(path, extra_cost_per_contract=extra_cost, top=top)


class ScalperTradeAnalysisTests(unittest.TestCase):
    def test_exit_without_entry_is_incomplete_not_ambiguous(self) -> None:
        result = report_for([row("1", "Exit long", "2026-06-01 09:05", "MAIN_L_X_1", "1", "10", "2", "3")])
        self.assertEqual(result["reconciliation"]["excluded_incomplete_groups"], 1)
        self.assertEqual(result["reconciliation"]["excluded_ambiguous_groups"], 0)
        self.assertEqual(result["performance"]["trade_count"], 0)

    def test_nonfinite_pnl_is_reported_and_excluded(self) -> None:
        for value in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(value=value):
                result = report_for([
                    row("1", "Entry long", "2026-06-01 09:00", "MAIN_L_1", "1", value, "2", "3"),
                    row("1", "Exit long", "2026-06-01 09:05", "MAIN_L_X_1", "1", value, "2", "3"),
                ])
                self.assertEqual(result["performance"]["trade_count"], 0)
                self.assertEqual(result["data_quality"]["numeric_parse_errors"]["exit_net_pnl"], 1)
                self.assertEqual(result["data_quality"]["numeric_parse_errors"]["entry_net_pnl"], 1)

    def test_invalid_exit_pnl_cannot_fall_back_to_valid_entry(self) -> None:
        for value in ("NaN", "Infinity", "-Infinity", "not a number"):
            with self.subTest(value=value):
                rows = trade_rows("1", "10")
                rows[1]["Net PnL USD"] = value
                report = report_for(rows)
                self.assertEqual(report["reconciliation"]["closed_trade_groups"], 1)
                self.assertEqual(report["performance"]["trade_count"], 0)
                self.assertEqual(report["data_quality"]["numeric_parse_errors"]["exit_net_pnl"], 1)

    def test_missing_exit_pnl_can_use_valid_entry(self) -> None:
        for value in ("", "-", "na"):
            with self.subTest(value=value):
                rows = trade_rows("1", "10")
                rows[1]["Net PnL USD"] = value
                report = report_for(rows)
                self.assertEqual(report["performance"]["trade_count"], 1)
                self.assertEqual(report["performance"]["net_pnl_usd"], "10")

    def test_valid_exit_values_remain_authoritative_over_bad_entry_metadata(self) -> None:
        rows = trade_rows("1", "10", duration="3")
        for field in ("Net PnL USD", "Commission USD", "Duration (bars)"):
            rows[0][field] = "invalid"
        report = report_for(rows)
        self.assertEqual(report["performance"]["trade_count"], 1)
        self.assertEqual(report["performance"]["net_pnl_usd"], "10")
        self.assertEqual(report["performance"]["reported_commission_usd"], "2")
        self.assertEqual(report["duration"]["median_bars"], "3")
        self.assertEqual(report["duration"]["trades_with_invalid_reported_duration"], 0)

    def test_invalid_exit_commission_or_duration_is_not_hidden_by_entry(self) -> None:
        rows = trade_rows("1", "10", duration="3")
        rows[1]["Commission USD"] = "invalid"
        rows[1]["Duration (bars)"] = "invalid"
        report = report_for(rows)
        self.assertEqual(report["performance"]["trades_missing_reported_commission"], 1)
        self.assertEqual(report["duration"]["trades_with_invalid_reported_duration"], 1)
        self.assertEqual(report["duration"]["trades_with_reported_duration"], 0)
        self.assertEqual(report["duration"]["trades_missing_reported_duration"], 0)
        self.assertIsNone(report["duration"]["median_bars"])

    def test_negative_duration_is_excluded_not_bucketed_as_one_to_five(self) -> None:
        report = report_for(trade_rows("1", "10", duration="-2") + trade_rows("2", "5", duration="3"))
        duration = report["duration"]
        self.assertEqual(duration["trades_with_reported_duration"], 1)
        self.assertEqual(duration["trades_with_invalid_reported_duration"], 1)
        self.assertEqual(duration["trades_missing_reported_duration"], 0)
        self.assertEqual(duration["median_bars"], "3")
        self.assertEqual(duration["total_bars"], "3")
        self.assertEqual(duration["distribution"]["1-5"], 1)
        self.assertEqual(report["data_quality"]["field_conflicts"]["negative_duration"], 1)

    def test_deduplicates_pair_rows_and_excludes_open_marked_groups(self) -> None:
        entry_one = row("1", "Entry long", "2026-06-01 09:00", "MAIN_L_1", "1", "10", "2", "3")
        exit_one = row("1", "Exit long", "2026-06-01 09:05", "MAIN_L_X_1", "1", "10", "2", "3")
        rows = [
            entry_one,
            exit_one,
            entry_one.copy(),
            exit_one.copy(),
            row("2", "Entry short", "2026-06-01 10:00", "BOS_S_2", "1", "99", "1", "2"),
            row("2", "Exit short", "2026-06-01 10:05", "Open position (unrealized)", "1", "99", "1", "2"),
            row("3", "Entry long", "2026-06-01 11:00", "OB_L_3", "1", "-5", "1", "1"),
            row("3", "Exit long", "2026-06-01 11:05", "Margin Call", "1", "-5", "1", "1"),
            row("4", "Entry long", "2026-06-01 12:00", "RE_L_4", "1", "7", "1", "1"),
        ]
        report = report_for(rows)
        reconciliation = report["reconciliation"]
        performance = report["performance"]
        duration = report["duration"]

        self.assertEqual(reconciliation["closed_trade_groups"], 2)
        self.assertEqual(reconciliation["closed_margin_call_groups"], 1)
        self.assertEqual(reconciliation["excluded_open_marked_groups"], 1)
        self.assertEqual(reconciliation["excluded_incomplete_groups"], 1)
        self.assertEqual(reconciliation["duplicate_rows_ignored"], 2)
        self.assertTrue(reconciliation["groups_reconcile_exactly"])
        self.assertTrue(reconciliation["rows_reconcile_exactly"])
        self.assertEqual(performance["net_pnl_usd"], "5")
        self.assertEqual(performance["reported_commission_usd"], "3")
        self.assertEqual(performance["gross_pnl_before_reported_commission_usd"], "8")
        self.assertEqual(performance["profit_factor"], "2")
        self.assertEqual(duration["trades_with_reported_duration"], 2)
        self.assertEqual(duration["median_bars"], "2")

    def test_no_wins_or_losses_has_safe_undefined_ratios(self) -> None:
        rows = [
            row("1", "Entry long", "2026-06-01 09:00", "MAIN_L_1", "1", "0", "0", "1"),
            row("1", "Exit long", "2026-06-01 09:05", "MAIN_L_X_1", "1", "0", "0", "1"),
        ]
        performance = report_for(rows)["performance"]

        self.assertEqual(performance["winning_trades"], 0)
        self.assertEqual(performance["losing_trades"], 0)
        self.assertEqual(performance["breakeven_trades"], 1)
        self.assertIsNone(performance["average_win_usd"])
        self.assertIsNone(performance["average_loss_usd"])
        self.assertIsNone(performance["profit_factor"])
        self.assertIsNone(performance["payoff_ratio"])

    def test_closed_equity_drawdown_groups_same_exit_timestamp(self) -> None:
        rows = [
            row("1", "Entry long", "2026-06-01 09:00", "MAIN_L_1", "1", "10", "0", "1"),
            row("1", "Exit long", "2026-06-01 10:00", "MAIN_L_X_1", "1", "10", "0", "1"),
            row("2", "Entry long", "2026-06-01 09:10", "BOS_L_2", "1", "20", "0", "1"),
            row("2", "Exit long", "2026-06-01 11:00", "BOS_L_X_2", "1", "20", "0", "1"),
            row("3", "Entry short", "2026-06-01 09:20", "OB_S_3", "1", "-30", "0", "1"),
            row("3", "Exit short", "2026-06-01 11:00", "OB_S_X_3", "1", "-30", "0", "1"),
        ]
        report = report_for(rows)
        equity = report["closed_equity"]
        overlap = report["overlap_dependence"]

        self.assertEqual(equity["same_exit_timestamp_groups"], 1)
        self.assertEqual(equity["max_closed_equity_drawdown_usd"], "10")
        self.assertEqual(equity["max_consecutive_losses"], 1)
        self.assertEqual(overlap["max_simultaneous_positions"], 3)
        self.assertEqual(overlap["overlapping_trade_pairs"], 3)

    def test_unusable_exit_timestamp_does_not_invent_chronology(self) -> None:
        for invalid_time in ("not a timestamp", ""):
            with self.subTest(timestamp=invalid_time):
                rows = (
                    trade_rows("1", "-10", exit_time=invalid_time)
                    + trade_rows("2", "20", exit_time="2026-06-01 10:00")
                    + trade_rows("3", "-10", exit_time="2026-06-01 10:10")
                )
                report = report_for(rows)
                equity = report["closed_equity"]
                self.assertEqual(equity["chronology_status"], "unavailable_missing_exit_timestamp")
                self.assertIsNone(equity["max_closed_equity_drawdown_usd"])
                self.assertIsNone(equity["closed_equity_peak_usd"])
                self.assertIsNone(equity["max_consecutive_losses"])
                self.assertEqual(equity["closed_equity_end_usd"], "0")
                self.assertIsNone(report["overlap_dependence"]["max_simultaneous_positions"])
                self.assertIn("Max chronological loss streak: —", render_markdown(report))

    def test_consistent_timezone_less_timestamps_are_sorted_not_csv_ordered(self) -> None:
        rows = (
            trade_rows("1", "-10", exit_time="2026-06-01 09:10")
            + trade_rows("3", "-10", exit_time="2026-06-01 09:30")
            + trade_rows("2", "20", exit_time="2026-06-01 09:20")
        )
        equity = report_for(rows)["closed_equity"]
        self.assertEqual(equity["chronology_status"], "available")
        self.assertEqual(equity["max_closed_equity_drawdown_usd"], "10")
        self.assertEqual(equity["max_consecutive_losses"], 1)

    def test_mixed_timezone_awareness_makes_chronology_unavailable(self) -> None:
        rows = trade_rows("1", "10") + trade_rows(
            "2", "-5", entry_time="2026-06-01T09:00-05:00", exit_time="2026-06-01T09:05-05:00",
        )
        report = report_for(rows)
        self.assertEqual(report["data_quality"]["timestamp_timezone_status"], "mixed")
        for key in ("closed_equity", "overlap_dependence"):
            self.assertEqual(report[key]["chronology_status"], "unavailable_mixed_timezone_awareness")
        self.assertIsNone(report["closed_equity"]["max_closed_equity_drawdown_usd"])
        self.assertIsNone(report["overlap_dependence"]["overlapping_trade_pairs"])

    def test_mixed_timezone_within_one_interval_is_not_compared(self) -> None:
        report = report_for(trade_rows("1", "10", exit_time="2026-06-01T09:05-05:00"))
        self.assertEqual(report["closed_equity"]["chronology_status"], "available")
        self.assertEqual(report["overlap_dependence"]["chronology_status"], "unavailable_mixed_timezone_awareness")
        self.assertIsNone(report["overlap_dependence"]["max_simultaneous_positions"])

    def test_explicit_offsets_keep_local_month_and_group_equal_instants(self) -> None:
        rows = trade_rows(
            "1", "10", entry_time="2026-06-30T23:00-05:00", exit_time="2026-06-30T23:30-05:00",
        ) + trade_rows(
            "2", "-20", entry_time="2026-07-01T04:00Z", exit_time="2026-07-01T04:30Z",
        )
        report = report_for(rows)
        months = report["breakdowns"]["by_month"]
        self.assertEqual(months["2026-06"]["net_pnl_usd"], "10")
        self.assertEqual(months["2026-07"]["net_pnl_usd"], "-20")
        self.assertEqual(report["closed_equity"]["chronology_status"], "available")
        self.assertEqual(report["closed_equity"]["same_exit_timestamp_groups"], 1)
        self.assertEqual(report["closed_equity"]["max_closed_equity_drawdown_usd"], "10")
        self.assertEqual(report["overlap_dependence"]["max_simultaneous_positions"], 2)

    def test_reversed_timestamp_interval_makes_overlap_unavailable(self) -> None:
        report = report_for(trade_rows("1", "10", exit_time="2026-06-01 08:55"))
        overlap = report["overlap_dependence"]
        self.assertTrue(overlap["chronology_status"].startswith("unavailable_"))
        self.assertEqual(overlap["negative_timestamp_intervals"], 1)
        self.assertIsNone(overlap["max_simultaneous_positions"])

    def test_entry_signal_is_path_attribution_and_mismatches_are_audited(self) -> None:
        rows = [
            row("1", "Entry long", "2026-06-01 09:00", "BOS_L_101", "1", "4", "0", "2"),
            row("1", "Exit long", "2026-06-01 09:10", "RE_L_X_202", "1", "4", "0", "2"),
        ]
        report = report_for(rows)
        attribution = report["data_quality"]["signal_attribution"]
        paths = report["breakdowns"]["by_path"]

        self.assertEqual(paths["BOS"]["trade_count"], 1)
        self.assertEqual(paths["RE"]["trade_count"], 0)
        self.assertEqual(attribution["ticket_id_mismatch"], 1)
        self.assertEqual(attribution["path_mismatch"], 1)

    def test_extra_cost_is_additional_to_already_net_pnl(self) -> None:
        rows = [
            row("1", "Entry long", "2026-06-01 09:00", "MAIN_L_1", "2", "2", "4", "1"),
            row("1", "Exit long", "2026-06-01 09:10", "MAIN_L_X_1", "2", "2", "4", "1"),
            row("2", "Entry short", "2026-06-01 10:00", "BOS_S_2", "3", "6", "4", "1"),
            row("2", "Exit short", "2026-06-01 10:10", "BOS_S_X_2", "3", "6", "4", "1"),
        ]
        report = report_for(rows, extra_cost="1.5")
        performance = report["performance"]
        sensitivity = report["extra_cost_sensitivity"]
        quantity = report["data_quality"]["quantity_anomalies"]

        self.assertEqual(performance["net_pnl_usd"], "8")
        self.assertEqual(performance["reported_commission_usd"], "8")
        self.assertEqual(sensitivity["known_additional_cost_usd"], "7.5")
        self.assertEqual(sensitivity["net_pnl_after_extra_cost_usd"], "0.5")
        self.assertEqual(sensitivity["trades_flipped_to_loss_after_extra_cost"], 1)
        self.assertEqual(quantity.get("entry_exit_quantity_mismatch", 0), 0)

    def test_quantity_mismatch_makes_cost_coverage_incomplete(self) -> None:
        rows = trade_rows("1", "2") + trade_rows("2", "6")
        rows[0]["Size (qty)"] = "2"
        rows[1]["Size (qty)"] = "3"
        rows[2]["Size (qty)"] = rows[3]["Size (qty)"] = "3"
        report = report_for(rows, extra_cost="1.5")
        extra = report["extra_cost_sensitivity"]
        self.assertEqual(report["performance"]["net_pnl_usd"], "8")
        self.assertEqual(extra["coverage_status"], "incomplete_quantity_coverage")
        self.assertEqual(extra["trades_with_cost_quantity"], 1)
        self.assertEqual(extra["trades_without_cost_quantity"], 1)
        self.assertEqual(extra["known_additional_cost_usd"], "4.5")
        self.assertIsNone(extra["net_pnl_after_extra_cost_usd"])
        self.assertIsNone(extra["profit_factor_after_extra_cost"])
        self.assertEqual(report["data_quality"]["quantity_anomalies"]["entry_exit_quantity_mismatch"], 1)

    def test_invalid_quantity_counterpart_cannot_make_cost_coverage_complete(self) -> None:
        for value in ("0", "-1", "invalid"):
            with self.subTest(quantity=value):
                rows = trade_rows("1", "10")
                rows[1]["Size (qty)"] = value
                extra = report_for(rows, extra_cost="1")["extra_cost_sensitivity"]
                self.assertEqual(extra["coverage_status"], "incomplete_quantity_coverage")
                self.assertIsNone(extra["net_pnl_after_extra_cost_usd"])

    def test_genuinely_missing_quantity_can_use_the_other_reported_side(self) -> None:
        for missing_row in (0, 1):
            with self.subTest(missing_row=missing_row):
                rows = trade_rows("1", "10")
                rows[missing_row]["Size (qty)"] = ""
                extra = report_for(rows, extra_cost="1")["extra_cost_sensitivity"]
                self.assertEqual(extra["coverage_status"], "complete")
                self.assertEqual(extra["known_additional_cost_usd"], "1")
                self.assertEqual(extra["net_pnl_after_extra_cost_usd"], "9")

    def test_top_outcomes_are_sign_filtered_and_rendered_in_markdown(self) -> None:
        rows = [part for number, pnl in enumerate(("7", "-4", "2", "0", "-1"), start=1) for part in trade_rows(str(number), pnl)]
        report = report_for(rows)
        self.assertEqual(report["performance"]["largest_winners_usd"], ["7", "2"])
        self.assertEqual(report["performance"]["largest_losers_usd"], ["-4", "-1"])
        limited = report_for(rows, top=1)
        self.assertEqual(limited["performance"]["largest_winners_usd"], ["7"])
        self.assertEqual(limited["performance"]["largest_losers_usd"], ["-4"])
        markdown = render_markdown(limited)
        self.assertIn("- Largest winners (up to 1): $7.00.", markdown)
        self.assertIn("- Largest losers (up to 1): -$4.00.", markdown)

    def test_top_outcomes_do_not_fill_empty_sign_groups(self) -> None:
        for pnl, empty_group in (("5", "largest_losers_usd"), ("-5", "largest_winners_usd"), ("0", "largest_winners_usd")):
            with self.subTest(pnl=pnl):
                report = report_for(trade_rows("1", pnl))
                self.assertEqual(report["performance"][empty_group], [])
                self.assertIn("(up to 5): —.", render_markdown(report))


if __name__ == "__main__":
    unittest.main()
