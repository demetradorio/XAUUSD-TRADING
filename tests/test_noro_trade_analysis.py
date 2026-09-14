"""Deterministic unit tests for the dependency-free TradingView trade CSV analyzer."""

from __future__ import annotations

import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.analyze_noro_trades import TradeCsvError, analyze_csv


HEADERS = [
    "Trade number",
    "Type",
    "Date and time",
    "Net PnL USD",
    "Commission USD",
    "Favorable excursion USD",
    "Adverse excursion USD",
    "Duration (bars)",
]


def row(
    trade_number: int,
    type_: str,
    at: str,
    pnl: str,
    commission: str = "0",
    mfe: str = "0",
    mae: str = "0",
    bars: str = "0",
) -> dict[str, str]:
    return {
        "Trade number": str(trade_number),
        "Type": type_,
        "Date and time": at,
        "Net PnL USD": pnl,
        "Commission USD": commission,
        "Favorable excursion USD": mfe,
        "Adverse excursion USD": mae,
        "Duration (bars)": bars,
    }


BASE_ROWS = [
    # TradingView commonly writes the exit row first; pairing must not depend on row order.
    row(1, "Exit long", "2026-01-31 09:05", "100", mfe="140", mae="-25", bars="5"),
    row(1, "Entry long", "2026-01-31 09:00", "100", mfe="140", mae="-25", bars="5"),
    row(2, "Entry short", "2026-02-01 09:00", "-50", mfe="60", mae="-80", bars="2"),
    row(2, "Exit short", "2026-02-01 09:10", "-50", mfe="60", mae="-80", bars="2"),
    # Current/open PnL is deliberately excluded from all realized measures.
    row(3, "Exit long", "Open", "-13.72", mfe="9.14", mae="-48.01"),
    row(3, "Entry long", "2026-02-02 09:00", "-13.72", mfe="9.14", mae="-48.01"),
]


