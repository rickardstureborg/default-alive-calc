// Keeps model.js in lockstep with the Swift core: same presets spec, same reference values.
// Run: node --test design/   (part of `make test`)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as m from "./model.js";

const spec = JSON.parse(readFileSync(new URL("./presets.json", import.meta.url)));
const [y, mo, d] = spec.now.split("-").map(Number);
const now = new Date(y, mo - 1, d); // local midnight, as in PresetTests.swift

for (const p of spec.presets) {
  test(`preset ${p.name}`, () => {
    assert.deepEqual(m.readout(p.input, now, { ...m.MONTHLY, ...p.units }, p.linear ?? false, p.taxes ?? null), p.expect);
  });
}

test("arithmetic in boxes (same cases as TextTests.swift)", () => {
  const amounts = [["163+5", 168], ["80k + 5k", 85_000], ["$1.2M-200k", 1_000_000], ["(20k+5k)*2", 50_000],
    ["100/4", 25], ["2×3k", 6_000], ["90k÷3", 30_000], ["-$1k+500", -500], ["1+2*3", 7], ["(1+2)*3", 9], ["10-(-2)", 12]];
  for (const [t, v] of amounts) assert.ok(Math.abs(m.parseAmount(t) - v) < 1e-6, t);
  for (const t of ["10/0", "1+", "(1+2", "1+2)", "()", "+", "5 5", "abc+1"]) assert.equal(m.parseAmount(t), null, t);
  for (const [t, v] of [["8+2", 0.10], ["8%+1%", 0.09], ["12/2", 0.06], ["-2+5%", 0.03]]) assert.ok(Math.abs(m.parsePercent(t) - v) < 1e-12, t);
  const compacts = [["cash", "163+5", false, "168"], ["cash", "$163k+5k", false, "168000"], ["expenses", "80k+5k", false, "85000"],
    ["expenses", "1234+0", false, "1234"], ["revenue", "1000/3", false, "333.3333"], ["cash", "$1.2M-200k", false, "1000000"],
    ["growth", "8+2", false, "10"], ["growth", "$1.6k+400", true, "2000"], ["growth", "-1k-600", true, "-1600"]];
  for (const [row, t, linear, out] of compacts) assert.equal(m.compactField(row, t, linear), out, t);
  for (const t of ["163", "$1.2M", "80k", "-$1.6k", "8%", "abc+1", "1+", ""]) assert.equal(m.compactField("expenses", t, false), null, t);
  // Box text is raw: "$", "%" and "," dropped; the box draws the unit and the commas.
  for (const [typed, kept] of [["1,000", "1000"], ["163,000+5,000", "163000+5000"], ["$400k", "400k"], ["-$1,600", "-1600"],
    ["8%", "8"], ["1234.5678", "1234.5678"], ["", ""]]) assert.equal(m.normalizeField(typed), kept, typed);
  const breaks = [["1630000", [1, 4]], ["1000", [1]], ["999", []], ["163000+5000", [3, 8]], ["1234.5678", [1]], ["12345.6789", [2]],
    ["0.12345", []], ["-1600", [2]], ["1500k", [1]], ["", []]];
  for (const [t, at] of breaks) assert.deepEqual(m.groupBreaks(t), at, t);
  for (const [t, out] of [["1630000", "1,630,000"], ["163000+5000", "163,000+5,000"], ["-1600", "-1,600"], ["80k", "80k"]]) assert.equal(m.groupedText(t), out, t);
  for (const [old, caret, now, at] of [["$400", 1, "400", 0], ["1,000", 5, "1000", 4], ["40$0", 3, "400", 2], ["163000", 6, "163000", 6]])
    assert.equal(m.caretAfterNormalizing(old, caret, now), at, old);
  assert.equal(m.fieldText("growth", 0.08, "year", false), "152");
  assert.equal(m.fieldText("growth", -1600, "month", true), "-1.6k");
});

