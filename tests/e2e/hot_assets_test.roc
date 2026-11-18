# Real-browser E2E: a file in public/ changing through ./joy dev. A stylesheet the
# page links is swapped in place. Another file the page loaded reloads it, and so
# does the page's own HTML. The replay brings back the state and the URL it had
# moved to.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.1/3tP6sNB4zffazkHJkdzQTxcme4m7x2Fk6fzL7zFKj4C6.tar.zst",
}

import playwright.Playwright exposing [assert!]
import HotDev

main! = |_args| {
	if !HotDev.has_cli!() {
		return Ok({})
	}
	started = HotDev.start!("hot_assets", "hot_pages", "", "8775")?
	{ dir, page, url, .. } = started
	HotDev.open!(page, "${url}/", "#other[data-joy-mounted]")?
	page.find("#other-inc").click!()?
	page.find("#other-inc").click!()?
	page.find("#other-move").click!()?
	HotDev.mark!(page)?

	HotDev.edit!("${dir}/public/site.css", "rgb(1, 2, 3)", "rgb(4, 5, 6)")?
	HotDev.shows!(page, "#other-count", "2")?
	HotDev.styled!(page, "rgb(4, 5, 6)")?
	HotDev.same_page!(page)?

	HotDev.edit!("${dir}/public/logo.svg", "width=\"1\"", "width=\"2\"")?
	HotDev.reloaded!(page)?
	HotDev.shows!(page, "#other-count", "2")?
	HotDev.same!(page.evaluate!("location.pathname")?, "/moved")?

	# The page's own HTML is not among the files it loaded, and the page has
	# moved to another URL than the one that file is served under.
	HotDev.mark!(page)?
	HotDev.edit!("${dir}/public/index.html", "<title>hot pages</title>", "<title>hot pages, edited</title>")?
	HotDev.reloaded!(page)?
	HotDev.same!(page.evaluate!("document.title")?, "hot pages, edited")?
	HotDev.shows!(page, "#other-count", "2")?

	HotDev.stop!(started)
}
