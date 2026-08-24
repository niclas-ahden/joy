# Real-browser E2E for the stack overflow canary. The node harness
# (tests/check_stack_canary.mjs) drives real overflows to a loud failure at
# every opt level. This test covers what only Chromium can: the overflow
# error reaching window, a dead instance ignoring clicks, and the depth
# budgets holding with real elements.
#
# It never drives a real overflow. The renderer dies below Joy's guards at
# depths that vary per machine, same Chromium build: Blink's layout
# recursion tab-crashes on attached trees (~1,800 levels on one machine,
# >10,000 on another), and deep wasm recursion can crash the tab outright
# instead of throwing Node's RangeError (~3,000 levels against Node's
# 9,700, same wasm). So the deep phase uses a detached root, never laid
# out, and asserts a budget instead of hunting the ceiling. Speed builds
# only: a dev level costs ~4x the shadow stack, the budget is not promised
# there.
#
# The page mounts deep.roc with empty flags (depth 1). Each scenario
# re-mounts through the page's own ./runtime.js at the depth it needs.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
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

# Playwright cannot click a detached node, so the deep phase dispatches
# through the DOM. A throwing listener still reports to window, where the
# trap listens.
click_detached = "(window.deepRoot.querySelector('button').click(), 'clicked')"

detached_divs = "String(window.deepRoot.querySelectorAll('div').length)"

# Uncaught errors from event listeners surface on window, nowhere else a test
# can reach. Arm a trap before the click that is expected to blow up.
arm_error_trap =
	\\(window.__joyErr = null,
	\\ window.addEventListener('error', (e) => {
	\\  window.__joyErr = String((e.error && e.error.message) || e.message)
	\\ }, { once: true }),
	\\ 'armed')

canary_ok = "String(window.app.instance.exports.stack_canary_ok())"

poke_band =
	\\(() => {
	\\  const ex = window.app.instance.exports
	\\  new Uint32Array(ex.memory.buffer, ex.stack_floor(), 1)[0] = 0
	\\  return 'poked'
	\\})()

main! = |_args| {
	{ browser, page } = Browser.open!("deep", "#app button")?

	# The attached budget: 1000 levels render in a real, laid-out tree and
	# leave the canary alone. Kept under Blink's layout ceiling, ~1,800 at
	# its lowest observed.
	_ = page.evaluate!(remount("1000"))?
	page.find("#app button").click!()?
	divs = page.evaluate!("String(document.querySelectorAll('#app div').length)")?
	if I64.from_str(divs) ?? 0 < 1000 {
		Err(DeepRenderTooShallow(divs))?
	}
	ok_before = page.evaluate!(canary_ok)?
	if ok_before != "1" {
		Err(CanaryTrippedInsideBudget(ok_before))?
	}

	# Corrupting the band by hand proves the detection path end to end: the
	# next dispatch throws the runtime's overflow error, the browser reports
	# it as an uncaught error, and the instance is dead afterwards.
	_ = page.evaluate!(arm_error_trap)?
	_ = page.evaluate!(poke_band)?
	page.find("#app button").click!()?
	poked_err = page.evaluate!("window.__joyErr || '(no error)'")?
	if !poked_err.contains("shadow stack overflowed") {
		Err(PokedBandNotReported(poked_err))?
	}
	ok_after = page.evaluate!(canary_ok)?
	if ok_after != "0" {
		Err(PokedBandNotDetected(ok_after))?
	}

	# A dead instance ignores further dispatches: the DOM stays where the
	# last good render left it, however hard the button is clicked.
	page.find("#app button").click!()?
	after = page.evaluate!("String(document.querySelectorAll('#app div').length)")?
	if after != divs {
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

# The speed-only budget: 2500 levels render and re-diff cleanly, canary
# intact, in a detached tree. The first click builds (the cheap REPLACE
# path), the second re-walks the full depth through diff and diff_children,
# the deepest-framed path the host has.
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
	ok_rediff = page.evaluate!(canary_ok)?
	if ok_rediff != "1" {
		Err(CanaryTrippedInsideRediffBudget(ok_rediff))?
	}

	Ok({})
}
