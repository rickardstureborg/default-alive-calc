// JS twin of Sources/DefaultAliveCore (same names, formulas, rounding) so the browser
// preview shows the numbers the app will. design/presets.json pins both sides: change
// wording or math in one and `make test` fails until the other (and the `expect`s) match.

const SUFFIXES = { k: 1e3, m: 1e6, b: 1e9 };
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// ── Parsing.swift ────────────────────────────────────────────────────────────

// Digits with at most one decimal point and an optional leading minus. Number() alone
// also accepts "Infinity", "1e3" and hex, none of which belong in a money field.
function plainNumber(s) {
  const body = s.startsWith("-") ? s.slice(1) : s;
  if (!/^\d*\.?\d*$/.test(body) || !/\d/.test(body)) return null;
  return Number(s);
}

export function parseAmount(text) {
  let s = text.trim().toLowerCase();
  if (s.startsWith("$")) s = s.slice(1);
  s = s.replaceAll(",", "");
  let multiplier = 1;
  const last = s.at(-1);
  if (last && Object.hasOwn(SUFFIXES, last)) {
    multiplier = SUFFIXES[last];
    s = s.slice(0, -1);
  }
  const n = plainNumber(s.trim());
  return n === null ? null : n * multiplier;
}

export function parsePercent(text) {
  let s = text.trim();
  if (s.endsWith("%")) s = s.slice(0, -1);
  const n = plainNumber(s.trim());
  return n === null ? null : n / 100;
}

// ── Readout.swift (field ranges) ─────────────────────────────────────────────

export function amountValue(text) {
  const n = parseAmount(text);
  return n !== null && n >= 0 ? n : null;
}

export function growthValue(text) {
  const n = parsePercent(text);
  return n !== null && n > -1 ? n : null;
}

// ── Projection.swift ─────────────────────────────────────────────────────────
// inputs: { cash, expenses, revenue, growth }, all monthly; growth is a fraction.

export function cumulativeBurn({ expenses: E, revenue: R, growth: g }, t) {
  const r = Math.log1p(g);
  const revenueSoFar = r === 0 ? R * t : (R * Math.expm1(r * t)) / r;
  return E * t - revenueSoFar;
}

