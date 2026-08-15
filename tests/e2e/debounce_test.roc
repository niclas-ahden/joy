# Real-browser E2E: the debounce example in Chromium. key_type! sends one
# real keystroke per character, so a three-letter burst re-arms the trailing
# 200ms timer three times on the browser's real event loop: exactly one
# search may fire, carrying the final text. The Cancel path stays in the
# fake-DOM harness (tests/check_debounce.mjs), where the clock is driven by
# hand, because clicking inside a real 200ms window would race the timer on
# a busy machine.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import pf.Sleep
import playwright.Playwright
import Support

main! = |_args| {
	{ browser, page } = Support.open!("debounce", "#search")?

	# A burst of three keystrokes: one search, with the final text.
	Playwright.key_type!(page, "#search", "joy")?
	Support.wait_for_text!(page, "#searches", "searches: 1")?
	Support.expect_text!(page, "#searched", "searched for: joy", |got| SearchedTooEarly(got))?

	# The timer fired once. Well past another debounce window it must not
	# have fired again.
	Sleep.millis!(300)
	Support.expect_text!(page, "#searches", "searches: 1", |got| TimerFiredTwice(got))?

	# The key is reusable: another keystroke arms a fresh timer.
	Playwright.key_type!(page, "#search", "x")?
	Support.wait_for_text!(page, "#searches", "searches: 2")?
	Support.expect_text!(page, "#searched", "searched for: joyx", |got| WrongSecondSearch(got))?

	Playwright.close!(browser)?
	Ok({})
}
