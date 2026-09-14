'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PineTS, Indicator, aggregateCandles } = require('pinets');

const ROOT = path.resolve(__dirname, '..');
const SOURCE = fs.readFileSync(path.join(ROOT, 'ict_xauusd_v6.pine'), 'utf8');
const M5_MS = 5 * 60_000;

function buildFixture(start = Date.UTC(2025, 11, 15, 7, 0)) {
    const specialBars = new Map([
        // Bounded rising-trend pullback followed by a bullish rejection.
        [330, { closeOffset: -0.8, highOffset: 0.1, lowOffset: -1.4 }],
        [331, { openOffset: -0.1, closeOffset: 0.06, highOffset: 0.1, lowOffset: -1.19 }],
        // Bounded falling-trend pullback followed by a bearish rejection.
        [620, { closeOffset: 0.8, highOffset: 1.4, lowOffset: -0.1 }],
        [621, { openOffset: 0.1, closeOffset: -0.06, highOffset: 1.15, lowOffset: -0.15 }],
    ]);

    let price = 3000;
    const m5 = [];
    for (let index = 0; index < 800; index += 1) {
        const baseOpen = price;
        const slope = index < 332 ? 0.15 : -0.15;
        const shape = specialBars.get(index);
        const open = shape?.openOffset != null ? baseOpen + shape.openOffset : baseOpen;
        const close = shape?.closeOffset != null ? baseOpen + shape.closeOffset : baseOpen + slope;
        const high = shape?.highOffset != null ? baseOpen + shape.highOffset : Math.max(open, close) + 0.4;
        const low = shape?.lowOffset != null ? baseOpen + shape.lowOffset : Math.min(open, close) - 0.4;

        m5.push({
            openTime: start + index * M5_MS,
            closeTime: start + (index + 1) * M5_MS,
            open: Number(open.toFixed(2)),
            high: Number(high.toFixed(2)),
            low: Number(low.toFixed(2)),
            close: Number(close.toFixed(2)),
            volume: 1000 + index,
        });
        price = close;
    }

    const data = {
        '5': m5,
        '15': aggregateCandles(m5, '15', '5'),
        '60': aggregateCandles(m5, '60', '5'),
    };
    assert.equal(data['15'].length, Math.ceil(m5.length / 3));
    assert.equal(data['60'].length, Math.ceil(m5.length / 12));
    return data;
}

function syntheticProvider(data, requests) {
    return {
        configure() {},
        async getSymbolInfo() {
            return {
                tickerid: 'XAUUSD',
                ticker: 'XAUUSD',
                currency: 'USD',
                mintick: 0.01,
                pointvalue: 1,
                mincontract: 1,
                timezone: 'Etc/UTC',
                session: '24x7',
            };
        },
        async getMarketData(_ticker, timeframe) {
            requests.push(timeframe);
            if (!data[timeframe]) throw new Error(`No synthetic data for ${timeframe}`);
            return data[timeframe];
        },
    };
}

function activeCalendarOverrides(m5) {
    const start = m5[0].openTime;
    const end = m5[m5.length - 1].closeTime + M5_MS;
    return {
        'Kalender high-impact sudah diperiksa': true,
        'Awal cakupan kalender terverifikasi (wajib diisi)': start,
        'Akhir cakupan kalender terverifikasi (wajib diisi)': end,
        'Mulai periode entri': start,
        'Akhir periode entri': end,
    };
}

function newsBlockedCalendarOverrides(m5) {
    return {
        ...activeCalendarOverrides(m5),
        'Berita UTC: satu YYYY-MM-DD HH:mm per baris': [331, 621]
            .map((index) => new Date(m5[index].closeTime).toISOString().slice(0, 16).replace('T', ' '))
            .join('\n'),
    };
}

function markerEvents(context, title) {
    return (context.plots[title]?.data ?? []).filter((point) => point.value === true);
}