test("linear growth closed forms", () => {
  // E 80k, R 20k, +5k/mo: T = 60k/5k, C = 60k²/(2·5k).
  const p = m.project({ cash: 400_000, expenses: 80_000, revenue: 20_000, growth: 5_000, linear: true });
  assert.equal(p.monthsToProfitability, 12);
  assert.equal(p.capitalNeeded, 360_000);
  // Shrinking revenue stops at zero (10 months here), then all of E burns.
  const shrink = { cash: 1_000_000, expenses: 80_000, revenue: 20_000, growth: -2_000, linear: true };
  const q = m.project(shrink);
  assert.ok(q.runwayMonths > 10);
  assert.ok(Math.abs(m.cumulativeBurn(shrink, q.runwayMonths) - 1_000_000) < 0.01);
});

test("units", () => {
  assert.ok(Math.abs(m.growthToUnit(0.08, "year") - (1.08 ** 12 - 1)) < 1e-12);
  assert.ok(Math.abs(m.growthFromUnit(m.growthToUnit(0.08, "week"), "week") - 0.08) < 1e-12);
  assert.equal(m.amountToUnit(80_000, "year"), 960_000);
  // $ growth adds to the Revenue box's figure each growth period: linear in that period.
  assert.equal(m.linearToUnit(5_000, "year", "month"), 60_000);
  assert.equal(m.linearToUnit(5_000, "year", "year"), 720_000);
  assert.ok(Math.abs(m.linearToUnit(m.linearFromUnit(50, "week", "month"), "year", "month") - 50 * 365.2425 / 7) < 1e-9);
});

test("breakeven bounds round toward the safe side", () => {
  assert.equal(m.formatMoneyBound(241.04, true), "$242");
  assert.equal(m.formatMoneyBound(241.04, false), "$241");
  assert.equal(m.formatMoneyBound(360_000, true), "$360k"); // exact stays put
  assert.equal(m.formatMoneyBound(7_461.06, false), "$7.46k");
  assert.equal(m.formatMoneyBound(999.7, true), "$1k");
  assert.equal(m.formatMoneyBound(1_234_567, true), "$1.24M");
  assert.equal(m.formatPercentBound(0.13571, true), "13.6%");
  assert.equal(m.formatPercentBound(0.0999999, true), "10%");
});

test("TLB reference (growth.tlb.org defaults, monthly)", () => {
  const wpm = 365.2425 / 7 / 12;
  const p = m.project({ cash: 0, expenses: 1600 * wpm, revenue: 100 * wpm, growth: 1.025 ** wpm - 1 });
  assert.ok(Math.abs(p.monthsToProfitability - 25.823576392986606) < 1e-6);
  assert.ok(Math.abs(p.capitalNeeded - 118907.70751121586) < 1);
});

test("shrinking revenue: runway is where burn hits cash", () => {
  const inputs = { cash: 300_000, expenses: 50_000, revenue: 20_000, growth: -0.05 };
  const p = m.project(inputs);
  assert.equal(p.verdict, "dead");
  assert.ok(p.runwayMonths < 10);
  assert.ok(Math.abs(m.cumulativeBurn(inputs, p.runwayMonths) - 300_000) < 0.01);
});

test("invalid inputs have no projection", () => {
  assert.equal(m.project({ cash: -1, expenses: 1, revenue: 0, growth: 0 }), null);
  assert.equal(m.project({ cash: 1, expenses: 1, revenue: 0, growth: -1 }), null);
});

test("parsing", () => {
  assert.equal(m.parseAmount("250k"), 250_000);
  assert.ok(Math.abs(m.parseAmount("$1.2M") - 1.2e6) < 1e-6);
  assert.equal(m.parseAmount("1,500"), 1500);
  assert.equal(m.parseAmount("  7 "), 7);
  assert.equal(m.parseAmount("5."), 5);
  assert.equal(m.parseAmount(".5k"), 500);
  assert.equal(m.parseAmount("-$1.6k"), -1600);
  for (const bad of ["", "abc", "1.2.3", "k", "$", "inf", "1e3", "12x", "--5", "$-5"]) assert.equal(m.parseAmount(bad), null, bad);
  assert.equal(m.parsePercent("8%"), 0.08);
  assert.equal(m.parsePercent("-3"), -0.03);
  assert.equal(m.parsePercent("%"), null);
  assert.equal(m.amountValue("-5"), null);
  assert.equal(m.growthValue("-100"), null);
});

