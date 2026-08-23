# Real-browser E2E: the events_input example in Chromium. Playwright's fill
# drives the browser's own input events through a real <textarea>; the app
# must echo the value into its <p> (typed value events, big-string path).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("events_input", "#app textarea")?

	typed = "hello from a real browser ✓"
	page.find("#app textarea").fill!(typed)?
	assert!(page.find("#draft").has_text(typed))?

	browser.close!()?
	Ok({})
}