export function project(inputs) {
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
    if (cumulativeBurn(inputs, mid) < target) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

// ── Formatting.swift ─────────────────────────────────────────────────────────

// Math.round on positives is ties-away-from-zero, matching Swift's .toNearestOrAwayFromZero.
const oneDecimal = (x) => (Math.round(x * 10) / 10).toFixed(1);

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

export function formatMonthYear(months, start) {
  const whole = Math.floor(months);
  // Calendar.date(byAdding: .month) clamps to the month's last day (Jan 31 + 1 → Feb 28);
  // Date.setMonth would overflow into March.
  const y = start.getFullYear();
  const m = start.getMonth() + whole;
  const lastDay = new Date(y, m + 1, 0).getDate();
  const base = new Date(y, m, Math.min(start.getDate(), lastDay),
    start.getHours(), start.getMinutes(), start.getSeconds(), start.getMilliseconds());
  const date = new Date(base.getTime() + (months - whole) * 30.436875 * 86_400_000);
  return `${MONTHS[date.getMonth()]} ${date.getFullYear()}`;
}

// ── Periods (prototype; not in Swift yet) ────────────────────────────────────
// The model runs in months. Flows typed per week or year convert in; growth compounds,
// so 8%/mo is 1.79%/wk and 152%/yr, not 2% and 96%. Weeks per month is TLB's 365.2425/7/12.

export const UNITS = {
  week: { months: 12 * 7 / 365.2425, adjective: "Weekly", plural: "weeks", short: "wk" },
  month: { months: 1, adjective: "Monthly", plural: "months", short: "mo" },
  year: { months: 12, adjective: "Yearly", plural: "years", short: "yr" },
};
export const amountToUnit = (monthly, unit) => monthly * UNITS[unit].months;
export const amountFromUnit = (perUnit, unit) => perUnit / UNITS[unit].months;
export const growthToUnit = (monthly, unit) => Math.expm1(Math.log1p(monthly) * UNITS[unit].months);
export const growthFromUnit = (perUnit, unit) => Math.expm1(Math.log1p(perUnit) / UNITS[unit].months);
export const formatDuration = (months, unit) => `${oneDecimal(months / UNITS[unit].months)} ${UNITS[unit].plural}`;

// 0.0179 → "1.79%", 0.105 → "10.5%", 1.52 → "152%": three significant digits.
export function formatPercent(fraction) {
  const v = fraction * 100;
  const places = Math.abs(v) >= 100 ? 0 : Math.abs(v) >= 10 ? 1 : 2;
  const s = (Math.round(v * 10 ** places) / 10 ** places).toFixed(places);
  return `${s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "") : s}%`;
}

/// Typed strings (per `unit`) → monthly model inputs, or null if any field is unusable.
export function monthlyInputs(raw, unit = "month") {
  const cash = amountValue(raw.cash);
  const expenses = amountValue(raw.expenses);
  const revenue = amountValue(raw.revenue);
  const growth = growthValue(raw.growth);
  if ([cash, expenses, revenue, growth].includes(null)) return null;
  return {
    cash,
    expenses: amountFromUnit(expenses, unit),
    revenue: amountFromUnit(revenue, unit),
    growth: growthFromUnit(growth, unit),
  };
}

// ── Single-lever breakevens (prototype; not in Swift yet) ────────────────────
// For each input: the value that makes capital needed exactly equal cash, holding the
// other three fixed. Capital needed is monotone in every input (up in expenses, down in
// cash/revenue/growth), so each has one crossing and bisection finds it. Monthly units.
// Each result is a number, or "never" (no value works), or "any" (every value works).

function capitalNeeded(E, R, r) {
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

export function breakevens({ cash, expenses: E, revenue: R, growth: g }) {
  const r = Math.log1p(g);
  const growing = R > 0 && r > 0;
  const C = capitalNeeded(E, R, r);

  // Expenses: alive up to the E where capital needed reaches cash.
  let maxExpenses = R;
  if (growing) {
    let hi = Math.max(E, R) * 2;
    for (let i = 0; i < 100 && capitalNeeded(hi, R, r) <= cash; i++) hi *= 2;
    maxExpenses = bisect((e) => capitalNeeded(e, R, r), cash, R, hi);
  }

  // Revenue: searched in log space, since the answer can sit many orders below E.
  let minRevenue = E;
  if (r > 0 && E > 0) {
    minRevenue = Math.exp(bisect((x) => capitalNeeded(E, Math.exp(x), r), cash, Math.log(E) - 40, Math.log(E)));
  }

  // Growth: none needed if already profitable; none suffices from zero revenue or zero cash.
  let minGrowth;
  if (R >= E) minGrowth = "any";
  else if (R === 0 || cash === 0) minGrowth = "never";
  else {
    let hi = 0.01;
    for (let i = 0; i < 100 && capitalNeeded(E, R, Math.log1p(hi)) > cash; i++) hi *= 2;
    minGrowth = bisect((x) => capitalNeeded(E, R, Math.log1p(x)), cash, 0, hi);
  }

  return { cash: Number.isFinite(C) ? C : "never", expenses: maxExpenses, revenue: minRevenue, growth: minGrowth };
}

// Bank balance from now until the story is told: past profitability (alive), or to zero
// (dead). Returns { points: [{ t, balance }], horizon, marker } in months.
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

// ── Readout.swift ────────────────────────────────────────────────────────────
// raw: { cash, expenses, revenue, growth } as typed. Returns { tone, headline, line1, line2 }.

// `unit` is what the strings were typed in; durations read out in `displayUnit`.
export function readout(raw, now, unit = "month", displayUnit = unit) {
  const inputs = monthlyInputs(raw, unit);
  const p = inputs && project(inputs);
  const formatMonths = (m) => formatDuration(m, displayUnit);
  if (!p) {
    const filledIn = ![raw.cash, raw.expenses, raw.revenue, raw.growth].some((s) => s.trim() === "");
    return { tone: "neutral", headline: "—", line1: filledIn ? "Check the numbers in red" : "Enter all four numbers", line2: "" };
  }

  if (p.verdict === "alive") {
    const T = p.monthsToProfitability ?? 0;
    if (T === 0) {
      return { tone: "alive", headline: "DEFAULT ALIVE", line1: "Already profitable", line2: "Revenue covers expenses" };
    }
    return {
      tone: "alive", headline: "DEFAULT ALIVE",
      line1: `Profitable in ${formatMonths(T)} · ${formatMonthYear(T, now)}`,
      line2: `Needs ${formatMoney(p.capitalNeeded ?? 0)} · ${formatMoney(p.cushion ?? 0)} to spare`,
    };
  }

  const runway = p.runwayMonths ?? 0;
  const line1 = runway === 0
    ? "Out of cash now"
    : `Out of cash in ${formatMonths(runway)} · ${formatMonthYear(runway, now)}`;
  const line2 = p.capitalNeeded !== null && p.cushion !== null
    ? `Needs ${formatMoney(p.capitalNeeded)} · ${formatMoney(-p.cushion)} short`
    : "Never profitable at this growth";
  return { tone: "dead", headline: "DEFAULT DEAD", line1, line2 };
}
