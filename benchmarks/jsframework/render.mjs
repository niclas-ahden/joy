#!/usr/bin/env node
// Render a dated js-framework-benchmark snapshot for tracking Joy's performance over
// time, and append the run to history.jsonl / HISTORY.md.
//
// Usage:
//   node render.mjs --results <webdriver-ts/results dir> --label "<iso datetime>" \
//        --commit <joy-git-short-sha> --subject "<joy commit subject>" \
//        --chromium "<version>" --out <runs/<slug> dir>
//
// Reads result JSONs ("<frameworkVersionString>_<benchmarkId>.json") with shape
//   { framework, benchmark, type, values: { total|DEFAULT: { median, ... } } }
// CPU medians are ms, MEM medians are MB, 40_sizes DEFAULT median is the transfer
// size (KB). See webdriver-ts/src/writeResults.ts.

import * as fs from "node:fs";
import * as path from "node:path";

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
// percy is a separate repo where most perf optimizations live, so track its commit too.
const PERCY = args["percy-commit"] ?? "unknown";
const NOTE = args.note ?? "";
const HERE = path.dirname(new URL(import.meta.url).pathname);

// Display order + friendly names. Joy first so it's the focus.
const FRAMEWORKS = [
  { key: "joy-v0.0.1-non-keyed", name: "Joy", keyed: false },
  { key: "elm-v0.19.1-3-non-keyed", name: "Elm (non-keyed)", keyed: false },
  { key: "elm-v0.19.1-6-keyed", name: "Elm (keyed)", keyed: true },
  { key: "leptos-v0.7.0-keyed", name: "Leptos", keyed: true },
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

function readMedian(fwKey, benchId) {
  const f = path.join(RESULTS, `${fwKey}_${benchId}.json`);
  if (!fs.existsSync(f)) return null;
  try {
    const j = JSON.parse(fs.readFileSync(f, "utf8"));
    const v = j.values.total ?? j.values.DEFAULT ?? Object.values(j.values)[0];
    return v?.median ?? null;
  } catch {
    return null;
  }
}

const geomean = (xs) => {
  const v = xs.filter((x) => x != null && x > 0);
  return v.length ? Math.exp(v.reduce((s, x) => s + Math.log(x), 0) / v.length) : null;
};
const fmt = (x, d = 1) => (x == null ? "—" : x.toFixed(d));

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

// CPU "slowdown factor vs fastest" per benchmark, then geomean per framework — the
// standard cross-framework score (1.00 == fastest on every benchmark).
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
md += `# js-framework-benchmark snapshot — ${LABEL}\n\n`;
md += `- **Joy commit:** \`${COMMIT}\`${SUBJECT ? ` — ${SUBJECT}` : ""}\n`;
md += `- **percy commit:** \`${PERCY}\`\n`;
md += `- **Browser:** chromium ${CHROMIUM} (headed), Playwright 1.59.1\n`;
md += `- **Frameworks:** ${FRAMEWORKS.map((f) => f.name).join(", ")}\n`;
if (NOTE) md += `- _note: ${NOTE}_\n`;
md += `\n`;

md += `## CPU — median duration (ms, lower is better)\n\n`;
md += headerRow("benchmark") + "\n" + sep + "\n";
for (const [id, label] of CPU) {
  const cells = FRAMEWORKS.map((fw) => fmt(cpu[fw.key][id]));
  md += `| ${label} | ${cells.join(" | ")} |\n`;
}
md += `| **geomean (ms)** | ${FRAMEWORKS.map((fw) => "**" + fmt(cpuGeomeanMs[fw.key]) + "**").join(" | ")} |\n`;
md += `| **slowdown vs best** | ${FRAMEWORKS.map((fw) => "**" + fmt(factorGeomean[fw.key], 2) + "×**").join(" | ")} |\n\n`;

md += `## Memory — heap (MB, lower is better)\n\n`;
md += headerRow("benchmark") + "\n" + sep + "\n";
for (const [id, label] of MEM) {
  md += `| ${label} | ${FRAMEWORKS.map((fw) => fmt(mem[fw.key][id], 1)).join(" | ")} |\n`;
}
md += `| **geomean (MB)** | ${FRAMEWORKS.map((fw) => "**" + fmt(memGeomeanMb[fw.key], 1) + "**").join(" | ")} |\n\n`;

md += `## Bundle size — transfer (KB, lower is better)\n\n`;
md += headerRow("metric") + "\n" + sep + "\n";
md += `| compressed KB | ${FRAMEWORKS.map((fw) => fmt(sizeC[fw.key], 1)).join(" | ")} |\n`;
md += `| uncompressed KB | ${FRAMEWORKS.map((fw) => fmt(sizeU[fw.key], 1)).join(" | ")} |\n\n`;

md += `> Headline for tracking: **Joy CPU geomean = ${fmt(cpuGeomeanMs["joy-v0.0.1-non-keyed"])} ms** `;
md += `(${fmt(factorGeomean["joy-v0.0.1-non-keyed"], 2)}× the per-benchmark best), `;
md += `**memory ${fmt(memGeomeanMb["joy-v0.0.1-non-keyed"], 1)} MB**, `;
md += `**bundle ${fmt(sizeC["joy-v0.0.1-non-keyed"], 1)} KB** compressed.\n`;

fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, "report.md"), md);

