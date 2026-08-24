#!/usr/bin/env node
// Render a dated js-framework-benchmark snapshot for tracking Joy's performance over
// time, and append the run to history.jsonl / HISTORY.md.
//
// Usage:
//   node render.mjs --results <webdriver-ts/results dir> --label "<iso datetime>" \
//        --commit <joy-git-short-sha> --subject "<joy commit subject>" \
//        --chromium "<version>" --out <runs/<slug> dir> [--note "<caveat>"]
//
// Reads result JSONs ("<frameworkVersionString>_<benchmarkId>.json") with shape
//   { framework, benchmark, type, values: { total|DEFAULT: { median, ... } } }
// CPU medians are ms, MEM medians are MB, 40_sizes DEFAULT median is the transfer
// size (KB). See webdriver-ts/src/writeResults.ts.

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, arr) => {
    if (a.startsWith("--")) acc.push([a.slice(2), arr[i + 1]]);
    return acc;
  }, [])
);

const RESULTS = args.results;
const OUT = args.out;
const LABEL = args.label ?? "unknown";
const COMMIT = args.commit ?? "unknown";
const SUBJECT = args.subject ?? "";
const CHROMIUM = args.chromium ?? "";
const ROC = args.roc ?? "";
const NOTE = args.note ?? "";
const HERE = path.dirname(fileURLToPath(import.meta.url));

// A Joy entry's version string comes from its package.json, so find the result
// files by shape instead of pinning a version here. `joy-dev` is this checkout
// (labelled with the commit that built it) and `joy` is the published release,
// measured in the same session so a Joy-vs-Joy delta carries no machine drift.
// `^joy-v` cannot match `joy-dev-v...`, so the two never collide.
const joyKey = (entry, bracket) => {
  const re = new RegExp(`^(${entry}-v[^_-]*-${bracket})_`);
  const hit = fs.readdirSync(RESULTS).map((f) => f.match(re)).find(Boolean);
  return hit ? hit[1] : `${entry}-v?-${bracket}`;
};
// The dev entry is what the history tracks: it is the number that moves.
const JOY_KEYED = joyKey("joy-dev", "keyed");
const JOY_NONKEYED = joyKey("joy-dev", "non-keyed");
const JOY_REL_KEYED = joyKey("joy", "keyed");
const JOY_REL_NONKEYED = joyKey("joy", "non-keyed");

// Name the released rows after the version they ship, so the table says what it
// is being compared against rather than just "released".
const relName = (key, bracket) => {
  const v = key.match(/^joy-v([^_-]*)-/);
  return v ? `Joy ${v[1]} (${bracket})` : `Joy released (${bracket})`;
};

// Display order + friendly names. Joy first so it's the focus, and the keyed entry
// is the headline (it plays in the same bracket as Elm keyed, Leptos and React).
const FRAMEWORKS = [
  { key: JOY_KEYED, name: "Joy dev (keyed)", keyed: true },
  { key: JOY_NONKEYED, name: "Joy dev (non-keyed)", keyed: false },
  { key: JOY_REL_KEYED, name: relName(JOY_REL_KEYED, "keyed"), keyed: true },
  { key: JOY_REL_NONKEYED, name: relName(JOY_REL_NONKEYED, "non-keyed"), keyed: false },
  { key: "elm-v0.19.1-6-keyed", name: "Elm (keyed)", keyed: true },
  { key: "elm-v0.19.1-3-non-keyed", name: "Elm (non-keyed)", keyed: false },
  { key: "halogen-v7.0.0-non-keyed", name: "Halogen", keyed: false },
  { key: "leptos-v0.7.0-keyed", name: "Leptos", keyed: true },
  { key: "solid-v1.9.3-keyed", name: "SolidJS", keyed: true },
  { key: "react-hooks-v19.2.0-keyed", name: "React", keyed: true },
  { key: "vanillajs-non-keyed", name: "vanilla", keyed: false },
];

