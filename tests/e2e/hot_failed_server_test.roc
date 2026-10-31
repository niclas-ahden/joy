# Real-browser E2E: a server that fails to build through ./joy dev. The report goes
# over the page and the running server stays. The fix reloads the page, which picks
# up where it was.
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
	started = HotDev.start!("hot_failed_server", "hot_project", "--serve-files", "8773")?
	{ dir, page, url, .. } = started
	server = "${dir}/server/main.roc"
	HotDev.open!(page, "${url}/", "[data-joy-mounted]")?
	page.find("#inc").click!()?
	HotDev.mark!(page)?

	HotDev.edit!(server, "version one\"", "version two\" oops = = \"")?
	HotDev.reports!(page, "oops")?
	HotDev.same_page!(page)?
	_ = page.evaluate!("(document.querySelector('#load').click(), 'clicked')")?
	assert!(page.find("#data").has_text("data for version one"))?

	HotDev.edit!(server, "version two\" oops = = \"", "version two\"")?
	HotDev.reloaded!(page)?
	HotDev.shows!(page, "#title", "version two")?
	HotDev.shows!(page, "#count", "1")?
	HotDev.no_report!(page)?

	HotDev.stop!(started)
}
