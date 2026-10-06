// JS twin of Sources/DefaultAliveCore (same names, formulas, rounding) so the browser
// preview shows the numbers the app will. design/presets.json pins both sides: change
// wording or math in one and `make test` fails until the other (and the `expect`s) match.

// The tax checklist: the very file the app compiles in (Package.swift, .embedInCode).
import taxCatalog from "../Sources/DefaultAliveCore/TaxPlaces.json" with { type: "json" };

const SUFFIXES = { k: 1e3, m: 1e6, b: 1e9 };
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export const KEYS = ["cash", "expenses", "revenue", "growth"];

// ── Parsing.swift ────────────────────────────────────────────────────────────

// "250k", "$1.2M", "1,500", "-$1.6k", and arithmetic on those ("163+5") → number.
export const parseAmount = (text) => evaluate(text, false);

// "8", "8%", "-3", "8+2" → fraction.
export function parsePercent(text) {
  const v = evaluate(text, true);
  return v === null ? null : v / 100;
}

// Arithmetic over the boxes' number syntax: + − * / × ÷ and parentheses, with unary minus
// only at the start of an expression or a parenthesis, so "--5" and "5--3" stay invalid.
// Amounts take "$" and k/m/b; percentages take "%".
export function evaluate(text, percent) {
  const s = [...text];
  let i = 0;
  const peek = () => {
    while (i < s.length && (s[i] === " " || s[i] === "\t")) i++;
    return i < s.length ? s[i] : null;
  };
  const number = () => {
    if (!percent && peek() === "$") i++;
    peek();
    const start = i;
    while (i < s.length && /[0-9.,]/.test(s[i])) i++;
    const n = plainNumber(s.slice(start, i).join("").replaceAll(",", ""));
    if (n === null) return null;
    if (percent) {
      if (peek() === "%") i++;
      return n;
    }
    const suffix = s[i]?.toLowerCase();
    if (suffix && Object.hasOwn(SUFFIXES, suffix)) {
      i++;
      return n * SUFFIXES[suffix];
    }
    return n;
  };
  const factor = () => {
    if (peek() !== "(") return number();
    i++;
    const v = expression();
    if (v === null || peek() !== ")") return null;
    i++;
    return v;
  };
  const term = () => {
    let value = factor();
    if (value === null) return null;
    for (let op = peek(); op !== null && "*×/÷".includes(op); op = peek()) {
      i++;
      const rhs = factor();
      if (rhs === null) return null;
      value = op === "*" || op === "×" ? value * rhs : value / rhs;
      if (!Number.isFinite(value)) return null;
    }
    return value;
  };
  const expression = () => {
    const negate = peek() === "-";
    if (negate) i++;
    let value = term();
    if (value === null) return null;
    if (negate) value = -value;
    for (let op = peek(); op === "+" || op === "-"; op = peek()) {
      i++;
      const rhs = term();
      if (rhs === null) return null;
      value = op === "+" ? value + rhs : value - rhs;
    }
    return value;
  };
  const v = expression();
  return v !== null && peek() === null && Number.isFinite(v) ? v : null;
}

// Digits with at most one decimal point. Number() alone also accepts "Infinity", "1e3"
// and hex, none of which belong in a money field.
function plainNumber(s) {
  if (!/^\d*\.?\d*$/.test(s) || !/\d/.test(s)) return null;
  return Number(s);
}

// If `text` is arithmetic ("163+5"), its exact result ("168", "85000", "333.3333"); null
// for plain numbers and anything that doesn't evaluate. Raw like all box text: the box
// draws the thousands commas and the unit ($ or %) itself.
export function compactField(row, text, linear) {
  const t = text.trim();
  if (!(t.startsWith("(") || /[+\-*/×÷()]/.test(t.slice(1)))) return null;
  const v = evaluate(t, row === "growth" && !linear);
  if (v === null) return null;
  // Sign-aware so ties round away from zero like Swift's .rounded() (Math.round goes up).
  return trimZeros((Math.sign(v) * Math.round(Math.abs(v) * 10_000) / 10_000).toFixed(4));
}

