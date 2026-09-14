"""Focused contracts for the active M5/M15 scalper.
The small reference models and source assertions below do not execute Pine or
TradingView backtests. They make no historical-performance or win-rate claims.
"""

from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))

from test_strategy_contract import (
    PIP, TICK, in_killzone, money, net_round_trip_result, news_blocked, partial_split,
    plan_has_valid_stop_and_tp1, risk_per_unit, risk_sized_quantity, split_is_valid, utc,
)

PINE_PATH = ROOT / "ict_xauusd_v6.pine"


@dataclass(frozen=True)
class Ohlc:
    open: Decimal
    high: Decimal
    low: Decimal
    close: Decimal


def bar(open_: object, high: object, low: object, close: object) -> Ohlc:
    return Ohlc(*(money(value) for value in (open_, high, low, close)))


def setup_event(side: int, candle: Ohlc, prior: tuple[Ohlc, ...], *, reference: object,
                slow: object, atr: object, was_pullback: bool = False, was_sweep: bool = False,
                touch_atr: object = "0.20", min_sweep_pips: object = "1") -> bool:
    """Reference only: fresh EMA-band visit or local prior-bar sweep."""
    ref, slow_ema, atr_value = money(reference), money(slow), money(atr)
    band = money(touch_atr) * atr_value
    touches_band = candle.low <= ref + band and candle.high >= ref - band
    pullback = touches_band and (candle.close > slow_ema if side == 1 else candle.close < slow_ema)
    prior_extreme = min(item.low for item in prior) if side == 1 else max(item.high for item in prior)
    sweep = (
        candle.low < prior_extreme - money(min_sweep_pips) * PIP and candle.close > prior_extreme
        if side == 1
        else candle.high > prior_extreme + money(min_sweep_pips) * PIP and candle.close < prior_extreme
    )
    return (pullback and not was_pullback) or (sweep and not was_sweep)


def trigger_confirmed(side: int, candle: Ohlc, previous: Ohlc, *, reference: object, atr: object) -> bool:
    """Reference only: directional trend reclaim plus a close-bar confirmation."""
    body = abs(candle.close - candle.open)
    candle_range = candle.high - candle.low
    if candle_range <= 0:
        return False
    directional = candle.close > candle.open if side == 1 else candle.close < candle.open
    reclaimed = candle.close > money(reference) if side == 1 else candle.close < money(reference)
    lower_wick = min(candle.open, candle.close) - candle.low
    upper_wick = candle.high - max(candle.open, candle.close)
    rejection = (
        lower_wick >= body and (candle.close - candle.low) / candle_range >= Decimal("0.6")
        if side == 1
        else upper_wick >= body and (candle.high - candle.close) / candle_range >= Decimal("0.6")
    )
    engulfing = (
        previous.close < previous.open and candle.open <= previous.close and candle.close >= previous.open
        if side == 1
        else previous.close > previous.open and candle.open >= previous.close and candle.close <= previous.open
    )
    previous_bar_break = candle.close > previous.high if side == 1 else candle.close < previous.low
    return directional and reclaimed and body >= Decimal("0.15") * money(atr) and (
        rejection or engulfing or previous_bar_break
    )


def active_signal(side: int, candle: Ohlc, previous: Ohlc, prior: tuple[Ohlc, ...], *, fast: object,
                  slow: object, reference: object, atr: object, htf_aligned: bool) -> bool:
    trend = money(fast) > money(slow) if side == 1 else money(fast) < money(slow)
    return (
        trend
        and htf_aligned
        and setup_event(side, candle, prior, reference=reference, slow=slow, atr=atr)
        and trigger_confirmed(side, candle, previous, reference=reference, atr=atr)
    )


def active_session(stamp: datetime) -> bool:
    stamp = stamp.astimezone(timezone.utc)
    return stamp.weekday() < 5 and 420 <= stamp.hour * 60 + stamp.minute < 1020
def active_window_allowed(events: list[datetime], start: datetime, end: datetime, *, reviewed: bool,
                          calendar_start: datetime, calendar_end: datetime, test_start: datetime,
                          test_end: datetime) -> bool:
    return (
        reviewed
        and start >= calendar_start
        and end <= calendar_end
        and start >= test_start
        and end <= test_end
        and active_session(start)
        and active_session(end)
        and not news_blocked(events, start, end)
    )
def daily_entry_allowed(day_pnl: object, start_equity: object, entries: int, losses_in_row: int) -> bool:
    return (
        money(start_equity) > 0
        and money(day_pnl) > -money(start_equity) * Decimal("0.02")
        and entries < 12
        and losses_in_row < 3
    )
def cooldown_ready(last_exit_bar: int | None, current_bar: int) -> bool:
    return last_exit_bar is None or current_bar - last_exit_bar >= 1
