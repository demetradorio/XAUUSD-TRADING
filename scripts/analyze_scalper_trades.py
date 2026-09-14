#!/usr/bin/env python3
"""Reproducible, closed-trade analysis for TradingView strategy CSV exports.

The CSV's ``Net PnL USD`` is treated as already net of its reported commission.
Additional-cost sensitivity therefore subtracts only the explicitly requested
extra round-trip cost; it never charges the CSV commission a second time.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import Counter, OrderedDict, defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Iterable, Mapping, Sequence


ZERO = Decimal("0")
KNOWN_PATHS = ("MAIN", "BOS", "OB", "RE", "TRAP", "OD")
EMPTY_NUMBERS = {"", "-", "na", "n a", "none", "null"}

FIELD_ALIASES: Mapping[str, tuple[str, ...]] = {
    "trade_number": ("Trade number", "Trade #", "Trade Number"),
    "type": ("Type",),
    "timestamp": ("Date and time", "Date/Time", "Date and Time", "Date"),
    "signal": ("Signal", "Order ID", "Order"),
    "net_pnl": ("Net PnL USD", "Net P&L USD", "Net PnL", "Net Profit"),
    "commission": ("Commission USD", "Commission"),
    "quantity": ("Size (qty)", "Qty", "Quantity", "Size"),
    "duration": ("Duration (bars)", "Duration", "Bars"),
}


class CsvSchemaError(ValueError):
    """Raised when a file cannot be interpreted as a TradingView trade CSV."""


@dataclass(frozen=True)
class CsvRow:
    index: int
    values: Mapping[str, str]
    raw_values: Mapping[str, str]

    def get(self, field_name: str) -> str:
        return self.values.get(field_name, "") or ""


@dataclass(frozen=True)
class SignalInfo:
    path: str
    ticket_id: str | None
    side: str | None


@dataclass
class Trade:
    number: str
    entry: CsvRow
    exit: CsvRow
    margin_call: bool
    entry_time: datetime | None = None
    exit_time: datetime | None = None
    entry_signal: SignalInfo = field(default_factory=lambda: SignalInfo("UNKNOWN", None, None))
    exit_signal: SignalInfo = field(default_factory=lambda: SignalInfo("UNKNOWN", None, None))
    side: str = "UNKNOWN"
    net_pnl: Decimal | None = None
    commission: Decimal | None = None
    entry_quantity: Decimal | None = None
    exit_quantity: Decimal | None = None
    cost_quantity: Decimal | None = None
    duration_bars: Decimal | None = None
    duration_invalid: bool = False


@dataclass
class PairingResult:
    trades: list[Trade]
    raw_rows: int
    canonical_rows: int
    duplicate_rows_ignored: int
    group_outcomes: Counter[str]
    open_marked_exit_rows: int
    unrecognized_rows: int
    missing_trade_number_rows: int


def _normalized_header(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def _resolve_headers(fieldnames: Sequence[str] | None) -> dict[str, str]:
    if not fieldnames:
        raise CsvSchemaError("CSV has no header row")
    normalized = {_normalized_header(name): name for name in fieldnames if name is not None}
    resolved: dict[str, str] = {}
    for canonical, aliases in FIELD_ALIASES.items():
        for alias in aliases:
            actual = normalized.get(_normalized_header(alias))
            if actual is not None:
                resolved[canonical] = actual
                break
    missing = [field for field in ("trade_number", "type", "net_pnl") if field not in resolved]
    if missing:
        human_names = ", ".join(missing)
        raise CsvSchemaError(f"CSV is missing required column(s): {human_names}")
    return resolved


def read_trade_csv(path: str | Path) -> tuple[list[CsvRow], tuple[str, ...]]:
    """Read a CSV without bringing in third-party dependencies."""
    try:
        handle = Path(path).open("r", encoding="utf-8-sig", newline="")
    except OSError as exc:
        raise CsvSchemaError(f"cannot read CSV: {exc}") from exc

    with handle:
        reader = csv.DictReader(handle)
        headers = tuple(reader.fieldnames or ())
        resolved = _resolve_headers(reader.fieldnames)
        rows: list[CsvRow] = []
        for index, raw in enumerate(reader, start=1):
            raw_values = {str(key): "" if value is None else str(value) for key, value in raw.items() if key is not None}
            values = {
                canonical: raw_values.get(actual, "")
                for canonical, actual in resolved.items()
            }
            # Ignore completely blank physical lines that DictReader can expose.
            if not any(value.strip() for value in raw_values.values()):
                continue
            rows.append(CsvRow(index=index, values=values, raw_values=raw_values))
    return rows, headers


def _compact(value: str) -> str:
    return " ".join(re.sub(r"[^a-z0-9]+", " ", value.lower()).split())


def _row_fingerprint(row: CsvRow) -> tuple[tuple[str, str], ...]:
    return tuple(sorted((key, " ".join(value.split())) for key, value in row.raw_values.items()))


def _is_margin_call(row: CsvRow) -> bool:
    return "margin call" in _compact(row.get("type")) or "margin call" in _compact(row.get("signal"))


def _is_open_marker(row: CsvRow) -> bool:
    """Recognize TradingView's open-position placeholders without matching IDs."""
    markers = {
        "open",
        "open trade",
        "open position",
        "open position unrealized",
        "unrealized",
    }
    type_text = _compact(row.get("type"))
    signal_text = _compact(row.get("signal"))
    return type_text in markers or signal_text in markers