// What a box holds for what was typed or pasted: "$", "%" and "," dropped. The box draws
// the unit and the thousands commas itself.
export const normalizeField = (text) => text.replace(/[$%,]/g, "");

// Where a box draws a thousands comma: before these UTF-16 offsets of `text`. Every
// number's whole part is grouped in threes; decimals aren't.
export function groupBreaks(text) {
  const breaks = [];
  for (const m of text.matchAll(/\d+/g)) {
    const start = m.index, length = m[0].length, end = start + length;
    if (length < 4 || text[start - 1] === ".") continue;
    for (let at = start + (length % 3 || 3); at < end; at += 3) breaks.push(at);
  }
  return breaks;
}

// `text` with the commas a box would draw, for places that show it as plain text.
export function groupedText(text) {
  let out = text;
  for (const at of groupBreaks(text).reverse()) out = `${out.slice(0, at)},${out.slice(at)}`;
  return out;
}

// Where the cursor goes after normalizeField dropped characters from `old`: after the
// same number of surviving characters. UTF-16 offsets.
export function caretAfterNormalizing(old, caret, now) {
  const kept = [...old.slice(0, caret)].filter((c) => !"$%,".includes(c)).length;
  return Math.min(kept, now.length);
}

// ── Units.swift ──────────────────────────────────────────────────────────────
// The model runs in months; each flow field can be typed per week, month or year.
// Weeks per month is TLB's 365.2425/7/12. % growth compounds per period, so 8%/mo is
// 1.79%/wk and 152%/yr (not 2% and 96%). $ growth means the Revenue box's figure (in that
// box's unit) rises by that much each growth period: linear in the growth period ("+$10k of
// MRR a month" is +$120k of MRR a year), and scaled by the revenue period.

export const UNITS = {
  week: { months: 12 * 7 / 365.2425 },
  month: { months: 1 },
  year: { months: 12 },
};
export const NEXT_UNIT = { week: "month", month: "year", year: "week" };
export const MONTHLY = { expenses: "month", revenue: "month", growth: "month" };
const per = (unit) => UNITS[unit].months;
export const amountToUnit = (monthly, unit) => monthly * per(unit);
export const amountFromUnit = (perUnit, unit) => perUnit / per(unit);
export const growthToUnit = (monthly, unit) => Math.expm1(Math.log1p(monthly) * per(unit));
export const growthFromUnit = (perUnit, unit) => Math.expm1(Math.log1p(perUnit) / per(unit));
export const linearToUnit = (monthly, unit, revenue = "month") => monthly * per(unit) * per(revenue);
export const linearFromUnit = (perUnit, unit, revenue = "month") => perUnit / (per(unit) * per(revenue));

// ── Projection.swift ─────────────────────────────────────────────────────────
// inputs: { cash, expenses, revenue, growth, linear }, all monthly. Compounding growth
// is a fraction per month; linear growth is $ of monthly revenue added per month.

export function cumulativeBurn(inputs, t) {
  return inputs.linear ? linearBurn(inputs, t) : compoundingBurn(inputs, t);
}

export function project(inputs) {
  return inputs.linear ? projectLinear(inputs) : projectCompounding(inputs);
}

function compoundingBurn({ expenses: E, revenue: R, growth: g }, t) {
  const r = Math.log1p(g);
  const revenueSoFar = r === 0 ? R * t : (R * Math.expm1(r * t)) / r;
  return E * t - revenueSoFar;
}

function projectCompounding(inputs) {
  const { cash, expenses: E, revenue: R, growth: g } = inputs;
  if (![cash, E, R, g].every(Number.isFinite) || cash < 0 || E < 0 || R < 0 || g <= -1) return null;

  if (R >= E) {
    return { verdict: "alive", monthsToProfitability: 0, capitalNeeded: 0, cushion: cash, runwayMonths: null };
  }

  const r = Math.log1p(g);
  if (!(R > 0 && r > 0)) {
    const runway = R === 0 || r === 0
      ? cash / (E - R)
      : monthsUntilBurned(cash, inputs, cash / E, cash / (E - R));
    return { verdict: "dead", monthsToProfitability: null, capitalNeeded: null, cushion: null, runwayMonths: runway };
  }

  const T = Math.log(E / R) / r;
  const C = E * T - (E - R) / r;
  if (C <= cash) {
    return { verdict: "alive", monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: null };
  }
  const runway = monthsUntilBurned(cash, inputs, cash / E, T);
  return { verdict: "dead", monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: runway };
}

