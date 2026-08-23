# Real-browser E2E: the fetch app (tests/apps) in Chromium, on the browser's
# own fetch. The fake-DOM harness for examples/http.roc hands the host a
# stubbed response, so what it cannot prove is the round trip: that Http.get
# reaches the network layer at all, that a real Response comes back through
# the callback with its status and bytes intact, and that a non-200 takes the
# error branch. The app is a fixture rather than the example because the
# example calls a public API, and CI must not depend on one.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

state = "#state"

main! = |_args| {
	{ browser, page } = Browser.open!("fetch", "#load")?

	# Nothing is requested until asked.
	assert!(page.find(state).has_text("nothing yet"))?

	# A real GET to the dev server: the body comes back as bytes, is decoded
	# as the JSON array serve.mjs sent, and lands in the model. The response
	# is async, and assert! re-checks until it arrives.
	page.find("#load").click!()?
	assert!(page.find(state).has_text("loaded: A real fetch, answered by the dev server."))?

	# A path no route claims: the callback still runs, and the response
	# carries the real status, which takes the non-200 branch.
	page.find("#load-missing").click!()?
	assert!(page.find(state).has_text("error: Request failed with status 404"))?

	browser.close!()?
	Ok({})
}
