#!/usr/bin/env node
// Render a dated js-framework-benchmark snapshot for tracking Joy's performance over
// time, and append the run to history.jsonl / HISTORY.md.
//
// Usage:
//   node render.mjs --results <webdriver-ts/results dir> --label "<iso datetime>" \
//        --commit <joy-git-short-sha> --subject "<joy commit subject>" \
//        --chromium "<version>" --out <runs/<slug> dir> [--note "<caveat>"] \
//        [--rounds <runs/<slug>/rounds dir>] [--icount <runs/<slug>/icount dir>]
//
// With --rounds, every result found under that directory is pooled with the
// other copies of the same result, so one median covers every round, and the
// first directory level under it names the round a copy came from. A result
// with no copy there is read from --results, which is how frameworks this run
// did not re-measure keep their cached numbers. --icount is where run.roc put
// the instruction counts, one <entry>-<bracket>.json per Joy arm.
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
const ROUNDS = args.rounds ?? null;
const ICOUNT = args.icount ?? null;
const HERE = path.dirname(fileURLToPath(import.meta.url));

// Every copy of each result under --rounds: file name -> [{ round, file }].
const copies = new Map();
const walk = (dir, round) => {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, round ?? e.name);
    else if (e.name.endsWith(".json")) {
      if (!copies.has(e.name)) copies.set(e.name, []);
      copies.get(e.name).push({ round, file: p });
    }
  }
};
if (ROUNDS && fs.existsSync(ROUNDS)) walk(ROUNDS, null);
const roundNames = [...new Set([...copies.values()].flat().map((c) => c.round))].sort();

