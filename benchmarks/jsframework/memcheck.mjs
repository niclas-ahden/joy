// Memory leak / high-water check: drive N create-1k/clear cycles on a Joy benchmark
// entry and measure total agent memory after each, using the same metric the benchmark
// uses (performance.measureUserAgentSpecificMemory, which counts the WASM heap and GCs
// first). Growing per cycle => leak. Plateau => allocator high-water / fragmentation.
//
// Run it from the benchmark clone's webdriver-ts dir (where `playwright` is installed),
// with the benchmark server running on :8080. FRAMEWORK picks the entry (default
// keyed/joy):
//
//   cp benchmarks/jsframework/memcheck.mjs path/to/js-framework-benchmark/webdriver-ts/
//   ( cd path/to/js-framework-benchmark && npm start & )
//   cd path/to/js-framework-benchmark/webdriver-ts && FRAMEWORK=keyed/joy node memcheck.mjs
//
// With $CHROME unset Playwright launches its own chromium. On NixOS (the clone's
// dev shell) point it at the nix one instead:
//
//   direnv exec path/to/js-framework-benchmark bash -c '
//     export CHROME=$(ls -d "$PLAYWRIGHT_BROWSERS_PATH"/chromium-*/chrome-linux64/chrome | head -1)
//     cd path/to/js-framework-benchmark/webdriver-ts && FRAMEWORK=keyed/joy node memcheck.mjs'
import { chromium } from "playwright";

const CHROME = process.env.CHROME;
const FRAMEWORK = process.env.FRAMEWORK ?? "keyed/joy";
const URL = `http://localhost:8080/frameworks/${FRAMEWORK}/index.html`;
const CYCLES = 10;

const browser = await chromium.launch({ executablePath: CHROME, headless: true });
const page = await browser.newPage();
await page.goto(URL, { waitUntil: "networkidle" });
await page.waitForSelector("#run");

console.log("framework:", FRAMEWORK);
console.log("crossOriginIsolated:", await page.evaluate(() => self.crossOriginIsolated));

async function memMB() {
  const bytes = await page.evaluate(async () => {
    const r = await performance.measureUserAgentSpecificMemory();
    return r.bytes;
  });
  return bytes / 1048576;
}

console.log("cycle\tafter_create(MB)\tafter_clear(MB)");
for (let i = 0; i < CYCLES; i++) {
  await page.click("#run");
  await page.waitForSelector("tbody > tr:nth-of-type(1000)");
  const created = await memMB();

  await page.click("#clear");
  await page.waitForFunction(() => document.querySelectorAll("tbody > tr").length === 0);
  const cleared = await memMB();

  console.log(`${i}\t${created.toFixed(1)}\t${cleared.toFixed(1)}`);
}

await browser.close();
