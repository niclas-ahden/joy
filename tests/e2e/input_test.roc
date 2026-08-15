# Real-browser E2E: the events_input example in Chromium. Playwright's fill
# drives the browser's own input events through a real <textarea>; the app
# must echo the value into its <p> (typed value events, big-string path).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

main! = |_args| {
	{ browser, page } = Support.open!("events_input", "#app textarea")?

	typed = "hello from a real browser ✓"
	Playwright.fill!(page, "#app textarea", typed)?
	Support.expect_text!(page, "#draft", typed, |got| InputNotEchoed(got))?

	Playwright.close!(browser)?
	Ok({})
}
