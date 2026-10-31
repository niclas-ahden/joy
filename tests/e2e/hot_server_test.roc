# Real-browser E2E: a server change through ./joy dev reloads the page, which
# replays what was done on the new markup. A GET is sent again and the new answer
# goes in, and the replay stops before a POST, so nothing is written twice.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
}

import playwright.Playwright exposing [assert!]
import HotDev

import pf.Path

main! = |_args| {
	if !HotDev.has_cli!() {
		return Ok({})
	}
	started = HotDev.start!("hot_server", "hot_project", "--serve-files", "8771")?
	{ dir, page, url, .. } = started
	server = "${dir}/server/main.roc"
	HotDev.open!(page, "${url}/", "[data-joy-mounted]")?

	page.find("#inc").click!()?
	page.find("#inc").click!()?
	page.find("#name").fill!("Ada")?
	page.find("#load").click!()?
	assert!(page.find("#data").has_text("data for version one"))?
	page.find("#open").click!()?
	HotDev.mark!(page)?

	HotDev.edit!(server, "version one", "version two")?
	HotDev.reloaded!(page)?
	HotDev.shows!(page, "#title", "version two")?
	HotDev.shows!(page, "#count", "2")?
	assert!(page.find("#name").has_value("Ada"))?
	assert!(page.find("#data").has_text("data for version two"))?
	HotDev.same!(page.evaluate!("String(document.querySelector('#dlg').open)")?, "true")?
	HotDev.same!(page.evaluate!("String(document.querySelector('#app').joy.hydration().mismatch)")?, "null")?
	_ = page.evaluate!("(document.querySelector('#dlg').close(), 'closed')")?

	# The session lives on after the reload, for the next hot reload.
	page.find("#inc").click!()?
	HotDev.edit!("${dir}/client/app.roc", "client one", "client two")?
	HotDev.shows!(page, "#label", "client two")?
	assert!(page.find("#count").has_text("3"))?

	# A POST is never sent twice: the replay stops before the message that sent it.
	page.find("#save").click!()?
	assert!(page.find("#saved").has_text("saved by version two"))?
	page.find("#inc").click!()?
	assert!(page.find("#count").has_text("4"))?
	HotDev.edit!(server, "version two", "version three")?
	HotDev.shows!(page, "#title", "version three")?
	HotDev.shows!(page, "#count", "3")?
	assert!(page.find("#saved").has_text(""))?
	HotDev.same!(Path.utf8("${dir}/.joy/save.log").read_utf8!()?, "saved\n")?

	HotDev.stop!(started)
}
