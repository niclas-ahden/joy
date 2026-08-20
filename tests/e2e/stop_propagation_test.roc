# Real-browser E2E: click propagation in Chromium. A browser is the only
# place the stop_propagation flag is observable end to end, since the
# fake-DOM harness calls a node's listener directly and never walks
# ancestors. Two clicks on the stop_propagation example: the first bubbles up
# to the outer div, the second must not.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

main! = |_args| {
	{ browser, page } = Support.open!("stop_propagation", "#bubbles")?

	# A plain on_click: the button's handler runs and the click travels on to
	# the outer div, so both counters move.
	Playwright.click!(page, "#bubbles")?
	Support.expect_text!(page, "#counts", "outer 1, inner 1", |got| ClickDidNotBubble(got))?

	# stop_propagation: the button's own handler still runs, but the outer
	# div never sees the click, so only the inner counter moves. This is the
	# assertion that fails if the flag is dropped anywhere along the way
	# (Roc constructor, host command buffer, or runtime.js).
	Playwright.click!(page, "#stops")?
	Support.expect_text!(page, "#counts", "outer 1, inner 2", |got| PropagationNotStopped(got))?

	Playwright.close!(browser)?
	Ok({})
}