def _row_role(row: CsvRow) -> str:
    type_text = _compact(row.get("type"))
    if _is_margin_call(row):
        return "exit"
    if type_text.startswith("entry"):
        return "entry"
    if type_text.startswith(("exit", "close", "closed")) or _is_open_marker(row):
        return "exit"
    return "unknown"


def _is_open_marked_exit(row: CsvRow) -> bool:
    return _row_role(row) == "exit" and _is_open_marker(row) and not _is_margin_call(row)


def pair_trade_rows(rows: Iterable[CsvRow]) -> PairingResult:
    """Create one canonical trade per Trade number and reject ambiguous groups."""
    grouped: OrderedDict[str, list[CsvRow]] = OrderedDict()
    missing_trade_number_rows = 0
    raw_rows = 0
    for row in rows:
        raw_rows += 1
        number = row.get("trade_number").strip()
        if not number:
            missing_trade_number_rows += 1
            number = f"__missing_trade_number_row_{row.index}"
        grouped.setdefault(number, []).append(row)

    trades: list[Trade] = []
    outcomes: Counter[str] = Counter()
    canonical_rows = 0
    duplicate_rows_ignored = 0
    open_marked_exit_rows = 0
    unrecognized_rows = 0

    for number, members in grouped.items():
        unique: list[CsvRow] = []
        fingerprints: set[tuple[tuple[str, str], ...]] = set()
        for row in members:
            fingerprint = _row_fingerprint(row)
            if fingerprint in fingerprints:
                duplicate_rows_ignored += 1
                continue
            fingerprints.add(fingerprint)
            unique.append(row)
        canonical_rows += len(unique)

        if number.startswith("__missing_trade_number_row_"):
            outcomes["invalid_trade_number"] += 1
            continue

        entries = [row for row in unique if _row_role(row) == "entry"]
        all_exits = [row for row in unique if _row_role(row) == "exit"]
        open_exits = [row for row in all_exits if _is_open_marked_exit(row)]
        closed_exits = [row for row in all_exits if not _is_open_marked_exit(row)]
        unrecognized_rows += sum(_row_role(row) == "unknown" for row in unique)
        open_marked_exit_rows += len(open_exits)

        if len(entries) > 1 or len(closed_exits) > 1:
            outcomes["ambiguous"] += 1
            continue
        if not entries:
            outcomes["incomplete"] += 1
            continue
        if not closed_exits:
            outcomes["open_marked"] += 1 if open_exits else 0
            outcomes["incomplete"] += 1 if not open_exits else 0
            continue

        exit_row = closed_exits[0]
        trades.append(
            Trade(
                number=number,
                entry=entries[0],
                exit=exit_row,
                margin_call=_is_margin_call(exit_row),
            )
        )
        outcomes["closed"] += 1

    return PairingResult(
        trades=trades,
        raw_rows=raw_rows,
        canonical_rows=canonical_rows,
        duplicate_rows_ignored=duplicate_rows_ignored,
        group_outcomes=outcomes,
        open_marked_exit_rows=open_marked_exit_rows,
        unrecognized_rows=unrecognized_rows,
        missing_trade_number_rows=missing_trade_number_rows,
    )


def _parse_decimal(value: str) -> tuple[Decimal | None, bool]:
    """Return ``(number, malformed)`` while accepting common USD CSV formatting."""
    text = value.strip()
    if _compact(text) in EMPTY_NUMBERS:
        return None, False
    negative_parentheses = text.startswith("(") and text.endswith(")")
    if negative_parentheses:
        text = text[1:-1]
    text = text.replace("−", "-").replace("–", "-")
    text = re.sub(r"[$,\s]", "", text).replace("%", "")
    try:
        number = Decimal(text)
    except (InvalidOperation, ValueError):
        return None, True
    if not number.is_finite():
        return None, True
    return (-number if negative_parentheses else number), False


def _parse_timestamp(value: str) -> tuple[datetime | None, bool, bool]:
    """Return ``(source-local timestamp, explicit_zone, malformed)``."""
    text = value.strip()
    if not text:
        return None, False, False
    explicit_zone = bool(re.search(r"(?:Z|[+-]\d\d:?\d\d)$", text, flags=re.IGNORECASE))
    iso_text = text[:-1] + "+00:00" if text.endswith(("Z", "z")) else text
    try:
        parsed = datetime.fromisoformat(iso_text)
    except ValueError:
        parsed = None
    if parsed is None:
        for fmt in (
            "%Y-%m-%d %H:%M:%S.%f",
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%d %H:%M",
            "%m/%d/%Y %H:%M:%S",
            "%m/%d/%Y %H:%M",
        ):
            try:
                parsed = datetime.strptime(text, fmt)
                break
            except ValueError:
                continue
    if parsed is None:
        return None, explicit_zone, True
    return parsed, parsed.utcoffset() is not None, False


def _side_from_type(value: str) -> str | None:
    text = _compact(value)
    if "long" in text:
        return "LONG"
    if "short" in text:
        return "SHORT"
    return None


def parse_signal(value: str) -> SignalInfo:
    tokens = [token for token in re.split(r"[^A-Z0-9]+", value.upper()) if token]
    path = next((token for token in tokens if token in KNOWN_PATHS), "UNKNOWN")
    side = next(("LONG" if token in {"L", "LONG"} else "SHORT" for token in tokens if token in {"L", "LONG", "S", "SHORT"}), None)
    numeric_tokens = re.findall(r"\d+", value)
    ticket_id = None
    if numeric_tokens:
        # Signal IDs are generally numeric. Normalize leading zeroes before comparison.
        ticket_id = str(int(numeric_tokens[-1]))
    return SignalInfo(path=path, ticket_id=ticket_id, side=side)


