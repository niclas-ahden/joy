#!/usr/bin/env node
// Say where the time of a js-framework-benchmark click goes, for several
// builds of a Joy entry side by side. The benchmark gives one number per
// click. This splits it into Joy's own click handler and the browser's style,
// layout and paint, and can name the functions the handler spent its time in.
//
// Profile builds in a real Chromium, in one session:
//
//   node profile.mjs [options] <label>=<entry dir> [<label>=<entry dir> ...]
//
//     --mode phases|cpu   phases is the default. cpu adds V8's sampling
//                         profiler, which slows every click a little and
//                         names the functions the handler was in.
//     --clicks N          measured clicks per build and benchmark (20)
//     --benches a,b       create, update, select, selectwarm, swap, remove,
//                         clear (select,swap)
//     --js-flags "..."    more V8 flags, like --liftoff-only or --no-liftoff
//
//   An entry dir holds index.html and dist/, like frameworks/keyed/joy-dev in
//   the js-framework-benchmark clone, or what compare.roc leaves under
//   build/compare/<commit>/entries/.
//
// Or split the traces the benchmark runner kept of its own measured clicks,
// with no browser:
//
//   node profile.mjs traces <traces dir> <benchmark id> <entry name> [...]
//
//   The traces dir is webdriver-ts/traces in the clone, a benchmark id is
//   04_select1k, and an entry name is joy-dev-v<version>-keyed.
//
// It uses the Playwright and the stylesheet of the js-framework-benchmark
// clone: the folder it runs in, or the one JS_FRAMEWORK_BENCHMARK_DIR names.
// Where the clone has a dev shell of its own, run it inside that
// (`cd <clone> && direnv exec . node <path>/profile.mjs ...`), so that it finds
// the browser.
//
// It measures the way the runner does: one browser for all the clicks of a
// build and a benchmark, a fresh page for each click, the runner's warmups, a
// forced GC and the runner's CPU slowdown. The browser keeps what it compiled
// of a page from one load to the next, so only the first clicks run code the
// browser has never seen, as in the runner. The builds each have a browser of
// their own, open side by side, and take turns going first. The numbers are
// medians, in milliseconds at that slowdown.
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';

const PHASES = ['UpdateLayoutTree', 'Layout', 'PrePaint', 'Paint', 'Layerize', 'Commit'];
const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? (s[(s.length - 1) >> 1] + s[s.length >> 1]) / 2 : 0;
};

// What the renderer's main thread did between the last click in a trace and
// the end of the last commit after it, which is the stretch the benchmark
// reports as the click's duration.
function phasesOf(events) {
  const done = events.filter((e) => e.ph === 'X');
  const click = done.filter((e) => e.name === 'EventDispatch' && e.args?.data?.type === 'click').sort((a, b) => a.ts - b.ts).at(-1);
  if (!click) return null;
  const main = done.filter((e) => e.pid === click.pid && e.tid === click.tid && e.ts >= click.ts);
  const commits = main.filter((e) => e.name === 'Commit');
  if (commits.length === 0) return null;
  const end = commits.at(-1).ts + commits.at(-1).dur;
  const out = { total: (end - click.ts) / 1000, handler: click.dur / 1000 };
  // A phase inside another one, or inside the handler, is that one's time.
  const staged = main.filter((e) => PHASES.includes(e.name) && e.ts + e.dur <= end + 1);
  const top = staged.filter((e) => e.ts >= click.ts + click.dur && !staged.some((o) => o !== e && o.ts <= e.ts && o.ts + o.dur >= e.ts + e.dur && (o.dur > e.dur || o.ts < e.ts)));
  for (const name of PHASES) out[name] = top.filter((e) => e.name === name).reduce((a, e) => a + e.dur, 0) / 1000;
  // Style or layout the handler forced by reading from the page.
  out.forced = staged.filter((e) => e.ts < click.ts + click.dur).reduce((a, e) => a + e.dur, 0) / 1000;
  out.gc = main.filter((e) => (e.name === 'MinorGC' || e.name === 'MajorGC') && e.ts + e.dur <= end + 1).reduce((a, e) => a + e.dur, 0) / 1000;
  out.rest = out.total - out.handler - PHASES.reduce((a, name) => a + out[name], 0);
  out.styled = main.filter((e) => e.name === 'UpdateLayoutTree').reduce((a, e) => a + (e.args?.elementCount ?? 0), 0);
  return { out, click };
}

