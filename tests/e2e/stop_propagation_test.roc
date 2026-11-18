# Real-browser E2E: click propagation in Chromium. A browser is the only
# place the stop_propagation flag is observable end to end, since the
# fake-DOM harness calls a node's listener directly and never walks
# ancestors. Two clicks on the stop_propagation example: the first bubbles up
# to the outer div, the second must not.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.1/3tP6sNB4zffazkHJkdzQTxcme4m7x2Fk6fzL7zFKj4C6.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("stop_propagation", "#bubbles")?

	# A plain on_click: the button's handler runs and the click travels on to
	# the outer div, so both counters move.
	page.find("#bubbles").click!()?
	assert!(page.find("#counts").has_text("outer 1, inner 1"))?

	# stop_propagation: the button's own handler still runs, but the outer
	# div never sees the click, so only the inner counter moves. This is the
	# assertion that fails if the flag is dropped anywhere along the way
	# (Roc constructor, host command buffer, or runtime.js).
	page.find("#stops").click!()?
	assert!(page.find("#counts").has_text("outer 1, inner 2"))?

	browser.close!()?
	Ok({})
}
