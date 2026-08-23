# Real-browser E2E: the time example in Chromium, on real timers and the
# real clock (the fake harness stubs both). A Time.every subscription must
# tick on its own, ticks must carry a real timestamp, dropping the
# subscription (pause) must stop the actual interval, and declaring it again
# must start a fresh one. The one test here that waits on wall-clock time,
# by nature: it costs a few seconds.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import pf.Sleep
import playwright.Playwright exposing [assert!]
import Browser

level = "#level"

main! = |_args| {
	{ browser, page } = Browser.open!("time", level)?

	# The subscription ticks by itself: within a few seconds the level leaves
	# 0. The not_ claim re-checks until the text changes away, so it is the
	# wait.
	assert!(page.find(level).not_has_text("Your excitement level for Roc: 0"))?

	# Remembering a moment reuses the time the last tick delivered, which on a
	# real clock is a genuine timestamp, not the 0 the model boots with
	# (www/index.html passes empty flags).
	page.find("#remember").click!()?
	moment = page.find("#moments p").text!()?
	if !moment.starts_with("Level ") or moment.contains("reached at 0") {
		Err(MomentWithoutClock(moment))?
	}

	# Pause drops the subscription, which must clear the real interval: over
	# a window longer than a tick, nothing moves.
	page.find("#pause").click!()?
	paused_at = page.find(level).text!()?
	Sleep.millis!(1500)
	assert!(page.find(level).has_text(paused_at))?

	# Unpause declares the subscription again: a fresh interval ticks.
	page.find("#pause").click!()?
	assert!(page.find(level).not_has_text(paused_at))?

	browser.close!()?
	Ok({})
}