class NoroTradeAnalysisTests(unittest.TestCase):
    def write_csv(self, rows: list[dict[str, str]], headers: list[str] = HEADERS) -> Path:
        temporary = tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="", suffix=".csv", delete=False)
        self.addCleanup(lambda: Path(temporary.name).unlink(missing_ok=True))
        with temporary:
            writer = csv.DictWriter(temporary, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)
        return Path(temporary.name)

    def test_pairs_exit_rows_once_and_excludes_open_trade(self) -> None:
        report = analyze_csv(self.write_csv(BASE_ROWS), starting_equity="1000")

        self.assertTrue(report["ok"])
        self.assertEqual(report["analysis_basis"]["closed_trade_count"], 2)
        self.assertEqual(report["analysis_basis"]["open_trade_count_excluded"], 1)
        self.assertEqual(report["performance"]["net_pnl"], 50.0)
        self.assertEqual(report["performance"]["return_on_starting_equity_percent"], 5.0)
        self.assertEqual(report["performance"]["wins"], 1)
        self.assertEqual(report["performance"]["losses"], 1)
        self.assertEqual(report["performance"]["average_win"], 100.0)
        self.assertEqual(report["performance"]["average_loss"], -50.0)
        self.assertEqual(report["performance"]["payoff_ratio"], 2.0)
        self.assertEqual(report["performance"]["profit_factor"], 2.0)
        self.assertEqual(report["performance"]["mean_expectancy_per_closed_trade"], 25.0)

        closed_drawdown = report["risk"]["max_closed_equity_drawdown"]
        self.assertEqual(closed_drawdown["amount"], 50.0)
        self.assertAlmostEqual(closed_drawdown["percent_of_closed_equity_peak"], 50 / 1100 * 100)
        self.assertFalse(report["risk"]["tradingview_intratrade_drawdown"]["available_from_this_csv"])
        self.assertEqual(report["risk"]["max_losing_streak"]["trades"], 1)

        self.assertEqual(report["long_short"]["long"]["net_pnl"], 100.0)
        self.assertEqual(report["long_short"]["short"]["net_pnl"], -50.0)
        self.assertEqual(report["duration_bars"]["mean"], 3.5)
        self.assertTrue(report["commissions"]["all_closed_trades_zero"])
        self.assertEqual(
            report["cost_headroom"]["additional_cost_per_closed_trade_until_aggregate_breakeven"], 25.0
        )
        self.assertEqual(report["losing_trade_mfe"]["favorable_excursion"]["mean"], 60.0)
        self.assertEqual(report["losing_trade_mfe"]["percent_of_losing_trades"], 100.0)

        months = report["monthly_realized_pnl_by_exit_month"]
        self.assertEqual([month["month"] for month in months], ["2026-01", "2026-02"])
        self.assertEqual([month["realized_pnl"] for month in months], [100.0, -50.0])
        self.assertEqual([month["coverage"] for month in months], ["incomplete_or_unknown"] * 2)
        self.assertEqual(months[1]["return_on_month_start_closed_equity_percent"], -50 / 1100 * 100)

    def test_zero_or_winning_trade_ends_a_losing_streak(self) -> None:
        rows: list[dict[str, str]] = []
        for number, pnl in enumerate(("-10", "0", "-20", "-30", "5"), start=1):
            rows.extend(
                [
                    row(number, "Entry long", f"2026-03-01 0{number}:00", pnl, bars="1"),
                    row(number, "Exit long", f"2026-03-01 0{number}:05", pnl, bars="1"),
                ]
            )
        report = analyze_csv(self.write_csv(rows), starting_equity="1000")
        streak = report["risk"]["max_losing_streak"]
        self.assertEqual(streak["trades"], 2)
        self.assertEqual(streak["ending_trade_number"], "4")

    def test_duplicate_closed_exit_is_rejected(self) -> None:
        rows = BASE_ROWS[:4] + [row(1, "Exit long", "2026-01-31 09:06", "100")]
        with self.assertRaisesRegex(TradeCsvError, "duplicate closed exit rows for trade 1"):
            analyze_csv(self.write_csv(rows))

    def test_duplicate_entry_is_rejected(self) -> None:
        rows = BASE_ROWS[:4] + [row(1, "Entry long", "2026-01-31 08:59", "100")]
        with self.assertRaisesRegex(TradeCsvError, "duplicate entry rows for trade 1"):
            analyze_csv(self.write_csv(rows))

    def test_unmatched_exit_is_rejected(self) -> None:
        rows = [item for item in BASE_ROWS[:4] if not (item["Trade number"] == "2" and item["Type"] == "Entry short")]
        with self.assertRaisesRegex(TradeCsvError, "unmatched exit row for trade 2"):
            analyze_csv(self.write_csv(rows))

    def test_unmatched_entry_is_rejected(self) -> None:
        rows = [item for item in BASE_ROWS[:4] if not (item["Trade number"] == "2" and item["Type"] == "Exit short")]
        with self.assertRaisesRegex(TradeCsvError, "unmatched entry row for trade 2"):
            analyze_csv(self.write_csv(rows))

    def test_open_pair_with_mismatched_side_is_rejected(self) -> None:
        rows = [row(1, "Entry long", "2026-01-31 09:00", "-10"), row(1, "Exit short", "Open", "-10")]
        with self.assertRaisesRegex(TradeCsvError, "Entry long but Open exit short"):
            analyze_csv(self.write_csv(rows))

    def test_non_usd_header_label_is_an_explicit_warning(self) -> None:
        headers = ["Net PnL EUR" if value == "Net PnL USD" else value for value in HEADERS]
        rows = []
        for source in BASE_ROWS:
            item = dict(source)
            item["Net PnL EUR"] = item.pop("Net PnL USD")
            rows.append(item)
        report = analyze_csv(self.write_csv(rows, headers), starting_equity="1000")
        warnings = report["validation"]["warnings"]
        self.assertEqual(len(warnings), 1)
        self.assertIn("EUR", warnings[0])
        self.assertIn("USD", report["source"]["currency_labels_in_monetary_headers"])
        self.assertIn("EUR", report["source"]["currency_labels_in_monetary_headers"])

    def test_cumulative_pnl_reconciliation_uses_exit_rows_for_metrics(self) -> None:
        headers = HEADERS + ["Cumulative PnL USD"]
        rows = []
        for source, cumulative in zip(BASE_ROWS, ("100", "100", "50", "50", "36.28", "36.28")):
            item = dict(source)
            item["Cumulative PnL USD"] = cumulative
            rows.append(item)

        report = analyze_csv(self.write_csv(rows, headers), starting_equity="1000")
        reconciliation = report["pnl_reconciliation"]
        self.assertEqual(reconciliation["closed_exit_net_pnl_sum"], 50.0)
        self.assertEqual(reconciliation["last_closed_csv_cumulative_pnl"], 50.0)
        self.assertEqual(reconciliation["difference"], 0.0)
        self.assertEqual(report["validation"]["warnings"], [])

    def test_mixed_timezone_pair_is_rejected_cleanly(self) -> None:
        rows = [dict(item) for item in BASE_ROWS]
        rows[0]["Date and time"] += "+00:00"
        with self.assertRaisesRegex(TradeCsvError, "mixes timezone"):
            analyze_csv(self.write_csv(rows))

    def test_cli_emits_json(self) -> None:
        csv_path = self.write_csv(BASE_ROWS)
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "analyze_noro_trades.py"),
                str(csv_path),
                "--starting-equity",
                "1000",
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertTrue(report["ok"])
        self.assertEqual(report["performance"]["net_pnl"], 50.0)


if __name__ == "__main__":
    unittest.main()