function monthsUntilBurned(target, inputs, low, high) {
  if (!(target > 0)) return 0;
  let lo = low, hi = high;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (mid <= lo || mid >= hi) break;
    if (compoundingBurn(inputs, mid) < target) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

// Linear: revenue R + a·t. Closed forms: T = (E−R)/a, capital needed C = (E−R)²/(2a).
function linearBurn({ expenses: E, revenue: R, growth: a }, t) {
  // Shrinking revenue stops at zero; after that the whole expense line burns.
  const t0 = a < 0 ? R / -a : Infinity;
  const s = Math.min(t, t0);
  return (E - R) * s - (a * s * s) / 2 + E * Math.max(0, t - t0);
}

function projectLinear(inputs) {
  const { cash, expenses: E, revenue: R, growth: a } = inputs;
  if (![cash, E, R, a].every(Number.isFinite) || cash < 0 || E < 0 || R < 0) return null;
  if (R >= E) return { verdict: "alive", monthsToProfitability: 0, capitalNeeded: 0, cushion: cash, runwayMonths: null };
  // Smaller root of (a/2)t² − (E−R)t + cash = 0, written so it stays exact as a → 0.
  let runway = (2 * cash) / ((E - R) + Math.sqrt((E - R) ** 2 - 2 * a * cash));
  if (a > 0) {
    const T = (E - R) / a;
    const C = (E - R) ** 2 / (2 * a);
    if (C <= cash) return { verdict: "alive", monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: null };
    return { verdict: "dead", monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: runway };
  }
  const t0 = a < 0 ? R / -a : Infinity;
  if (runway > t0) runway = t0 + (cash - linearBurn(inputs, t0)) / E;
  return { verdict: "dead", monthsToProfitability: null, capitalNeeded: null, cushion: null, runwayMonths: runway };
}

// ── Breakevens.swift ─────────────────────────────────────────────────────────
// For each input: the value that makes capital needed exactly equal cash, holding the
// other three fixed. Capital needed is monotone in every input (up in expenses, down in
// cash/revenue/growth), so each has one crossing. Monthly units. Each result is a
// number, "never" (no value works) or "any" (every value works).

function compoundingCapital(E, R, r) {
  if (R >= E) return 0;
  if (!(R > 0 && r > 0)) return Infinity;
  return E * (Math.log(E / R) / r) - (E - R) / r;
}

// x where f(x) crosses target, given f(lo) and f(hi) straddle it.
function bisect(f, target, lo, hi) {
  const up = f(hi) > f(lo);
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (mid <= lo || mid >= hi) break;
    if ((f(mid) < target) === up) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

export function breakevens(inputs) {
  const { cash, expenses: E, revenue: R, growth: g } = inputs;
  if (inputs.linear) {
    // √(2a·cash) is the revenue gap that cash can carry all the way to profitability.
    const reach = g > 0 ? Math.sqrt(2 * g * cash) : 0;
    return {
      cash: R >= E ? 0 : g > 0 ? (E - R) ** 2 / (2 * g) : "never",
      expenses: R + reach,
      revenue: E - reach <= 0 ? "any" : E - reach,
      growth: R >= E ? "any" : cash === 0 ? "never" : (E - R) ** 2 / (2 * cash),
    };
  }

  const r = Math.log1p(g);
  const C = compoundingCapital(E, R, r);

  let maxExpenses = R;
  if (R > 0 && r > 0) {
    let hi = Math.max(E, R) * 2;
    for (let i = 0; i < 100 && compoundingCapital(hi, R, r) <= cash; i++) hi *= 2;
    maxExpenses = bisect((e) => compoundingCapital(e, R, r), cash, R, hi);
  }

  // Searched in log space, since the answer can sit many orders below E.
  let minRevenue = E;
  if (r > 0 && E > 0) {
    minRevenue = Math.exp(bisect((x) => compoundingCapital(E, Math.exp(x), r), cash, Math.log(E) - 40, Math.log(E)));
  }

  // None needed if already profitable; none suffices from zero revenue or zero cash.
  let minGrowth;
  if (R >= E) minGrowth = "any";
  else if (R === 0 || cash === 0) minGrowth = "never";
  else {
    let hi = 0.01;
    for (let i = 0; i < 100 && compoundingCapital(E, R, Math.log1p(hi)) > cash; i++) hi *= 2;
    minGrowth = bisect((x) => compoundingCapital(E, R, Math.log1p(x)), cash, 0, hi);
  }

  return { cash: Number.isFinite(C) ? C : "never", expenses: maxExpenses, revenue: minRevenue, growth: minGrowth };
}

// ── Formatting.swift ─────────────────────────────────────────────────────────

// Math.round on positives is ties-away-from-zero, matching Swift's .toNearestOrAwayFromZero.
const oneDecimal = (x) => (Math.round(x * 10) / 10).toFixed(1);
const trimZeros = (s) => (s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "") : s);

export function formatMoney(value) {
  const v = Math.abs(value);
  if (v < 0.5) return "$0";
  const sign = value < 0 ? "-" : "";
  for (const [scale, suffix] of [[1e9, "B"], [1e6, "M"], [1e3, "k"]]) {
    if (v >= scale - scale / 2000) {
      const x = v / scale;
      const digits = x < 99.95 ? oneDecimal(x) : String(Math.round(x));
      return `${sign}$${digits.endsWith(".0") ? digits.slice(0, -2) : digits}${suffix}`;
    }
  }
  return `${sign}$${Math.round(v)}`;
}

export const formatMonths = (months) => `${oneDecimal(months)} months`;

// `months` from `start`: whole months on the calendar, the rest as days of 30.436875.
function dateAfter(months, start) {
  const whole = Math.floor(months);
  // Calendar.date(byAdding: .month) clamps to the month's last day (Jan 31 + 1 → Feb 28);
  // Date.setMonth would overflow into March.
  const y = start.getFullYear();
  const m = start.getMonth() + whole;
  const lastDay = new Date(y, m + 1, 0).getDate();
  const base = new Date(y, m, Math.min(start.getDate(), lastDay),
    start.getHours(), start.getMinutes(), start.getSeconds(), start.getMilliseconds());
  return new Date(base.getTime() + (months - whole) * 30.436875 * 86_400_000);
}

export function formatMonthYear(months, start) {
  const date = dateAfter(months, start);
  return `${MONTHS[date.getMonth()]} ${date.getFullYear()}`;
}

// "Jul 10, 2027"
export function formatDate(months, start) {
  const date = dateAfter(months, start);
  return `${MONTHS[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`;
}

// 0.0179 → "1.79%", 0.105 → "10.5%", 1.52 → "152%": three significant digits.
export function formatPercent(fraction) {
  const v = fraction * 100;
  const places = Math.abs(v) >= 100 ? 0 : Math.abs(v) >= 10 ? 1 : 2;
  return `${trimZeros((Math.round(v * 10 ** places) / 10 ** places).toFixed(places))}%`;
}

// Breakeven hints round toward the safe side ("≥" up, "≤" down), so the shown value
// really flips the verdict: $241.04 needed must read "≥ $242", never "≥ $241". They also
// carry one more digit than formatMoney ($7.46k, $252.1k) so the rounding costs little.
// The 1e-9 slack keeps an exact grid value (360000) from stepping to the next one.
const STEPS = [[1e10, 1e8], [1e9, 1e7], [1e7, 1e5], [1e6, 1e4], [1e4, 100], [1e3, 10], [0, 1]];

export function formatMoneyBound(value, roundUp) {
  const v = Math.max(0, value);
  const step = STEPS.find(([from]) => v >= from)[1];
  const r = (roundUp ? Math.ceil(v / step - 1e-9) : Math.floor(v / step + 1e-9)) * step;
  for (const [scale, suffix] of [[1e9, "B"], [1e6, "M"], [1e3, "k"]]) {
    if (r >= scale) {
      const x = r / scale;
      return `$${trimZeros(x.toFixed(x < 10 ? 2 : 1))}${suffix}`;
    }
  }
  return `$${r}`;
}

/// Tax rates keep their significant digits, however small: 0.3983%, 0.00052%.
export function formatRate(fraction, digits = 4) {
  const v = fraction * 100;
  if (v === 0) return "0%";
  const places = Math.max(0, digits - 1 - Math.floor(Math.log10(Math.abs(v))));
  return `${trimZeros((Math.round(v * 10 ** places) / 10 ** places).toFixed(places))}%`;
}

export function formatPercentBound(fraction, roundUp) {
  const v = fraction * 100;
  const places = Math.abs(v) >= 100 ? 0 : Math.abs(v) >= 10 ? 1 : 2;
  const f = 10 ** places;
  const r = (roundUp ? Math.ceil(v * f - 1e-9) : Math.floor(v * f + 1e-9)) / f;
  return `${trimZeros(r.toFixed(places))}%`;
}

// ── Readout.swift ────────────────────────────────────────────────────────────

export function amountValue(text) {
  const n = parseAmount(text);
  return n !== null && n >= 0 ? n : null;
}

export function growthValue(text) {
  const n = parsePercent(text);
  return n !== null && n > -1 ? n : null;
}

/// One typed field → its monthly model value, or null if unusable. $ growth may be negative.
export function fieldValue(key, text, unit, linear, revenueUnit = "month") {
  if (key === "cash") return amountValue(text);
  if (key === "growth" && linear) {
    const n = parseAmount(text);
    return n === null ? null : linearFromUnit(n, unit, revenueUnit);
  }
  if (key === "growth") {
    const g = growthValue(text);
    return g === null ? null : growthFromUnit(g, unit);
  }
  const n = amountValue(text);
  return n === null ? null : amountFromUnit(n, unit);
}

/// A monthly model value → what the field shows in `unit`. Inverse of fieldValue.
/// No "$" or "%": the box draws the unit.
export function fieldText(key, monthly, unit, linear, revenueUnit = "month") {
  if (key === "growth") {
    return normalizeField(linear ? formatMoney(linearToUnit(monthly, unit, revenueUnit)) : formatPercent(growthToUnit(monthly, unit)));
  }
  return normalizeField(formatMoney(key === "cash" ? monthly : amountToUnit(monthly, unit)));
}

// % ↔ $ growth: the same first-period step, measured in the growth field's own unit,
// so 8%/mo on $20k/mo revenue becomes +$1.6k/mo (8% of 20k), and back.
export function switchGrowthKind(monthlyGrowth, toLinear, monthlyRevenue, unit, revenueUnit = "month") {
  const revenue = amountToUnit(monthlyRevenue, revenueUnit);
  if (!(revenue > 0)) return null;
  return toLinear
    ? linearFromUnit(growthToUnit(monthlyGrowth, unit) * revenue, unit, revenueUnit)
    : growthFromUnit(linearToUnit(monthlyGrowth, unit, revenueUnit) / revenue, unit);
}

function hint(key, threshold, units, linear) {
  if (threshold === "never" || threshold === "any") return threshold;
  switch (key) {
    case "cash": return `≥ ${formatMoneyBound(threshold, true)}`;
    case "expenses": return `≤ ${formatMoneyBound(amountToUnit(threshold, units.expenses), false)}`;
    case "revenue": return `≥ ${formatMoneyBound(amountToUnit(threshold, units.revenue), true)}`;
    default: return linear
      ? `≥ ${formatMoneyBound(linearToUnit(threshold, units.growth, units.revenue), true)}`
      : `≥ ${formatPercentBound(growthToUnit(threshold, units.growth), true)}`;
  }
}

const NO_HINTS = { cash: "", expenses: "", revenue: "", growth: "" };

/// Everything the result area and the "alive if" column say, from monthly model inputs
/// (null if a field is unusable). Durations always read in months.
/// `taxes` (prototype, browser only): null, or the assumptions for withTaxes() below.
export function readoutFor(inputs, filledIn, units, now, taxes = null) {
  const taxed = inputs && taxes ? withTaxes(inputs, taxes) : null;
  const p = inputs && project(taxed?.inputs ?? inputs);
  if (!p) {
    return { tone: "neutral", headline: "—", line1: filledIn ? "Check the numbers in red" : "Enter all four numbers", line2: "", hints: NO_HINTS };
  }
  const b = taxed ? taxed.gross(breakevens(taxed.inputs)) : breakevens(inputs);
  const hints = Object.fromEntries(KEYS.map((k) => [k, hint(k, b[k], units, inputs.linear)]));

  // One line under the verdict: when, as a duration and a day.
  if (p.verdict === "alive") {
    const T = p.monthsToProfitability ?? 0;
    if (T === 0) return { tone: "alive", headline: "DEFAULT ALIVE", line1: "Already profitable", line2: "", hints };
    return { tone: "alive", headline: "DEFAULT ALIVE", line1: `Profitable in ${formatMonths(T)} · ${formatDate(T, now)}`, line2: "", hints };
  }
  const runway = p.runwayMonths ?? 0;
  return { tone: "dead", headline: "DEFAULT DEAD", line1: `Out of cash in ${formatMonths(runway)} · ${formatDate(runway, now)}`, line2: "", hints };
}

/// readoutFor, straight from the typed strings.
export function readout(raw, now, units = MONTHLY, linear = false, taxes = null) {
  const values = KEYS.map((k) => fieldValue(k, raw[k], units[k], linear, units.revenue));
  const inputs = values.includes(null) ? null
    : { cash: values[0], expenses: values[1], revenue: values[2], growth: values[3], linear };
  return readoutFor(inputs, KEYS.every((k) => raw[k].trim() !== ""), units, now, taxes);
}

// ── BalanceCurve.swift ───────────────────────────────────────────────────────
// Bank balance from now until the story is told: past profitability (alive), or to zero
// (dead). Returns { points: [{ t, balance }], horizon, marker, verdict } in months.

export function balanceCurve(inputs, samples = 160) {
  const p = project(inputs);
  if (!p) return null;
  let horizon, marker = null;
  if (p.verdict === "alive" && p.monthsToProfitability > 0) {
    horizon = p.monthsToProfitability * 1.35;
    marker = { t: p.monthsToProfitability, balance: p.cushion, kind: "profitable" };
  } else if (p.verdict === "alive") {
    horizon = 24;
  } else {
    horizon = Math.max(p.runwayMonths * 1.15, 1);
    marker = { t: p.runwayMonths, balance: 0, kind: "broke" };
  }
  const end = p.verdict === "dead" ? p.runwayMonths : horizon;
  const points = [];
  for (let i = 0; i <= samples; i++) {
    const t = (end * i) / samples;
    points.push({ t, balance: inputs.cash - cumulativeBurn(inputs, t) });
  }
  return { points, horizon, marker, verdict: p.verdict };
}

// ── Taxes.swift ───────────────────────────────────────────────────────────────
//
// Only taxes that cost money before profitability can change the verdict, because
// default alive asks whether you reach breakeven, and at breakeven profit is zero, so
// income taxes are zero all the way there. What's left are receipts taxes and fixed
// yearly amounts, per state and city, in TAX_PLACES (TaxPlaces.json, built from
// research/ by research/places.mjs; the app compiles in the same file).

export const { places: TAX_PLACES, nothingOwed: TAX_NOTHING_OWED, checked: TAX_CHECKED } = taxCatalog;
const placeById = new Map(TAX_PLACES.map((p) => [p.id, p]));
export const taxPlace = (id) => placeById.get(id) ?? null;
/// Most venture-backed startups are Delaware corporations; every other place is the
/// user's to add.
export const DEFAULT_TAX_PLACES = ["DE"];

/// The share of revenue a place's receipts tax takes, at `annual` revenue: rate × share,
/// or nothing at or under its threshold, or only the part above it for an exclusion.
/// Thresholds are judged on current revenue only; a forecast that crosses one mid-way is
/// ignored (Texas's is worth ~0.03% of revenue).
export function placeRate(place, share, annual) {
  if (place.rate === 0) return 0;
  const t = place.threshold;
  if (!t) return place.rate * share;
  const there = annual * share;
  if ((t.on === "total" ? annual : there) <= t.perYear) return 0;
  return t.excess ? place.rate * share * (1 - t.perYear / there) : place.rate * share;
}

/// "0.36% of revenue there + $64/yr": what a place costs,
/// in a line. `short` drops the threshold, for the checklist.
export function placeSummary(place, short = false) {
  const parts = [];
  if (place.rate > 0) {
    const t = place.threshold;
    const when = !t || short ? ""
      : t.excess ? ` above ${formatMoneyBound(t.perYear, true)}/yr`
      : t.on === "total" ? `, once revenue tops ${formatMoneyBound(t.perYear, true)}/yr`
      : `, once it tops ${formatMoneyBound(t.perYear, true)}/yr`;
    parts.push(short ? formatRate(place.rate) : `${formatRate(place.rate)} of revenue there${when}`);
  }
  if (place.perYear > 0) parts.push(`${formatMoney(place.perYear)}/yr`);
  return parts.join(" + ") || "$0";
}

/// taxes: { [place id]: share }, the share of revenue counted to each place you're in.
/// Returns { inputs, gross, revenueRate, fixedMonthly }: the inputs after taxes (revenue
/// net of receipts taxes, fixed amounts added to expenses), and gross() to turn
/// breakevens computed on those back into the numbers you'd type.
export function withTaxes(inputs, taxes) {
  const annual = inputs.revenue * 12;
  let revenueRate = 0, perYear = 0;
  // Catalog order, not the selection's, so the sum (and its last bit) matches Swift.
  for (const place of TAX_PLACES) {
    if (!(place.id in taxes)) continue;
    revenueRate += placeRate(place, taxes[place.id], annual);
    perYear += place.perYear;
  }
  const fixedMonthly = perYear / 12;
  const keep = 1 - revenueRate;
  const after = {
    ...inputs,
    revenue: inputs.revenue * keep,
    // Linear growth adds taxed revenue too; a % growth rate is unchanged by a flat cut.
    growth: inputs.linear ? inputs.growth * keep : inputs.growth,
    expenses: inputs.expenses + fixedMonthly,
  };
  const gross = (b) => {
    const back = (v, f) => (typeof v === "number" ? f(v) : v);
    return {
      cash: b.cash,
      expenses: back(b.expenses, (v) => Math.max(0, v - fixedMonthly)),
      revenue: back(b.revenue, (v) => v / keep),
      growth: inputs.linear ? back(b.growth, (v) => v / keep) : b.growth,
    };
  };
  return { inputs: after, gross, revenueRate, fixedMonthly };
}

// Dragging the profitability dot changes growth only. As growth varies, the dot
// (T, cash − C) moves along a straight line, since C = k·T with k = E − (E−R)/ln(E/R)
// (compounding) or (E−R)/2 (linear). Project the pointer onto it in screen space, stop at
// the zero line (the default-alive minimum), half a month, and maxMonths. Twin of
// dragProfitPoint in BalanceCurve.swift.
export function dragProfitPoint(t, balance, inputs, px, py, maxMonths = Infinity) {
  const { expenses: E, revenue: R, cash } = inputs;
  if (!(E > R) || !(inputs.linear || R > 0)) return null;
  const k = inputs.linear ? (E - R) / 2 : E - (E - R) / Math.log(E / R);
  if (!(k > 0)) return null;
  const nearest = (px * px * t + k * py * py * (cash - balance)) / (px * px + k * k * py * py);
  const zeroLine = cash / k;
  const T = Math.min(Math.max(nearest, 0.5), maxMonths, zeroLine);
  const growth = inputs.linear ? (E - R) / T : Math.expm1(Math.log(E / R) / T);
  return { monthlyGrowth: growth, monthsToProfitability: T, balance: cash - k * T, pinned: T === zeroLine };
}

// Monthly revenue `t` months from now. Shrinking linear revenue stops at zero.
export function revenueAt(inputs, t) {
  return inputs.linear
    ? Math.max(0, inputs.revenue + inputs.growth * t)
    : inputs.revenue * Math.exp(Math.log1p(inputs.growth) * t);
}
