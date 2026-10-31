# Real-browser E2E: which apps a rebuild reaches through ./joy dev. A bundle below
# a folder of client/ takes its new build, the other bundle on the page keeps
# running as it was, and so does a page that mounts an app by hand.
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
	started = HotDev.start!("hot_bundles", "hot_pages", "", "8774")?
	{ dir, page, url, .. } = started
	cart = "${dir}/client/Shop/cart.roc"
	HotDev.open!(page, "${url}/", "#other[data-joy-mounted]")?
	page.find("#cart-inc").click!()?
	page.find("#cart-inc").click!()?
	page.find("#other-inc").click!()?
	HotDev.mark!(page)?

	HotDev.edit!(cart, "cart one", "cart two")?
	HotDev.shows!(page, "#cart-label", "cart two")?
	HotDev.same_page!(page)?
	assert!(page.find("#cart-count").has_text("2"))?
	assert!(page.find("#other-count").has_text("1"))?

	HotDev.edit!("${dir}/client/other.roc", "other one", "other two")?
	HotDev.shows!(page, "#other-label", "other two")?
	HotDev.same_page!(page)?
	assert!(page.find("#other-count").has_text("1"))?
	assert!(page.find("#cart-count").has_text("2"))?

	HotDev.open!(page, "${url}/hand.html", "body[data-ready]")?
	page.find("#cart-inc").click!()?
	HotDev.mark!(page)?
	HotDev.edit!(cart, "cart two", "cart three")?
	HotDev.shows!(page, "#cart-label", "cart three")?
	HotDev.same_page!(page)?
	assert!(page.find("#cart-count").has_text("1"))?

	HotDev.stop!(started)
}