const CPU = [
  ["01_run1k", "create 1k"],
  ["02_replace1k", "replace all 1k"],
  ["03_update10th1k_x16", "update every 10th (x16)"],
  ["04_select1k", "select row"],
  ["05_swap1k", "swap rows"],
  ["06_remove-one-1k", "remove row"],
  ["07_create10k", "create 10k"],
  ["08_create1k-after1k_x2", "append 1k to 10k"],
  ["09_clear1k_x8", "clear 1k (x8)"],
];
// Only the active memory benchmarks (23/24/26 are disabled upstream in this version).
const MEM = [
  ["21_ready-memory", "ready"],
  ["22_run-memory", "after create 1k"],
  ["25_run-clear-memory", "after clear"],
];
// The 40_sizes benchmark writes sub-results 41_size-uncompressed / 42_size-compressed
// (KB) and 43_first-paint. Bundle size = compressed transfer.
const SIZE_COMPRESSED = "42_size-compressed";
const SIZE_UNCOMPRESSED = "41_size-uncompressed";

function readValues(fwKey, benchId) {
  const f = path.join(RESULTS, `${fwKey}_${benchId}.json`);
  if (!fs.existsSync(f)) return null;
  try {
    const j = JSON.parse(fs.readFileSync(f, "utf8"));
    return j.values.total ?? j.values.DEFAULT ?? Object.values(j.values)[0] ?? null;
  } catch {
    return null;
  }
}

function readMedian(fwKey, benchId) {
  return readValues(fwKey, benchId)?.median ?? null;
}

// How many samples the median was taken over. 07_create10k cannot be batched
// with the rest of the suite, so it runs in its own pass and is the one
// benchmark that can end up with a single sample, which is no median at all.
// Some frameworks are bimodal there, so a lone sample can sit 25% off.
function readSampleCount(fwKey, benchId) {
  const v = readValues(fwKey, benchId);
  return Array.isArray(v?.values) ? v.values.length : null;
}

const geomean = (xs) => {
  const v = xs.filter((x) => x != null && x > 0);
  return v.length ? Math.exp(v.reduce((s, x) => s + Math.log(x), 0) / v.length) : null;
};
const fmt = (x, d = 1) => (x == null ? "-" : x.toFixed(d));

// Collect the matrix.
const cpu = {}; // fwKey -> {benchId -> median}
const mem = {};
const sizeC = {};
const sizeU = {};
for (const fw of FRAMEWORKS) {
  cpu[fw.key] = Object.fromEntries(CPU.map(([id]) => [id, readMedian(fw.key, id)]));
  mem[fw.key] = Object.fromEntries(MEM.map(([id]) => [id, readMedian(fw.key, id)]));
  sizeC[fw.key] = readMedian(fw.key, SIZE_COMPRESSED);
  sizeU[fw.key] = readMedian(fw.key, SIZE_UNCOMPRESSED);
}

// CPU "slowdown factor vs fastest" per benchmark, then geomean per framework. That
// is the standard cross-framework score (1.00 == fastest on every benchmark).
const factorGeomean = {};
for (const fw of FRAMEWORKS) {
  const factors = CPU.map(([id]) => {
    const mine = cpu[fw.key][id];
    const best = Math.min(...FRAMEWORKS.map((f) => cpu[f.key][id]).filter((x) => x != null && x > 0));
    return mine != null && best > 0 ? mine / best : null;
  });
  factorGeomean[fw.key] = geomean(factors);
};
const cpuGeomeanMs = Object.fromEntries(
  FRAMEWORKS.map((fw) => [fw.key, geomean(CPU.map(([id]) => cpu[fw.key][id]))])
);
const memGeomeanMb = Object.fromEntries(
  FRAMEWORKS.map((fw) => [fw.key, geomean(MEM.map(([id]) => mem[fw.key][id]))])
);

// ---- Markdown report ----
const cols = FRAMEWORKS.map((f) => f.name);
const headerRow = (first) => `| ${first} | ${cols.join(" | ")} |`;
const sep = `|${"---|".repeat(cols.length + 1)}`;

let md = "";
md += `# js-framework-benchmark snapshot: ${LABEL}\n\n`;
md += `- **Joy commit:** \`${COMMIT}\`${SUBJECT ? ` (${SUBJECT})` : ""}\n`;
md += `- **Browser:** chromium ${CHROMIUM} (headed)\n`;
if (ROC) md += `- **Roc:** ${ROC}\n`;
md += `- **Frameworks:** ${FRAMEWORKS.map((f) => f.name).join(", ")}\n`;
if (NOTE) md += `- _note: ${NOTE}_\n`;
md += `\n`;

