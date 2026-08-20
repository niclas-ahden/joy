# Real-browser E2E: the fetch app (tests/apps) in Chromium, on the browser's
# own fetch. The fake-DOM harness for examples/http.roc hands the host a
# stubbed response, so what it cannot prove is the round trip: that Http.get
# reaches the network layer at all, that a real Response comes back through
# the callback with its status and bytes intact, and that a non-200 takes the
# error branch. The app is a fixture rather than the example because the
# example calls a public API, and CI must not depend on one.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

state = "#state"

main! = |_args| {
	{ browser, page } = Support.open!("fetch", "#load")?

	# Nothing is requested until asked.
	Support.expect_text!(page, state, "nothing yet", |got| RequestedTooEarly(got))?

	# A real GET to the dev server: the body comes back as bytes, is decoded
	# as the JSON array serve.mjs sent, and lands in the model. The response
	# is async, so poll.
	Playwright.click!(page, "#load")?
	Support.wait_for_text!(page, state, "loaded: A real fetch, answered by the dev server.")?

	# A path no route claims: the callback still runs, and the response
	# carries the real status, which takes the non-200 branch.
	Playwright.click!(page, "#load-missing")?
	Support.wait_for_text!(page, state, "error: Request failed with status 404")?

	Playwright.close!(browser)?
	Ok({})
}
