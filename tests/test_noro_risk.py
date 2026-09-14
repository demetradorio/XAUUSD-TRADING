"""Reference arithmetic and source contracts, not a TradingView broker emulator."""

import math
from pathlib import Path
import unittest


SOURCE = (Path(__file__).resolve().parents[1] / "xauusd_trading_v2.pine").read_text()


def be_stop(entry, side, fee, slip_ticks, extra_ticks, tick):
    distance = (2 * entry * fee + extra_ticks * tick) / (1 - side * fee) + slip_ticks * tick
    return entry + side * math.ceil(distance / tick) * tick


def size(equity, risk_pct, remaining_daily, entry, distance, pointvalue, step, fee, slip, exposure=100):
    costs = ((2 * entry + distance) * fee + 2 * slip) * pointvalue
    unit_risk = distance * pointvalue + costs
    budget = min(equity * risk_pct / 100, remaining_daily)
    available = equity * exposure / 100 * 0.95 / (entry * pointvalue)
    qty = math.floor(min(budget / unit_risk, available) / step) * step
    return qty, unit_risk, budget


class NoroRiskArithmetic(unittest.TestCase):
    def test_be_covers_two_sided_fees_exit_slip_and_buffer(self):
        for side in (-1, 1):
            for entry in (100, 3000, 5000):
                for fee in (0, 0.00005, 0.001, 0.01):
                    with self.subTest(side=side, entry=entry, fee=fee):
                        stop = be_stop(entry, side, fee, 3, 2, 0.01)
                        exit_fill = stop - side * 0.03
                        net = side * (exit_fill - entry) - fee * (entry + exit_fill)
                        self.assertGreaterEqual(net + 1e-9, 0.02)

    def test_nominal_entry_is_not_net_break_even(self):
        entry = 3000
        self.assertLess(-(entry + entry) * 0.00005, 0)
        for side in (-1, 1):
            self.assertGreater(side * (be_stop(entry, side, 0.00005, 3, 2, 0.01) - entry), 0)

    def test_qty_rounds_down_to_budget_and_no_leverage(self):
        for pointvalue in (1, 100):
            for step in (0.01, 0.1, 1):
                for remaining in (0, 20, 500, 2000):
                    with self.subTest(pointvalue=pointvalue, step=step, remaining=remaining):
                        qty, unit_risk, budget = size(100000, 0.5, remaining, 3000, 30, pointvalue, step, 0.00005, 0.03)
                        self.assertGreaterEqual(qty, 0)
                        self.assertLessEqual(qty * unit_risk, budget + 1e-8)
                        self.assertLessEqual(qty * 3000 * pointvalue, 95000 + 1e-8)
                        self.assertAlmostEqual(qty / step, round(qty / step))

    def test_insufficient_budget_does_not_round_up(self):
        qty, _, _ = size(100, 0.5, 2, 3000, 10, 100, 1, 0.00005, 0.03)
        self.assertEqual(qty, 0)

    def test_daily_profits_do_not_expand_risk_budget(self):
        for day_pnl, expected in ((500, 2000), (0, 2000), (-1500, 500), (-2100, 0)):
            remaining = max(0, 100000 * 2 / 100 + min(day_pnl, 0))
            self.assertEqual(remaining, expected)


class NoroSourceContract(unittest.TestCase):
    def test_user_facing_strategy_name_and_original_credit(self):
        self.assertIn('strategy("XAUUSD Trading v2", shorttitle = "XAUUSD v2"', SOURCE)
        self.assertIn("Noro's Bands Scalper v1.6 (Noro, 2018)", SOURCE)

    def test_preserves_noro_price_channel_and_body_logic(self):
        for fragment in (
            "(ta.highest(close, length) + ta.lowest(close, length)) / 2",
            "ta.sma(math.abs(close - center), length)",
            "ta.ema(body, 30) / 10 * bodyLength",
            "candle == -1 and candle[1] == -1",
            "candle == 1 and candle[1] == 1",
        ):
            self.assertIn(fragment, SOURCE)

    def test_explicit_relative_brackets_and_safe_execution(self):
        self.assertEqual(SOURCE.count("loss = stopTicks, profit = targetTicks"), 2)
        self.assertEqual(SOURCE.count("stop = activeStop, limit = activeTarget"), 2)
        for fragment in (
            "process_orders_on_close = false", "calc_on_order_fills = false",
            "calc_on_every_tick = false", "pyramiding = 0", "if barstate.isconfirmed",
            "strategy.position_size == 0 and not planned", "bar_index - lastExitBar > cooldownBars",
            "qty >= qtyStep", "plannedDistance <= atr[1] * maxStopAtr",
            "syminfo.currency != \"USD\"", "margin_long = 100, margin_short = 100",
            "strategy.account_currency != \"USD\"", "currentInSession and nextOpenInSession",
        ):
            self.assertIn(fragment, SOURCE)
        self.assertNotIn("request.security", SOURCE)
        self.assertNotIn("qty_percent", SOURCE)

    def test_be_is_close_confirmed_and_stop_only_tightens(self):
        for fragment in (
            "side * (close - entry)", "favorableClose >= beTriggerR * riskDistance",
            "math.max(activeStop, bePrice)", "math.min(activeStop, bePrice)",
            "(2 * entry * feeRate + beExtraTicks * syminfo.mintick) / (1 - side * feeRate)",
            "riskCash = math.min(strategy.equity * riskPercent / 100, remainingDailyRisk)",
        ):
            self.assertIn(fragment, SOURCE)


if __name__ == "__main__":
    unittest.main()
