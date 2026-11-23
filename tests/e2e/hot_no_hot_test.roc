# Real-browser E2E: ./joy dev --no-hot builds what ships, so it records nothing, and
# the page reloads and starts over after each rebuild.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.2/BFCzMMp3DePaKT1sLy1m38p7qS5QB3okSVoFy6A1Y3Jf.tar.zst",
}

import playwright.Playwright exposing [assert!]
import HotDev

main! = |_args| {
	if !HotDev.has_cli!() {
		return Ok({})
	}
	started = HotDev.start!("hot_no_hot", "hot_pages", "--no-hot", "8776")?
	{ dir, page, url, .. } = started
	HotDev.open!(page, "${url}/", "#other[data-joy-mounted]")?
	page.find("#cart-inc").click!()?
	assert!(page.find("#cart-count").has_text("1"))?
	HotDev.mark!(page)?

	HotDev.edit!("${dir}/client/Shop/cart.roc", "cart one", "cart two")?
	HotDev.reloaded!(page)?
	HotDev.shows!(page, "#cart-label", "cart two")?
	assert!(page.find("#cart-count").has_text("0"))?

	HotDev.stop!(started)
}
