'use strict';

// Executes extracted, unchanged Pine helpers and probes full-source compatibility.
// Synthetic inputs only: this does not validate TradingView fills or performance.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PineTS, Indicator, aggregateCandles } = require('pinets');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', 'xau_scalper_v3.pine'), 'utf8');
const M5 = 300_000;
const fixture = Array.from({ length: 60 }, (_,i) => ({
    openTime: Date.UTC(2026, 5, 1, 7) + i * M5,
    closeTime: Date.UTC(2026, 5, 1, 7) + (i + 1) * M5,
    open: 3000 + i, high: 3002 + i, low: 2998 + i, close: 3001 + i, volume: 1000,
}));

function functionSource(name) {
    const match = SOURCE.match(new RegExp(`^${name}\\([^\\n]*\\) =>[^\\n]*(?:\\n[ \\t]+[^\\n]*)*`, 'm'));
    assert(match, `missing actual-source helper: ${name}`);
    return match[0];
}

function lineSource(prefix) {
    const lines = SOURCE.split('\n').filter((line) => line.startsWith(prefix));
    assert.equal(lines.length, 1, `expected unique source line: ${prefix}`);
    return lines[0];
}

async function runSnippet(body, data = fixture) {
    return new PineTS(data).run(new Indicator(`//@version=6\nindicator("V3 isolated helper test")\n${body}\n`));
}

function values(context, name) {
    assert(context.plots[name], `missing plot ${name}`);
    return context.plots[name].data.map((point) => point.value);
}

async function verifyStopCapsAndBrackets() {
    const offsets = [-1000, -30, -20, -10, -1, 0, 1, 10, 20, 30, 1000];
    const functions = ['f_capSessionSlLong', 'f_capSessionSlShort', 'f_validLongBracket', 'f_validShortBracket'].map(functionSource).join('\n');
    const calls = offsets.flatMap((offset, i) => [
        `plot(f_capSessionSlLong(close + ${offset}) - close, "long-${i}")`,
        `plot(f_capSessionSlShort(close + ${offset}) - close, "short-${i}")`,
    ]);
    const checks = [
        ['validLong', 'f_validLongBracket(close + 5, close - 20)', 1],
        ['validShort', 'f_validShortBracket(close - 5, close + 20)', 1],
        ['wrongLongStop', 'f_validLongBracket(close + 5, close)', 0],
        ['wrongShortStop', 'f_validShortBracket(close - 5, close)', 0],
        ['smallLongTarget', 'f_validLongBracket(close + 4.99, close - 20)', 0],
        ['smallShortTarget', 'f_validShortBracket(close - 4.99, close + 20)', 0],
        ['missingLongStop', 'f_validLongBracket(close + 5, na)', 0],
        ['missingShortStop', 'f_validShortBracket(close - 5, na)', 0],
    ];
    calls.push(...checks.map(([name, expression]) => `plot(${expression} ? 1 : 0, "${name}")`));
    const context = await runSnippet(`atr = 10.0\nminProfit = 5.0\n${functions}\n${calls.join('\n')}`);
    offsets.forEach((offset, i) => {
        assert(values(context, `long-${i}`).every((v) => v === Math.min(-10, Math.max(-30, offset))));
        assert(values(context, `short-${i}`).every((v) => v === Math.max(10, Math.min(30, offset))));
    });
    for (const [name, , expected] of checks) assert(values(context, name).every((v) => v === expected), name);
    return { stopCapCases: offsets.length * 2, bracketCases: checks.length };
}

async function verifyPovAndFootprintGates() {
    const cases = [
        { eth: false, pov: '3000.0', distance: 0.5, expected: 0 },
        { eth: true, pov: '3000.0', distance: 0.5, expected: 1 },
        { eth: true, pov: 'na', distance: 0.5, expected: 0 },
        { eth: true, pov: '3000.0', distance: 2.0, expected: 0 },
    ];
    for (const item of cases) {
        const context = await runSnippet(`bool inETH = ${item.eth}\nfloat povLevel = ${item.pov}\npovProxAtr = ${item.distance}\npovBlockThresh = 1.5\n${lineSource('bool ethPovBlock =')}\nplot(ethPovBlock ? 1 : 0, "blocked")`);
        assert(values(context, 'blocked').every((v) => v === item.expected));
    }
    const flows = [
        { available: false, buy: 0, sell: 0, ratioBuy: 1, ratioSell: 1 },
        { available: true, buy: 0, sell: 0, ratioBuy: 1, ratioSell: 1 },
        { available: true, buy: 300, sell: 100, ratioBuy: 3, ratioSell: 1 / 3 },
        { available: true, buy: 100, sell: 0, ratioBuy: 99, ratioSell: 0 },
        { available: true, buy: 0, sell: 100, ratioBuy: 0, ratioSell: 99 },
    ];
    for (const item of flows) {
        // No footprint API is mocked; only its scalar results feed unchanged ratio lines.
        const context = await runSnippet(`fpBuyVol = ${item.buy}.0\nfpSellVol = ${item.sell}.0\nfpHasVolume = ${item.available} and fpBuyVol + fpSellVol > 0\n${lineSource('fpBuyRatio =')}\n${lineSource('fpSellRatio =')}\nplot(fpBuyRatio, "buy")\nplot(fpSellRatio, "sell")`);
        assert(values(context, 'buy').every((v) => Math.abs(v - item.ratioBuy) < 1e-9));
        assert(values(context, 'sell').every((v) => Math.abs(v - item.ratioSell) < 1e-9));
    }
    return { povCases: cases.length, scalarFootprintRatioCases: flows.length };
}

