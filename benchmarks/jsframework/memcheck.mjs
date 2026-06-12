// Memory leak / high-water check: drive N create-1k/clear cycles on the Joy benchmark
// entry and measure total agent memory after each, using the same metric the benchmark
// uses (performance.measureUserAgentSpecificMemory, which counts the WASM heap and GCs
// first). Growing per cycle => leak. Plateau => allocator high-water / fragmentation.
//
// Run it from the benchmark clone's webdriver-ts dir (where `playwright` is installed),
// with the benchmark server running on :8080 and the nix chromium path in $CHROME:
//
//   cp benchmarks/jsframework/memcheck.mjs ~/dev/js-framework-benchmark/webdriver-ts/
//   ( cd ~/dev/js-framework-benchmark && npm start & )
//   direnv exec ~/dev/js-framework-benchmark bash -c '
//     export CHROME=$(ls -d "$PLAYWRIGHT_BROWSERS_PATH"/chromium-*/chrome-linux64/chrome | head -1)
//     cd ~/dev/js-framework-benchmark/webdriver-ts && node memcheck.mjs'
import { chromium } from "playwright";

const CHROME = process.env.CHROME;
const URL = "http://localhost:8080/frameworks/non-keyed/joy/dist/index.html";
const CYCLES = 10;

const browser = await chromium.launch({ executablePath: CHROME, headless: true });
const page = await browser.newPage();
await page.goto(URL, { waitUntil: "networkidle" });
await page.waitForSelector("#run");

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
