# Real-browser E2E: the time example in Chromium, on real timers and the
# real clock (the fake harness stubs both). A Time.every subscription must
# tick on its own, ticks must carry a real timestamp, dropping the
# subscription (pause) must stop the actual interval, and declaring it again
# must start a fresh one. The one test here that waits on wall-clock time,
# by nature: it costs a few seconds.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import pf.Sleep
import playwright.Playwright
import spec.Wait
import Support

level = "#level"

main! = |_args| {
	{ browser, page } = Support.open!("time", level)?

	# The subscription ticks by itself: within a few seconds the level leaves 0.
	wait_for_change!(page, "Your excitement level for Roc: 0")?

	# Remembering a moment reuses the time the last tick delivered, which on a
	# real clock is a genuine timestamp, not the 0 the model boots with
	# (www/index.html passes empty flags).
	Playwright.click!(page, "#remember")?
	moment = Playwright.text_content!(page, "#moments p")?
	if !moment.starts_with("Level ") or moment.contains("reached at 0") {
		Err(MomentWithoutClock(moment))?
	}

	# Pause drops the subscription, which must clear the real interval: over
	# a window longer than a tick, nothing moves.
	Playwright.click!(page, "#pause")?
	paused_at = Playwright.text_content!(page, level)?
	Sleep.millis!(1500)
	while_paused = Playwright.text_content!(page, level)?
	if while_paused != paused_at {
		Err(TickedWhilePaused(paused_at, while_paused))?
	}

	# Unpause declares the subscription again: a fresh interval ticks.
	Playwright.click!(page, "#pause")?
	wait_for_change!(page, paused_at)?

	Playwright.close!(browser)?
	Ok({})
}

# Poll until the level heading no longer reads `from` (ticks are 1s apart,
# so give it a few). The condition's errors stay a closed union, for the
# reason Support.wait_for_text! explains.
wait_for_change! = |page, from|
	Wait.until!(
		{ sleep!: Sleep.millis! },
		|_| {
			match Playwright.text_content!(page, level) {
				Ok(got) if got != from => Ok({})
				Ok(got) => Err(StillAt(got))
				Err(_) => Err(CouldNotReadText(level))
			}
		},
		{ max_attempts: 30, delay_ms: 200 },
	)
