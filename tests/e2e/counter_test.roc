# Real-browser E2E: the counter example in Chromium. Two real clicks on "+"
# must render "+2-", the same assertion the fake-DOM harness makes, now with
# the browser's own event dispatch and DOM.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("counter", "#increment")?

	# <div><button>+</button>0<button>-</button></div>, so the div's text is
	# the count with both labels around it.
	page.find("#increment").click!()?
	page.find("#increment").click!()?
	assert!(page.find("#app div").has_text("+2-"))?

	page.find("#decrement").click!()?
	assert!(page.find("#app div").has_text("+1-"))?

	browser.close!()?
	Ok({})
}