// How long each function was on top of the stack while the click handler ran,
// from the sampling profiler's chunks in a trace.
function handlerSelfTimes(events, click) {
  const nodes = new Map();
  const samples = [];
  const start = events.find((e) => e.name === 'Profile' && e.pid === click.pid)?.args?.data?.startTime;
  for (const e of events.filter((x) => x.name === 'ProfileChunk' && x.pid === click.pid).sort((a, b) => a.ts - b.ts)) {
    for (const node of e.args?.data?.cpuProfile?.nodes ?? []) nodes.set(node.id, node);
    const ids = e.args?.data?.cpuProfile?.samples ?? [];
    const deltas = e.args?.data?.timeDeltas ?? [];
    let at = samples.length ? samples.at(-1).ts : (start ?? e.ts);
    ids.forEach((id, i) => {
      at += deltas[i] ?? 0;
      samples.push({ id, ts: at });
    });
  }
  const self = {};
  for (let i = 0; i < samples.length - 1; i++) {
    const { id, ts } = samples[i];
    if (ts < click.ts || ts > click.ts + click.dur) continue;
    const frame = nodes.get(id)?.callFrame ?? {};
    const file = frame.url ? frame.url.split('/').at(-1) : '';
    const name = `${frame.functionName || '(anonymous)'}${file ? ' @' + file : ''}`;
    self[name] = (self[name] ?? 0) + (samples[i + 1].ts - ts) / 1000;
  }
  return self;
}

function printPhases(title, rows) {
  const keys = ['total', 'handler', ...PHASES, 'gc', 'forced', 'rest'];
  console.log(`\n=== ${title}`);
  console.log(['build'.padEnd(14), ...keys.map((k) => k.slice(0, 9).padStart(9)), '   styled'].join(' '));
  for (const [label, all] of rows) {
    console.log([label.slice(0, 14).padEnd(14), ...keys.map((k) => median(all.map((p) => p[k])).toFixed(2).padStart(9)), String(median(all.map((p) => p.styled))).padStart(9)].join(' '));
  }
}

const argv = process.argv.slice(2);

if (argv[0] === 'traces') {
  const [, dir, bench, ...entries] = argv;
  if (!dir || !bench || entries.length === 0) {
    console.error('usage: node profile.mjs traces <traces dir> <benchmark id> <entry name> [...]');
    process.exit(2);
  }
  const rows = entries.map((entry) => {
    const files = readdirSync(dir).filter((f) => f.startsWith(`${entry}_${bench}_`) && f.endsWith('.json'));
    const all = files.map((f) => {
      const raw = JSON.parse(readFileSync(join(dir, f), 'utf8'));
      return phasesOf(raw.traceEvents ?? raw)?.out;
    }).filter(Boolean);
    return [`${entry} (${all.length})`, all];
  });
  printPhases(`${bench}: median ms per click, from the runner's traces`, rows.map(([label, all]) => [label.replace(/^joy-?/, '').replace(/-v/, ' ').slice(0, 14), all]));
  for (const [label] of rows) console.log(`  ${label}`);
  process.exit(0);
}

const option = (name, fallback) => {
  const at = argv.indexOf(`--${name}`);
  return at < 0 ? fallback : argv[at + 1];
};
const mode = option('mode', 'phases');
const clicks = Number(option('clicks', 20));
const chosen = option('benches', 'select,swap').split(',');
const jsFlags = ['--expose-gc', ...option('js-flags', '').split(' ').filter(Boolean)].join(' ');
const builds = argv.filter((a) => /^[A-Za-z0-9.]+=/.test(a)).map((a) => {
  const [label, ...dir] = a.split('=');
  return { label, dir: resolve(dir.join('=')) };
});
// The clone: named, or the folder this runs in.
const fork = process.env.JS_FRAMEWORK_BENCHMARK_DIR ?? (existsSync('webdriver-ts/node_modules/playwright') ? process.cwd() : undefined);
if (builds.length === 0 || !fork) {
  console.error('usage: node profile.mjs [--mode phases|cpu] [--clicks N] [--benches a,b] [--js-flags "..."] <label>=<entry dir> [...]');
  if (!fork) console.error('Run this in your js-framework-benchmark clone, or name the clone in JS_FRAMEWORK_BENCHMARK_DIR.');
  process.exit(2);
}

const { chromium } = createRequire(`${fork}/webdriver-ts/`)('playwright');