def _number_sort_key(number: str) -> tuple[int, Decimal | str]:
    parsed, malformed = _parse_decimal(number)
    if parsed is not None and not malformed:
        return (0, parsed)
    return (1, number)


def _decimal_text(value: Decimal | None) -> str | None:
    if value is None:
        return None
    if value == 0:
        return "0"
    return format(value.normalize(), "f")


def _numeric_text(value: Decimal | None) -> str | None:
    return _decimal_text(value)


def _ratio_text(value: Decimal | None) -> str | None:
    return _decimal_text(value)


def enrich_trades(trades: Iterable[Trade]) -> dict[str, object]:
    """Parse fields once and collect data-quality diagnostics."""
    numeric_errors: Counter[str] = Counter()
    field_conflicts: Counter[str] = Counter()
    quantity_anomalies: Counter[str] = Counter()
    timestamp_errors: Counter[str] = Counter()
    timestamp_missing: Counter[str] = Counter()
    timestamp_seen = 0
    timestamp_with_zone = 0
    attribution: Counter[str] = Counter()

    for trade in trades:
        trade.entry_signal = parse_signal(trade.entry.get("signal"))
        trade.exit_signal = parse_signal(trade.exit.get("signal"))
        entry_type_side = _side_from_type(trade.entry.get("type"))
        exit_type_side = _side_from_type(trade.exit.get("type"))
        trade.side = entry_type_side or trade.entry_signal.side or exit_type_side or "UNKNOWN"

        if trade.entry_signal.path == "UNKNOWN":
            attribution["unknown_entry_path"] += 1
        if trade.exit_signal.path == "UNKNOWN":
            attribution["unknown_exit_path"] += 1
        if trade.entry_signal.ticket_id is None:
            attribution["missing_entry_ticket_id"] += 1
        if trade.exit_signal.ticket_id is None:
            attribution["missing_exit_ticket_id"] += 1
        if (
            trade.entry_signal.ticket_id is not None
            and trade.exit_signal.ticket_id is not None
            and trade.entry_signal.ticket_id != trade.exit_signal.ticket_id
        ):
            attribution["ticket_id_mismatch"] += 1
        if (
            trade.entry_signal.path != "UNKNOWN"
            and trade.exit_signal.path != "UNKNOWN"
            and trade.entry_signal.path != trade.exit_signal.path
        ):
            attribution["path_mismatch"] += 1
        if entry_type_side is not None and exit_type_side is not None and entry_type_side != exit_type_side:
            attribution["type_side_mismatch"] += 1

        for label, row in (("entry", trade.entry), ("exit", trade.exit)):
            raw_time = row.get("timestamp")
            if raw_time.strip():
                timestamp_seen += 1
            else:
                timestamp_missing[label] += 1
            parsed_time, explicit_zone, malformed_time = _parse_timestamp(raw_time)
            if explicit_zone:
                timestamp_with_zone += 1
            if malformed_time:
                timestamp_errors[label] += 1
            if label == "entry":
                trade.entry_time = parsed_time
            else:
                trade.exit_time = parsed_time

        parsed_values: dict[str, tuple[Decimal | None, Decimal | None]] = {}
        parsed_errors: dict[str, tuple[bool, bool]] = {}
        canonical_values: dict[str, Decimal | None] = {}
        for field_name in ("net_pnl", "commission", "quantity", "duration"):
            entry_value, entry_bad = _parse_decimal(trade.entry.get(field_name))
            exit_value, exit_bad = _parse_decimal(trade.exit.get(field_name))
            if entry_bad:
                numeric_errors[f"entry_{field_name}"] += 1
            if exit_bad:
                numeric_errors[f"exit_{field_name}"] += 1
            parsed_values[field_name] = (entry_value, exit_value)
            parsed_errors[field_name] = (entry_bad, exit_bad)
            canonical_values[field_name] = exit_value if exit_value is not None or exit_bad else entry_value
            if entry_value is not None and exit_value is not None and entry_value != exit_value:
                field_conflicts[field_name] += 1

        trade.net_pnl = canonical_values["net_pnl"]
        if trade.net_pnl is None:
            field_conflicts["missing_net_pnl"] += 1

        trade.commission = canonical_values["commission"]
        if trade.commission is None:
            field_conflicts["missing_commission"] += 1

        trade.entry_quantity, trade.exit_quantity = parsed_values["quantity"]
        if trade.entry_quantity is None and trade.exit_quantity is None:
            quantity_anomalies["missing_quantity"] += 1
        if trade.entry_quantity is not None and trade.entry_quantity <= 0:
            quantity_anomalies["non_positive_entry_quantity"] += 1
        if trade.exit_quantity is not None and trade.exit_quantity <= 0:
            quantity_anomalies["non_positive_exit_quantity"] += 1
        quantity_mismatch = (
            trade.entry_quantity is not None
            and trade.exit_quantity is not None
            and trade.entry_quantity != trade.exit_quantity
        )
        if quantity_mismatch:
            quantity_anomalies["entry_exit_quantity_mismatch"] += 1
        invalid_quantity = any(parsed_errors["quantity"]) or any(
            value is not None and value <= ZERO for value in parsed_values["quantity"]
        )
        if quantity_mismatch or invalid_quantity:
            trade.cost_quantity = None
        elif trade.entry_quantity is not None:
            trade.cost_quantity = trade.entry_quantity
            if trade.exit_quantity is None:
                quantity_anomalies["used_entry_quantity_for_extra_cost"] += 1
        elif trade.exit_quantity is not None:
            trade.cost_quantity = trade.exit_quantity
            quantity_anomalies["used_exit_quantity_for_extra_cost"] += 1
        else:
            trade.cost_quantity = None

        _, exit_duration = parsed_values["duration"]
        entry_bad, exit_bad = parsed_errors["duration"]
        trade.duration_invalid = exit_bad or (exit_duration is None and entry_bad)
        trade.duration_bars = canonical_values["duration"]
        if trade.duration_bars is not None and trade.duration_bars < 0:
            field_conflicts["negative_duration"] += 1
            trade.duration_invalid = True
            trade.duration_bars = None

    if timestamp_seen == 0:
        timezone_status = "unavailable"
    elif timestamp_with_zone == 0:
        timezone_status = "unknown"
    elif timestamp_with_zone == timestamp_seen:
        timezone_status = "explicit_in_csv"
    else:
        timezone_status = "mixed"

    return {
        "numeric_parse_errors": dict(sorted(numeric_errors.items())),
        "field_conflicts": dict(sorted(field_conflicts.items())),
        "quantity_anomalies": dict(sorted(quantity_anomalies.items())),
        "timestamp_parse_errors": dict(sorted(timestamp_errors.items())),
        "timestamp_missing": dict(sorted(timestamp_missing.items())),
        "timestamp_timezone_status": timezone_status,
        "timestamps_seen": timestamp_seen,
        "timestamps_with_explicit_zone": timestamp_with_zone,
        "signal_attribution": dict(sorted(attribution.items())),
    }