// ---- history.jsonl (append) + HISTORY.md (regenerate) ----
const histLine = {
  timestamp: LABEL,
  joyCommit: COMMIT,
  percyCommit: PERCY,
  joyCpuGeomeanMs: round(cpuGeomeanMs["joy-v0.0.1-non-keyed"]),
  joySlowdownVsBest: round(factorGeomean["joy-v0.0.1-non-keyed"], 3),
  joyMemGeomeanMb: round(memGeomeanMb["joy-v0.0.1-non-keyed"]),
  joyBundleKb: round(sizeC["joy-v0.0.1-non-keyed"]),
  joyCpu: Object.fromEntries(CPU.map(([id]) => [id, round(cpu["joy-v0.0.1-non-keyed"][id])])),
};
function round(x, d = 2) {
  return x == null ? null : Math.round(x * 10 ** d) / 10 ** d;
}
const histPath = path.join(HERE, "history.jsonl");
fs.appendFileSync(histPath, JSON.stringify(histLine) + "\n");

const hist = fs
  .readFileSync(histPath, "utf8")
  .trim()
  .split("\n")
  .map((l) => JSON.parse(l));
let h = `# Joy performance history (js-framework-benchmark)\n\n`;
h += `Each row is one full run. Lower is better; "slowdown" is the geomean factor vs the\n`;
h += `fastest framework on each CPU benchmark. See \`runs/<timestamp>/report.md\` for the\n`;
h += `full cross-framework table of that run.\n\n`;
h += `| run | Joy commit | percy commit | CPU geomean (ms) | slowdown vs best | memory (MB) | bundle (KB) |\n`;
h += `|---|---|---|---|---|---|---|\n`;
// Rows may carry a hand-written `note` (add it to the row's line in history.jsonl) for
// caveats that must survive regeneration — e.g. "geomean not comparable, stale results".
const notes = [];
for (const r of hist) {
  let mark = "";
  if (r.note) {
    notes.push(r.note);
    mark = `<sup>${notes.length}</sup>`;
  }
  h += `| ${r.timestamp}${mark} | \`${r.joyCommit}\` | \`${r.percyCommit ?? "—"}\` | ${fmt(r.joyCpuGeomeanMs)} | ${fmt(r.joySlowdownVsBest, 2)}× | ${fmt(r.joyMemGeomeanMb, 1)} | ${fmt(r.joyBundleKb, 1)} |\n`;
}
if (notes.length) {
  h += `\n`;
  notes.forEach((n, i) => {
    h += `<sup>${i + 1}</sup> ${n}\n\n`;
  });
}
fs.writeFileSync(path.join(HERE, "HISTORY.md"), h);

console.log(`Wrote ${path.join(OUT, "report.md")}`);
console.log(`Joy CPU geomean: ${fmt(cpuGeomeanMs["joy-v0.0.1-non-keyed"])} ms  (${fmt(factorGeomean["joy-v0.0.1-non-keyed"], 2)}x vs best)`);
console.log(`Updated ${histPath} and HISTORY.md (${hist.length} run(s))`);
