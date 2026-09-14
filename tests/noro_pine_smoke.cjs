'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PineTS, Indicator } = require('pinets');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', 'xauusd_trading_v2.pine'), 'utf8');

function fixture(minutes = 5) {
    const bars = [];
    let price = 3000;
    const start = Date.UTC(2026, 5, 1);
    for (let i = 0; i < 1000; i += 1) {
        const side = i < 500 ? 1 : -1;
        const phase = i % 45;
        const step = phase === 30 || phase === 31 ? -side * 0.65 : side * (0.24 + phase * 0.008);
        const open = price;
        price = Math.round((price + step) * 100) / 100;
        bars.push({
            openTime: start + i * minutes * 60_000,
            closeTime: start + (i + 1) * minutes * 60_000,
            open, close: price, high: Math.round((Math.max(open, price) + 0.12) * 100) / 100,
            low: Math.round((Math.min(open, price) - 0.12) * 100) / 100, volume: 1000,
        });
    }
    return bars;
}

function provider(bars) {
    return {
        configure() {},
        async getSymbolInfo() {
            return { tickerid: 'XAUUSD', ticker: 'XAUUSD', currency: 'USD', mintick: 0.01,
                pointvalue: 1, mincontract: 0.1, timezone: 'Etc/UTC', session: '24x7' };
        },
        async getMarketData() { return bars; },
    };
}

async function run(overrides = {}, minutes = 5, bars = fixture(minutes)) {
    const context = await new PineTS(provider(bars), 'XAUUSD', String(minutes)).run(new Indicator(SOURCE, overrides));
    assert.equal(context.warnings.length, 0, 'actual-source execution should not emit warnings');
    return context;
}

function events(context, title) {
    return (context.plots[title]?.data ?? []).filter((point) => point.value === true);
}

function tradePoints(context, trade, title) {
    return context.plots[title].data.filter((point) => point.time >= trade.entry_time
        && point.time < trade.exit_time && Number.isFinite(point.value));
}

function assertLevels(context, expectBe) {
    let checked = 0;
    for (const trade of context.strategy.closedtrades) {
        const side = trade.size > 0 ? 1 : -1;
        const stops = tradePoints(context, trade, 'SL / BEP');
        const targets = tradePoints(context, trade, 'Target');
        if (!stops.length) continue;
        checked += 1;
        for (let i = 1; i < stops.length; i += 1) {
            assert(side * (stops[i].value - stops[i - 1].value) >= -1e-8, 'stop must never loosen');
        }
        assert(targets.every((point) => Math.abs(point.value - targets[0].value) < 1e-8), 'target must stay frozen');
        if (!expectBe) {
            assert(stops.every((point) => Math.abs(point.value - stops[0].value) < 1e-8), 'initial stop must stay frozen without BE/trail');
            const risk = side * (trade.entry_price - stops[0].value);
            const reward = side * (targets[0].value - trade.entry_price);
            assert(risk > 0 && Math.abs(reward / risk - 2) < 1e-8, 'default plotted target must be 2R from the actual fill');
        }
    }
    assert(checked > 0, 'level checks must exercise filled positions');
}

async function assertWickDoesNotArmBe(baseline) {
    for (const side of [1, -1]) {
        const trade = baseline.strategy.closedtrades.find((item) => Math.sign(item.size) === side);
        const initialStop = tradePoints(baseline, trade, 'SL / BEP')[0].value;
        const risk = side * (trade.entry_price - initialStop);
        assert(risk > 0);
        const bars = fixture();
        const bar = bars[trade.entry_bar_index];
        bar.close = trade.entry_price + side * risk * 0.25;
        bar.high = side === 1 ? trade.entry_price + risk * 1.25 : Math.max(bar.open, bar.close) + 0.12;
        bar.low = side === -1 ? trade.entry_price - risk * 1.25 : Math.min(bar.open, bar.close) - 0.12;
        const changed = await run({}, 5, bars);
        assert(changed.strategy.closedtrades.some((item) => item.entry_bar_index === trade.entry_bar_index), 'wick probe must actually enter');
        const flag = changed.plots['BEP armed'].data.find((point) => point.time === bar.openTime);
        assert.equal(flag.value, 0, 'a 1.25R wick with only a 0.25R close must not retroactively arm BE');
    }
}

