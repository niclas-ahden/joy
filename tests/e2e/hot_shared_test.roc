# Real-browser E2E: a change in a package both the server and a bundle use, through
# ./joy dev. A module both read gives one reload, once both are built, so the new
# markup meets the new bundle and nothing mismatches. A module only the bundle
# reads takes the new build in place, with no reload.
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
	started = HotDev.start!("hot_shared", "hot_project", "--serve-files", "8772")?
	{ dir, page, url, .. } = started
	HotDev.open!(page, "${url}/", "[data-joy-mounted]")?
	page.find("#inc").click!()?
	page.find("#inc").click!()?

	HotDev.mark!(page)?
	HotDev.edit!("${dir}/shared/Label.roc", "view one", "view two")?
	HotDev.shows!(page, "#view", "view two")?
	HotDev.same_page!(page)?
	assert!(page.find("#count").has_text("2"))?

	HotDev.edit!("${dir}/shared/Greeting.roc", "shared one", "shared two")?
	HotDev.reloaded!(page)?
	HotDev.shows!(page, "#shared", "shared two")?
	HotDev.shows!(page, "#count", "2")?
	HotDev.same!(page.evaluate!("String(document.querySelector('#app').joy.hydration().mismatch)")?, "null")?
	# Nothing follows the reload: the bundle landed with it.
	HotDev.mark!(page)?
	HotDev.quiet!()?
	HotDev.same_page!(page)?

	HotDev.stop!(started)
}
