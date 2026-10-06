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

// ── Readout.swift ────────────────────────────────────────────────────────────
// raw: { cash, expenses, revenue, growth } as typed, monthly, % growth.
// Returns { tone, headline, line1, line2 }.

export function readout(raw, now) {
  const v = [amountValue(raw.cash), amountValue(raw.expenses), amountValue(raw.revenue), growthValue(raw.growth)];
  const p = v.includes(null) ? null : project({ cash: v[0], expenses: v[1], revenue: v[2], growth: v[3] });
  return describe(p, Object.values(raw).every((s) => s.trim() !== ""), now);
}

// The text half of readout(), shared with the prototype's other growth modes.
export function describe(p, filledIn, now) {
  if (!p) {
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

// ═════════════════════════════════════════════════════════════════════════════
// Prototype: not in Swift yet. Design-preview only until approved and ported.
// ═════════════════════════════════════════════════════════════════════════════

// ── Units ────────────────────────────────────────────────────────────────────
// The model runs in months; each flow field can be typed per week, month or year.
// Weeks per month is TLB's 365.2425/7/12. % growth compounds per period, so 8%/mo is
// 1.79%/wk and 152%/yr (not 2% and 96%). $ growth means the per-period revenue figure
// rises by that much each period ("+$10k MRR a month"), so it scales with period².

export const UNITS = {
  week: { months: 12 * 7 / 365.2425, short: "wk" },
  month: { months: 1, short: "mo" },
  year: { months: 12, short: "yr" },
};
export const NEXT_UNIT = { week: "month", month: "year", year: "week" };
const per = (unit) => UNITS[unit].months;
export const amountToUnit = (monthly, unit) => monthly * per(unit);
export const amountFromUnit = (perUnit, unit) => perUnit / per(unit);
export const growthToUnit = (monthly, unit) => Math.expm1(Math.log1p(monthly) * per(unit));
export const growthFromUnit = (perUnit, unit) => Math.expm1(Math.log1p(perUnit) / per(unit));
export const linearToUnit = (monthly, unit) => monthly * per(unit) ** 2;
export const linearFromUnit = (perUnit, unit) => perUnit / per(unit) ** 2;

// 0.0179 → "1.79%", 0.105 → "10.5%", 1.52 → "152%": three significant digits.
export function formatPercent(fraction) {
  const v = fraction * 100;
  const places = Math.abs(v) >= 100 ? 0 : Math.abs(v) >= 10 ? 1 : 2;
  const s = (Math.round(v * 10 ** places) / 10 ** places).toFixed(places);
  return `${s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "") : s}%`;
}

/// One typed field → its monthly model value, or null if unusable. $ growth may be negative.
export function fieldValue(key, text, unit, linear) {
  if (key === "cash") return amountValue(text);
  if (key === "growth" && linear) {
    const n = parseAmount(text);
    return n === null ? null : linearFromUnit(n, unit);
  }
  if (key === "growth") {
    const g = growthValue(text);
    return g === null ? null : growthFromUnit(g, unit);
  }
  const n = amountValue(text);
  return n === null ? null : amountFromUnit(n, unit);
}

/// A monthly model value → what the field shows in `unit`. Inverse of fieldValue.
export function fieldText(key, monthly, unit, linear) {
  if (key === "growth" && !linear) return formatPercent(growthToUnit(monthly, unit));
  const shown = key === "cash" ? monthly : key === "growth" ? linearToUnit(monthly, unit) : amountToUnit(monthly, unit);
  return formatMoney(shown).replace("$", "");
}

// % ↔ $ growth: the same first-period step, measured in the growth field's own unit,
// so 8%/mo on $20k/mo revenue becomes +$1.6k/mo (8% of 20k), and back.
export function switchGrowthKind(monthlyGrowth, toLinear, monthlyRevenue, unit) {
  const revenue = amountToUnit(monthlyRevenue, unit);
  if (!(revenue > 0)) return null;
  return toLinear
    ? linearFromUnit(growthToUnit(monthlyGrowth, unit) * revenue, unit)
    : growthFromUnit(linearToUnit(monthlyGrowth, unit) / revenue, unit);
}

// ── Linear growth ────────────────────────────────────────────────────────────
// Revenue R + a·t, with a in $/month per month. Everything has a closed form:
// T = (E−R)/a, capital needed C = (E−R)²/(2a).

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

export const projectAny = (inputs) => (inputs.linear ? projectLinear(inputs) : project(inputs));
export const burnAny = (inputs, t) => (inputs.linear ? linearBurn(inputs, t) : cumulativeBurn(inputs, t));

// ── Single-lever breakevens ──────────────────────────────────────────────────
// For each input: the value that makes capital needed exactly equal cash, holding the
// other three fixed. Capital needed is monotone in every input (up in expenses, down in
// cash/revenue/growth), so each has one crossing. Monthly units. Each result is a
// number, "never" (no value works) or "any" (every value works).

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
  const C = capitalNeeded(E, R, r);

  let maxExpenses = R;
  if (R > 0 && r > 0) {
    let hi = Math.max(E, R) * 2;
    for (let i = 0; i < 100 && capitalNeeded(hi, R, r) <= cash; i++) hi *= 2;
    maxExpenses = bisect((e) => capitalNeeded(e, R, r), cash, R, hi);
  }

  // Searched in log space, since the answer can sit many orders below E.
  let minRevenue = E;
  if (r > 0 && E > 0) {
    minRevenue = Math.exp(bisect((x) => capitalNeeded(E, Math.exp(x), r), cash, Math.log(E) - 40, Math.log(E)));
  }

  // None needed if already profitable; none suffices from zero revenue or zero cash.
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

// ── Chart data ───────────────────────────────────────────────────────────────
// Bank balance from now until the story is told: past profitability (alive), or to zero
// (dead). Returns { points: [{ t, balance }], horizon, marker, verdict } in months.

export function balanceCurve(inputs, samples = 160) {
  const p = projectAny(inputs);
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
    points.push({ t, balance: inputs.cash - burnAny(inputs, t) });
  }
  return { points, horizon, marker, verdict: p.verdict };
}
