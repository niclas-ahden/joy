# Real-browser E2E: the counter example in Chromium. Two real clicks on "+"
# must render "+2-", the same assertion the fake-DOM harness makes, now with
# the browser's own event dispatch and DOM.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

main! = |_args| {
	{ browser, page } = Support.open!("counter", "#increment")?

	# <div><button>+</button>0<button>-</button></div>, so the div's text is
	# the count with both labels around it.
	Playwright.click!(page, "#increment")?
	Playwright.click!(page, "#increment")?
	Support.expect_text!(page, "#app div", "+2-", |got| WrongCountAfterPlus(got))?

	Playwright.click!(page, "#decrement")?
	Support.expect_text!(page, "#app div", "+1-", |got| WrongCountAfterMinus(got))?

	Playwright.close!(browser)?
	Ok({})
}