// The entries at /<label>/, and the clone's stylesheet where their pages ask for it.
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.css': 'text/css' };
const server = createServer((req, res) => {
  try {
    const [, first, ...rest] = decodeURIComponent(new URL(req.url, 'http://x').pathname).split('/');
    const build = builds.find((b) => b.label === first);
    const path = build ? join(build.dir, ...rest) : join(fork, first, ...rest);
    const body = readFileSync(path);
    res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((ready) => server.listen(0, '127.0.0.1', ready));
const base = `http://127.0.0.1:${server.address().port}`;

// The nix shell names its browser, and without one Playwright has its own.
const browsers = process.env.PLAYWRIGHT_BROWSERS_PATH;
const chrome = browsers ? `${browsers}/${readdirSync(browsers).find((d) => d.startsWith('chromium-'))}/chrome-linux64/chrome` : undefined;

// The steps and the CPU slowdown of webdriver-ts/src/benchmarksPlaywright.ts
// and benchmarksCommon.ts. selectwarm is ours: the select click once its code
// has run forty times, to tell code that is slower from code that is new.
const row = (n) => `tbody>tr:nth-of-type(${n})>td:nth-of-type(2)>a`;
const remove = (n) => `tbody>tr:nth-of-type(${n})>td:nth-of-type(3)>a`;
const filled = async (page) => {
  await page.click('#run');
  await page.waitForSelector(row(1000));
};
const times = async (n, step) => {
  for (let i = 0; i < n; i++) await step(i);
};
const benches = {
  create: { slow: 1, warm: (page) => times(5, async () => { await filled(page); await page.click('#clear'); await page.waitForSelector(row(1), { state: 'detached' }); }), measured: '#run' },
  update: { slow: 4, warm: async (page) => { await filled(page); await times(3, () => page.click('#update')); }, measured: '#update' },
  select: { slow: 4, warm: async (page) => { await filled(page); await page.click(row(5)); }, measured: row(2) },
  selectwarm: { slow: 4, warm: async (page) => { await filled(page); await times(40, (i) => page.click(row(3 + (i % 7)))); }, measured: row(2) },
  swap: { slow: 4, warm: async (page) => { await filled(page); await times(6, () => page.click('#swaprows')); }, measured: '#swaprows' },
  remove: { slow: 2, warm: async (page) => { await filled(page); await times(5, (i) => page.click(remove(5 - i + 4))); await page.click(remove(6)); }, measured: remove(4) },
  clear: { slow: 4, warm: async (page) => { await times(5, async () => { await filled(page); await page.click('#clear'); await page.waitForSelector(row(1), { state: 'detached' }); }); await filled(page); }, measured: '#clear' },
};
for (const bench of chosen) {
  if (!benches[bench]) {
    console.error(`unknown benchmark ${bench}, expected one of ${Object.keys(benches).join(', ')}`);
    process.exit(2);
  }
}
const categories = ['blink.user_timing', 'devtools.timeline', 'disabled-by-default-devtools.timeline']
  .concat(mode === 'cpu' ? ['v8', 'disabled-by-default-v8.cpu_profiler', 'disabled-by-default-v8.cpu_profiler.hires'] : []);

const launch = () => chromium.launch({ headless: false, executablePath: chrome, args: ['--window-size=1000,800', `--js-flags=${jsFlags}`, '--enable-benchmarking'] });

async function once(browser, label, bench) {
  const page = await browser.newPage();
  try {
    const client = await page.context().newCDPSession(page);
    await page.goto(`${base}/${label}/index.html`, { waitUntil: 'networkidle' });
    await page.waitForSelector('#run');
    await benches[bench].warm(page);
    await page.evaluate("window.gc({type:'major',execution:'sync',flavor:'last-resort'})");
    if (benches[bench].slow > 1) await client.send('Emulation.setCPUThrottlingRate', { rate: benches[bench].slow });
    await browser.startTracing(page, { screenshots: false, categories });
    await page.click(benches[bench].measured);
    await new Promise((r) => setTimeout(r, 60));
    const trace = JSON.parse((await browser.stopTracing()).toString());
    return trace.traceEvents ?? trace;
  } finally {
    await page.close();
  }
}

const results = {};
for (const bench of chosen) {
  results[bench] = Object.fromEntries(builds.map((b) => [b.label, { phases: [], self: [] }]));
  const open = Object.fromEntries(await Promise.all(builds.map(async (b) => [b.label, await launch()])));
  for (let i = 0; i < clicks; i++) {
    // Each round walks the builds from another start and in another direction,
    // so that none always goes first.
    const order = builds.map((_, k) => builds[(k + i) % builds.length].label);
    if (i % 2 === 1) order.reverse();
    for (const label of order) {
      const events = await once(open[label], label, bench);
      const found = phasesOf(events);
      if (!found) continue;
      results[bench][label].phases.push(found.out);
      if (mode === 'cpu') results[bench][label].self.push(handlerSelfTimes(events, found.click));
    }
  }
  await Promise.all(Object.values(open).map((browser) => browser.close()));
}
server.close();

for (const bench of chosen) {
  const flags = option('js-flags', '');
  printPhases(`${bench}: median ms over ${clicks} clicks, CPU slowed ${benches[bench].slow}x (${mode}${flags ? ', ' + flags : ''})`, builds.map((b) => [b.label, results[bench][b.label].phases]));
  if (mode !== 'cpu') continue;
  for (const { label } of builds) {
    const all = results[bench][label].self;
    const names = new Set(all.flatMap((s) => Object.keys(s)));
    const mean = [...names].map((name) => [name, all.reduce((a, s) => a + (s[name] ?? 0), 0) / all.length]).sort((a, b) => b[1] - a[1]);
    const where = { wasm: 0, 'runtime.js': 0, 'the browser': 0 };
    for (const [name, ms] of mean) where[name.includes('wasm') ? 'wasm' : name.includes('@runtime') ? 'runtime.js' : 'the browser'] += ms;
    console.log(`\n${label}: inside the handler, mean ms per click: ${Object.entries(where).map(([k, v]) => `${k} ${v.toFixed(2)}`).join(', ')}`);
    for (const [name, ms] of mean.slice(0, 14)) console.log(`  ${ms.toFixed(3)}  ${name}`);
  }
}
console.log(`
total     from the click to the end of the last commit, what the benchmark reports
handler   Joy's own share: the wasm and runtime.js that the click ran
forced    style or layout inside the handler, which a read from the page forces
rest      what no column holds, mostly waiting for the frame
styled    elements the browser restyled, the same number for the same DOM change`);