def _summary_from_pnls(pnls: Sequence[Decimal]) -> dict[str, object]:
    count = len(pnls)
    wins = [pnl for pnl in pnls if pnl > ZERO]
    losses = [pnl for pnl in pnls if pnl < ZERO]
    breakeven = [pnl for pnl in pnls if pnl == ZERO]
    total = sum(pnls, ZERO)
    gross_wins = sum(wins, ZERO)
    gross_losses = -sum(losses, ZERO)
    average_win = gross_wins / len(wins) if wins else None
    average_loss = gross_losses / len(losses) if losses else None
    profit_factor = gross_wins / gross_losses if gross_losses > ZERO else None
    payoff_ratio = average_win / average_loss if average_win is not None and average_loss and average_loss > ZERO else None

    if gross_losses > ZERO:
        profit_factor_status = "defined"
    elif wins:
        profit_factor_status = "undefined_no_losing_trades"
    else:
        profit_factor_status = "undefined_no_winning_or_losing_trades"

    return {
        "trade_count": count,
        "winning_trades": len(wins),
        "losing_trades": len(losses),
        "breakeven_trades": len(breakeven),
        "win_rate_pct": _ratio_text(Decimal(len(wins)) * Decimal("100") / count if count else None),
        "net_pnl_usd": _decimal_text(total),
        "gross_wins_usd": _decimal_text(gross_wins),
        "gross_losses_usd": _decimal_text(gross_losses),
        "profit_factor": _ratio_text(profit_factor),
        "profit_factor_status": profit_factor_status,
        "average_win_usd": _decimal_text(average_win),
        "average_loss_usd": _decimal_text(average_loss),
        "payoff_ratio": _ratio_text(payoff_ratio),
        "expectancy_usd_per_trade": _decimal_text(total / count if count else None),
    }


def summarize_trades(trades: Sequence[Trade]) -> dict[str, object]:
    pnls = [trade.net_pnl for trade in trades if trade.net_pnl is not None]
    summary = _summary_from_pnls(pnls)
    commissions = [trade.commission for trade in trades if trade.commission is not None]
    total_commission = sum(commissions, ZERO)
    pre_commission_pnls = [
        trade.net_pnl + (trade.commission if trade.commission is not None else ZERO)
        for trade in trades
        if trade.net_pnl is not None
    ]
    pre_commission_wins = sum((pnl for pnl in pre_commission_pnls if pnl > ZERO), ZERO)
    pre_commission_losses = -sum((pnl for pnl in pre_commission_pnls if pnl < ZERO), ZERO)
    summary.update(
        {
            "reported_commission_usd": _decimal_text(total_commission),
            "trades_missing_reported_commission": sum(trade.commission is None for trade in trades),
            "gross_pnl_before_reported_commission_usd": _decimal_text(sum(pre_commission_pnls, ZERO)),
            "gross_wins_before_reported_commission_usd": _decimal_text(pre_commission_wins),
            "gross_losses_before_reported_commission_usd": _decimal_text(pre_commission_losses),
        }
    )
    return summary


def _duration_summary(trades: Sequence[Trade]) -> dict[str, object]:
    values = sorted(trade.duration_bars for trade in trades if trade.duration_bars is not None)
    count = len(values)
    invalid_count = sum(trade.duration_invalid for trade in trades)
    if count:
        middle = count // 2
        median = values[middle] if count % 2 else (values[middle - 1] + values[middle]) / Decimal("2")
        average = sum(values, ZERO) / count
    else:
        median = None
        average = None
    buckets = Counter()
    for value in values:
        if value == 0:
            buckets["0"] += 1
        elif value <= 5:
            buckets["1-5"] += 1
        elif value <= 15:
            buckets["6-15"] += 1
        elif value <= 60:
            buckets["16-60"] += 1
        else:
            buckets["61+"] += 1
    return {
        "trades_with_reported_duration": count,
        "trades_missing_reported_duration": len(trades) - count - invalid_count,
        "trades_with_invalid_reported_duration": invalid_count,
        "total_bars": _numeric_text(sum(values, ZERO)),
        "average_bars": _numeric_text(average),
        "median_bars": _numeric_text(median),
        "minimum_bars": _numeric_text(values[0] if values else None),
        "maximum_bars": _numeric_text(values[-1] if values else None),
        "distribution": {label: buckets.get(label, 0) for label in ("0", "1-5", "6-15", "16-60", "61+")},
        "definition": "TradingView-reported Duration (bars), not elapsed clock time.",
    }


