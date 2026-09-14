#!/usr/bin/env python3
"""Analyze a TradingView list-of-trades CSV without third-party dependencies.

The export repeats a trade's result on both its entry and exit rows. This tool
pairs those rows by ``Trade number`` and only realizes the PnL on a non-Open
exit row. It intentionally does not infer stop-loss or break-even performance
from favorable/adverse excursion summaries.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from statistics import median
from typing import Any, Iterable, Mapping, Sequence


class TradeCsvError(ValueError):
    """Raised when a list-of-trades CSV cannot be paired safely."""


@dataclass(frozen=True)
class _Row:
    trade_number: str
    kind: str
    side: str
    at: datetime | None
    row_number: int
    values: Mapping[str, str | None]


@dataclass(frozen=True)
class ClosedTrade:
    """One realized round trip, represented by its paired entry and exit."""

    trade_number: str
    side: str
    entered_at: datetime
    exited_at: datetime
    pnl: Decimal
    commission: Decimal
    favorable_excursion: Decimal
    adverse_excursion: Decimal
    duration_bars: Decimal
    reported_cumulative_pnl: Decimal | None


_REQUIRED_COLUMN_PREFIXES = {
    "trade_number": "trade number",
    "type": "type",
    "date_and_time": "date and time",
    "net_pnl": "net pnl",
    "commission": "commission",
    "favorable_excursion": "favorable excursion",
    "adverse_excursion": "adverse excursion",
    "duration_bars": "duration (bars)",
}
_OPTIONAL_COLUMN_PREFIXES = {"cumulative_pnl": "cumulative pnl"}
_MONEY_HEADER_WORDS = ("price", "pnl", "commission", "excursion", "value")
_OPEN_MARKERS = {"open"}


def _normalise_header(value: str) -> str:
    return " ".join(value.casefold().strip().split())


def _column_map(fieldnames: Sequence[str] | None) -> dict[str, str]:
    if not fieldnames:
        raise TradeCsvError("CSV has no header row")

    result: dict[str, str] = {}
    normalised = {name: _normalise_header(name) for name in fieldnames}
    for key, prefix in _REQUIRED_COLUMN_PREFIXES.items():
        matches = [
            name
            for name, normalised_name in normalised.items()
            if (normalised_name == prefix or normalised_name.startswith(prefix + " "))
            and "%" not in normalised_name
        ]
        if not matches:
            raise TradeCsvError(f"CSV is missing required column matching {prefix!r}")
        if len(matches) > 1:
            raise TradeCsvError(f"CSV has ambiguous columns matching {prefix!r}: {matches}")
        result[key] = matches[0]
    for key, prefix in _OPTIONAL_COLUMN_PREFIXES.items():
        matches = [
            name
            for name, normalised_name in normalised.items()
            if (normalised_name == prefix or normalised_name.startswith(prefix + " "))
            and "%" not in normalised_name
        ]
        if len(matches) > 1:
            raise TradeCsvError(f"CSV has ambiguous columns matching {prefix!r}: {matches}")
        if matches:
            result[key] = matches[0]
    return result


def _header_currency_labels(fieldnames: Iterable[str]) -> list[str]:
    """Return explicit three-letter labels from monetary-looking headers."""
    labels: set[str] = set()
    for name in fieldnames:
        lowered = name.casefold()
        if not any(word in lowered for word in _MONEY_HEADER_WORDS):
            continue
        labels.update(re.findall(r"(?<![A-Z])[A-Z]{3}(?![A-Z])", name))
    return sorted(labels)


def _parse_decimal(value: str | None, *, field: str, trade_number: str) -> Decimal:
    raw = "" if value is None else value.strip()
    if not raw or raw in {"—", "-", "N/A", "n/a"}:
        raise TradeCsvError(f"Trade {trade_number}: {field} is blank or non-numeric")
    try:
        parsed = Decimal(raw.replace(",", "").replace("−", "-"))
    except InvalidOperation as error:
        raise TradeCsvError(f"Trade {trade_number}: invalid {field} value {raw!r}") from error
    if not parsed.is_finite():
        raise TradeCsvError(f"Trade {trade_number}: {field} must be finite")
    return parsed


def _parse_timestamp(value: str | None, *, trade_number: str, field: str) -> datetime:
    raw = "" if value is None else value.strip()
    if not raw:
        raise TradeCsvError(f"Trade {trade_number}: {field} is blank")
    try:
        # TradingView's standard export is ``YYYY-MM-DD HH:MM``. fromisoformat
        # also accepts seconds and explicit offsets without losing information.
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as error:
        raise TradeCsvError(f"Trade {trade_number}: invalid {field} value {raw!r}") from error


def _parse_type(value: str | None, *, trade_number: str) -> tuple[str, str]:
    pieces = ("" if value is None else value).casefold().split()
    if len(pieces) != 2 or pieces[0] not in {"entry", "exit"} or pieces[1] not in {"long", "short"}:
        raise TradeCsvError(
            f"Trade {trade_number}: Type must be Entry/Exit long/short, got {value!r}"
        )
    return pieces[0], pieces[1]


def _is_open(value: str | None) -> bool:
    return ("" if value is None else value).strip().casefold() in _OPEN_MARKERS


def _trade_number_key(value: str) -> tuple[int, Decimal | str]:
    """Sort numeric trade identifiers naturally while retaining arbitrary identifiers."""
    try:
        numeric = Decimal(value)
        return (0, numeric) if numeric.is_finite() else (1, value)
    except InvalidOperation:
        return (1, value)


def _number(value: Decimal | None) -> float | None:
    return None if value is None else float(value)


def _percent(numerator: Decimal, denominator: Decimal) -> Decimal | None:
    return None if denominator == 0 else numerator / denominator * Decimal("100")


def _distribution(values: Sequence[Decimal]) -> dict[str, float | int | None]:
    if not values:
        return {"count": 0, "mean": None, "median": None, "minimum": None, "maximum": None}
    return {
        "count": len(values),
        "mean": _number(sum(values) / len(values)),
        "median": _number(median(values)),
        "minimum": _number(min(values)),
        "maximum": _number(max(values)),
    }


def _streak(trades: Sequence[ClosedTrade]) -> dict[str, Any]:
    longest = current = 0
    ending_trade: ClosedTrade | None = None
    for trade in trades:
        if trade.pnl < 0:
            current += 1
            if current > longest:
                longest = current
                ending_trade = trade
        else:
            current = 0
    return {
        "trades": longest,
        "ending_trade_number": None if ending_trade is None else ending_trade.trade_number,
        "ending_exit_time": None if ending_trade is None else ending_trade.exited_at.isoformat(sep=" "),
        "definition": "Consecutive closed trades with negative Net PnL; a zero or winning trade ends the streak.",
    }


def _closed_equity_drawdown(
    trades: Sequence[ClosedTrade], starting_equity: Decimal
) -> dict[str, float | str | None]:
    equity = peak_equity = starting_equity
    peak_trade: ClosedTrade | None = None
    maximum = Decimal("0")
    trough_equity = starting_equity
    trough_trade: ClosedTrade | None = None
    drawdown_peak_equity = starting_equity
    drawdown_peak_trade: ClosedTrade | None = None

    for trade in trades:
        equity += trade.pnl
        if equity > peak_equity:
            peak_equity = equity
            peak_trade = trade
        drawdown = peak_equity - equity
        if drawdown > maximum:
            maximum = drawdown
            trough_equity = equity
            trough_trade = trade
            drawdown_peak_equity = peak_equity
            drawdown_peak_trade = peak_trade

    return {
        "amount": _number(maximum),
        "percent_of_closed_equity_peak": _number(_percent(maximum, drawdown_peak_equity)),
        "peak_equity": _number(drawdown_peak_equity),
        "peak_trade_number": None if drawdown_peak_trade is None else drawdown_peak_trade.trade_number,
        "trough_equity": _number(trough_equity),
        "trough_trade_number": None if trough_trade is None else trough_trade.trade_number,
        "trough_exit_time": None if trough_trade is None else trough_trade.exited_at.isoformat(sep=" "),
        "definition": "Peak-to-trough drawdown using only equity after each realized exit.",
    }


def _side_summary(trades: Sequence[ClosedTrade]) -> dict[str, Any]:
    pnls = [trade.pnl for trade in trades]
    wins = [pnl for pnl in pnls if pnl > 0]
    losses = [pnl for pnl in pnls if pnl < 0]
    return {
        "closed_trade_count": len(trades),
        "net_pnl": _number(sum(pnls)),
        "wins": len(wins),
        "losses": len(losses),
        "breakevens": len(pnls) - len(wins) - len(losses),
        "win_rate_percent": _number(_percent(Decimal(len(wins)), Decimal(len(pnls)))) if pnls else None,
        "mean_expectancy_per_trade": _number(sum(pnls) / len(pnls)) if pnls else None,
    }


def _monthly_results(trades: Sequence[ClosedTrade], starting_equity: Decimal) -> list[dict[str, Any]]:
    months: list[dict[str, Any]] = []
    equity = starting_equity
    by_month: dict[str, dict[str, Any]] = {}

    for trade in trades:
        month = trade.exited_at.strftime("%Y-%m")
        if month not in by_month:
            record = {
                "month": month,
                "starting_closed_equity": equity,
                "pnl": Decimal("0"),
                "closed_trade_count": 0,
            }
            by_month[month] = record
            months.append(record)
        record = by_month[month]
        record["pnl"] += trade.pnl
        record["closed_trade_count"] += 1
        equity += trade.pnl

    result: list[dict[str, Any]] = []
    for index, record in enumerate(months):
        pnl = record["pnl"]
        month_start = record["starting_closed_equity"]
        edge_month = index == 0 or index == len(months) - 1
        result.append(
            {
                "month": record["month"],
                "coverage": "incomplete_or_unknown" if edge_month else "unknown",
                "closed_trade_count": record["closed_trade_count"],
                "starting_closed_equity": _number(month_start),
                "ending_closed_equity": _number(month_start + pnl),
                "realized_pnl": _number(pnl),
                "return_on_starting_equity_percent": _number(_percent(pnl, starting_equity)),
                "return_on_month_start_closed_equity_percent": _number(_percent(pnl, month_start)),
            }
        )
    return result


def _rows_to_trades(
    rows: Iterable[Mapping[str, str | None]], column_names: Mapping[str, str]
) -> tuple[list[ClosedTrade], int, int]:
    grouped: dict[str, dict[str, list[_Row]]] = defaultdict(lambda: {"entry": [], "exit": [], "open_exit": []})
    row_count = 0

    for row_count, values in enumerate(rows, start=1):
        trade_number = (values.get(column_names["trade_number"]) or "").strip()
        if not trade_number:
            raise TradeCsvError(f"CSV row {row_count}: Trade number is blank")
        kind, side = _parse_type(values.get(column_names["type"]), trade_number=trade_number)
        date_value = values.get(column_names["date_and_time"])
        is_open_exit = kind == "exit" and _is_open(date_value)
        at = None if is_open_exit else _parse_timestamp(
            date_value, trade_number=trade_number, field="Date and time"
        )
        item = _Row(trade_number, kind, side, at, row_count, values)
        grouped[trade_number]["open_exit" if is_open_exit else kind].append(item)

    if row_count == 0:
        raise TradeCsvError("CSV has no trade rows")

    errors: list[str] = []
    closed: list[ClosedTrade] = []
    open_trade_count = 0
    timestamp_awareness: set[bool] = set()

    for trade_number, group in grouped.items():
        entries, exits, open_exits = group["entry"], group["exit"], group["open_exit"]
        pairing_errors: list[str] = []
        if len(entries) > 1:
            pairing_errors.append(f"duplicate entry rows for trade {trade_number}")
        if len(exits) > 1:
            pairing_errors.append(f"duplicate closed exit rows for trade {trade_number}")
        if len(open_exits) > 1:
            pairing_errors.append(f"duplicate Open exit rows for trade {trade_number}")
        if exits and open_exits:
            pairing_errors.append(f"both closed and Open exit rows for trade {trade_number}")
        if (exits or open_exits) and not entries:
            pairing_errors.append(f"unmatched exit row for trade {trade_number}")
        if entries and not exits and not open_exits:
            pairing_errors.append(f"unmatched entry row for trade {trade_number}")
        if pairing_errors:
            errors.extend(pairing_errors)
            continue

        entry = entries[0]
        if open_exits:
            if entry.side != open_exits[0].side:
                errors.append(
                    f"trade {trade_number} has Entry {entry.side} but Open exit {open_exits[0].side}"
                )
                continue
            open_trade_count += 1
            continue
        exit_row = exits[0]
        if entry.side != exit_row.side:
            errors.append(
                f"trade {trade_number} has Entry {entry.side} but Exit {exit_row.side}"
            )
            continue
        assert entry.at is not None and exit_row.at is not None
        timestamp_awareness.update({entry.at.tzinfo is not None, exit_row.at.tzinfo is not None})
        if len(timestamp_awareness) > 1:
            raise TradeCsvError("CSV mixes timezone-aware and timezone-naive timestamps")
        if exit_row.at < entry.at:
            errors.append(f"trade {trade_number} exits before it enters")
            continue
        closed.append(
            ClosedTrade(
                trade_number=trade_number,
                side=entry.side,
                entered_at=entry.at,
                exited_at=exit_row.at,
                pnl=_parse_decimal(
                    exit_row.values.get(column_names["net_pnl"]),
                    field="Net PnL",
                    trade_number=trade_number,
                ),
                commission=_parse_decimal(
                    exit_row.values.get(column_names["commission"]),
                    field="Commission",
                    trade_number=trade_number,
                ),
                favorable_excursion=_parse_decimal(
                    exit_row.values.get(column_names["favorable_excursion"]),
                    field="Favorable excursion",
                    trade_number=trade_number,
                ),
                adverse_excursion=_parse_decimal(
                    exit_row.values.get(column_names["adverse_excursion"]),
                    field="Adverse excursion",
                    trade_number=trade_number,
                ),
                duration_bars=_parse_decimal(
                    exit_row.values.get(column_names["duration_bars"]),
                    field="Duration (bars)",
                    trade_number=trade_number,
                ),
                reported_cumulative_pnl=(
                    _parse_decimal(
                        exit_row.values.get(column_names["cumulative_pnl"]),
                        field="Cumulative PnL",
                        trade_number=trade_number,
                    )
                    if "cumulative_pnl" in column_names
                    else None
                ),
            )
        )

    if errors:
        raise TradeCsvError("Invalid trade pairing: " + "; ".join(errors))
    if len(timestamp_awareness) > 1:
        raise TradeCsvError("CSV mixes timezone-aware and timezone-naive timestamps")

    closed.sort(key=lambda trade: (trade.exited_at, _trade_number_key(trade.trade_number)))
    return closed, open_trade_count, row_count


def analyze_rows(
    rows: Iterable[Mapping[str, str | None]],
    fieldnames: Sequence[str] | None,
    *,
    starting_equity: Decimal | int | float | str = Decimal("100000"),
    source_name: str = "<rows>",
) -> dict[str, Any]:
    """Return JSON-ready statistics for paired TradingView rows.

    ``starting_equity`` is used solely for equity and return calculations. It
    does not alter the CSV's realized Net PnL values.
    """
    try:
        start = Decimal(str(starting_equity))
    except InvalidOperation as error:
        raise TradeCsvError(f"starting_equity must be numeric, got {starting_equity!r}") from error
    if not start.is_finite() or start <= 0:
        raise TradeCsvError("starting_equity must be a finite number greater than zero")

    columns = _column_map(fieldnames)
    closed, open_count, source_rows = _rows_to_trades(rows, columns)
    if not closed:
        raise TradeCsvError("CSV contains no closed trades after excluding Open exits")

    currency_labels = _header_currency_labels(fieldnames or [])
    warnings: list[str] = []
    non_usd = [label for label in currency_labels if label != "USD"]
    if non_usd:
        warnings.append(
            "Non-USD currency label(s) found in monetary headers: "
            + ", ".join(non_usd)
            + ". Values are not converted; interpret all amount metrics in the export's labels."
        )

    pnls = [trade.pnl for trade in closed]
    wins = [pnl for pnl in pnls if pnl > 0]
    losses = [pnl for pnl in pnls if pnl < 0]
    gross_profit = sum(wins)
    gross_loss = sum(losses)
    net_pnl = sum(pnls)
    average_win = sum(wins) / len(wins) if wins else None
    average_loss = sum(losses) / len(losses) if losses else None
    profit_factor = gross_profit / abs(gross_loss) if gross_loss else None
    payoff_ratio = average_win / abs(average_loss) if average_win is not None and average_loss else None
    commissions = [trade.commission for trade in closed]
    losers = [trade for trade in closed if trade.pnl < 0]
    losing_mfe = [trade.favorable_excursion for trade in losers]
    worst_mae_trade = max(closed, key=lambda trade: abs(trade.adverse_excursion))
    mfe_at_or_above_loss = [
        trade for trade in losers if trade.favorable_excursion >= abs(trade.pnl)
    ]
    long_trades = [trade for trade in closed if trade.side == "long"]
    short_trades = [trade for trade in closed if trade.side == "short"]
    additional_cost_headroom = max(net_pnl, Decimal("0"))
    last_reported_cumulative_pnl = closed[-1].reported_cumulative_pnl
    cumulative_difference = (
        net_pnl - last_reported_cumulative_pnl if last_reported_cumulative_pnl is not None else None
    )
    if cumulative_difference not in (None, Decimal("0")):
        warnings.append(
            "The sum of rounded closed-exit Net PnL values differs from the last closed CSV "
            f"Cumulative PnL by {_number(cumulative_difference)}. Metrics use the exit-row Net PnL sum."
        )

    report: dict[str, Any] = {
        "ok": True,
        "source": {
            "csv": source_name,
            "source_row_count": source_rows,
            "currency_labels_in_monetary_headers": currency_labels,
            "timestamp_note": "Timestamps are analyzed exactly as exported; the CSV does not identify its timezone.",
        },
        "analysis_basis": {
            "starting_equity": _number(start),
            "closed_trade_count": len(closed),
            "open_trade_count_excluded": open_count,
            "realization_rule": "Only paired, non-Open exit rows contribute Net PnL; entry-row duplicate PnL is ignored.",
            "ordering_rule": "Closed exits ordered by exit timestamp, then Trade number for timestamp ties.",
        },
        "validation": {"warnings": warnings},
        "period": {
            "first_entry_time": min(trade.entered_at for trade in closed).isoformat(sep=" "),
            "first_exit_time": closed[0].exited_at.isoformat(sep=" "),
            "last_exit_time": closed[-1].exited_at.isoformat(sep=" "),
        },
        "performance": {
            "net_pnl": _number(net_pnl),
            "return_on_starting_equity_percent": _number(_percent(net_pnl, start)),
            "gross_profit": _number(gross_profit),
            "gross_loss": _number(gross_loss),
            "wins": len(wins),
            "losses": len(losses),
            "breakevens": len(closed) - len(wins) - len(losses),
            "win_rate_percent": _number(_percent(Decimal(len(wins)), Decimal(len(closed)))),
            "average_win": _number(average_win),
            "average_loss": _number(average_loss),
            "average_loss_absolute": _number(abs(average_loss)) if average_loss is not None else None,
            "payoff_ratio": _number(payoff_ratio),
            "profit_factor": _number(profit_factor),
            "mean_expectancy_per_closed_trade": _number(net_pnl / len(closed)),
        },
        "pnl_reconciliation": {
            "closed_exit_net_pnl_sum": _number(net_pnl),
            "last_closed_csv_cumulative_pnl": _number(last_reported_cumulative_pnl),
            "difference": _number(cumulative_difference),
            "interpretation": (
                "A non-zero difference can result from TradingView rounding individual displayed PnL values. "
                "All calculated metrics use the paired exit-row Net PnL values."
            ),
        },
        "risk": {
            "max_closed_equity_drawdown": _closed_equity_drawdown(closed, start),
            "tradingview_intratrade_drawdown": {
                "available_from_this_csv": False,
                "value": None,
                "reason": (
                    "Trade-level excursions do not provide the chronological equity path needed "
                    "to reconstruct TradingView's intratrade portfolio drawdown."
                ),
                "worst_single_trade_adverse_excursion": {
                    "amount": _number(abs(worst_mae_trade.adverse_excursion)),
                    "trade_number": worst_mae_trade.trade_number,
                    "exit_time": worst_mae_trade.exited_at.isoformat(sep=" "),
                },
            },
            "max_losing_streak": _streak(closed),
        },
        "long_short": {"long": _side_summary(long_trades), "short": _side_summary(short_trades)},
        "duration_bars": _distribution([trade.duration_bars for trade in closed]),
        "commissions": {
            "total": _number(sum(commissions)),
            "mean_per_closed_trade": _number(sum(commissions) / len(commissions)),
            "nonzero_closed_trade_count": sum(commission != 0 for commission in commissions),
            "all_closed_trades_zero": all(commission == 0 for commission in commissions),
        },
        "cost_headroom": {
            "additional_aggregate_cost_until_closed_net_pnl_is_zero": _number(additional_cost_headroom),
            "additional_cost_per_closed_trade_until_aggregate_breakeven": _number(
                additional_cost_headroom / len(closed)
            ),
            "interpretation": (
                "Aggregate only: Net PnL is treated as CSV-reported realized net PnL. "
                "It does not show which individual trades would remain viable after costs."
            ),
        },
        "losing_trade_mfe": {
            "favorable_excursion": _distribution(losing_mfe),
            "trades_with_mfe_at_or_above_absolute_realized_loss": len(mfe_at_or_above_loss),
            "percent_of_losing_trades": _number(
                _percent(Decimal(len(mfe_at_or_above_loss)), Decimal(len(losers)))
            )
            if losers
            else None,
            "interpretation": (
                "Descriptive only. Excursion aggregates omit the order and timing of MFE/MAE, "
                "so they cannot simulate a new stop-loss, break-even trigger, or exit rule."
            ),
        },
        "monthly_realized_pnl_by_exit_month": _monthly_results(closed, start),
        "caveats": [
            "First and last listed months are incomplete_or_unknown: trade dates alone cannot prove calendar coverage.",
            "Monthly PnL is realized on the exit month, not allocated across the holding period.",
            "This report excludes the open trade and therefore can differ from TradingView totals that include mark-to-market PnL.",
        ],
    }
    return report


def analyze_csv(
    csv_path: str | Path, *, starting_equity: Decimal | int | float | str = Decimal("100000")
) -> dict[str, Any]:
    """Read a CSV path and return the same JSON-ready result as :func:`analyze_rows`."""
    path = Path(csv_path)
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return analyze_rows(
            reader,
            reader.fieldnames,
            starting_equity=starting_equity,
            source_name=str(path),
        )


def _argument_decimal(value: str) -> Decimal:
    try:
        parsed = Decimal(value)
    except InvalidOperation as error:
        raise argparse.ArgumentTypeError("must be a decimal number") from error
    if not parsed.is_finite() or parsed <= 0:
        raise argparse.ArgumentTypeError("must be a finite number greater than zero")
    return parsed


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", type=Path, help="TradingView List of Trades CSV")
    parser.add_argument(
        "--starting-equity",
        type=_argument_decimal,
        default=Decimal("100000"),
        help="Equity before the first closed exit (default: 100000)",
    )
    parser.add_argument("--indent", type=int, default=2, help="JSON indentation (default: 2)")
    args = parser.parse_args(argv)

    try:
        report = analyze_csv(args.csv_path, starting_equity=args.starting_equity)
    except (OSError, TradeCsvError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, indent=args.indent), file=sys.stderr)
        return 2
    print(json.dumps(report, indent=args.indent, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
