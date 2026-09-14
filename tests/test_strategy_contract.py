"""Reference-contract tests for ``ict_xauusd_v6.pine``.

These dependency-free tests model the documented financial and timing rules and
check focused Pine source contracts.  They do not compile Pine Script, execute
a TradingView backtest, or establish any historical or future win rate.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR
from pathlib import Path
import math
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
PINE_PATH = ROOT / "ict_xauusd_v6.pine"

PIP = Decimal("0.10")
TICK = Decimal("0.01")
UTC = timezone.utc
EPSILON = Decimal("0.000000001")


def money(value: object) -> Decimal:
    """Convert reference-model inputs without inheriting binary float noise."""
    return value if isinstance(value, Decimal) else Decimal(str(value))


def floor_to_step(value: Decimal, step: Decimal) -> Decimal:
    if step <= 0:
        raise ValueError("step must be positive")
    return (value / step).to_integral_value(rounding=ROUND_FLOOR) * step


def ceil_to_step(value: Decimal, step: Decimal) -> Decimal:
    if step <= 0:
        raise ValueError("step must be positive")
    return (value / step).to_integral_value(rounding=ROUND_CEILING) * step


def structural_stop(
    side: int,
    extreme: object,
    *,
    buffer_pips: object = "2",
    pip_size: Decimal = PIP,
    tick_size: Decimal = TICK,
) -> Decimal:
    """Place a stop outside the structural extreme and round away from it."""
    if side not in (1, -1):
        raise ValueError("side must be 1 (buy) or -1 (sell)")
    raw_stop = money(extreme) - Decimal(side) * money(buffer_pips) * pip_size
    return floor_to_step(raw_stop, tick_size) if side == 1 else ceil_to_step(raw_stop, tick_size)


def risk_in_pips(entry: object, stop: object, pip_size: Decimal = PIP) -> Decimal:
    return abs(money(entry) - money(stop)) / pip_size


def tp1_for(entry: object, stop: object, side: int) -> Decimal:
    risk = abs(money(entry) - money(stop))
    return money(entry) + Decimal(side) * Decimal("2") * risk


def plan_has_valid_stop_and_tp1(
    entry: object,
    stop: object,
    *,
    pip_size: Decimal = PIP,
    max_stop_pips: object = "50",
    min_tp1_pips: object = "80",
) -> bool:
    risk = abs(money(entry) - money(stop))
    return (
        risk > 0
        and risk <= money(max_stop_pips) * pip_size
        and Decimal("2") * risk >= money(min_tp1_pips) * pip_size
    )


def select_liquidity_target(
    levels: list[object],
    side: int,
    entry: object,
    risk: object,
    minimum_rr: object = "3",
    *,
    tick_size: Decimal = TICK,
    tolerance_ticks: object = "0.001",
) -> Decimal | None:
    """Choose the nearest qualifying observed liquidity level; never invent one."""
    selected: Decimal | None = None
    entry_value = money(entry)
    risk_value = money(risk)
    if side not in (1, -1) or risk_value <= 0:
        return None
    for raw_level in levels:
        level = money(raw_level)
        reward = Decimal(side) * (level - entry_value)
        if reward >= money(minimum_rr) * risk_value - tick_size * money(tolerance_ticks) and (
            selected is None or reward < Decimal(side) * (selected - entry_value)
        ):
            selected = level
    return selected


def ote_levels(side: int, sweep: object, range_end: object) -> tuple[Decimal, Decimal, Decimal, Decimal]:
    """Return OTE low/high, 0.705 sweet spot, and equilibrium for either side."""
    if side not in (1, -1):
        raise ValueError("side must be 1 (buy) or -1 (sell)")
    sweep_value = money(sweep)
    end_value = money(range_end)
    dealing_range = abs(end_value - sweep_value)
    if side == 1:
        low = end_value - Decimal("0.786") * dealing_range
        high = end_value - Decimal("0.618") * dealing_range
    else:
        low = end_value + Decimal("0.618") * dealing_range
        high = end_value + Decimal("0.786") * dealing_range
    sweet = end_value - Decimal(side) * Decimal("0.705") * dealing_range
    equilibrium = (end_value + sweep_value) / Decimal("2")
    return low, high, sweet, equilibrium


def risk_per_unit(
    entry: object,
    stop: object,
    *,
    point_value: object,
    slippage_ticks: object = "2",
    tick_size: Decimal = TICK,
    commission_percent: object = "0.001",
) -> Decimal:
    """Cash risk of one strategy quantity unit, including both stated reserves."""
    entry_value = money(entry)
    stop_value = money(stop)
    stop_loss = abs(entry_value - stop_value) + money(slippage_ticks) * tick_size
    fees = (abs(entry_value) + abs(stop_value)) * money(commission_percent) / Decimal("100")
    return (stop_loss + fees) * money(point_value)


def broker_qty_step(min_contract: object, point_value: object, override: object = "0") -> Decimal:
    min_contract_value = money(min_contract)
    point_value_value = money(point_value)
    override_value = money(override)
    if min_contract_value <= 0 or point_value_value <= 0:
        raise ValueError("contract minimum and point value must be positive")
    requested = override_value if override_value > 0 else max(min_contract_value, Decimal("1") / point_value_value)
    return ceil_to_step(requested, min_contract_value)


def risk_sized_quantity(budget: object, per_unit: object, qty_step: object) -> Decimal:
    budget_value = money(budget)
    per_unit_value = money(per_unit)
    step_value = money(qty_step)
    return Decimal("0") if per_unit_value <= 0 else floor_to_step(budget_value / per_unit_value, step_value)


def affordable_quantity(
    equity: object,
    entry: object,
    point_value: object,
    qty_step: object,
    *,
    reserve: object = "0.9",
    margin_fraction: object = "0.05",
) -> Decimal:
    denominator = money(entry) * money(point_value) * money(margin_fraction)
    return Decimal("0") if denominator <= 0 else floor_to_step(money(equity) * money(reserve) / denominator, money(qty_step))


def partial_split(qty: object, partial_percent: object, qty_step: object) -> tuple[Decimal, Decimal]:
    qty_value = money(qty)
    step_value = money(qty_step)
    first = floor_to_step(qty_value * money(partial_percent) / Decimal("100") + EPSILON * step_value, step_value)
    return first, qty_value - first


def split_is_valid(first: Decimal, runner: Decimal, total: Decimal, step: Decimal) -> bool:
    return (
        total > 0
        and first >= step
        and runner >= step
        and first / total >= Decimal("0.5")
        and first / total <= Decimal("0.8")
        and first + runner == total
    )


def active_stop(side: int, entry: object, initial_stop: object, break_even: bool) -> Decimal:
    if side not in (1, -1):
        raise ValueError("side must be 1 (buy) or -1 (sell)")
    return money(entry) if break_even else money(initial_stop)


def utc(year: int, month: int, day: int, hour: int, minute: int) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=UTC)


def in_killzone(stamp: datetime, *, london: bool = True, new_york: bool = True, overlap: bool = True) -> bool:
    stamp = stamp.astimezone(UTC)
    if stamp.weekday() > 4:
        return False
    minute_of_day = stamp.hour * 60 + stamp.minute
    return (
        (london and 420 <= minute_of_day < 600)
        or (new_york and 720 <= minute_of_day < 900)
        or (overlap and 780 <= minute_of_day < 1020)
    )


def news_blocked(events: list[datetime], start: datetime, end: datetime) -> bool:
    """A bar is blocked when it intersects an inclusive +/- 15-minute blackout."""
    blackout = timedelta(minutes=15)
    return any(start - blackout <= event <= end + blackout for event in events)


def window_allowed(
    events: list[datetime],
    start: datetime,
    end: datetime,
    *,
    calendar_reviewed: bool,
    calendar_start: datetime,
    calendar_end: datetime,
    test_start: datetime,
    test_end: datetime,
    london: bool = True,
    new_york: bool = True,
    overlap: bool = True,
) -> bool:
    return (
        calendar_reviewed
        and start >= calendar_start
        and end <= calendar_end
        and start >= test_start
        and end <= test_end
        and in_killzone(start, london=london, new_york=new_york, overlap=overlap)
        and in_killzone(end, london=london, new_york=new_york, overlap=overlap)
        and not news_blocked(events, start, end)
    )


def actual_fill_allowed(
    side: int,
    entry: object,
    equilibrium: object,
    chase_boundary: object,
    *,
    market_order: bool,
    fill_time_allowed: bool,
) -> bool:
    """Revalidate the actual fill price and time, not just the order plan."""
    if side not in (1, -1):
        raise ValueError("side must be 1 (buy) or -1 (sell)")
    entry_value = money(entry)
    half_ok = entry_value < money(equilibrium) if side == 1 else entry_value > money(equilibrium)
    chase_ok = not market_order or (
        entry_value <= money(chase_boundary) if side == 1 else entry_value >= money(chase_boundary)
    )
    return fill_time_allowed and half_ok and chase_ok


NEWS_LINE = re.compile(r"^([0-9]{4})-([0-9]{2})-([0-9]{2}) ([0-9]{2}):([0-9]{2})$")


def parse_news_schedule(schedule: str) -> list[datetime]:
    """Strict UTC schedule parser equivalent to the documented input contract."""
    events: list[datetime] = []
    for raw_line in schedule.splitlines():
        text = raw_line.strip()
        if not text:
            continue
        match = NEWS_LINE.fullmatch(text)
        if match is None:
            raise ValueError("news must use YYYY-MM-DD HH:mm UTC")
        year, month, day, hour, minute = (int(part) for part in match.groups())
        if not 1970 <= year <= 2099:
            raise ValueError("news year is outside the supported range")
        try:
            events.append(utc(year, month, day, hour, minute))
        except ValueError as error:
            raise ValueError("news contains an invalid calendar date") from error
        if len(events) > 500:
            raise ValueError("too many news events")
    return sorted(events)


PHASE_REQUIREMENTS = ("sweep", "mss_and_displacement", "fvg_and_confluence", "zone_touch", "rejection")


def advance_phase(phase: int, checks: dict[str, bool]) -> int:
    """Reference five-stage gate: one satisfied prerequisite advances one stage."""
    if 0 <= phase < len(PHASE_REQUIREMENTS) and checks[PHASE_REQUIREMENTS[phase]]:
        return phase + 1
    return phase


def net_round_trip_result(net_at_start: object, net_when_flat: object) -> Decimal:
    return money(net_when_flat) - money(net_at_start)


def round_trip_is_profitable(net_at_start: object, net_when_flat: object) -> bool:
    return net_round_trip_result(net_at_start, net_when_flat) > 0


def wilson_lower_bound(successes: int, count: int) -> float | None:
    if count <= 0:
        return None
    if successes < 0 or successes > count:
        raise ValueError("successes must be within count")
    z = 1.96
    proportion = successes / count
    numerator = proportion + z * z / (2 * count) - z * math.sqrt(
        (proportion * (1 - proportion) + z * z / (4 * count)) / count
    )
    return 100 * numerator / (1 + z * z / count)


class ReferenceContractFinancialTests(unittest.TestCase):
    """Reference-contract tests only; these are not a native Pine backtest."""

    def test_reference_contract_structural_stops_are_outward_and_tick_aligned(self) -> None:
        buy_stop = structural_stop(1, "4628.004")
        sell_stop = structural_stop(-1, "4628.004")

        self.assertEqual(buy_stop, Decimal("4627.80"))
        self.assertEqual(sell_stop, Decimal("4628.21"))
        self.assertLess(buy_stop, Decimal("4628.004") - Decimal("2") * PIP)
        self.assertGreater(sell_stop, Decimal("4628.004") + Decimal("2") * PIP)
        self.assertEqual(buy_stop % TICK, 0)
        self.assertEqual(sell_stop % TICK, 0)

    def test_reference_contract_user_example_is_rejected_by_max_stop(self) -> None:
        entry = Decimal("4633.30")
        correct_stop = structural_stop(1, "4628.00")

        self.assertEqual(correct_stop, Decimal("4627.80"))
        self.assertEqual(risk_in_pips(entry, correct_stop), Decimal("55"))
        self.assertFalse(plan_has_valid_stop_and_tp1(entry, correct_stop))

    def test_reference_contract_tp1_is_exactly_2r_with_implied_risk_floor(self) -> None:
        buy_entry, buy_stop = Decimal("4633.30"), Decimal("4629.30")
        sell_entry, sell_stop = Decimal("4633.30"), Decimal("4637.30")
        fifty_pip_stop = Decimal("4628.30")

        self.assertEqual(tp1_for(buy_entry, buy_stop, 1), Decimal("4641.30"))
        self.assertEqual(tp1_for(sell_entry, sell_stop, -1), Decimal("4625.30"))
        self.assertEqual(risk_in_pips(buy_entry, buy_stop), Decimal("40"))
        self.assertEqual(risk_in_pips(buy_entry, fifty_pip_stop), Decimal("50"))
        self.assertTrue(plan_has_valid_stop_and_tp1(buy_entry, buy_stop, min_tp1_pips="80"))
        self.assertFalse(plan_has_valid_stop_and_tp1("4633.30", "4629.31", min_tp1_pips="80"))
        self.assertTrue(plan_has_valid_stop_and_tp1(buy_entry, fifty_pip_stop, min_tp1_pips="100"))
        self.assertFalse(plan_has_valid_stop_and_tp1("4633.30", "4628.31", min_tp1_pips="100"))

    def test_reference_contract_tp2_uses_real_level_and_requires_three_r(self) -> None:
        entry = Decimal("4633.30")
        risk = Decimal("4.30")
        original_target = Decimal("4646.00")
        three_r_target = entry + Decimal("3") * risk
        one_thousandth_tick = TICK * Decimal("0.001")

        self.assertLess((original_target - entry) / risk, Decimal("3"))
        self.assertIsNone(select_liquidity_target([original_target], 1, entry, risk))
        self.assertEqual(one_thousandth_tick, Decimal("0.00001"))
        self.assertEqual(
            select_liquidity_target([three_r_target - one_thousandth_tick], 1, entry, risk),
            three_r_target - one_thousandth_tick,
        )
        self.assertIsNone(
            select_liquidity_target([three_r_target - one_thousandth_tick - Decimal("0.000001")], 1, entry, risk)
        )
        self.assertEqual(
            select_liquidity_target(["4648.00", "4646.20", "4650.00"], 1, entry, risk),
            Decimal("4646.20"),
        )
        self.assertEqual(
            select_liquidity_target(["4620.00", "4619.50", "4621.00"], -1, entry, risk),
            Decimal("4620.00"),
        )

    def test_reference_contract_ote_is_mirrored_for_buy_and_sell(self) -> None:
        buy_low, buy_high, buy_sweet, buy_equilibrium = ote_levels(1, "4628", "4646")
        sell_low, sell_high, sell_sweet, sell_equilibrium = ote_levels(-1, "4646", "4628")

        self.assertEqual((buy_low, buy_high, buy_sweet, buy_equilibrium), (
            Decimal("4631.852"), Decimal("4634.876"), Decimal("4633.310"), Decimal("4637")
        ))
        self.assertEqual((sell_low, sell_high, sell_sweet, sell_equilibrium), (
            Decimal("4639.124"), Decimal("4642.148"), Decimal("4640.690"), Decimal("4637")
        ))
        self.assertLess(buy_low, buy_sweet)
        self.assertLess(buy_sweet, buy_high)
        self.assertLess(sell_low, sell_sweet)
        self.assertLess(sell_sweet, sell_high)
        self.assertLess(buy_sweet, buy_equilibrium)
        self.assertGreater(sell_sweet, sell_equilibrium)

    def test_reference_contract_risk_sizing_uses_symbol_units_and_reserves(self) -> None:
        entry, stop, budget = Decimal("4633.30"), Decimal("4629.00"), Decimal("100")
        per_ounce = risk_per_unit(entry, stop, point_value="1")
        qty_step = broker_qty_step("0.01", "1")
        risk_qty = risk_sized_quantity(budget, per_ounce, qty_step)
        affordable_qty = affordable_quantity("10000", entry, "1", qty_step)

        self.assertEqual(per_ounce, Decimal("4.412623"))
        self.assertEqual(qty_step, Decimal("1"))
        self.assertEqual(risk_qty, Decimal("22"))
        self.assertEqual(Decimal("22") / Decimal("100"), Decimal("0.22"))
        self.assertLess(risk_qty * per_ounce, budget)
        self.assertGreater((risk_qty + qty_step) * per_ounce, budget)
        self.assertGreater(affordable_qty, risk_qty)

    def test_reference_contract_qty_step_and_partial_legs_preserve_fixed_units(self) -> None:
        cases = (
            (Decimal("22"), Decimal("1"), Decimal("70")),
            (Decimal("1.00"), Decimal("0.01"), Decimal("50")),
            (Decimal("1.00"), Decimal("0.01"), Decimal("80")),
        )
        for total, step, percent in cases:
            with self.subTest(total=total, step=step, percent=percent):
                first, runner = partial_split(total, percent, step)
                self.assertTrue(split_is_valid(first, runner, total, step))
                self.assertEqual(first + runner, total)
                self.assertEqual(first % step, 0)
                self.assertEqual(runner % step, 0)

        self.assertEqual(broker_qty_step("0.25", "3"), Decimal("0.50"))
        first, runner = partial_split("1", "70", "1")
        self.assertFalse(split_is_valid(first, runner, Decimal("1"), Decimal("1")))

    def test_reference_contract_bep_replaces_the_same_stop_for_both_sides(self) -> None:
        for side, entry, initial_stop in ((1, "4633.30", "4629.00"), (-1, "4633.30", "4637.60")):
            with self.subTest(side=side):
                self.assertEqual(active_stop(side, entry, initial_stop, False), money(initial_stop))
                self.assertEqual(active_stop(side, entry, initial_stop, True), money(entry))

    def test_reference_contract_actual_fill_rechecks_time_half_and_chasing_for_both_sides(self) -> None:
        fill_time = utc(2026, 9, 14, 7, 30)
        time_ok = window_allowed(
            [], fill_time, fill_time, calendar_reviewed=True,
            calendar_start=utc(2026, 9, 14, 7, 0), calendar_end=utc(2026, 9, 14, 10, 0),
            test_start=utc(2026, 1, 1, 0, 0), test_end=utc(2026, 12, 31, 23, 59),
        )
        blocked_time = window_allowed(
            [fill_time], fill_time, fill_time, calendar_reviewed=True,
            calendar_start=utc(2026, 9, 14, 7, 0), calendar_end=utc(2026, 9, 14, 10, 0),
            test_start=utc(2026, 1, 1, 0, 0), test_end=utc(2026, 12, 31, 23, 59),
        )

        self.assertTrue(time_ok)
        self.assertFalse(blocked_time)
        self.assertTrue(actual_fill_allowed(1, "4633", "4637", "4635", market_order=True, fill_time_allowed=time_ok))
        self.assertTrue(actual_fill_allowed(-1, "4641", "4637", "4639", market_order=True, fill_time_allowed=time_ok))
        self.assertFalse(actual_fill_allowed(1, "4636", "4636", "4636", market_order=True, fill_time_allowed=time_ok))
        self.assertFalse(actual_fill_allowed(-1, "4638", "4637", "4639", market_order=True, fill_time_allowed=time_ok))
        self.assertTrue(actual_fill_allowed(1, "4635.01", "4637", "4635", market_order=False, fill_time_allowed=time_ok))
        self.assertFalse(actual_fill_allowed(1, "4633", "4637", "4635", market_order=True, fill_time_allowed=blocked_time))


class ReferenceContractTimeTests(unittest.TestCase):
    """UTC timing reference-contract tests only; no external calendar is queried."""

    def test_reference_contract_killzone_union_and_toggle_boundaries(self) -> None:
        monday = (2026, 9, 14)
        self.assertTrue(in_killzone(utc(*monday, 7, 0)))
        self.assertFalse(in_killzone(utc(*monday, 10, 0)))
        self.assertTrue(in_killzone(utc(*monday, 12, 0)))
        self.assertTrue(in_killzone(utc(*monday, 13, 0)))
        self.assertTrue(in_killzone(utc(*monday, 15, 0)))
        self.assertFalse(in_killzone(utc(*monday, 17, 0)))
        self.assertFalse(in_killzone(utc(2026, 9, 19, 13, 0)))

        self.assertTrue(in_killzone(utc(*monday, 9, 59), london=True, new_york=False, overlap=False))
        self.assertFalse(in_killzone(utc(*monday, 10, 0), london=True, new_york=False, overlap=False))
        self.assertTrue(in_killzone(utc(*monday, 12, 0), london=False, new_york=True, overlap=False))
        self.assertFalse(in_killzone(utc(*monday, 15, 0), london=False, new_york=True, overlap=False))
        self.assertTrue(in_killzone(utc(*monday, 13, 0), london=False, new_york=False, overlap=True))
        self.assertFalse(in_killzone(utc(*monday, 17, 0), london=False, new_york=False, overlap=True))

    def test_reference_contract_news_blackout_is_inclusive_for_m1_and_m5(self) -> None:
        event = utc(2026, 9, 14, 13, 0)
        for minutes in (1, 5):
            with self.subTest(timeframe=f"M{minutes}"):
                self.assertTrue(news_blocked([event], utc(2026, 9, 14, 12, 45 - minutes), utc(2026, 9, 14, 12, 45)))
                self.assertTrue(news_blocked([event], utc(2026, 9, 14, 13, 15), utc(2026, 9, 14, 13, 15 + minutes)))
                self.assertFalse(news_blocked([event], utc(2026, 9, 14, 13, 15 + minutes), utc(2026, 9, 14, 13, 15 + 2 * minutes)))

    def test_reference_contract_calendar_acknowledgement_and_coverage_gate_entries(self) -> None:
        start, end = utc(2026, 9, 14, 7, 30), utc(2026, 9, 14, 7, 31)
        calendar_start, calendar_end = utc(2026, 9, 14, 7, 0), utc(2026, 9, 14, 10, 0)
        test_start, test_end = utc(2026, 1, 1, 0, 0), utc(2026, 12, 31, 23, 59)

        kwargs = dict(
            events=[], start=start, end=end, calendar_start=calendar_start, calendar_end=calendar_end,
            test_start=test_start, test_end=test_end,
        )
        self.assertFalse(window_allowed(calendar_reviewed=False, **kwargs))
        self.assertTrue(window_allowed(calendar_reviewed=True, **kwargs))
        self.assertFalse(window_allowed(calendar_reviewed=True, calendar_start=utc(2026, 9, 14, 7, 31), **{key: value for key, value in kwargs.items() if key != "calendar_start"}))
        self.assertFalse(window_allowed(calendar_reviewed=True, calendar_end=utc(2026, 9, 14, 7, 30), **{key: value for key, value in kwargs.items() if key != "calendar_end"}))
        self.assertFalse(window_allowed(calendar_reviewed=True, test_end=utc(2026, 9, 14, 7, 30), **{key: value for key, value in kwargs.items() if key != "test_end"}))

    def test_reference_contract_news_parser_rejects_malformed_and_invalid_leap_dates(self) -> None:
        self.assertEqual(
            parse_news_schedule("2024-03-01 12:00\n2024-02-29 13:30"),
            [utc(2024, 2, 29, 13, 30), utc(2024, 3, 1, 12, 0)],
        )
        malformed = (
            "2024/02/29 13:30",
            "2024-2-29 13:30",
            "2024-02-29 3:30",
            "2024-02-29 13:3",
            "2024-02-29T13:30",
            "2024-02-29 24:00",
            "2024-02-29 13:60",
            "2023-02-29 13:30",
            "2024-04-31 13:30",
            "1969-12-31 23:59",
            "2100-02-29 13:30",
        )
        for text in malformed:
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    parse_news_schedule(text)


class ReferenceContractOutcomeTests(unittest.TestCase):
    """Outcome reference-contract tests only; hypothetical counts are not performance claims."""

    def test_reference_contract_phases_advance_in_order_without_skips(self) -> None:
        checks = {name: True for name in PHASE_REQUIREMENTS}
        phase = 0
        for expected in range(1, len(PHASE_REQUIREMENTS) + 1):
            phase = advance_phase(phase, checks)
            self.assertEqual(phase, expected)

        for missing_index, missing in enumerate(PHASE_REQUIREMENTS):
            with self.subTest(missing=missing):
                checks = {name: True for name in PHASE_REQUIREMENTS}
                checks[missing] = False
                phase = 0
                for _ in PHASE_REQUIREMENTS:
                    phase = advance_phase(phase, checks)
                self.assertEqual(phase, missing_index)

    def test_reference_contract_round_trip_net_delta_avoids_partial_leg_win_counting(self) -> None:
        net_at_start = Decimal("1000")
        net_after_first_partial = Decimal("1040")
        net_when_flat = Decimal("980")
        hypothetical_partial_legs = (Decimal("40"), Decimal("-60"))
        partial_leg_positive_fraction = sum(leg > 0 for leg in hypothetical_partial_legs) / len(hypothetical_partial_legs)

        self.assertGreater(net_after_first_partial - net_at_start, 0)
        self.assertEqual(partial_leg_positive_fraction, 0.5)
        self.assertEqual(net_round_trip_result(net_at_start, net_when_flat), Decimal("-20"))
        self.assertFalse(round_trip_is_profitable(net_at_start, net_when_flat))
        self.assertTrue(round_trip_is_profitable(net_at_start, Decimal("1001")))

    def test_reference_contract_wilson_lower_bound_is_a_sample_gate_not_a_performance_result(self) -> None:
        self.assertIsNone(wilson_lower_bound(0, 0))
        self.assertAlmostEqual(wilson_lower_bound(30, 30) or 0, 88.6483, places=3)
        self.assertLess(wilson_lower_bound(18, 30) or 100, 50)
        self.assertLess(wilson_lower_bound(59, 100) or 100, 50)
        self.assertGreater(wilson_lower_bound(60, 100) or 0, 50)


class PineSourceSafetyContracts(unittest.TestCase):
    """Focused source contracts; these checks are not native Pine compilation."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.source = PINE_PATH.read_text(encoding="utf-8")
        cls.compact_source = re.sub(r"\s+", " ", cls.source)

    def section(self, start: str, end: str) -> str:
        start_index = self.source.index(start)
        end_index = self.source.index(end, start_index)
        return self.source[start_index:end_index]

    def test_source_contract_declares_v6_and_hard_risk_caps(self) -> None:
        self.assertTrue(self.source.startswith("//@version=6"))
        self.assertRegex(self.source, r"float riskPercent = input\.float\(1\.0,.*?maxval = 1")
        self.assertRegex(self.source, r"float stopBufferPips = input\.float\(2\.0,.*?minval = 2, maxval = 3")
        self.assertRegex(self.source, r"float maxStopPips = input\.float\(50\.0,.*?maxval = 50")
        self.assertRegex(self.source, r"float minTp1Pips = input\.float\(80\.0,.*?minval = 80, maxval = 100")
        self.assertRegex(self.source, r"float partialPercent = input\.float\(70\.0,.*?minval = 50, maxval = 80")
        self.assertRegex(self.source, r"float minRunnerR = input\.float\(3\.0,.*?minval = 3, maxval = 5")
        self.assertRegex(self.source, r"float bePips = input\.float\(45\.0,.*?minval = 45, maxval = 50")
        self.assertIn("bool stopOk = risk > 0 and risk <= maxStopPips * pipSize", self.compact_source)
        self.assertIn("bool tp1Ok = 2 * risk >= minTp1Pips * pipSize", self.compact_source)

    def test_source_contract_structural_stop_and_tp1_match_reference_semantics(self) -> None:
        stop_helper = self.section("f_structuralStop", "f_riskPerUnit")
        self.assertIn("float pipSize = input.float(0.10", self.source)
        self.assertIn("pipSize < syminfo.mintick", self.source)
        self.assertIn("float rawStop = extreme - side * stopBufferPips * pipSize", stop_helper)
        self.assertIn("math.floor(rawStop / syminfo.mintick) * syminfo.mintick", stop_helper)
        self.assertIn("math.ceil(rawStop / syminfo.mintick) * syminfo.mintick", stop_helper)
        self.assertIn("trade.tp1 := f_roundPrice(entry + setup.side * 2 * risk)", self.source)
        self.assertIn("trade.tp1 := f_roundPrice(trade.entry + trade.side * 2 * trade.risk)", self.source)

    def test_source_contract_ote_and_real_liquidity_targets_are_preserved(self) -> None:
        setup_section = self.section("bool gapValid", "bool drawSetup")
        target_helper = self.section("f_target", "f_confirmedPivots")
        self.assertIn("setup.oteLow := isBuy ? rangeEnd - 0.786 * dealingRange : rangeEnd + 0.618 * dealingRange", setup_section)
        self.assertIn("setup.oteHigh := isBuy ? rangeEnd - 0.618 * dealingRange : rangeEnd + 0.786 * dealingRange", setup_section)
        self.assertIn("setup.sweet := rangeEnd - setup.side * 0.705 * dealingRange", setup_section)
        self.assertIn("for level in pool", target_helper)
        self.assertIn("reward >= minRunnerR * risk - syminfo.mintick * 0.001", target_helper)
        self.assertIn("selected := level", target_helper)
        self.assertIn("float target = f_target(isBuy ? buyTargets : sellTargets, setup.side, entry, risk)", setup_section)
        self.assertIn("bool fillTargetOk = trade.risk > 0 and trade.side * (trade.tp2 - trade.entry) >= minRunnerR * trade.risk - syminfo.mintick * 0.001", self.source)
        self.assertIn("f_addPool(buyTargets, h1High, 1)", self.source)
        self.assertIn("f_addPool(sellTargets, h1Low, -1)", self.source)
        self.assertIn("f_addPool(buyTargets, h4High, 1)", self.source)
        self.assertIn("f_addPool(sellTargets, h4Low, -1)", self.source)
        self.assertNotRegex(setup_section, r"float target\s*=\s*entry\s*\+\s*setup\.side\s*\*\s*minRunnerR")

    def test_source_contract_qty_is_floor_sized_in_symbol_units_with_reserves(self) -> None:
        risk_helper = self.section("f_riskPerUnit", "f_prunePool")
        sizing_section = self.section("float minContract", "bool sizingOk")
        self.assertIn("slippageTicks * syminfo.mintick", risk_helper)
        self.assertIn("commissionPercent / 100", risk_helper)
        self.assertIn("* syminfo.pointvalue", risk_helper)
        self.assertIn("commission_value = 0.001", self.source)
        self.assertIn("slippage = 2", self.source)
        self.assertIn("math.max(minContract, 1.0 / syminfo.pointvalue)", sizing_section)
        self.assertIn("math.ceil(requestedStep / minContract) * minContract", sizing_section)
        self.assertIn("math.floor(budget / perUnit / qtyStep) * qtyStep", sizing_section)
        self.assertIn("math.floor(strategy.equity * 0.9 / (entry * syminfo.pointvalue * 0.05) / qtyStep) * qtyStep", sizing_section)
        self.assertIn("float firstQty = math.floor(qty * partialPercent / 100 / qtyStep + 1e-9) * qtyStep", sizing_section)
        self.assertIn("float runnerQty = qty - firstQty", sizing_section)
        self.assertIn("trade.qty * syminfo.pointvalue / 100", self.source)

    def test_source_contract_time_filter_has_utc_union_inclusive_blackout_and_coverage(self) -> None:
        killzone_helper = self.section("f_killzone", "f_newsBlocked")
        news_helper = self.section("f_newsBlocked", "f_windowAllowed")
        window_helper = self.section("f_windowAllowed", "f_inside")
        self.assertIn("weekday >= dayofweek.monday and weekday <= dayofweek.friday", killzone_helper)
        for bounds in (("420", "600"), ("720", "900"), ("780", "1020")):
            self.assertIn(f"minuteOfDay >= {bounds[0]} and minuteOfDay < {bounds[1]}", killzone_helper)
        self.assertIn("eventTime < startTime - 15 * 60 * 1000", news_helper)
        self.assertIn("eventTime > endTime + 15 * 60 * 1000", news_helper)
        self.assertIn("calendarReviewed and startTime >= calendarStart and endTime <= calendarEnd", window_helper)
        self.assertIn("startTime >= testStart and endTime <= testEnd", window_helper)
        self.assertIn("f_killzone(startTime) and f_killzone(endTime)", window_helper)
        self.assertIn("timeframe.multiplier != 1 and timeframe.multiplier != 5", self.source)
        self.assertIn("calendarEnd <= calendarStart", self.source)
        self.assertIn("bool nextWindow = f_windowAllowed(newsEvents, time_close, nextClose)", self.source)
        self.assertIn("passiveLimit and f_inside(entry, setup.zoneLow, setup.zoneHigh) and nextWindow", self.source)
        self.assertIn("staleOrder or not nextWindow", self.source)

    def test_source_contract_news_parser_validates_shape_canonical_date_and_limit(self) -> None:
        parser = self.section("f_parseNews", "f_killzone")
        self.assertIn("str.length(text) == 16", parser)
        self.assertIn("string canonical", parser)
        self.assertIn("if canonical != text", parser)
        self.assertIn("timestamp(\"GMT+0\"", parser)
        self.assertIn("if year(stamp, \"GMT+0\") != int(y)", parser)
        self.assertIn("if array.size(events) > 500", parser)

    def test_source_contract_phase_machine_requires_the_five_stages_in_order(self) -> None:
        switch_start = self.source.index("switch setup.phase")
        phase_positions = [self.source.index(f"{phase} =>", switch_start) for phase in range(5)]
        self.assertEqual(phase_positions, sorted(phase_positions))
        phase0 = self.source[phase_positions[0]:phase_positions[1]]
        phase1 = self.source[phase_positions[1]:phase_positions[2]]
        phase2 = self.source[phase_positions[2]:phase_positions[3]]
        phase3 = self.source[phase_positions[3]:phase_positions[4]]
        phase4 = self.source[phase_positions[4]:]
        self.assertIn("bool buySweep", phase0)
        self.assertIn("setup.phase := 1", phase0)
        self.assertIn("bool structureClosed", phase1)
        self.assertIn("bool displacement", phase1)
        self.assertIn("setup.phase := 2", phase1)
        self.assertIn("bool gapValid", phase2)
        self.assertIn("fvgConfluence", phase2)
        self.assertIn("setup.phase := 3", phase2)
        self.assertIn("setup.phase := 4", phase3)
        self.assertIn("bool pin", phase4)
        self.assertIn("bool engulfing", phase4)
        self.assertIn("strategy.entry", phase4)

    def test_source_contract_htf_requests_are_confirmed_before_lookahead_on(self) -> None:
        bias_request = self.section("[biasClose", "[h1High")
        pivot_helper = self.section("f_confirmedPivots", "f_wilsonLower")
        htf_requests = self.section("[h1High", "bool newH1")
        self.assertIn("[close[1], ta.ema(close, fastLength)[1], ta.ema(close, slowLength)[1]]", bias_request)
        self.assertIn("lookahead = barmerge.lookahead_on", bias_request)
        self.assertIn("[ph[1], pl[1]]", pivot_helper)
        self.assertEqual(htf_requests.count("f_confirmedPivots(targetPivotLength)"), 2)
        self.assertEqual(htf_requests.count("lookahead = barmerge.lookahead_on"), 2)

    def test_source_contract_fixed_exit_legs_share_actual_stop_and_do_not_recreate_tp1(self) -> None:
        exits = self.source[self.source.index("// Dua bracket tetap"):self.source.index("bool drawSetup")]
        self.assertIn("if trade.active and not trade.closing", exits)
        self.assertIn("float activeStop = trade.breakEven ? trade.entry : trade.initialStop", exits)
        exit_contracts = (
            ("L-TP1", "L", "trade.firstQty", "trade.tp1", "L-bracket-1"),
            ("L-TP2", "L", "trade.runnerQty", "trade.tp2", "L-bracket-2"),
            ("S-TP1", "S", "trade.firstQty", "trade.tp1", "S-bracket-1"),
            ("S-TP2", "S", "trade.runnerQty", "trade.tp2", "S-bracket-2"),
        )
        for exit_id, entry_id, quantity, target, oca_group in exit_contracts:
            with self.subTest(exit_id=exit_id):
                pattern = (
                    rf'strategy\.exit\("{exit_id}", "{entry_id}", qty = {re.escape(quantity)}, '
                    rf"stop = activeStop, limit = {re.escape(target)}, oca_name = \"{oca_group}\""
                )
                self.assertRegex(exits, pattern)
        self.assertEqual(exits.count('strategy.exit("L-TP1"'), 1)
        self.assertEqual(exits.count('strategy.exit("S-TP1"'), 1)
        for exit_id in ("L-TP1", "S-TP1"):
            exit_index = exits.index(f'strategy.exit("{exit_id}"')
            guard_index = exits.rfind("if not trade.firstLegClosed", 0, exit_index)
            self.assertGreaterEqual(guard_index, 0)
            self.assertRegex(exits, rf"if not trade\.firstLegClosed\s+strategy\.exit\(\"{exit_id}\"")

    def test_source_contract_fill_guards_and_close_only_bep_are_not_retroactive(self) -> None:
        fill_section = self.section("bool newClosedLegs", "closedSeen := strategy.closedtrades")
        self.assertIn("int filledAt = strategy.opentrades.entry_time(0)", fill_section)
        self.assertIn("bool fillTimeOk = f_windowAllowed(newsEvents, filledAt, filledAt)", fill_section)
        self.assertIn("bool fillHalfOk = trade.side == 1 ? trade.entry < trade.equilibrium : trade.entry > trade.equilibrium", fill_section)
        self.assertIn("bool fillChaseOk = not trade.market or (trade.side == 1 ? trade.entry <= trade.chaseBoundary : trade.entry >= trade.chaseBoundary)", fill_section)
        self.assertIn("trade.equilibrium := setup.equilibrium", self.source)
        self.assertIn("trade.chaseBoundary := isBuy ? setup.zoneHigh + maxChasePips * pipSize : setup.zoneLow - maxChasePips * pipSize", self.source)
        self.assertIn("bool unexpectedReduction = not trade.firstLegClosed", fill_section)
        self.assertIn("math.abs(strategy.position_size) < trade.qty - qtyStep * 0.1", fill_section)
        self.assertIn("or not fillTimeOk or not fillHalfOk or not fillChaseOk", fill_section)
        self.assertIn("or unexpectedReduction", fill_section)
        self.assertIn("strategy.close_all(comment = \"Fill di luar batas risiko\"", fill_section)
        self.assertIn("trade.side * (close - trade.entry) >= math.max(bePips * pipSize, trade.risk)", fill_section)
        self.assertNotRegex(fill_section, r"trade\.side \* \(high\s*-\s*trade\.entry\).*trade\.breakEven")
        self.assertNotRegex(fill_section, r"trade\.side \* \(low\s*-\s*trade\.entry\).*trade\.breakEven")

    def test_source_contract_completed_results_use_full_round_trip_net_delta_and_are_qualified(self) -> None:
        result_section = self.section("if trade.filled and strategy.position_size == 0", "lastExitBar := bar_index")
        self.assertIn("float netResult = strategy.netprofit - trade.netAtStart", result_section)
        self.assertIn("completed += 1", result_section)
        self.assertIn("if netResult > 0", result_section)
        self.assertIn("else if netResult < 0", result_section)
        self.assertIn("int minimumSample = input.int(100", self.source)
        self.assertIn("minval = 30, maxval = 1000", self.source)
        self.assertIn("completed >= minimumSample and lowerBound > 50", self.source)
        self.assertIn("Target WR >50%, bukan jaminan", self.source)
        self.assertIn("Out-of-sample + forward test; baca README", self.source)
        self.assertNotRegex(
            self.source.lower(),
            r"(?:win\s*rate|wr)[^\n\"]{0,40}(?:guaranteed|guarantee|dijamin|pasti)",
        )

    def test_source_contract_wilson_formula_is_present_for_the_sample_gate(self) -> None:
        wilson_helper = self.section("f_wilsonLower", "f_price")
        self.assertIn("1.96 * math.sqrt", wilson_helper)
        self.assertIn("3.8416", wilson_helper)
        self.assertIn("count > 0", wilson_helper)


if __name__ == "__main__":
    unittest.main()