async function assertDailyGuards(baseline) {
    const limited = await run({ 'Maksimum order entri per hari UTC': 1 });
    const perDay = new Map();
    for (const point of [...events(limited, 'Order Long'), ...events(limited, 'Order Short')]) {
        const day = new Date(point.time + 5 * 60_000).toISOString().slice(0, 10);
        perDay.set(day, (perDay.get(day) ?? 0) + 1);
    }
    assert(perDay.size > 1, 'daily-order test must span a UTC reset');
    assert([...perDay.values()].every((count) => count === 1));

    const first = baseline.strategy.closedtrades[0];
    const bars = fixture();
    bars[first.entry_bar_index].low = tradePoints(baseline, first, 'SL / BEP')[0].value - 0.5;
    const lossLimited = await run({ 'Berhenti setelah loss beruntun per hari': 1 }, 5, bars);
    assert(lossLimited.strategy.closedtrades[0].profit < 0, 'fixture must actually hit an initial stop');
    const firstDay = new Date(first.entry_time).toISOString().slice(0, 10);
    const orders = [...events(lossLimited, 'Order Long'), ...events(lossLimited, 'Order Short')];
    assert.equal(orders.filter((point) => new Date(point.time + 5 * 60_000).toISOString().startsWith(firstDay)).length, 1,
        'a loss at the configured streak limit must block the rest of that day');
    assert(orders.some((point) => !new Date(point.time + 5 * 60_000).toISOString().startsWith(firstDay)), 'UTC reset must allow later setups');
}

async function probeSessionLimitation() {
    const context = await run({ 'Batasi sesi entri UTC': true, 'Sesi UTC (Senin-Jumat)': '0000-0000' });
    const probe = await new PineTS(provider(fixture()), 'XAUUSD', '5').run(new Indicator(`//@version=6
indicator("PineTS session compatibility probe")
plot(time(timeframe.period, "0000-0000:23456", "Etc/UTC"), "current")
plot(time(timeframe.period, "0000-0000:23456", "Etc/UTC", bars_back = -1), "next")`));
    assert(probe.plots.current.data.every((point) => Number.isFinite(point.value)), 'weekday fixture must be in the current session');
    // PineTS 0.9.33 cannot resolve future session timestamps; keep the native guard intact.
    assert(probe.plots.next.data.every((point) => Number.isNaN(point.value)), 'future-session support changed: replace this limitation probe with boundary assertions');
    assert.equal(events(context, 'Order Long').length + events(context, 'Order Short').length, 0,
        'the recognized PineTS future-time blocker must fail closed');
}

async function main() {
    const active = await run();
    const buy = events(active, 'Order Long').length;
    const sell = events(active, 'Order Short').length;
    assert(buy > 0 && sell > 0, 'default Noro fixtures must reach both order flows');
    assert(active.plots['BEP armed'].data.some((point) => point.value === 1), 'fixture must arm BEP');
    const disabled = await run({ Long: false, Short: false });
    assert.equal(events(disabled, 'Order Long').length + events(disabled, 'Order Short').length, 0);
    const longOnly = await run({ Short: false });
    assert(events(longOnly, 'Order Long').length > 0);
    assert.equal(events(longOnly, 'Order Short').length, 0);
    const shortOnly = await run({ Long: false });
    assert(events(shortOnly, 'Order Short').length > 0);
    assert.equal(events(shortOnly, 'Order Long').length, 0);
    const excluded = await run({ 'Mulai entri (UTC)': Date.UTC(2030, 0, 1) });
    assert.equal(events(excluded, 'Order Long').length + events(excluded, 'Order Short').length, 0);
    const noBe = await run({ 'Aktifkan BEP otomatis': false });
    assert(noBe.plots['BEP armed'].data.every((point) => point.value === 0));
    assertLevels(noBe, false);
    assertLevels(active, true);
    await assertWickDoesNotArmBe(noBe);
    await assertDailyGuards(noBe);
    await probeSessionLimitation();
    const trailing = await run({ 'Trailing ATR setelah BEP': true });
    assert(trailing.plots['BEP armed'].data.some((point) => point.value === 1));
    assertLevels(trailing, true);
    const m15 = await run({}, 15);
    assert(events(m15, 'Order Long').length > 0 && events(m15, 'Order Short').length > 0);
    await assert.rejects(run({ 'BEP setelah profit CLOSE mencapai R': 2.0 }), /Trigger BEP harus lebih kecil/);
    await assert.rejects(run({ 'Trailing ATR setelah BEP': true, 'Aktifkan BEP otomatis': false }), /Trailing memerlukan BEP/);
    console.log(JSON.stringify({ buyOrders: buy, sellOrders: sell,
        experimentalClosedTrades: active.strategy.closedtrades.length,
        sessionGuardVerified: false,
        sessionPineTsBlocker: 'PineTS 0.9.33 returns na for time(..., bars_back = -1). Native TradingView session boundaries still need verification.',
        scope: 'Actual Pine source on synthetic M5/M15: order flows, toggles, dates, frozen 2R plotted targets, monotonic stops, close-only BE, daily order/streak guards and UTC reset. Not native TradingView compilation or fill/performance evidence.' }));
}

module.exports = { fixture, run, events };
if (require.main === module) {
    main().catch((error) => { console.error(error.stack || error); process.exitCode = 1; });
}
