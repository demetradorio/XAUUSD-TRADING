"""Source contracts for the separate six-path port, not a TradingView backtest."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "xau_scalper_v3.pine").read_text()
PATHS = ("MAIN", "BOS", "OB", "RE", "TRAP", "OD")


class XauV3Contracts(unittest.TestCase):
    def test_separate_strategy_keeps_legacy_execution_defaults(self) -> None:
        self.assertTrue(SOURCE.startswith("//@version=6\n"))
        for contract in (
            'strategy("XAU Scalper v3 [BACKTEST]"', "initial_capital=15000",
            "default_qty_type=strategy.fixed", "default_qty_value=1", "pyramiding=20",
            "commission_type=strategy.commission.cash_per_contract", "commission_value=0.62",
            "slippage=2", "process_orders_on_close=false", "calc_on_every_tick=false",
            "currency=currency.USD", "margin_long=5", "margin_short=5",
        ):
            self.assertIn(contract, SOURCE)
        self.assertTrue((ROOT / "ict_xauusd_v6.pine").is_file())
        self.assertTrue((ROOT / "strategies/ict_strict_v6.pine").is_file())

    def test_all_twelve_entries_attach_same_ticket_id_brackets(self) -> None:
        entries = re.findall(r'strategy\.entry\("(\w+)_(L|S)_" \+ str\.tostring\(bar_index\), strategy\.(long|short)\)', SOURCE)
        self.assertEqual(entries, [(path, side, direction) for path in PATHS for side, direction in (("L", "long"), ("S", "short"))])
        for path, side, _ in entries:
            bracket = f'strategy.exit("{path}_{side}_X_" + str.tostring(bar_index), "{path}_{side}_" + str.tostring(bar_index), stop=activeSl, limit=activeTp)'
            self.assertEqual(SOURCE.count(bracket), 1)
        self.assertEqual(SOURCE.count("strategy.entry("), 12)
        self.assertEqual(SOURCE.count("strategy.exit("), 12)

    def test_every_entry_uses_common_gates_and_both_per_bar_latches(self) -> None:
        blocks = re.findall(r"^if can(Long|Short) ([^\n]+)\n((?:[ \t]+[^\n]*\n)+)", SOURCE, re.M)
        self.assertEqual(len(blocks), 12)
        for side, condition, body in blocks:
            self.assertIn("not longFiredThisBar and not shortFiredThisBar", condition)
            self.assertIn(f"if f_valid{side}Bracket(", body)
            self.assertIn("strategy.entry(", body)
        self.assertIn("bool canLong = orderDataReady and sessionAllowed and longsEnabled and not isShort", SOURCE)
        self.assertIn("bool canShort = orderDataReady and sessionAllowed and not isLong", SOURCE)
        self.assertIn("bool orderDataReady = barstate.isconfirmed and atr > 0 and not na(volume) and volume > 0", SOURCE)
        self.assertIn("bool sessionAllowed = ethEnabled or inRTH", SOURCE)

    def test_stop_cap_direction_atr_order_and_missing_profile_guards(self) -> None:
        self.assertIn("math.min(close - atr, math.max(close - atr * 3.0, rawSl))", SOURCE)
        self.assertIn("math.max(close + atr, math.min(close + atr * 3.0, rawSl))", SOURCE)
        self.assertIn("bool ethPovBlock = inETH and not na(povLevel) and povProxAtr < povBlockThresh", SOURCE)
        self.assertIn("for i = 0 to math.min(hvbLookback - 1, bar_index)", SOURCE)
        self.assertIn("if not na(close[i])", SOURCE)
        self.assertIn("if hvbTotalVol > 0", SOURCE)
        self.assertLess(SOURCE.index("atr = isOpen ?"), SOURCE.index("float aerMeanATR"))
        self.assertLess(SOURCE.index("atr = isOpen ?"), SOURCE.index("atrOk ="))
        self.assertNotRegex(SOURCE, r"^atr\s*:=", "ATR must not be changed after gates are computed")

    def test_missing_footprint_cannot_fabricate_extreme_flow_or_absorption(self) -> None:
        for contract in (
            "bool fpHasVolume = not na(fp) and fpBuyVol + fpSellVol > 0",
            "fpBuyRatio = fpHasVolume ? (fpSellVol > 0 ? fpBuyVol / fpSellVol : 99.0) : 1.0",
            "fpSellRatio = fpHasVolume ? (fpBuyVol > 0 ? fpSellVol / fpBuyVol : 99.0) : 1.0",
            "fpDeltaBull = fpHasVolume and fpDeltaSlope > 0",
            "fpDeltaBear = fpHasVolume and fpDeltaSlope < 0",
            "absHighVol = fpHasVolume and",
            "absDeltaFlat = fpHasVolume and",
        ):
            self.assertIn(contract, SOURCE)
        for line in SOURCE.splitlines():
            if line.startswith(("if canLong and bearSweep", "if canShort and bullSweep")):
                self.assertIn("and fpHasVolume and", line)
        self.assertIn("fpPocMid := na\nif fpHasVolume\n    volume_row pocRow = fp.poc()", SOURCE)
        self.assertIn("if not na(pocRow)\n        fpPocMid :=", SOURCE)

    def test_overnight_range_resets_at_session_start_not_calendar_midnight(self) -> None:
        self.assertIn('inOvernight = f_inSession("1500-0830")', SOURCE)
        self.assertIn("if inOvernight and not inOvernight[1]\n    onHigh := na\n    onLow := na", SOURCE)
        daily_resets = re.findall(r"^if isNewDay\n((?:[ \t]+[^\n]*\n)+)", SOURCE, re.M)
        self.assertTrue(daily_resets)
        for reset in daily_resets:
            self.assertNotIn("onHigh :=", reset)
            self.assertNotIn("onLow :=", reset)

    def test_orb_toggle_and_session_transition_lock(self) -> None:
        for signal in ("stratA_Long", "stratA_Short", "stratB_Long", "stratB_Short"):
            self.assertIn(f"{signal} = useORB and", SOURCE)
        self.assertIn("if not inORBBuild and inORBBuild[1]", SOURCE)
        self.assertNotRegex(SOURCE, r"time\([^\n]+\)\s*!=\s*0")

    def test_twenty_patterns_each_side_remain_diagnostic_not_live_exits(self) -> None:
        for name, end in (("f_exitBuyScore", "f_exitSellScore"), ("f_exitSellScore", "int exitBuyScore")):
            section = SOURCE.split(name + "() =>", 1)[1].split(end, 1)[0]
            patterns = re.findall(r"^    p(\d+) =", section, re.M)
            self.assertEqual(patterns, [str(i) for i in range(1, 21)])
        self.assertIn("bool smartExitL = false", SOURCE)
        self.assertIn("bool smartExitS = false", SOURCE)
        self.assertNotRegex(SOURCE, r"strategy\.(close|close_all|cancel|cancel_all)\(")
        self.assertIn('"Smart exits enabled: 0 = OFF"', SOURCE)


if __name__ == "__main__":
    unittest.main()
