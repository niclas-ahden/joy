# Real-browser E2E: a file in public/ changing through ./joy dev. A stylesheet the
# page links is swapped in place. Another file the page loaded reloads it, and the
# replay brings back the state and the URL it had moved to.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
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

	HotDev.stop!(started)
}
