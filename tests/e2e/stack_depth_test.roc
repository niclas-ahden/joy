# Real-browser E2E for deep views and crashes. The node harness
# (tests/check_stack_overflow.mjs) drives real overflows to a trap at every
# opt level. This test covers what only Chromium can: a crash reaching window
# through real event dispatch, a dead instance ignoring clicks, and the depth
# budgets holding with real elements.
#
# It never drives a real overflow. The renderer dies below the wasm stack's
# own limit at depths that vary per machine, same Chromium build: Blink's
# layout recursion tab-crashes on attached trees (~1,800 levels on one
# machine, >10,000 on another), and deep wasm recursion can crash the tab
# outright instead of throwing Node's RangeError (~3,000 levels against
# Node's 9,700, same wasm). So the deep phase uses a detached root, never
# laid out, and asserts a budget instead of hunting the ceiling. Speed builds
# only: a dev level costs ~4x the shadow stack, the budget is not promised
# there.
#
# The page mounts deep.roc with empty flags (depth 1). Each scenario
# re-mounts through the page's own ./runtime.js at the depth it needs.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
}

import pf.Env
import pf.Stdout
import playwright.Playwright
import Browser

# Replace the page's app with one mounted at the given depth, through the
# same ./runtime.js module the page itself imports. The mount resolves before
# the expression returns, so the next click hits the new instance.
remount = |depth|
	\\(async () => {
	\\  const { mount } = await import('./runtime.js')
	\\  const root = document.getElementById('app')
	\\  root.replaceChildren()
	\\  window.app = await mount({ wasm: './app.wasm', root, flags: '${depth}' })
	\\  return 'mounted'
	\\})()

# Mount at the given depth into a root that never attaches to the document.
# Same wasm and runtime work, real elements, but no layout, so depths past
# Blink's ceiling stay reachable.
remount_detached = |depth|
	\\(async () => {
	\\  const { mount } = await import('./runtime.js')
	\\  const root = document.createElement('div')
	\\  window.deepRoot = root
	\\  window.app = await mount({ wasm: './app.wasm', root, flags: '${depth}' })
	\\  return 'mounted'
	\\})()

# Mount through makeRuntime with the dispatch export wrapped, so a click
# throws the engine error a real overflow trap does, on demand. A real
# overflow can crash the tab instead (see above), and the runtime handles a
# trap the same whatever caused it. The flags put the button's target at 50
# levels, so a dead instance that still dispatched would change the DOM.
fault_mount =
	\\(async () => {
	\\  const { makeRuntime, browserDom } = await import('./runtime.js')
	\\  const bytes = await (await fetch('./app.wasm')).arrayBuffer()
	\\  const { instance } = await WebAssembly.instantiate(bytes, {})
	\\  const real = instance.exports
	\\  window.__fault = true
	\\  const exports = {
	\\    ...real,
	\\    dispatch: (id) => {
	\\      if (window.__fault) throw new WebAssembly.RuntimeError('memory access out of bounds')
	\\      return real.dispatch(id)
	\\    },
	\\  }
	\\  const root = document.getElementById('app')
	\\  root.replaceChildren()
	\\  makeRuntime(exports, browserDom, root).start('50')
	\\  return 'mounted'
	\\})()

app_divs = "String(document.querySelectorAll('#app div').length)"

# Playwright cannot click a detached node, so the deep phase dispatches
# through the DOM. A throwing listener still reports to window, where the
# trap listens.
click_detached = "(window.deepRoot.querySelector('button').click(), 'clicked')"

detached_divs = "String(window.deepRoot.querySelectorAll('div').length)"

# Uncaught errors from event listeners surface on window, nowhere else a test
# can reach. Arm a trap before a click to catch anything it throws.
arm_error_trap =
	\\(window.__joyErr = null,
	\\ window.addEventListener('error', (e) => {
	\\  window.__joyErr = String((e.error && e.error.message) || e.message)
	\\ }, { once: true }),
	\\ 'armed')

main! = |_args| {
	{ browser, page } = Browser.open!("deep", "#app button")?

	# The attached budget: 1000 levels render in a real, laid-out tree. Kept
	# under Blink's layout ceiling, ~1,800 at its lowest observed.
	_ = page.evaluate!(remount("1000"))?
	page.find("#app button").click!()?
	divs = page.evaluate!(app_divs)?
	if I64.from_str(divs) ?? 0 < 1000 {
		Err(DeepRenderTooShallow(divs))?
	}

	# A trap during a real click reaches window as the runtime's crash
	# error. Disarming the fault afterwards proves the instance stays dead:
	# the next click would render 50 levels if it still dispatched.
	_ = page.evaluate!(fault_mount)?
	before = page.evaluate!(app_divs)?
	_ = page.evaluate!(arm_error_trap)?
	page.find("#app button").click!()?
	crash_err = page.evaluate!("window.__joyErr || '(no error)'")?
	if !crash_err.contains("Joy: the app crashed") {
		Err(CrashNotReported(crash_err))?
	}
	_ = page.evaluate!("(window.__fault = false, 'disarmed')")?
	page.find("#app button").click!()?
	after = page.evaluate!(app_divs)?
	if after != before {
		Err(DeadInstanceStillDispatches(after))?
	}

	# JOY_OPT comes from e2e.roc. Anything but speed skips the deep budget,
	# loudly.
	opt = Env.var_str!("JOY_OPT") ?? ""
	if opt == "speed" {
		deep_budget!(page)?
	} else {
		Stdout.line!("JOY_OPT=${opt}: the deep budget only runs on speed builds")?
	}

	browser.close!()?
	Ok({})
}

# The speed-only budget: 2500 levels render and re-diff cleanly in a
# detached tree. The first click builds (the cheap REPLACE path), the
# second re-walks the full depth through diff and diff_children, the
# deepest-framed path the host has.
deep_budget! = |page| {
	budget : I64
	budget = 2500
	_ = page.evaluate!(remount_detached(budget.to_str()))?
	_ = page.evaluate!(arm_error_trap)?
	_ = page.evaluate!(click_detached)?
	built = page.evaluate!("window.__joyErr || '(ok)'")?
	if built != "(ok)" {
		Err(RediffBudgetBuildFailed(built))?
	}
	deep_divs = page.evaluate!(detached_divs)?
	if I64.from_str(deep_divs) ?? 0 < budget {
		Err(RediffBudgetTooShallow(deep_divs))?
	}
	_ = page.evaluate!(arm_error_trap)?
	_ = page.evaluate!(click_detached)?
	rediff_err = page.evaluate!("window.__joyErr || '(ok)'")?
	if rediff_err != "(ok)" {
		Err(RediffBudgetNotMet(rediff_err))?
	}

	Ok({})
}