def exit_required(filled_at: datetime, bar_close: datetime, *, session_open: bool) -> bool:
    return bar_close - filled_at >= timedelta(minutes=60) or not session_open


def close_reaches_one_r(side: int, close: object, entry: object, risk: object) -> bool:
    return Decimal(side) * (money(close) - money(entry)) >= money(risk)


def counts_as_loss(net_at_start: object, net_when_flat: object) -> bool:
    return net_round_trip_result(net_at_start, net_when_flat) < 0


def entry_budget(equity: object, day_start_equity: object, day_pnl: object) -> Decimal:
    remaining = max(money(day_start_equity) * Decimal("0.02") + money(day_pnl), Decimal("0"))
    return min(money(equity) * Decimal("0.005"), remaining)


class ActiveScalperReferenceTests(unittest.TestCase):
    """Deterministic fixtures model rules only; they do not guarantee winning trades."""

    def test_planned_entry_budget_cannot_exceed_remaining_daily_risk(self) -> None:
        for equity, pnl, expected in (
            ("10000", "0", "50"),
            ("9810", "-190", "10"),
            ("9800", "-200", "0"),
            ("9790", "-210", "0"),
            ("10050", "50", "50.25"),
        ):
            with self.subTest(pnl=pnl):
                budget = entry_budget(equity, "10000", pnl)
                self.assertEqual(budget, money(expected))
                unit_risk = risk_per_unit("4633.30", "4630.80", point_value="1")
                qty = risk_sized_quantity(budget, unit_risk, "1")
                self.assertLessEqual(qty * unit_risk, budget)

    def test_ten_pip_plans_use_new_targets_but_fail_the_legacy_tp1_floor(self) -> None:
        for side, entry, stop, tp1, tp2 in (
            (1, "2400.00", "2399.00", "2401.20", "2402.00"),
            (-1, "2400.00", "2401.00", "2398.80", "2398.00"),
        ):
            with self.subTest(side=side):
                risk = Decimal(side) * (money(entry) - money(stop))
                self.assertEqual(risk / PIP, Decimal("10"))
                self.assertTrue(Decimal("10") * PIP <= risk <= Decimal("50") * PIP)
                self.assertEqual(money(entry) + Decimal(side) * Decimal("1.2") * risk, money(tp1))
                self.assertEqual(money(entry) + Decimal(side) * Decimal("2") * risk, money(tp2))
                self.assertLess(abs(money(tp1) - money(entry)), Decimal("80") * PIP)
                self.assertFalse(plan_has_valid_stop_and_tp1(entry, stop))
        self.assertTrue(plan_has_valid_stop_and_tp1("2400", "2396"))  # Legacy implied 40-pip floor.

    def test_half_percent_budget_includes_fees_slippage_and_fixed_partial(self) -> None:
        equity, entry, stop, step = Decimal("10000"), Decimal("2400"), Decimal("2398.50"), Decimal("1")
        budget = equity * Decimal("0.005")
        per_unit = risk_per_unit(entry, stop, point_value="1", slippage_ticks="2", tick_size=TICK)
        quantity = risk_sized_quantity(budget, per_unit, step)
        first, runner = partial_split(quantity, "70", step)
        self.assertEqual(budget, Decimal("50"))
        self.assertGreater(per_unit, abs(entry - stop))
        self.assertLessEqual(quantity * per_unit, budget)
        self.assertGreater((quantity + step) * per_unit, budget)
        self.assertTrue(split_is_valid(first, runner, quantity, step))
        self.assertTrue(Decimal("50") <= first * 100 / quantity <= Decimal("80"))

    def test_deterministic_ohlc_fixtures_accept_and_reject_both_directions(self) -> None:
        long_previous = bar("100.75", "100.80", "100.15", "100.20")
        long_prior = (bar("100.10", "100.40", "99.90", "100.20"), long_previous)
        long_ok = bar("100.30", "100.75", "99.70", "100.65")
        long_rejected = bar("100.00", "100.20", "99.80", "100.05")
        short_previous = bar("100.70", "101.20", "100.60", "101.10")
        short_prior = (bar("100.90", "101.20", "100.70", "101.00"), short_previous)
        short_ok = bar("101.10", "101.50", "100.50", "100.75")
        short_rejected = bar("101.00", "101.20", "100.80", "100.95")
        self.assertTrue(active_signal(1, long_ok, long_previous, long_prior, fast="101", slow="99", reference="100", atr="1", htf_aligned=True))
        self.assertFalse(active_signal(1, long_rejected, long_previous, long_prior, fast="101", slow="99", reference="100", atr="1", htf_aligned=True))
        self.assertTrue(active_signal(-1, short_ok, short_previous, short_prior, fast="100", slow="102", reference="101", atr="1", htf_aligned=True))
        self.assertFalse(active_signal(-1, short_rejected, short_previous, short_prior, fast="100", slow="102", reference="101", atr="1", htf_aligned=True))

    def test_setup_is_fresh_band_visit_or_local_sweep_not_a_duplicate(self) -> None:
        prior = (bar("100", "100.4", "99.9", "100.2"), bar("100.2", "100.5", "100.0", "100.3"))
        band_visit = bar("100.1", "100.3", "99.9", "100.2")
        local_sweep = bar("99.1", "99.96", "98.7", "99.95")
        self.assertTrue(setup_event(1, band_visit, prior, reference="100", slow="99", atr="1"))
        self.assertFalse(setup_event(1, band_visit, prior, reference="100", slow="99", atr="1", was_pullback=True))
        self.assertTrue(setup_event(1, local_sweep, prior, reference="100", slow="98", atr="0.1"))
        self.assertFalse(setup_event(1, local_sweep, prior, reference="100", slow="98", atr="0.1", was_sweep=True))

    def test_utc_news_coverage_continuous_session_and_exit_guards(self) -> None:
        monday = (2026, 9, 14)
        calendar_start, calendar_end = utc(*monday, 7, 0), utc(*monday, 17, 0)
        start, end = utc(*monday, 10, 30), utc(*monday, 10, 35)
        base = dict(calendar_start=calendar_start, calendar_end=calendar_end, test_start=utc(2026, 1, 1, 0, 0), test_end=utc(2026, 12, 31, 23, 59))
        self.assertTrue(active_session(start))
        self.assertFalse(in_killzone(start))  # Legacy strategy had the 10:00-12:00 gap.
        self.assertTrue(active_window_allowed([], start, end, reviewed=True, **base))
        self.assertFalse(active_window_allowed([], start, end, reviewed=False, **base))
        self.assertFalse(active_window_allowed([], start, end, reviewed=True, calendar_end=utc(*monday, 10, 34), **{key: value for key, value in base.items() if key != "calendar_end"}))
        event = utc(*monday, 12, 0)
        self.assertFalse(active_window_allowed([event], utc(*monday, 11, 45), utc(*monday, 11, 50), reviewed=True, **base))
        self.assertFalse(active_window_allowed([event], utc(*monday, 12, 15), utc(*monday, 12, 15), reviewed=True, **base))
        self.assertTrue(active_window_allowed([event], utc(*monday, 12, 16), utc(*monday, 12, 20), reviewed=True, **base))
        self.assertTrue(exit_required(utc(*monday, 15, 0), utc(*monday, 16, 0), session_open=True))
        self.assertTrue(exit_required(utc(*monday, 16, 55), utc(*monday, 17, 0), session_open=False))

    def test_daily_cooldown_close_be_and_negative_flat_results_remain_guards(self) -> None:
        self.assertTrue(daily_entry_allowed("0", "10000", 11, 0))
        self.assertFalse(daily_entry_allowed("0", "10000", 12, 0))
        self.assertFalse(daily_entry_allowed("-200", "10000", 0, 0))
        self.assertFalse(daily_entry_allowed("0", "10000", 0, 3))
        self.assertFalse(cooldown_ready(10, 10))
        self.assertTrue(cooldown_ready(10, 11))
        self.assertFalse(close_reaches_one_r(1, "100.99", "100", "1"))
        self.assertTrue(close_reaches_one_r(1, "101", "100", "1"))
        self.assertTrue(close_reaches_one_r(-1, "99", "100", "1"))
        for outcome, flat_net in (("ordinary", "999"), ("time exit", "999.60"), ("BE price after fees", "999.98")):
            with self.subTest(outcome=outcome):
                self.assertTrue(counts_as_loss("1000", flat_net))