// A Joy entry's version string comes from its package.json, so find the result
// files by shape instead of pinning a version here. `joy-dev` is this checkout
// (labelled with the commit that built it) and `joy` is the published release,
// measured in the same session so a Joy-vs-Joy delta carries no machine drift.
// `^joy-v` cannot match `joy-dev-v...`, so the two never collide.
// A version this run measured wins over one cached from an earlier run, so
// swapping the release for another build does not pick up the old numbers.
const joyKey = (entry, bracket) => {
  const re = new RegExp(`^(${entry}-v[^_-]*-${bracket})_`);
  const hit = [...copies.keys(), ...fs.readdirSync(RESULTS)].map((f) => f.match(re)).find(Boolean);
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

const sampleValues = (file) => {
  try {
    const j = JSON.parse(fs.readFileSync(file, "utf8"));
    const v = j.values.total ?? j.values.DEFAULT ?? Object.values(j.values)[0];
    return Array.isArray(v?.values) ? v.values : v?.median != null ? [v.median] : [];
  } catch {
    return [];
  }
};
const median = (xs) => {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

// A result's samples from every round, and per round.
function pooled(fwKey, benchId) {
  const found = copies.get(`${fwKey}_${benchId}.json`);
  if (!found) return null;
  const byRound = new Map();
  for (const { round, file } of found) {
    byRound.set(round, [...(byRound.get(round) ?? []), ...sampleValues(file)]);
  }
  return { values: [...byRound.values()].flat(), byRound };
}

function readValues(fwKey, benchId) {
  const p = pooled(fwKey, benchId);
  if (p) return { median: median(p.values), values: p.values };
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
if (roundNames.length) md += `- **Rounds:** ${roundNames.length}, the arms in reverse order in each one after the first, medians pooled over all of them\n`;
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
// A seeded generator, so the same results always render the same interval.
const rng = (() => {
  let a = 0x9e3779b9;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
})();
const resample = (xs) => xs.map(() => xs[Math.floor(rng() * xs.length)]);
// 95% bootstrap interval of the change in median, in percent.
const interval = (dev, rel) => {
  const changes = [];
  for (let i = 0; i < 2000; i++) changes.push((median(resample(dev)) / median(resample(rel)) - 1) * 100);
  changes.sort((a, b) => a - b);
  return [changes[49], changes[1949]];
};
const noiseTable = (devKey, relKey) => {
  let t = `| benchmark | dev (ms) | released (ms) | change | 95% interval | ${roundNames.map((r) => `round ${r}`).join(" | ")} | verdict |\n`;
  t += `|---|---|---|---|---|${"---|".repeat(roundNames.length)}---|\n`;
  for (const [id, label] of CPU) {
    const d = pooled(devKey, id);
    const r = pooled(relKey, id);
    if (!d || !r || !d.values.length || !r.values.length) {
      t += `| ${label} | ${fmt(cpu[devKey][id])} | ${fmt(cpu[relKey][id])} | ${signed(pct(cpu[devKey][id], cpu[relKey][id]))} | - | ${roundNames.map(() => "-").join(" | ")} | - |\n`;
      continue;
    }
    const change = pct(median(d.values), median(r.values));
    const [lo, hi] = interval(d.values, r.values);
    const perRound = roundNames.map((n) => pct(median(d.byRound.get(n) ?? []), median(r.byRound.get(n) ?? [])));
    // A change counts only when the interval leaves out zero and every round
    // moved the same way. The interval alone treats all samples as one
    // batch, so it cannot see a round that drifted as a whole.
    const agree = perRound.every((x) => x != null && Math.sign(x) === Math.sign(change));
    const verdict = (lo > 0 || hi < 0) && agree ? (change > 0 ? "slower" : "faster") : "noise";
    t += `| ${label} | ${fmt(median(d.values))} | ${fmt(median(r.values))} | ${signed(change)} | ${signed(lo)} to ${signed(hi)} | ${perRound.map(signed).join(" | ")} | ${verdict} |\n`;
  }
  return t;
};
if (roundNames.length) {
  md += `### Keyed\n\n` + noiseTable(JOY_KEYED, JOY_REL_KEYED) + `\n`;
  md += `### Non-keyed\n\n` + noiseTable(JOY_NONKEYED, JOY_REL_NONKEYED) + `\n`;
  md += `A change is called only when its 95% bootstrap interval leaves out zero and every\n`;
  md += `round moved the same way. Everything else is \`noise\`, whatever the size of the change.\n\n`;
}
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

// ---- Instruction counts ----
const counts = (entry, bracket) => {
  const f = ICOUNT && path.join(ICOUNT, `${entry}-${bracket}.json`);
  if (!f || !fs.existsSync(f)) return null;
  return JSON.parse(fs.readFileSync(f, "utf8"));
};
const ic = {
  keyed: { dev: counts("joy-dev", "keyed"), rel: counts("joy", "keyed") },
  nonKeyed: { dev: counts("joy-dev", "non-keyed"), rel: counts("joy", "non-keyed") },
};
const instrGeomean = (c) => (c ? geomean(CPU.map(([id]) => c[id]?.instr)) : null);
const millions = (x) => (x == null ? null : x / 1e6);
const countTable = ({ dev, rel }) => {
  let t = `| benchmark | dev instr (M) | released instr (M) | change | dev DOM calls | released DOM calls | dev bulk (KB) | released bulk (KB) |\n`;
  t += `|---|---|---|---|---|---|---|---|\n`;
  for (const [id, label] of CPU) {
    const d = dev?.[id];
    const r = rel?.[id];
    t += `| ${label} | ${fmt(millions(d?.instr), 2)} | ${fmt(millions(r?.instr), 2)} | ${signed(pct(d?.instr, r?.instr))} | ${d?.dom ?? "-"} | ${r?.dom ?? "-"} | ${fmt(d && d.bulk / 1024)} | ${fmt(r && r.bulk / 1024)} |\n`;
  }
  const gd = instrGeomean(dev);
  const gr = instrGeomean(rel);
  t += `| **geomean** | **${fmt(millions(gd), 2)}** | **${fmt(millions(gr), 2)}** | **${signed(pct(gd, gr))}** | | | | |\n`;
  return t;
};
if (ic.keyed.dev || ic.nonKeyed.dev) {
  md += `## Instruction counts: per measured click (exact, lower is better)\n\n`;
  md += `Wasm instructions executed, calls into the DOM, and bytes moved by \`memory.copy\`\n`;
  md += `and \`memory.fill\` for each benchmark's measured click, replayed on the fake DOM\n`;
  md += `after the same warmups as the browser run (icount.mjs). They are the same on every\n`;
  md += `run and every machine, so any change here is real. What they leave out is the\n`;
  md += `browser's style, layout and paint, and how well the engine compiles the wasm.\n\n`;
  md += `### Keyed\n\n` + countTable(ic.keyed) + `\n`;
  md += `### Non-keyed\n\n` + countTable(ic.nonKeyed) + `\n`;
}

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
  rounds: roundNames.length || 1,
  keyed: {
    cpuGeomeanMs: round(cpuGeomeanMs[JOY_KEYED]),
    slowdownVsBest: round(factorGeomean[JOY_KEYED], 3),
    memGeomeanMb: round(memGeomeanMb[JOY_KEYED]),
    bundleKb: round(sizeC[JOY_KEYED]),
    cpu: Object.fromEntries(CPU.map(([id]) => [id, round(cpu[JOY_KEYED][id])])),
    instrGeomeanM: round(millions(instrGeomean(ic.keyed.dev)), 3),
    instr: ic.keyed.dev ? Object.fromEntries(CPU.map(([id]) => [id, ic.keyed.dev[id]?.instr ?? null])) : null,
  },
  nonKeyed: {
    cpuGeomeanMs: round(cpuGeomeanMs[JOY_NONKEYED]),
    slowdownVsBest: round(factorGeomean[JOY_NONKEYED], 3),
    memGeomeanMb: round(memGeomeanMb[JOY_NONKEYED]),
    bundleKb: round(sizeC[JOY_NONKEYED]),
    cpu: Object.fromEntries(CPU.map(([id]) => [id, round(cpu[JOY_NONKEYED][id])])),
    instrGeomeanM: round(millions(instrGeomean(ic.nonKeyed.dev)), 3),
    instr: ic.nonKeyed.dev ? Object.fromEntries(CPU.map(([id]) => [id, ic.nonKeyed.dev[id]?.instr ?? null])) : null,
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
h += `the full cross-framework table of that run. The instruction columns are the geomean of\n`;
h += `the wasm instructions per measured click, exact and free of machine noise.\n\n`;
h += `| run | commit | roc | change | keyed CPU (ms) | keyed slowdown | non-keyed CPU (ms) | non-keyed slowdown | memory (MB) | bundle (KB) | keyed instr (M) | non-keyed instr (M) |\n`;
h += `|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
// Rows may carry a hand-written `note` (add it to the row's line in history.jsonl) for
// caveats that must survive regeneration, e.g. "geomean not comparable, stale results".
const notes = [];
for (const r of hist) {
  let mark = "";
  if (r.note) {
    notes.push(r.note);
    mark = `<sup>${notes.length}</sup>`;
  }
  h += `| ${r.timestamp}${mark} | \`${r.joyCommit}\` | ${r.roc ?? ""} | ${r.subject ?? ""} | ${fmt(r.keyed?.cpuGeomeanMs)} | ${fmt(r.keyed?.slowdownVsBest, 2)}× | ${fmt(r.nonKeyed?.cpuGeomeanMs)} | ${fmt(r.nonKeyed?.slowdownVsBest, 2)}× | ${fmt(r.keyed?.memGeomeanMb, 1)} | ${fmt(r.keyed?.bundleKb, 1)} | ${fmt(r.keyed?.instrGeomeanM, 2)} | ${fmt(r.nonKeyed?.instrGeomeanM, 2)} |\n`;
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