def _mixed_timezone_awareness(timestamps: Iterable[datetime | None]) -> bool:
    return len({stamp.utcoffset() is not None for stamp in timestamps if stamp is not None}) > 1


def _chronological_groups(trades: Sequence[Trade]) -> list[list[Trade]]:
    timestamped: defaultdict[datetime, list[Trade]] = defaultdict(list)
    for trade in trades:
        if trade.exit_time is not None:
            timestamped[trade.exit_time].append(trade)
    return [timestamped[stamp] for stamp in sorted(timestamped)]


def _closed_equity_metrics(trades: Sequence[Trade]) -> dict[str, object]:
    unparsed_count = sum(trade.exit_time is None for trade in trades)
    result = {
        "chronology_status": "available",
        "max_closed_equity_drawdown_usd": None,
        "closed_equity_peak_usd": None,
        "closed_equity_end_usd": _decimal_text(sum((trade.net_pnl or ZERO for trade in trades), ZERO)),
        "max_consecutive_losses": None,
        "same_exit_timestamp_groups": None,
        "trades_with_unparseable_exit_timestamp": unparsed_count,
        "drawdown_method": "Exit-time groups are summed before updating closed equity. Requires usable exit timestamps with consistent timezone awareness; no fallback chronology is invented.",
        "loss_streak_tie_break": "Trade number, then CSV row order, only when exit timestamps are equal.",
    }
    if unparsed_count:
        result["chronology_status"] = "unavailable_missing_exit_timestamp"
        return result
    if _mixed_timezone_awareness(trade.exit_time for trade in trades):
        result["chronology_status"] = "unavailable_mixed_timezone_awareness"
        return result

    groups = _chronological_groups(trades)
    equity = ZERO
    peak = ZERO
    max_drawdown = ZERO
    same_timestamp_groups = 0
    ordered: list[Trade] = []

    for group in groups:
        if len(group) > 1:
            same_timestamp_groups += 1
        pnl = sum((trade.net_pnl or ZERO for trade in group), ZERO)
        equity += pnl
        peak = max(peak, equity)
        max_drawdown = max(max_drawdown, peak - equity)
        ordered.extend(sorted(group, key=lambda item: (_number_sort_key(item.number), item.exit.index)))

    streak = 0
    max_streak = 0
    for trade in ordered:
        if trade.net_pnl is not None and trade.net_pnl < ZERO:
            streak += 1
            max_streak = max(max_streak, streak)
        else:
            streak = 0

    result.update(
        {
            "max_closed_equity_drawdown_usd": _decimal_text(max_drawdown),
            "closed_equity_peak_usd": _decimal_text(peak),
            "max_consecutive_losses": max_streak,
            "same_exit_timestamp_groups": same_timestamp_groups,
        }
    )
    return result