class ActiveScalperSourceContracts(unittest.TestCase):
    """Text contracts only; they do not compile or execute the active Pine script."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.source = PINE_PATH.read_text(encoding="utf-8")
        cls.compact = re.sub(r"\s+", " ", cls.source)

    def test_active_timeframe_bias_risk_and_budget_contracts(self) -> None:
        self.assertTrue(self.source.startswith("//@version=6"))
        self.assertIn('strategy("XAUUSD Active Scalper M5-M15 v6"', self.source)
        self.assertIn('timeframe.multiplier != 5 and timeframe.multiplier != 15', self.source)
        self.assertIn('biasTf = autoBias ? (timeframe.multiplier == 5 ? "15" : "60")', self.source)
        self.assertIn('timeframe.in_seconds(biasTf) <= timeframe.in_seconds()', self.source)
        self.assertRegex(self.source, r"riskPercent = input\.float\(0\.5,.*maxval = 1")
        self.assertRegex(self.source, r"minStopPips = input\.float\(10\.0,.*SL minimum")
        self.assertRegex(self.source, r"maxStopPips = input\.float\(50\.0,.*maxval = 50")
        self.assertIn("bool riskOk = risk >= minStopPips * pipSize", self.source)
        self.assertRegex(self.source, r"partialPercent = input\.float\(70\.0,.*minval = 50, maxval = 80")
        self.assertIn("slippageTicks * syminfo.mintick", self.source)
        self.assertIn("commissionPercent / 100", self.source)
        self.assertIn("float qty = math.min(riskQty, affordableQty)", self.source)
        self.assertIn("float remainingDailyRisk = math.max(dayStartEquity * dailyLossPercent / 100 + dayPnl, 0)", self.source)
        self.assertIn("float budget = math.min(strategy.equity * riskPercent / 100, remainingDailyRisk)", self.source)
        self.assertIn("f_riskPerUnit(trade.entry, trade.initialStop) * trade.qty <= trade.riskBudget", self.compact)

    def test_target_setup_and_trigger_contracts_replace_legacy_pool(self) -> None:
        for formula in ("setup.side * tp1R * risk", "setup.side * tp2R * risk", "trade.side * tp1R * trade.risk", "trade.side * tp2R * trade.risk"):
            self.assertIn(formula, self.source)
        self.assertRegex(self.source, r"tp1R = input\.float\(1\.2,.*TP1 dalam R")
        self.assertRegex(self.source, r"tp2R = input\.float\(2\.0,.*TP2 dalam R")
        for legacy_name in ("minTp1Pips", "minRunnerR", "f_target"):
            self.assertNotIn(legacy_name, self.source)
        for contract in (
            "float previousLow = ta.lowest(low, sweepLookback)[1]",
            "float previousHigh = ta.highest(high, sweepLookback)[1]",
            "bool newBuyPullback = buyPullback and not buyPullback[1]",
            "bool newSellPullback = sellPullback and not sellPullback[1]",
            "bool newBuySweep = buySweep and not buySweep[1]",
            "bool newSellSweep = sellSweep and not sellSweep[1]",
            "bool buyBias = emaFast[1] > emaSlow[1]",
            "bool sellBias = emaFast[1] < emaSlow[1]",
            "if setup.side == 0 and not resetThisBar",
            "bool reclaimed = isBuy ? close > setup.reference : close < setup.reference",
            "bool trigger = directional and reclaimed and body >= minBodyAtr * atr[1] and (rejection or engulfing or minorBreak)",
        ):
            self.assertIn(contract, self.source)

    def test_utc_exit_daily_and_close_only_break_even_contracts(self) -> None:
        self.assertIn("calendarReviewed and startTime >= calendarStart and endTime <= calendarEnd", self.compact)
        for contract in (
            "bool continuous = minuteOfDay >= 420 and minuteOfDay < 1020",
            "eventTime < startTime - 15 * 60 * 1000",
            "eventTime > endTime + 15 * 60 * 1000",
            "maxHoldMinutes = input.int(60",
            "bool timeExit = time_close - filledAt >= maxHoldMinutes * 60 * 1000",
            "bool sessionExit = flatAtSessionEnd and not f_session(time_close)",
            "maxTradesDay = input.int(12, \"Batas posisi baru per hari GMT (bukan target)\"",
            "dailyLossPercent = input.float(2.0",
            "maxLosingStreak = input.int(3",
            "cooldownBars = input.int(1",
            "bool cooldownReady = na(lastExitBar) or bar_index - lastExitBar >= cooldownBars",
            "beAtR = input.float(1.0",
            "trade.side * (close - trade.entry) >= beAtR * trade.risk",
        ):
            self.assertIn(contract, self.source)
        self.assertNotRegex(self.source, r"else if trade\.side \* \((?:high|low) - trade\.entry\) >= beAtR")

    def test_fill_partial_flat_state_and_loss_contracts(self) -> None:
        for contract in (
            "bool firstObservedFill = not trade.filled and (strategy.position_size != 0 or newClosedLegs)",
            "if exitId == \"L-TP1\" or exitId == \"S-TP1\"",
            "if trade.filled and strategy.position_size == 0",
            "float netResult = strategy.netprofit - trade.netAtStart",
            "else if netResult < 0",
            "losers += 1",
            "trade := TradePlan.new()",
            "if not trade.firstLegClosed",
        ):
            self.assertIn(contract, self.source)
        for exit_id in ("L-TP1", "L-TP2", "S-TP1", "S-TP2"):
            self.assertIn(f'strategy.exit("{exit_id}"', self.source)
        self.assertEqual(self.source.count('strategy.exit("L-TP1"'), 1)
        self.assertEqual(self.source.count('strategy.exit("S-TP1"'), 1)
        self.assertIn('strategy.close_all(comment = reason', self.source)
if __name__ == "__main__":
    unittest.main()
