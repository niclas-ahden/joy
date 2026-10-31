# Real-browser E2E: a client change through ./joy dev takes the new build in
# place: the same document, with the state, the typed text and the focus it had.
# A build that fails shows roc's report over the page, with the app running on
# under it.
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
	started = HotDev.start!("hot_client", "hot_project", "--serve-files", "8770")?
	{ dir, page, url, .. } = started
	file = "${dir}/client/app.roc"
	HotDev.open!(page, "${url}/", "[data-joy-mounted]")?
	assert!(page.find("#title").has_text("version one"))?

	page.find("#inc").click!()?
	page.find("#inc").click!()?
	page.find("#name").fill!("Ada")?
	page.find("#load").click!()?
	assert!(page.find("#data").has_text("data for version one"))?
	_ = page.evaluate!("(document.querySelector('#name').focus(), 'focused')")?
	HotDev.mark!(page)?

	HotDev.edit!(file, "client one", "client two")?
	HotDev.shows!(page, "#label", "client two")?
	HotDev.same_page!(page)?
	assert!(page.find("#count").has_text("2"))?
	assert!(page.find("#name").has_value("Ada"))?
	assert!(page.find("#data").has_text("data for version one"))?
	HotDev.same!(page.evaluate!("document.activeElement.id")?, "name")?
	page.find("#inc").click!()?
	assert!(page.find("#count").has_text("3"))?

	# A new update replays the session through the new code.
	HotDev.edit!(file, "count: model.count + 1 }", "count: model.count + 10 }")?
	HotDev.shows!(page, "#count", "30")?
	HotDev.same_page!(page)?
	HotDev.edit!(file, "count: model.count + 10 }", "count: model.count + 1 }")?
	HotDev.shows!(page, "#count", "3")?

	# A dialog the user closed stays closed: a native close is not a message, and
	# the replay must not open it again.
	page.find("#open").click!()?
	_ = page.evaluate!("(document.querySelector('#dlg').close(), 'closed')")?
	HotDev.edit!(file, "client two", "client three")?
	HotDev.shows!(page, "#label", "client three")?
	HotDev.same!(page.evaluate!("String(document.querySelector('#dlg').open)")?, "false")?

	# A build that fails.
	HotDev.edit!(file, "client three", "client three\" oops = = \"")?
	HotDev.reports!(page, "oops")?
	assert!(page.find("#count").has_text("3"))?
	HotDev.edit!(file, "client three\" oops = = \"", "client four")?
	HotDev.no_report!(page)?
	HotDev.shows!(page, "#label", "client four")?
	HotDev.same_page!(page)?
	assert!(page.find("#count").has_text("3"))?

	HotDev.stop!(started)
}