test("formatting, including ties", () => {
  const cases = [[270_000, "$270k"], [1.2e6, "$1.2M"], [950, "$950"], [0, "$0"], [999_999, "$1M"],
    [12_345_678, "$12.3M"], [-130_000, "-$130k"], [1_250_000, "$1.3M"], [100_500, "$101k"], [999.5, "$1k"]];
  for (const [v, s] of cases) assert.equal(m.formatMoney(v), s, String(v));
  assert.equal(m.formatMonths(12.25), "12.3 months");
  assert.equal(m.formatMonthYear(3, new Date(2026, 0, 15)), "Apr 2026");
  assert.equal(m.formatMonthYear(1, new Date(2026, 0, 31)), "Feb 2026"); // clamps like Calendar, no Mar 3 overflow
});

test("readout date, drag math and revenue over time (same cases as Swift)", () => {
  assert.equal(m.formatDate(0, new Date(2026, 0, 10)), "Jan 10, 2026");
  assert.equal(m.formatDate(18.0129, new Date(2026, 0, 10)), "Jul 10, 2027");
  assert.equal(m.formatDate(7.567, new Date(2026, 0, 10)), "Aug 27, 2026");
  assert.equal(m.formatDate(1, new Date(2026, 0, 31)), "Feb 28, 2026");

  const alive = { cash: 1_200_000, expenses: 80_000, revenue: 20_000, growth: 0.08 };
  const k = 80_000 - 60_000 / Math.log(4);
  const on = m.dragProfitPoint(12, 1_200_000 - k * 12, alive, 10, 1e-4);
  assert.ok(Math.abs(on.monthsToProfitability - 12) < 1e-9 && Math.abs(on.monthlyGrowth - (4 ** (1 / 12) - 1)) < 1e-12 && !on.pinned);
  const off = m.dragProfitPoint(12, 1_200_000, alive, 10, 1e-4);
  assert.ok(Math.abs(off.monthsToProfitability - 100 * 12 / (100 + k * k * 1e-8)) < 1e-9);
  const pinned = m.dragProfitPoint(60, -500_000, alive, 10, 1e-4);
  assert.ok(pinned.pinned && Math.abs(pinned.monthlyGrowth - 0.043332) < 1e-6 && Math.abs(pinned.balance) < 1e-6);
  assert.equal(m.dragProfitPoint(0, 1_200_000, alive, 10, 1e-4).monthsToProfitability, 0.5);
  assert.equal(m.dragProfitPoint(25, 1_200_000 - k * 25, alive, 10, 1e-4, 20).monthsToProfitability, 20);
  const linear = { cash: 400_000, expenses: 80_000, revenue: 20_000, growth: 5_000, linear: true };
  assert.ok(Math.abs(m.dragProfitPoint(10, 100_000, linear, 10, 1e-4).monthlyGrowth - 6_000) < 1e-9);
  assert.equal(m.dragProfitPoint(5, 0, { ...alive, revenue: 90_000 }, 10, 1e-4), null);
  assert.equal(m.dragProfitPoint(5, 0, { ...alive, revenue: 0 }, 10, 1e-4), null);

  assert.ok(Math.abs(m.revenueAt({ revenue: 20_000, growth: 0.08 }, 12) - 20_000 * 1.08 ** 12) < 1e-6);
  assert.equal(m.revenueAt({ revenue: 20_000, growth: 5_000, linear: true }, 12), 80_000);
  assert.equal(m.revenueAt({ revenue: 20_000, growth: -2_000, linear: true }, 15), 0);
});
