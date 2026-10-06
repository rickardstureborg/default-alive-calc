// Research → Sources/DefaultAliveCore/TaxPlaces.json, the tax checklist both the app and the
// browser mock read. Run: node research/places.mjs
//
// The research is one Opus agent per state (research/workflow.js, Oct 2026), each asked for
// the taxes a pre-profit Delaware C corp selling software/services nationally actually pays:
// receipts taxes and fixed yearly amounts. Income taxes are zero before profit and are left
// out. Next year: rerun the workflow, save it as research/taxes-YYYY-MM.json, point
// RESEARCH below at it, rerun this, and diff TaxPlaces.json.
import fs from "node:fs";

const RESEARCH = "research/taxes-2026-10.json";
const OUT = "Sources/DefaultAliveCore/TaxPlaces.json";

const STATE_CODES = {
  Alabama: "AL", Alaska: "AK", Arizona: "AZ", Arkansas: "AR", California: "CA", Colorado: "CO", Connecticut: "CT",
  Delaware: "DE", Florida: "FL", Georgia: "GA", Hawaii: "HI", Idaho: "ID", Illinois: "IL", Indiana: "IN", Iowa: "IA",
  Kansas: "KS", Kentucky: "KY", Louisiana: "LA", Maine: "ME", Maryland: "MD", Massachusetts: "MA", Michigan: "MI",
  Minnesota: "MN", Mississippi: "MS", Missouri: "MO", Montana: "MT", Nebraska: "NE", Nevada: "NV",
  "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY", "North Carolina": "NC",
  "North Dakota": "ND", Ohio: "OH", Oklahoma: "OK", Oregon: "OR", Pennsylvania: "PA", "Rhode Island": "RI",
  "South Carolina": "SC", "South Dakota": "SD", Tennessee: "TN", Texas: "TX", Utah: "UT", Vermont: "VT",
  Virginia: "VA", Washington: "WA", "West Virginia": "WV", Wisconsin: "WI", Wyoming: "WY",
};

// Thresholds where the law taxes only the amount above them (an exclusion or deduction, per
// each agent's reading of the statute). Every other threshold is a cliff: past it, all the
// revenue there is taxed (SF says so explicitly; so do Texas, Tennessee and the Virginia
// BPOL localities).
const EXCESS = new Set(["DE", "NV", "OH", "OR", "WA-seattle", "GA-atlanta", "NV-reno", "NV-sparks", "CA-culver-city", "WV-parkersburg"]);

// Corrections to the agents' calculator fields. Each says why.
const OVERRIDES = {
  // Hawaii's GET is legally the seller's, but it's routinely itemized on invoices, so it's
  // treated like sales tax (not counted), the same as New Mexico's GRT. User's call, Oct 2026.
  HI: {
    rate: 0, threshold: null,
    note: "Hawaii's 4.5% general excise tax (4% + 0.5% county) is assumed itemized on invoices like sales tax, so it isn't counted; $12.50 annual report.",
  },
  // Agent notes written for a cliff model; these two are now modeled as exclusions.
  "WA-seattle": {
    note: "0.342% (2026) of revenue from Seattle customers above a $2M/yr deduction; nothing owed at or under $2M; $73 business license.",
  },
  OR: {
    note: "0.57% Corporate Activity Tax on Oregon-sourced revenue above $1M/yr (the real tax also adds $250 and subtracts 35% of costs, so this is a ceiling), plus a $150 minimum excise tax and a $275 foreign annual report.",
  },
  // Culver City measures its $200k exclusion on the same receipts it taxes.
  "CA-culver-city": { thresholdOn: "there" },
};

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
// Cities are grouped under their state, so drop the agents' ", MO" / "(DE)" disambiguators.
const cityName = (label) => label.replace(/,\s*[A-Z]{2}$/, "").replace(/\s*\((?:DE|City|Birmingham area)\)$/, "");

const research = JSON.parse(fs.readFileSync(RESEARCH, "utf8"));
const places = [];
const skipped = [];
for (const s of research) {
  const code = STATE_CODES[s.state];
  for (const j of s.jurisdictions) {
    const c = j.calculatorOption;
    const isDC = j.name === "Washington, DC";
    const isState = j.kind === "state" || isDC;
    const state = isDC ? "DC" : code;
    const name = isState ? (isDC ? "Washington, DC" : s.state) : cityName(c.label);
    const id = isState ? state : `${state}-${slug(name)}`;
    // Every state is listed, even at $0, so "nothing owed" is an answer rather than a gap.
    // Local places only when they charge something and the research is at least medium
    // confidence.
    if (!isState && !(c.worthListing && j.confidence !== "low")) {
      skipped.push(`${name}, ${state}${c.worthListing ? " (low confidence)" : ""}`);
      continue;
    }
    const o = OVERRIDES[id] ?? {};
    const thresholdOn = o.thresholdOn ?? (c.thresholdOn === "total revenue" ? "total" : "there");
    const rate = o.rate ?? c.revenueRate;
    const over = "threshold" in o ? o.threshold : c.thresholdPerYear;
    places.push({
      id, name, state, local: !isState,
      rate,
      share: c.defaultShare,
      threshold: rate && over ? { perYear: over, on: thresholdOn, excess: EXCESS.has(id) } : null,
      perYear: Math.round(c.fixedPerYear * 100) / 100,
      note: o.note ?? c.assumptionText,
      confidence: j.confidence,
      sources: j.sources,
    });
  }
}

const stateName = Object.fromEntries([...Object.entries(STATE_CODES).map(([n, c]) => [c, n]), ["DC", "Washington, DC"]]);
places.sort((a, b) => stateName[a.state].localeCompare(stateName[b.state]) || a.local - b.local || a.name.localeCompare(b.name));

for (const id of [...EXCESS, ...Object.keys(OVERRIDES)]) {
  if (!places.some((p) => p.id === id)) throw new Error(`override for unknown place ${id}`);
}
fs.writeFileSync(OUT, JSON.stringify({ checked: "2026-10", places, nothingOwed: skipped }, null, 1) + "\n");
const states = places.filter((p) => !p.local).length;
console.log(`${OUT}: ${places.length} places (${states} states incl. DC, ${places.length - states} local); ${skipped.length} checked and left out`);