async function runM5Smoke(data, overrides) {
    const lockedRequests = [];
    const locked = await new PineTS(syntheticProvider(data, lockedRequests), 'XAUUSD', '5').run(new Indicator(SOURCE));
    assert.equal(locked.strategy.closedtrades.length, 0, 'calendar-lock defaults must not close a trade');
    assert.equal(locked.strategy.opentrades.length, 0, 'calendar-lock defaults must not open a trade');
    assert.equal(markerEvents(locked, 'Order buy dikirim').length, 0, 'calendar-lock defaults must not send a buy order');
    assert.equal(markerEvents(locked, 'Order sell dikirim').length, 0, 'calendar-lock defaults must not send a sell order');
    assert(lockedRequests.includes('15'), 'M5 run must request the locally aggregated M15 bias data');

    const activeRequests = [];
    const active = await new PineTS(syntheticProvider(data, activeRequests), 'XAUUSD', '5').run(new Indicator(SOURCE, overrides));
    const buyOrders = markerEvents(active, 'Order buy dikirim');
    const sellOrders = markerEvents(active, 'Order sell dikirim');
    assert(buyOrders.length > 0, 'rising-pullback fixture must reach the actual buy order flow');
    assert(sellOrders.length > 0, 'falling-pullback fixture must reach the actual sell order flow');
    assert(activeRequests.includes('15'), 'active M5 run must request the locally aggregated M15 bias data');
    assert.equal(active.warnings.length, 0, 'M5 PineTS execution should not emit warnings');

    return {
        locked: { buyOrders: 0, sellOrders: 0 },
        active: {
            buyOrders: buyOrders.length,
            sellOrders: sellOrders.length,
            closedTrades: active.strategy.closedtrades.length,
            openTrades: active.strategy.opentrades.length,
        },
    };
}

async function runM5NewsBlockedSmoke(data, overrides) {
    const requests = [];
    const blocked = await new PineTS(syntheticProvider(data, requests), 'XAUUSD', '5').run(new Indicator(SOURCE, overrides));
    const buyOrders = markerEvents(blocked, 'Order buy dikirim');
    const sellOrders = markerEvents(blocked, 'Order sell dikirim');

    assert.equal(buyOrders.length, 0, 'news blackout must suppress the deterministic buy order flow');
    assert.equal(sellOrders.length, 0, 'news blackout must suppress the deterministic sell order flow');
    assert.equal(blocked.strategy.closedtrades.length, 0, 'news-blocked fixture must not close any trades');
    assert.equal(blocked.strategy.opentrades.length, 0, 'news-blocked fixture must not open any trades');
    assert(requests.includes('15'), 'news-blocked M5 run must still request locally aggregated M15 bias data');
    assert.equal(blocked.warnings.length, 0, 'news-blocked M5 PineTS execution should not emit warnings');

    return {
        verified: true,
        buyOrders: buyOrders.length,
        sellOrders: sellOrders.length,
        closedTrades: blocked.strategy.closedtrades.length,
        openTrades: blocked.strategy.opentrades.length,
    };
}

async function probeNewsPaddingPineTsLimitation() {
    const data = buildFixture(Date.UTC(2026, 0, 5, 7, 0));
    const overrides = newsBlockedCalendarOverrides(data['5']);
    try {
        await new PineTS(syntheticProvider(data, []), 'XAUUSD', '5').run(new Indicator(SOURCE, overrides));
    } catch (error) {
        // PineTS 0.9.33 formats str.tostring(int(1), "00") as "1", rejecting valid January input.
        assert.match(
            String(error.message),
            /Gunakan angka dua digit untuk bulan, tanggal, jam, dan menit/,
            'only the documented PineTS numeric-format blocker is expected for the actual-source news probe',
        );
        return String(error.message);
    }
    throw new Error('PineTS zero-padding compatibility changed; verify January news parsing and update this probe.');
}

async function probeM15PineTsLimitation(data, overrides) {
    const requests = [];
    try {
        // PineTS re-runs the full source in request.security's H1 context.
        await new PineTS(syntheticProvider(data, requests), 'XAUUSD', '15').run(new Indicator(SOURCE, overrides));
    } catch (error) {
        assert.match(
            String(error.message),
            /Active Scalper: gunakan candle standar M5 atau M15/,
            'only the documented PineTS secondary-context limitation is expected',
        );
        assert(requests.includes('60'), 'M15 probe must supply actual locally aggregated H1 data');
        return String(error.message);
    }
    throw new Error('PineTS M15/H1 compatibility changed; update this probe and verify M15 behavior before accepting it.');
}

async function main() {
    const data = buildFixture();
    const overrides = activeCalendarOverrides(data['5']);
    const m5 = await runM5Smoke(data, overrides);
    const newsBlocked = await runM5NewsBlockedSmoke(data, newsBlockedCalendarOverrides(data['5']));
    const newsPaddingBlocker = await probeNewsPaddingPineTsLimitation();
    const m15Blocker = await probeM15PineTsLimitation(data, overrides);

    console.log(JSON.stringify({
        calendarOverrides: Object.keys(overrides),
        m5,
        newsBlocked,
        pineTsVerificationScope: 'Synthetic M5 order-flow and December news blackout only; native exit, PnL, and OCA semantics are not asserted.',
        newsZeroPaddingVerified: false,
        newsPaddingPineTsBlocker: newsPaddingBlocker,
        m15Verified: false,
        m15PineTsBlocker: m15Blocker,
    }));
}

main().catch((error) => {
    console.error(error.stack || error);
    process.exitCode = 1;
});
