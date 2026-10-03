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
    assert.deepEqual(m.readout(p.input, now), p.expect);
  });
}

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
  for (const bad of ["", "abc", "1.2.3", "k", "$", "inf", "1e3", "12x"]) assert.equal(m.parseAmount(bad), null, bad);
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