md += `## CPU: median duration (ms, lower is better)\n\n`;
md += headerRow("benchmark") + "\n" + sep + "\n";
for (const [id, label] of CPU) {
  const cells = FRAMEWORKS.map((fw) => fmt(cpu[fw.key][id]));
  md += `| ${label} | ${cells.join(" | ")} |\n`;
}
md += `| **geomean (ms)** | ${FRAMEWORKS.map((fw) => "**" + fmt(cpuGeomeanMs[fw.key]) + "**").join(" | ")} |\n`;
md += `| **slowdown vs best** | ${FRAMEWORKS.map((fw) => "**" + fmt(factorGeomean[fw.key], 2) + "×**").join(" | ")} |\n\n`;

// Say so in the report when create 10k rests on too few samples to have a
// median, rather than letting it read like every other cell in the table.
const thin = FRAMEWORKS.map((fw) => [fw, readSampleCount(fw.key, "07_create10k")]).filter(
  ([, n]) => n != null && n < 2,
);
if (thin.length) {
  md += `> ⚠ **create 10k is a single sample** for ${thin.map(([fw]) => fw.name).join(", ")}. `;
  md += `That benchmark runs in its own pass and some frameworks are bimodal there, so a lone `;
  md += `sample can sit well off the field. Re-measure before reading a change into it.\n\n`;
}

md += `## Memory: heap (MB, lower is better)\n\n`;
md += headerRow("benchmark") + "\n" + sep + "\n";
for (const [id, label] of MEM) {
  md += `| ${label} | ${FRAMEWORKS.map((fw) => fmt(mem[fw.key][id], 1)).join(" | ")} |\n`;
}
md += `| **geomean (MB)** | ${FRAMEWORKS.map((fw) => "**" + fmt(memGeomeanMb[fw.key], 1) + "**").join(" | ")} |\n\n`;

md += `## Bundle size: transfer (KB, lower is better)\n\n`;
md += headerRow("metric") + "\n" + sep + "\n";
md += `| compressed KB | ${FRAMEWORKS.map((fw) => fmt(sizeC[fw.key], 1)).join(" | ")} |\n`;
md += `| uncompressed KB | ${FRAMEWORKS.map((fw) => fmt(sizeU[fw.key], 1)).join(" | ")} |\n\n`;

// Dev against the release, both measured in this session. This is the only Joy
// comparison here that no machine drift can reach, so it is the one to read
// when asking whether a change helped.
const pct = (dev, rel) => (dev == null || rel == null ? null : ((dev - rel) / rel) * 100);
const signed = (x) => (x == null ? "-" : `${x >= 0 ? "+" : ""}${x.toFixed(1)}%`);
md += `## Dev vs released, same session\n\n`;
md += `| | dev | ${relName(JOY_REL_KEYED, "keyed").replace(" (keyed)", "")} | change |\n|---|---|---|---|\n`;
for (const [label, dev, rel] of [
  ["CPU geomean, keyed (ms)", cpuGeomeanMs[JOY_KEYED], cpuGeomeanMs[JOY_REL_KEYED]],
  ["CPU geomean, non-keyed (ms)", cpuGeomeanMs[JOY_NONKEYED], cpuGeomeanMs[JOY_REL_NONKEYED]],
  ["memory, keyed (MB)", memGeomeanMb[JOY_KEYED], memGeomeanMb[JOY_REL_KEYED]],
  ["bundle, keyed (KB)", sizeC[JOY_KEYED], sizeC[JOY_REL_KEYED]],
]) {
  md += `| ${label} | ${fmt(dev, 2)} | ${fmt(rel, 2)} | ${signed(pct(dev, rel))} |\n`;
}
md += `\nNegative is dev being better. Both arms ran back to back in one session, so\n`;
md += `this comparison is free of the day-to-day drift that makes cross-run Joy deltas\n`;
md += `hard to read. The apps are not identical, though: the released entry is frozen at\n`;
md += `the app it shipped with, so a delta is product-level, not platform-only.\n\n`;

md += `> Headline for tracking: **Joy keyed CPU geomean = ${fmt(cpuGeomeanMs[JOY_KEYED])} ms** `;
md += `(${fmt(factorGeomean[JOY_KEYED], 2)}× the per-benchmark best), `;
md += `non-keyed ${fmt(cpuGeomeanMs[JOY_NONKEYED])} ms (${fmt(factorGeomean[JOY_NONKEYED], 2)}×), `;
md += `**memory ${fmt(memGeomeanMb[JOY_KEYED], 1)} MB**, `;
md += `**bundle ${fmt(sizeC[JOY_KEYED], 1)} KB** compressed.\n`;

fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, "report.md"), md);

// ---- history.jsonl (append) + HISTORY.md (regenerate) ----
function round(x, d = 2) {
  return x == null ? null : Math.round(x * 10 ** d) / 10 ** d;
}
const histLine = {
  timestamp: LABEL,
  joyCommit: COMMIT,
  // The compiler is the confounder a size delta is most often hiding: a nightly
  // bump moved the bundle 25% on 2026-08-25 with the source unchanged.
  roc: ROC || null,
  // The commit subject says what changed between rows, so the history reads
  // as a changelog. Commit before benchmarking to keep it truthful.
  subject: SUBJECT,
  keyed: {
    cpuGeomeanMs: round(cpuGeomeanMs[JOY_KEYED]),
    slowdownVsBest: round(factorGeomean[JOY_KEYED], 3),
    memGeomeanMb: round(memGeomeanMb[JOY_KEYED]),
    bundleKb: round(sizeC[JOY_KEYED]),
    cpu: Object.fromEntries(CPU.map(([id]) => [id, round(cpu[JOY_KEYED][id])])),
  },
  nonKeyed: {
    cpuGeomeanMs: round(cpuGeomeanMs[JOY_NONKEYED]),
    slowdownVsBest: round(factorGeomean[JOY_NONKEYED], 3),
    memGeomeanMb: round(memGeomeanMb[JOY_NONKEYED]),
    bundleKb: round(sizeC[JOY_NONKEYED]),
    cpu: Object.fromEntries(CPU.map(([id]) => [id, round(cpu[JOY_NONKEYED][id])])),
  },
};
const histPath = path.join(HERE, "history.jsonl");
fs.appendFileSync(histPath, JSON.stringify(histLine) + "\n");

const hist = fs
  .readFileSync(histPath, "utf8")
  .trim()
  .split("\n")
  .map((l) => JSON.parse(l));
let h = `# Joy performance history (js-framework-benchmark)\n\n`;
h += `Each row is one run. Lower is better, and "slowdown" is the geomean factor vs\n`;
h += `the fastest framework on each CPU benchmark. See \`runs/<timestamp>/report.md\` for\n`;
h += `the full cross-framework table of that run.\n\n`;
h += `| run | commit | roc | change | keyed CPU (ms) | keyed slowdown | non-keyed CPU (ms) | non-keyed slowdown | memory (MB) | bundle (KB) |\n`;
h += `|---|---|---|---|---|---|---|---|---|---|\n`;
// Rows may carry a hand-written `note` (add it to the row's line in history.jsonl) for
// caveats that must survive regeneration, e.g. "geomean not comparable, stale results".
const notes = [];
for (const r of hist) {
  let mark = "";
  if (r.note) {
    notes.push(r.note);
    mark = `<sup>${notes.length}</sup>`;
  }
  h += `| ${r.timestamp}${mark} | \`${r.joyCommit}\` | ${r.roc ?? ""} | ${r.subject ?? ""} | ${fmt(r.keyed?.cpuGeomeanMs)} | ${fmt(r.keyed?.slowdownVsBest, 2)}× | ${fmt(r.nonKeyed?.cpuGeomeanMs)} | ${fmt(r.nonKeyed?.slowdownVsBest, 2)}× | ${fmt(r.keyed?.memGeomeanMb, 1)} | ${fmt(r.keyed?.bundleKb, 1)} |\n`;
}
if (notes.length) {
  h += `\n`;
  notes.forEach((n, i) => {
    h += `<sup>${i + 1}</sup> ${n}\n\n`;
  });
}
fs.writeFileSync(path.join(HERE, "HISTORY.md"), h);

console.log(`Wrote ${path.join(OUT, "report.md")}`);
console.log(`Joy CPU geomean: keyed ${fmt(cpuGeomeanMs[JOY_KEYED])} ms (${fmt(factorGeomean[JOY_KEYED], 2)}x vs best), non-keyed ${fmt(cpuGeomeanMs[JOY_NONKEYED])} ms (${fmt(factorGeomean[JOY_NONKEYED], 2)}x)`);
console.log(`Updated ${histPath} and HISTORY.md (${hist.length} run(s))`);
