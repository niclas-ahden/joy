# Real-browser E2E: the debounce example in Chromium. key_type! sends one
# real keystroke per character, so a three-letter burst re-arms the trailing
# 200ms timer three times on the browser's real event loop: exactly one
# search may fire, carrying the final text. The Cancel path stays in the
# fake-DOM harness (tests/check_debounce.mjs), where the clock is driven by
# hand, because clicking inside a real 200ms window would race the timer on
# a busy machine.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
}

import pf.Sleep
import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("debounce", "#search")?

	# A burst of three keystrokes: one search, with the final text. The first
	# claim rides out the debounce window, since assert! re-checks until it
	# holds.
	page.key_type!("#search", "joy")?
	assert!(page.find("#searches").has_text("searches: 1"))?
	assert!(page.find("#searched").has_text("searched for: joy"))?

	# The timer fired once. Well past another debounce window it must not
	# have fired again.
	Sleep.millis!(300)?
	assert!(page.find("#searches").has_text("searches: 1"))?

	# The key is reusable: another keystroke arms a fresh timer.
	page.key_type!("#search", "x")?
	assert!(page.find("#searches").has_text("searches: 2"))?
	assert!(page.find("#searched").has_text("searched for: joyx"))?

	browser.close!()?
	Ok({})
}