async function verifyProfileWarmup() {
    const start = SOURCE.indexOf('hvbHi = ta.highest');
    const end = SOURCE.indexOf('\ndivRsi =', start);
    assert(start > 0 && end > start);
    const variables = ['hvbZone1', 'hvbZone2', 'hvbZone3', 'povLevel', 'vahLevel', 'valLevel', 'pocBuyPct', 'pocRawBuy', 'pocRawSell', 'nodeStrength'];
    const declarations = variables.map((name) => lineSource(`var float ${name} =`)).join('\n');
    const body = `hvbLookback = 50\nhvbBins = 15\n${declarations}\n${SOURCE.slice(start, end)}\nplot(hvbZone1, "poc")\nplot(nodeStrength, "strength")`;
    const warmup = await runSnippet(body, fixture.slice(0, 8));
    assert(values(warmup, 'poc').every(Number.isFinite), 'partial warmup history must produce finite POC');
    assert(values(warmup, 'strength').every((v) => v > 0 && v <= 100));
    const empty = await runSnippet(body, fixture.slice(0, 8).map((bar) => ({ ...bar, volume: 0 })));
    assert(values(empty, 'poc').every((v) => !Number.isFinite(v)), 'empty profile must not invent a node');
    assert(values(empty, 'strength').every((v) => v === 0));
    return { partialHistoryBars: 8, emptyVolumeBars: 8 };
}

async function verifyOvernightRange() {
    const start = SOURCE.indexOf('if inOvernight and not inOvernight[1]');
    const end = SOURCE.indexOf('\nif inORBBuild and not orbLocked', start);
    assert(start > 0 && end > start);
    // Session flags are synthetic; this tests range state, not timezone handling.
    const steps = [
        ['2026-06-01T19:55Z', 130, 70, false, NaN, NaN],
        ['2026-06-01T20:00Z', 120, 80, true, 120, 80],
        ['2026-06-02T04:55Z', 115, 85, true, 120, 80],
        ['2026-06-02T05:00Z', 110, 90, true, 120, 80],
        ['2026-06-02T12:00Z', 125, 75, true, 125, 75],
        ['2026-06-02T13:30Z', 140, 60, false, 125, 75],
        ['2026-06-02T20:00Z', 108, 92, true, 108, 92],
    ];
    const data = steps.map(([time, high, low, active]) => ({
        openTime: Date.parse(time), closeTime: Date.parse(time) + M5,
        open: 100, close: 100, high, low, volume: active ? 1 : 0,
    }));
    const declarations = ['onHigh', 'onLow'].map((name) => lineSource(`var float ${name} =`)).join('\n');
    const context = await runSnippet(`${declarations}\nbool inOvernight = volume > 0\n${SOURCE.slice(start, end)}\nplot(onHigh, "high")\nplot(onLow, "low")`, data);
    assert.deepEqual(values(context, 'high'), steps.map((step) => step[4]));
    assert.deepEqual(values(context, 'low'), steps.map((step) => step[5]));
    return { sessionStateBars: steps.length, timezoneHandlingVerified: false };
}

async function probeFullSource() {
    const requests = [];
    const timeframes = { '5': fixture };
    for (const tf of ['15', '60', '240', '1D']) timeframes[tf] = aggregateCandles(fixture, tf, '5');
    timeframes.D = timeframes['1D'];
    const provider = {
        configure() {},
        async getSymbolInfo() {
            return { tickerid: 'XAUUSD', ticker: 'XAUUSD', currency: 'USD', mintick: 0.01, pointvalue: 1, mincontract: 1, timezone: 'Etc/UTC', session: '24x7' };
        },
        async getMarketData(symbol, timeframe) {
            requests.push(`${symbol}:${timeframe}`);
            assert(timeframes[timeframe], `unconfigured fixture timeframe ${timeframe}`);
            return timeframes[timeframe];
        },
    };
    const instance = new PineTS(provider, 'XAUUSD', '5');
    try {
        await instance.run(new Indicator(SOURCE));
    } catch (error) {
        assert(instance.transpiledCode, 'the entire unmodified source must transpile before the known runtime blocker');
        assert.match(error.message, /footprint.*not a function/, `unexpected full-source blocker: ${error.message}`);
        return { transpiled: true, fullRuntimeVerified: false, blocker: error.message, requests: [...new Set(requests)] };
    }
    throw new Error('Full-source compatibility changed: review footprint/fill coverage instead of silently marking native execution verified.');
}

async function main() {
    const stops = await verifyStopCapsAndBrackets();
    const gates = await verifyPovAndFootprintGates();
    const profile = await verifyProfileWarmup();
    const overnight = await verifyOvernightRange();
    const fullSource = await probeFullSource();
    console.log(JSON.stringify({ stops, gates, profile, overnight, fullSource, nativeTradingViewVerified: false }));
}

main().catch((error) => {
    console.error(error.stack || error);
    process.exitCode = 1;
});