def _overlap_metrics(trades: Sequence[Trade]) -> dict[str, object]:
    intervals: list[Trade] = []
    missing_time = 0
    zero_length = 0
    negative_interval = 0
    mixed_intervals = 0
    for trade in trades:
        if trade.entry_time is None or trade.exit_time is None:
            missing_time += 1
        elif _mixed_timezone_awareness((trade.entry_time, trade.exit_time)):
            mixed_intervals += 1
        elif trade.entry_time == trade.exit_time:
            zero_length += 1
        elif trade.entry_time > trade.exit_time:
            negative_interval += 1
        else:
            intervals.append(trade)

    if _mixed_timezone_awareness(stamp for trade in trades for stamp in (trade.entry_time, trade.exit_time)):
        chronology_status = "unavailable_mixed_timezone_awareness"
    elif missing_time:
        chronology_status = "unavailable_missing_timestamp"
    elif negative_interval:
        chronology_status = "unavailable_reversed_interval"
    else:
        chronology_status = "available"
    result = {
        "chronology_status": chronology_status,
        "trades_with_usable_intervals": len(intervals),
        "trades_without_usable_intervals": missing_time + zero_length + negative_interval + mixed_intervals,
        "missing_timestamp_intervals": missing_time,
        "zero_length_timestamp_intervals": zero_length,
        "negative_timestamp_intervals": negative_interval,
        "incomparable_timezone_intervals": mixed_intervals,
        "max_simultaneous_positions": None,
        "overlapping_trade_pairs": None,
        "trades_with_at_least_one_overlap": None,
        "overlap_rate_pct": None,
        "overlap_components": None,
        "largest_overlap_component_size": None,
        "method": "Strict overlap among positive-duration timestamp intervals only; same-bar intervals are excluded. Aggregates are unavailable with missing, reversed, or mixed-timezone timestamps.",
        "dependence_caveat": "Overlapping positions can share market exposure, so per-trade observations are not necessarily independent.",
    }
    if chronology_status != "available":
        return result

    parent = list(range(len(intervals)))

    def find(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(left: int, right: int) -> None:
        left_root, right_root = find(left), find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    overlap_pairs = 0
    participants: set[int] = set()
    for left_index, left in enumerate(intervals):
        for right_index in range(left_index + 1, len(intervals)):
            right = intervals[right_index]
            if left.entry_time < right.exit_time and right.entry_time < left.exit_time:
                overlap_pairs += 1
                participants.update((left_index, right_index))
                union(left_index, right_index)

    component_sizes: Counter[int] = Counter(find(index) for index in participants)
    max_simultaneous = 0
    active = 0
    events: list[tuple[datetime, int]] = []
    for trade in intervals:
        # Exit events sort first at the same timestamp: [entry, exit) intervals.
        events.append((trade.entry_time, 1))
        events.append((trade.exit_time, -1))
    for _, delta in sorted(events, key=lambda event: (event[0], 0 if event[1] < 0 else 1)):
        active += delta
        max_simultaneous = max(max_simultaneous, active)

    result.update(
        {
            "max_simultaneous_positions": max_simultaneous,
            "overlapping_trade_pairs": overlap_pairs,
            "trades_with_at_least_one_overlap": len(participants),
            "overlap_rate_pct": _ratio_text(Decimal(len(participants)) * Decimal("100") / len(intervals) if intervals else None),
            "overlap_components": len(component_sizes),
            "largest_overlap_component_size": max(component_sizes.values(), default=0),
        }
    )
    return result


def _trade_month(trade: Trade) -> str:
    return trade.exit_time.strftime("%Y-%m") if trade.exit_time is not None else "UNKNOWN"


def _breakdowns(trades: Sequence[Trade]) -> dict[str, object]:
    by_path: dict[str, list[Trade]] = {path: [] for path in KNOWN_PATHS}
    by_path["UNKNOWN"] = []
    by_side: dict[str, list[Trade]] = {"LONG": [], "SHORT": [], "UNKNOWN": []}
    by_month: defaultdict[str, list[Trade]] = defaultdict(list)

    for trade in trades:
        by_path.setdefault(trade.entry_signal.path, []).append(trade)
        by_side.setdefault(trade.side, []).append(trade)
        by_month[_trade_month(trade)].append(trade)

    return {
        "path_attribution": "Entry signal path. Exit signal IDs are audited separately because FIFO/pyramiding can associate a different exit order ID.",
        "month_attribution": "Source-local exit timestamp calendar month, preserving explicit offsets. No session or CT inference is made from timezone-less CSV timestamps.",
        "by_path": {path: summarize_trades(by_path[path]) for path in (*KNOWN_PATHS, "UNKNOWN")},
        "by_side": {side: summarize_trades(by_side[side]) for side in ("LONG", "SHORT", "UNKNOWN")},
        "by_month": {month: summarize_trades(by_month[month]) for month in sorted(by_month)},
    }


def _extra_cost_sensitivity(trades: Sequence[Trade], extra_cost_per_contract: Decimal) -> dict[str, object]:
    unavailable_quantity = [trade for trade in trades if trade.cost_quantity is None]
    additional_costs = [extra_cost_per_contract * trade.cost_quantity for trade in trades if trade.cost_quantity is not None]
    base = {
        "additional_round_trip_cost_per_contract_usd": _decimal_text(extra_cost_per_contract),
        "method": "Subtracts only additional round-trip cost from CSV Net PnL; reported commission is not charged again. Mismatched, nonpositive, or malformed quantities make complete estimates unavailable.",
        "trades_with_cost_quantity": len(trades) - len(unavailable_quantity),
        "trades_without_cost_quantity": len(unavailable_quantity),
        "known_additional_cost_usd": _decimal_text(sum(additional_costs, ZERO)),
    }
    if unavailable_quantity:
        base.update(
            {
                "coverage_status": "incomplete_quantity_coverage",
                "net_pnl_after_extra_cost_usd": None,
                "profit_factor_after_extra_cost": None,
                "profit_factor_after_extra_cost_status": "unavailable_quantity_coverage",
                "expectancy_after_extra_cost_usd_per_trade": None,
                "trades_flipped_to_loss_after_extra_cost": None,
            }
        )
        return base

    adjusted = [trade.net_pnl - extra_cost_per_contract * trade.cost_quantity for trade in trades if trade.net_pnl is not None]
    baseline = [trade.net_pnl for trade in trades if trade.net_pnl is not None]
    adjusted_summary = _summary_from_pnls(adjusted)
    flips = sum(before >= ZERO and after < ZERO for before, after in zip(baseline, adjusted))
    base.update(
        {
            "coverage_status": "complete",
            "net_pnl_after_extra_cost_usd": adjusted_summary["net_pnl_usd"],
            "profit_factor_after_extra_cost": adjusted_summary["profit_factor"],
            "profit_factor_after_extra_cost_status": adjusted_summary["profit_factor_status"],
            "expectancy_after_extra_cost_usd_per_trade": adjusted_summary["expectancy_usd_per_trade"],
            "trades_flipped_to_loss_after_extra_cost": flips,
        }
    )
    return base


def _top_pnl_values(trades: Sequence[Trade], *, descending: bool, limit: int) -> list[str]:
    values = sorted(
        (trade.net_pnl for trade in trades if trade.net_pnl is not None and (trade.net_pnl > ZERO if descending else trade.net_pnl < ZERO)),
        reverse=descending,
    )
    return [_decimal_text(value) or "0" for value in values[:limit]]


def analyze_csv(path: str | Path, *, extra_cost_per_contract: Decimal | str | int = ZERO, top: int = 5) -> dict[str, object]:
    """Analyze a TradingView export and return JSON-safe aggregate statistics."""
    if top < 1:
        raise ValueError("top must be at least 1")
    extra_cost, malformed_cost = _parse_decimal(str(extra_cost_per_contract))
    if malformed_cost or extra_cost is None or extra_cost < ZERO:
        raise ValueError("extra_cost_per_contract must be a non-negative decimal")

    rows, headers = read_trade_csv(path)
    pairing = pair_trade_rows(rows)
    quality = enrich_trades(pairing.trades)
    financial_trades = [trade for trade in pairing.trades if trade.net_pnl is not None]
    outcomes = pairing.group_outcomes
    group_count = sum(outcomes.values())
    closed_count = outcomes.get("closed", 0)
    closed_equity = _closed_equity_metrics(financial_trades)
    overlap = _overlap_metrics(pairing.trades)
    extra_cost_summary = _extra_cost_sensitivity(financial_trades, extra_cost)

    warnings: list[str] = []
    if quality["timestamp_timezone_status"] in {"unknown", "unavailable", "mixed"}:
        warnings.append("CSV timestamps do not establish a single explicit timezone; no CT/session classification is inferred.")
    if outcomes.get("open_marked", 0):
        warnings.append("Open-marked exit groups were excluded from closed-trade performance.")
    if outcomes.get("ambiguous", 0):
        warnings.append("Ambiguously paired Trade number groups were excluded from closed-trade performance.")
    if len(financial_trades) != closed_count:
        warnings.append("Some structurally closed trades lack usable Net PnL and are excluded from financial metrics.")
    if closed_equity["chronology_status"] != "available":
        warnings.append(f"Closed-equity drawdown and loss streak unavailable: {closed_equity['chronology_status']}.")
    if overlap["chronology_status"] != "available":
        warnings.append(f"Overlap aggregates unavailable: {overlap['chronology_status']}.")
    if extra_cost_summary["coverage_status"] != "complete":
        warnings.append("Extra-cost estimates unavailable: quantities are missing, invalid, or inconsistent.")

    performance = summarize_trades(financial_trades)
    performance.update(
        {
            "largest_winners_usd": _top_pnl_values(financial_trades, descending=True, limit=top),
            "largest_losers_usd": _top_pnl_values(financial_trades, descending=False, limit=top),
            "largest_value_count": top,
        }
    )
    report = {
        "report_version": 1,
        "source": {
            "filename": Path(path).name,
            "header_count": len(headers),
            "raw_row_count": pairing.raw_rows,
        },
        "methodology": {
            "closed_trade_definition": "Exactly one canonical Entry row and one non-open Exit/Margin Call row sharing a Trade number.",
            "pnl_definition": "Net PnL USD from the canonical Exit row, falling back to Entry only for missing exit values. Malformed/nonfinite exit values are excluded; paired values are audited for conflicts.",
            "commission_definition": "One reported Commission USD value per paired trade, not the sum of duplicated Entry and Exit values.",
            "profit_factor_definition": "Gross wins divided by absolute gross losses using CSV Net PnL (after reported commission).",
            "drawdown_definition": "Closed-equity drawdown from cumulative closed Net PnL, not TradingView's intrabar drawdown.",
        },
        "reconciliation": {
            "trade_number_groups": group_count,
            "closed_trade_groups": closed_count,
            "closed_margin_call_groups": sum(trade.margin_call for trade in pairing.trades),
            "excluded_open_marked_groups": outcomes.get("open_marked", 0),
            "excluded_incomplete_groups": outcomes.get("incomplete", 0),
            "excluded_ambiguous_groups": outcomes.get("ambiguous", 0),
            "excluded_invalid_trade_number_groups": outcomes.get("invalid_trade_number", 0),
            "groups_reconcile_exactly": group_count == sum(outcomes.values()),
            "raw_rows": pairing.raw_rows,
            "canonical_rows_after_exact_duplicate_removal": pairing.canonical_rows,
            "duplicate_rows_ignored": pairing.duplicate_rows_ignored,
            "rows_reconcile_exactly": pairing.raw_rows == pairing.canonical_rows + pairing.duplicate_rows_ignored,
            "open_marked_exit_rows": pairing.open_marked_exit_rows,
            "unrecognized_rows_within_groups": pairing.unrecognized_rows,
            "missing_trade_number_rows": pairing.missing_trade_number_rows,
            "financially_analyzed_closed_trades": len(financial_trades),
        },
        "performance": performance,
        "closed_equity": closed_equity,
        "duration": _duration_summary(financial_trades),
        "breakdowns": _breakdowns(financial_trades),
        "overlap_dependence": overlap,
        "extra_cost_sensitivity": extra_cost_summary,
        "data_quality": {
            **quality,
            "warnings": warnings,
            "signal_attribution_note": "Entry/exit ticket ID mismatches are flagged, not silently reassigned. They can occur under FIFO/pyramiding and do not alter Trade-number PnL pairing.",
        },
    }
    return report


def _markdown_value(value: object, *, money: bool = False, places: int | None = None) -> str:
    if value is None:
        return "—"
    try:
        decimal_value = Decimal(str(value))
    except InvalidOperation:
        return str(value)
    if money:
        rounded = decimal_value.quantize(Decimal("0.01"))
        sign = "-" if rounded < ZERO else ""
        return f"{sign}${abs(rounded):,.2f}"
    if places is not None:
        return f"{decimal_value.quantize(Decimal(1).scaleb(-places)):,}"
    return _decimal_text(decimal_value) or "0"


def _markdown_percent(value: object) -> str:
    rendered = _markdown_value(value, places=2)
    return "—" if rendered == "—" else f"{rendered}%"


def render_markdown(report: Mapping[str, object]) -> str:
    """Render summaries and selected PnL values without raw rows or ticket IDs."""
    reconciliation = report["reconciliation"]  # type: ignore[index]
    performance = report["performance"]  # type: ignore[index]
    equity = report["closed_equity"]  # type: ignore[index]
    duration = report["duration"]  # type: ignore[index]
    overlap = report["overlap_dependence"]  # type: ignore[index]
    extra = report["extra_cost_sensitivity"]  # type: ignore[index]
    breakdowns = report["breakdowns"]  # type: ignore[index]
    quality = report["data_quality"]  # type: ignore[index]
    winners = ", ".join(_markdown_value(value, money=True) for value in performance["largest_winners_usd"]) or "—"  # type: ignore[index]
    losers = ", ".join(_markdown_value(value, money=True) for value in performance["largest_losers_usd"]) or "—"  # type: ignore[index]

    lines = [
        "# TradingView closed-trade analysis",
        "",
        f"- Source: `{report['source']['filename']}`",  # type: ignore[index]
        f"- Closed trades: {reconciliation['closed_trade_groups']} (financially analyzed: {reconciliation['financially_analyzed_closed_trades']})",  # type: ignore[index]
        f"- Net PnL: {_markdown_value(performance['net_pnl_usd'], money=True)}",  # type: ignore[index]
        f"- Reported commission: {_markdown_value(performance['reported_commission_usd'], money=True)}",  # type: ignore[index]
        f"- Profit factor: {_markdown_value(performance['profit_factor'], places=2)}",  # type: ignore[index]
        f"- Win rate: {_markdown_percent(performance['win_rate_pct'])}",  # type: ignore[index]
        f"- Largest winners (up to {performance['largest_value_count']}): {winners}.",  # type: ignore[index]
        f"- Largest losers (up to {performance['largest_value_count']}): {losers}.",  # type: ignore[index]
        f"- Closed-equity max drawdown: {_markdown_value(equity['max_closed_equity_drawdown_usd'], money=True)}",  # type: ignore[index]
        f"- Max chronological loss streak: {_markdown_value(equity['max_consecutive_losses'])}",  # type: ignore[index]
        "",
        "## Entry-path breakdown",
        "",
        "| Path | Trades | Net PnL | PF | Win rate |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for path, item in breakdowns["by_path"].items():  # type: ignore[index]
        lines.append(
            f"| {path} | {item['trade_count']} | {_markdown_value(item['net_pnl_usd'], money=True)} | "  # type: ignore[index]
            f"{_markdown_value(item['profit_factor'], places=2)} | {_markdown_percent(item['win_rate_pct'])} |"  # type: ignore[index]
        )
    lines.extend(
        [
            "",
            "## Trade structure",
            "",
            f"- Duration (bars): median {_markdown_value(duration['median_bars'], places=2)}, average {_markdown_value(duration['average_bars'], places=2)}.",  # type: ignore[index]
            f"- Maximum simultaneous positions among usable intervals: {_markdown_value(overlap['max_simultaneous_positions'])}; overlapping trade pairs: {_markdown_value(overlap['overlapping_trade_pairs'])}.",  # type: ignore[index]
            f"- Extra-cost sensitivity at {_markdown_value(extra['additional_round_trip_cost_per_contract_usd'], money=True)}/contract: "  # type: ignore[index]
            f"net PnL {_markdown_value(extra['net_pnl_after_extra_cost_usd'], money=True)}.",  # type: ignore[index]
            "",
            "## Data-quality notes",
            "",
            f"- Timestamp timezone status: {quality['timestamp_timezone_status']} (no session classification is inferred).",  # type: ignore[index]
            f"- Entry/exit ticket-ID mismatches: {quality['signal_attribution'].get('ticket_id_mismatch', 0)}.",  # type: ignore[index]
            f"- Quantity anomalies: {sum(quality['quantity_anomalies'].values())}.",  # type: ignore[index]
            f"- Invalid durations excluded: {duration['trades_with_invalid_reported_duration']}.",  # type: ignore[index]
            f"- Exact reconciliation: groups={reconciliation['groups_reconcile_exactly']}, rows={reconciliation['rows_reconcile_exactly']}.",  # type: ignore[index]
        ]
    )
    for warning in quality["warnings"]:  # type: ignore[index]
        lines.append(f"- Warning: {warning}")
    return "\n".join(lines) + "\n"


def _parse_nonnegative_decimal(value: str) -> Decimal:
    parsed, malformed = _parse_decimal(value)
    if malformed or parsed is None or parsed < ZERO:
        raise argparse.ArgumentTypeError("must be a non-negative decimal")
    return parsed


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", help="TradingView trade-list CSV export")
    parser.add_argument("--format", choices=("json", "markdown"), default="json", help="report format (default: json)")
    parser.add_argument(
        "--extra-cost-per-contract",
        type=_parse_nonnegative_decimal,
        default=ZERO,
        metavar="USD",
        help="additional round-trip USD cost per contract; does not re-charge reported commission",
    )
    parser.add_argument("--top", type=int, default=5, help="maximum winners and losers to list in either format (default: 5)")
    args = parser.parse_args(argv)
    if args.top < 1:
        parser.error("--top must be at least 1")
    try:
        report = analyze_csv(args.csv_path, extra_cost_per_contract=args.extra_cost_per_contract, top=args.top)
    except (CsvSchemaError, ValueError) as exc:
        parser.error(str(exc))

    if args.format == "json":
        json.dump(report, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(render_markdown(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
